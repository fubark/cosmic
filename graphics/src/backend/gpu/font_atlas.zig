const std = @import("std");
const stdx = @import("stdx");
const stbi = @import("stbi");
const Point2 = stdx.math.Point2;

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const RectBinPacker = graphics.RectBinPacker;
const log = stdx.log.scoped(.font_atlas);

/// Holds a buffer of font glyphs in memory that is then synced to the gpu.
pub const FontAtlas = struct {
    g: *gpu.Graphics,

    /// Uses a rect bin packer to allocate space.
    packer: RectBinPacker,

    /// The gl buffer always contains 4 channels. This lets it use the same shader/batch for rendering outline text.
    /// Kept in memory since it will be updated for glyphs on demand.
    gl_buf: []u8,

    width: u32,
    height: u32,
    channels: u8,

    image: gpu.ImageTex,

    // The same allocator is used to do resizing.
    alloc: std.mem.Allocator,

    linear_filter: bool,
    dirty: bool,

    /// Linear filter disabled is good for bitmap fonts that scale upwards.
    /// Outline glyphs and color bitmaps would use linear filtering. Although in the future, outline glyphs might also need to have linear filter disabled.
    pub fn init(self: *FontAtlas, alloc: std.mem.Allocator, g: *gpu.Graphics, width: u32, height: u32, linear_filter: bool) void {
        self.* = .{
            .g = g,
            .alloc = alloc,
            .packer = RectBinPacker.init(alloc, width, height),
            .width = width,
            .height = height,
            // Always 4 to match the gpu texture data.
            .channels = 4,
            .image = undefined,
            .gl_buf = undefined,
            .linear_filter = linear_filter,
            .dirty = false,
        };
        self.image = g.image_store.createImageFromBitmap(width, height, null, .{
            .linear_filter = linear_filter
        });

        self.gl_buf = alloc.alloc(u8, width * height * self.channels) catch @panic("error");
        std.mem.set(u8, self.gl_buf, 0);

        const S = struct {
            fn onResize(ptr: ?*anyopaque, width_: u32, height_: u32) void {
                const self_ = stdx.ptrCastAlign(*FontAtlas, ptr);
                self_.resizeLocalBuffer(width_, height_);
            }
        };
        self.packer.addResizeCallback(self, S.onResize);
    }

    pub fn deinit(self: *FontAtlas) void {
        self.packer.deinit();
        self.alloc.free(self.gl_buf);
        self.g.image_store.markForRemoval(self.image.image_id);
    }

    fn resizeLocalBuffer(self: *FontAtlas, width: u32, height: u32) void {
        const old_buf = self.gl_buf;
        defer self.alloc.free(old_buf);

        self.gl_buf = self.alloc.alloc(u8, width * height * self.channels) catch @panic("error");
        std.mem.set(u8, self.gl_buf, 0);

        var old_width = self.width;
        var old_height = self.height;
        self.width = width;
        self.height = height;

        // Copy over existing data.
        self.copySubImageFrom(0, 0, old_width, old_height, old_buf);

        // End the current command so the current uv data still maps to correct texture data and create a new image.
        const old_image_id = self.image.image_id;
        self.g.image_store.endCmdAndMarkForRemoval(self.image.image_id);
        self.image = self.g.image_store.createImageFromBitmap(self.width, self.height, null, .{
            .linear_filter = self.linear_filter,
        });

        // Update tex_id and uvs in existing glyphs.
        const tex_width = @intToFloat(f32, self.width);
        const tex_height = @intToFloat(f32, self.height);
        for (self.g.font_cache.render_fonts.items) |font| {
            var iter = font.glyphs.valueIterator();
            while (iter.next()) |glyph| {
                if (glyph.image.image_id == old_image_id) {
                    glyph.image = self.image;
                    const x = @intToFloat(f32, glyph.x);
                    const y = @intToFloat(f32, glyph.y);
                    const widthf = @intToFloat(f32, glyph.width);
                    const heightf = @intToFloat(f32, glyph.height);
                    glyph.u0 = x / tex_width;
                    glyph.v0 = y / tex_height;
                    glyph.u1 = (x + widthf) / tex_width;
                    glyph.v1 = (y + heightf) / tex_height;
                }
            }
        }
    }

    /// Copy from 1 channel row major sub image data. markDirtyBuffer needs to be called afterwards to queue a sync op to the gpu.
    pub fn copySubImageFrom1Channel(self: *FontAtlas, x: usize, y: usize, width: usize, height: usize, src: []const u8) void {
        // Ensure src has the correct data length.
        std.debug.assert(width * height == src.len);
        // Ensure bounds in atlas bitmap.
        std.debug.assert(x + width <= self.width);
        std.debug.assert(y + height <= self.height);

        const dst_row_size = self.width * self.channels;
        const src_row_size = width;

        var row: usize = 0;
        var buf_offset: usize = (x + y * self.width) * self.channels;
        var src_offset: usize = 0;
        while (row < height) : (row += 1) {
            for (src[src_offset .. src_offset + src_row_size]) |it, i| {
                const dst_idx = buf_offset + (i * self.channels);
                self.gl_buf[dst_idx + 0] = 255;
                self.gl_buf[dst_idx + 1] = 255;
                self.gl_buf[dst_idx + 2] = 255;
                self.gl_buf[dst_idx + 3] = it;
            }
            buf_offset += dst_row_size;
            src_offset += src_row_size;
        }
    }

    /// Copy from 4 channel row major sub image data. markDirtyBuffer needs to be called afterwards to queue a sync op to the gpu.
    pub fn copySubImageFrom(self: *FontAtlas, bm_x: usize, bm_y: usize, width: usize, height: usize, src: []const u8) void {
        // Ensure src has the correct data length.
        std.debug.assert(width * height * self.channels == src.len);
        // Ensure bounds in atlas bitmap.
        std.debug.assert(bm_x + width <= self.width);
        std.debug.assert(bm_y + height <= self.height);

        const dst_row_size = self.width * self.channels;
        const src_row_size = width * self.channels;

        var row: usize = 0;
        var buf_offset: usize = (bm_x + bm_y * self.width) * self.channels;
        var src_offset: usize = 0;
        while (row < height) : (row += 1) {
            std.mem.copy(u8, self.gl_buf[buf_offset .. buf_offset + src_row_size], src[src_offset .. src_offset + src_row_size]);
            buf_offset += dst_row_size;
            src_offset += src_row_size;
        }
    }

    pub fn markDirtyBuffer(self: *FontAtlas) void {
        if (!self.dirty) {
            self.dirty = true;
            self.g.batcher.addNextPreFlushTask(self, syncFontAtlasToGpu);
        }
    }

    pub fn dumpBufferToDisk(self: FontAtlas, filename: [*:0]const u8) void {
        _ = stbi.stbi_write_bmp(filename, @intCast(c_int, self.width), @intCast(c_int, self.height), self.channels, &self.gl_buf[0]);
        // _ = stbi.stbi_write_png("font_cache.png", @intCast(c_int, self.bm_width), @intCast(c_int, self.bm_height), 1, &self.bm_buf[0], @intCast(c_int, self.bm_width));
    }
};

/// Updates gpu texture before current draw call batch is sent to gpu.
fn syncFontAtlasToGpu(ptr: ?*anyopaque) void {
    const self = stdx.ptrCastAlign(*FontAtlas, ptr);
    self.dirty = false;

    // Send bitmap data.
    // TODO: send only subimage that changed.
    const image = self.g.image_store.images.getNoCheck(self.image.image_id);
    self.g.updateTextureData(image, self.gl_buf);
}
