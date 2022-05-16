const std = @import("std");
const stdx = @import("stdx");
const stbi = @import("stbi");
const Point2 = stdx.math.Point2;

const graphics = @import("../../graphics.zig");
const Graphics = graphics.gl.Graphics;
const Image = graphics.gl.Image;
const ImageDesc = graphics.gl.ImageDesc;
const Texture = graphics.gl.Texture;
const log = stdx.log.scoped(.font_atlas);

/// Holds a buffer of font glyphs in memory that is then synced the gpu.
pub const FontAtlas = struct {
    const Self = @This();

    g: *Graphics,

    /// The gl buffer always contains 4 channels. This lets it use the same shader/batch for rendering outline text.
    /// Kept in memory since it will be updated for glyphs on demand.
    gl_buf: []u8,

    width: u32,
    height: u32,
    channels: u8,

    // Start pos for the next glyph.
    next_x: u32,
    next_y: u32,

    // The max height of the current glyph row we're rendering to.
    // Used to advance next_y once width is reached for the current row.
    row_height: u32,

    image: ImageDesc,

    needs_texture_resize: bool,

    // The same allocator is used to do resizing.
    alloc: std.mem.Allocator,

    /// Linear filter disabled is good for bitmap fonts that scale upwards.
    /// Outline glyphs and color bitmaps would use linear filtering. Although in the future, outline glyphs might also need to have linear filter disabled.
    pub fn init(self: *Self, alloc: std.mem.Allocator, g: *Graphics, width: u32, height: u32, linear_filter: bool) void {
        self.* = .{
            .g = g,
            .alloc = alloc,
            .width = width,
            .height = height,
            // Always 4 to match the gpu texture data.
            .channels = 4,
            .image = undefined,
            .gl_buf = undefined,
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
            .needs_texture_resize = false,
        };
        self.image = g.createImageFromBitmap(width, height, null, linear_filter, .{ .ctx = self, .update = updateFontAtlasImage });

        self.gl_buf = alloc.alloc(u8, width * height * self.channels) catch @panic("error");
        std.mem.set(u8, self.gl_buf, 0);
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.gl_buf);
        self.g.removeImage(self.image.image_id);
    }

    fn resizeLocalBuffer(self: *Self, width: u32, height: u32) void {
        if (width != self.width) {
            stdx.debug.panic("TODO: Implement rearranging glyphs after growing buffer width, for now start with large width");
        }
        self.width = width;
        self.height = height;
        self.gl_buf = self.alloc.realloc(self.gl_buf, width * height * self.channels) catch @panic("error");

        // We need to flush since the current batch could have old uv geometry.
        self.g.flushDraw();

        // The next batch is when we want to do a new texture upload.
        self.needs_texture_resize = true;
        // log.debug("resize atlas to: {}x{}", .{width, height});
    }

    pub fn nextPosForSize(self: *Self, glyph_width: u32, glyph_height: u32) Point2(u32) {
        if (self.next_x + glyph_width > self.width) {
            // Wrap to the next row.
            if (self.row_height == 0) {
                // Current buffer width can't fit one glyph.
                // We haven't implemented rearranging glyphs after increasing the buffer width so fail for now.
                stdx.debug.panic("TODO: Implement rearranging glyphs after growing buffer width, for now start with large width");
                unreachable;
            }
            self.next_y += self.row_height;
            self.next_x = 0;
            self.row_height = 0;
            return self.nextPosForSize(glyph_width, glyph_height);
        }
        if (self.next_y + glyph_height > self.height) {
            // self.dumpBufferToDisk("font_cache.bmp");

            // Increase buffer height.
            self.resizeLocalBuffer(self.width, self.height * 2);
            return self.nextPosForSize(glyph_width, glyph_height);
        }
        defer self.advancePos(glyph_width, glyph_height);
        return .{ .x = self.next_x, .y = self.next_y };
    }

    fn advancePos(self: *Self, glyph_width: u32, glyph_height: u32) void {
        self.next_x += glyph_width;
        if (glyph_height > self.row_height) {
            self.row_height = glyph_height;
        }
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
