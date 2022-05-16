const std = @import("std");
const stdx = @import("stdx");
const stbi = @import("stbi");
const Point2 = stdx.math.Point2;

const graphics = @import("../../graphics.zig");
const Graphics = graphics.gl.Graphics;
const Image = graphics.gl.Image;
const ImageDesc = graphics.gl.ImageDesc;
const Texture = graphics.gl.Texture;
const RectBinPacker = graphics.RectBinPacker;
const log = stdx.log.scoped(.font_atlas);

/// Holds a buffer of font glyphs in memory that is then synced to the gpu.
pub const FontAtlas = struct {
    g: *Graphics,

    /// Uses a rect bin packer to allocate space.
    packer: RectBinPacker,

    /// The gl buffer always contains 4 channels. This lets it use the same shader/batch for rendering outline text.
    /// Kept in memory since it will be updated for glyphs on demand.
    gl_buf: []u8,

    width: u32,
    height: u32,
    channels: u8,

    image: ImageDesc,

    needs_texture_resize: bool,

    // The same allocator is used to do resizing.
    alloc: std.mem.Allocator,

    const Self = @This();

    /// Linear filter disabled is good for bitmap fonts that scale upwards.
    /// Outline glyphs and color bitmaps would use linear filtering. Although in the future, outline glyphs might also need to have linear filter disabled.
    pub fn init(self: *Self, alloc: std.mem.Allocator, g: *Graphics, width: u32, height: u32, linear_filter: bool) void {
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
            .needs_texture_resize = false,
        };
        self.image = g.createImageFromBitmap(width, height, null, linear_filter, .{ .ctx = self, .update = updateFontAtlasImage });

        self.gl_buf = alloc.alloc(u8, width * height * self.channels) catch @panic("error");
        std.mem.set(u8, self.gl_buf, 0);

        const S = struct {
            fn onResize(ptr: ?*anyopaque, width_: u32, height_: u32) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ptr);
                self_.resizeLocalBuffer(width_, height_);
            }
        };
        self.packer.addResizeCallback(self, S.onResize);
    }

    pub fn deinit(self: Self) void {
        self.packer.deinit();
        self.alloc.free(self.gl_buf);
        self.g.removeImage(self.image.image_id);
    }

    fn resizeLocalBuffer(self: *Self, width: u32, height: u32) void {
        const old_buf = self.gl_buf;
        defer self.alloc.free(old_buf);

        // We need to flush since the current batch could have old uv geometry.
        self.g.flushDraw();

        self.gl_buf = self.alloc.alloc(u8, width * height * self.channels) catch @panic("error");
        std.mem.set(u8, self.gl_buf, 0);

        var old_width = self.width;
        var old_height = self.height;
        self.width = width;
        self.height = height;

        // Copy over existing data.
        self.copySubImageFrom(0, 0, old_width, old_height, old_buf);

        // The next batch will perform the new texture upload.
        self.needs_texture_resize = true;
        // log.debug("resize atlas to: {}x{}", .{width, height});
    }

    /// Copy from 1 channel row major sub image data. markDirtyBuffer needs to be called afterwards to queue a sync op to the gpu.
    pub fn copySubImageFrom1Channel(self: *Self, x: usize, y: usize, width: usize, height: usize, src: []const u8) void {
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
    pub fn copySubImageFrom(self: *Self, bm_x: usize, bm_y: usize, width: usize, height: usize, src: []const u8) void {
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

    pub fn markDirtyBuffer(self: *Self) void {
        const image = self.g.images.getPtrNoCheck(self.image.image_id);
        image.needs_update = true;
    }

    pub fn dumpBufferToDisk(self: Self, filename: [*:0]const u8) void {
        _ = stbi.stbi_write_bmp(filename, @intCast(c_int, self.width), @intCast(c_int, self.height), self.channels, &self.gl_buf[0]);
        // _ = stbi.stbi_write_png("font_cache.png", @intCast(c_int, self.bm_width), @intCast(c_int, self.bm_height), 1, &self.bm_buf[0], @intCast(c_int, self.bm_width));
    }
};

// Updates gpu texture before current draw call batch is sent to gpu.
fn updateFontAtlasImage(image: *Image) void {
    const atlas = stdx.mem.ptrCastAlign(*FontAtlas, image.ctx);
    const g = atlas.g;

    // Check to resize.
    if (atlas.needs_texture_resize) {
        atlas.needs_texture_resize = false;

        // Make sure we don't recurse from deleteTexture's implicit flushDraw.
        image.needs_update = false;

        const old_tex_id = image.tex_id;

        g.deinitImage(image.*);
        g.initImage(image, atlas.width, atlas.height, null, false, .{ .ctx = atlas, .update = updateFontAtlasImage });

        // Update tex_id and uvs in existing glyphs.
        const tex_width = @intToFloat(f32, atlas.width);
        const tex_height = @intToFloat(f32, atlas.height);
        for (g.font_cache.render_fonts.items) |font| {
            var iter = font.glyphs.valueIterator();
            while (iter.next()) |glyph| {
                if (glyph.image.tex_id == old_tex_id) {
                    glyph.image.tex_id = image.tex_id;
                    glyph.u0 = @intToFloat(f32, glyph.x) / tex_width;
                    glyph.v0 = @intToFloat(f32, glyph.y) / tex_height;
                    glyph.u1 = @intToFloat(f32, glyph.x + glyph.width) / tex_width;
                    glyph.v1 = @intToFloat(f32, glyph.y + glyph.height) / tex_height;
                }
            }
        }
    }

    // Send bitmap data.
    // TODO: send only subimage that changed.
    g.updateTextureData(image, atlas.gl_buf);
}
