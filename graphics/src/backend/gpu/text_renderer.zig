const std = @import("std");
const stdx = @import("stdx");
const stbtt = @import("stbtt");
const gl = @import("gl");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const TextMetrics = graphics.TextMetrics;
const FontGroupId = graphics.FontGroupId;
const FontGroup = graphics.FontGroup;
const Font = graphics.Font;
const RenderFont = gpu.RenderFont;
const OpenTypeFont = graphics.OpenTypeFont;
const ImageTex = gpu.ImageTex;
const font_cache = @import("font_cache.zig");
const BitmapFontStrike = graphics.BitmapFontStrike;
const log = stdx.log.scoped(.text_renderer);
const Glyph = @import("glyph.zig").Glyph;

/// Returns an glyph iterator over UTF8 text.
pub fn textGlyphIter(g: *gpu.Graphics, font_gid: FontGroupId, font_size: f32, dpr: u32, str: []const u8) graphics.TextGlyphIterator {
    var iter: graphics.TextGlyphIterator = undefined;
    const fgroup = g.font_cache.getFontGroup(font_gid);
    iter.inner.init(g, fgroup, font_size, dpr, str, &iter);
    return iter;
}

pub fn measureCharAdvance(g: *gpu.Graphics, font_gid: FontGroupId, font_size: f32, dpr: u32, prev_cp: u21, cp: u21) f32 {
    const font_grp = g.font_cache.getFontGroup(font_gid);
    var req_font_size = font_size;
    const render_font_size = font_cache.computeRenderFontSize(&req_font_size) * @intCast(u16, dpr);

    const primary = g.font_cache.getOrCreateRenderFont(font_grp.fonts[0], render_font_size);
    const to_user_scale = primary.getScaleToUserFontSize(req_font_size);

    const glyph_info = g.getOrLoadFontGroupGlyph(font_grp, cp);
    const glyph = glyph_info.glyph;
    var advance = glyph.advance_width * to_user_scale;

    const prev_glyph_info = g.getOrLoadFontGroupGlyph(font_grp, prev_cp);
    const prev_glyph = prev_glyph_info.glyph;
    advance += computeKern(prev_glyph.glyph_id, prev_glyph_info.font, glyph.glyph_id, glyph_info.font, to_user_scale, cp);
    return @round(advance);
}

/// For lower font sizes, snap_to_grid is desired since baked fonts don't have subpixel rendering. TODO: Could this be achieved if multiple subpixel variation renders were baked as well?
pub fn measureText(g: *gpu.Graphics, font_gid: FontGroupId, font_size: f32, dpr: u32, str: []const u8, res: *TextMetrics, comptime snap_to_grid: bool) void {
    var iter = textGlyphIter(g, font_gid, font_size, dpr, str);
    res.height = iter.primary_height;
    res.width = 0;
    while (iter.nextCodepoint()) {
        res.width += iter.state.kern;
        if (snap_to_grid) {
            res.width = @round(res.width);
        }
        // Add advance width.
        res.width += iter.state.advance_width;
    }
}

pub const TextGlyphIterator = struct {
    g: *gpu.Graphics,
    fgroup: *FontGroup,

    cp_iter: std.unicode.Utf8Iterator,
    user_scale: f32,

    prev_glyph_id_opt: ?u16,
    prev_glyph_font: ?*Font,

    req_font_size: f32,
    render_font_size: u16,

    primary_font: graphics.FontId,
    primary_ascent: f32,

    const Self = @This();

    fn init(self: *Self, g: *gpu.Graphics, fgroup: *FontGroup, font_size: f32, dpr: u32, str: []const u8, iter: *graphics.TextGlyphIterator) void {
        var req_font_size = font_size;
        const render_font_size = font_cache.computeRenderFontSize(fgroup.primary_font_desc, &req_font_size) * @intCast(u16, dpr);

        const primary = g.font_cache.getOrCreateRenderFont(fgroup.primary_font, render_font_size);
        const user_scale = primary.getScaleToUserFontSize(req_font_size);

        iter.primary_ascent = primary.ascent * user_scale;
        iter.primary_descent = -primary.descent * user_scale;
        iter.primary_height = primary.font_height * user_scale;

        iter.state = .{
            // TODO: Update ascent, descent, height depending on current font.
            .ascent = iter.primary_ascent,
            .descent = iter.primary_descent,
            .height = iter.primary_height,
            .start_idx = 0,
            .end_idx = 0,
            .cp = undefined,
            .kern = undefined,
            .advance_width = undefined,
            .primary_offset_y = 0,
        };
        self.* = .{
            .g = g,
            .fgroup = fgroup,
            .user_scale = user_scale,
            .cp_iter = std.unicode.Utf8View.initUnchecked(str).iterator(),
            .prev_glyph_id_opt = null,
            .prev_glyph_font = null,
            .req_font_size = req_font_size,
            .render_font_size = render_font_size,
            .primary_font = fgroup.primary_font,
            .primary_ascent = iter.primary_ascent,
        };
    }

    pub fn setIndex(self: *Self, i: usize) void {
        self.cp_iter.i = i;
    }

    /// Provide a callback to the glyph data so a renderer can prepare a quad.
    pub fn nextCodepoint(self: *Self, state: *graphics.TextGlyphIterator.State, ctx: anytype, comptime m_cb: ?fn (@TypeOf(ctx), Glyph) void) bool {
        state.start_idx = self.cp_iter.i;
        state.cp = self.cp_iter.nextCodepoint() orelse return false;
        state.end_idx = self.cp_iter.i;

        const glyph_info = self.g.font_cache.getOrLoadFontGroupGlyph(self.g, self.fgroup, self.render_font_size, state.cp);
        const glyph = glyph_info.glyph;

        if (self.prev_glyph_font != glyph_info.font) {
            // Recompute the scale for the new font.
            self.user_scale = glyph_info.render_font.getScaleToUserFontSize(self.req_font_size);
            if (glyph_info.font.id != self.primary_font) {
                state.primary_offset_y = self.primary_ascent - glyph_info.render_font.ascent * self.user_scale;
            } else {
                state.primary_offset_y = 0;
            }
        }

        if (self.prev_glyph_id_opt) |prev_glyph_id| {
            // Advance kerning from previous codepoint.
            switch (glyph_info.font.font_type) {
                .Outline => {
                    state.kern = computeKern(prev_glyph_id, self.prev_glyph_font.?, glyph.glyph_id, glyph_info.font, glyph_info.render_font, self.user_scale, state.cp);
                },
                .Bitmap => {
                    const bm_font = glyph_info.font.getBitmapFontBySize(@floatToInt(u16, self.req_font_size));
                    state.kern += computeBitmapKern(prev_glyph_id, self.prev_glyph_font.?, glyph.glyph_id, glyph_info.font, bm_font, glyph_info.render_font, self.user_scale, state.cp);
                },
            }
        } else {
            state.kern = 0;
        }

        state.advance_width = glyph.advance_width * self.user_scale;

        if (m_cb) |cb| {
            // Once the state has updated, invoke the callback.
            cb(ctx, glyph.*);
        }

        self.prev_glyph_id_opt = glyph.glyph_id;
        self.prev_glyph_font = glyph_info.font;
        return true;
    }

    // Consumes until the next non space cp or end of string.
    pub fn nextNonSpaceCodepoint(self: *Self) bool {
        const parent = @fieldParentPtr(graphics.MeasureTextIterator, "inner", self);
        while (self.next_codepoint()) {
            if (!stdx.unicode.isSpace(parent.state.cp)) {
                return true;
            }
        }
        return false;
    }

    // Consumes until the next space cp or end of string.
    pub fn nextSpaceCodepoint(self: *Self) bool {
        const parent = @fieldParentPtr(graphics.MeasureTextIterator, "inner", self);
        while (self.next_codepoint()) {
            if (stdx.unicode.isSpace(parent.state.cp)) {
                return true;
            }
        }
        return false;
    }
};

// TODO: Cache results since each time it scans the in memory ot font data.
/// Return kerning from previous glyph id.
inline fn computeKern(prev_glyph_id: u16, prev_font: *Font, glyph_id: u16, fnt: *Font, render_font: *RenderFont, user_scale: f32, cp: u21) f32 {
    _ = cp;
    if (prev_font == fnt) {
        const kern = fnt.getKernAdvance(prev_glyph_id, glyph_id);
        return @intToFloat(f32, kern) * render_font.scale_from_ttf * user_scale;
    } else {
        // TODO: What to do for kerning between two different fonts?
        //       Maybe it's best to just always return the current font's kerning.
    }
    return 0;
}

inline fn computeBitmapKern(prev_glyph_id: u16, prev_font: *Font, glyph_id: u16, fnt: *Font, bm_font: BitmapFontStrike, render_font: *RenderFont, user_scale: f32, cp: u21) f32 {
    _ = cp;
    if (prev_font == fnt) {
        const kern = bm_font.getKernAdvance(prev_glyph_id, glyph_id);
        return @intToFloat(f32, kern) * render_font.scale_from_ttf * user_scale;
    } else {
        // TODO, maybe it's best to just always return the current font kerning.
    }
    return 0;
}

pub const RenderTextIterator = struct {
    iter: graphics.TextGlyphIterator,
    quad: TextureQuad,

    // cur top left position for next codepoint to be drawn.
    x: f32,
    y: f32,

    const Self = @This();

    pub fn init(g: *gpu.Graphics, group_id: FontGroupId, font_size: f32, dpr: u32, x: f32, y: f32, str: []const u8) Self {
        return .{
            .iter = textGlyphIter(g, group_id, font_size, dpr, str),
            .quad = undefined,
            // Start at snapped pos.
            .x = @round(x),
            .y = @round(y),
        };
    }

    /// Writes the vertex data of the next codepoint to ctx.quad
    pub fn nextCodepointQuad(self: *Self, comptime snap_to_grid: bool) bool {
        const S = struct {
            fn onGlyphSnap(self_: *Self, glyph: Glyph) void {
                const scale = self_.iter.inner.user_scale;
                self_.x += self_.iter.state.kern;
                // Snap to pixel after applying advance and kern.
                self_.x = @round(self_.x);

                // Update quad result.
                self_.quad.image = glyph.image;
                self_.quad.cp = self_.iter.state.cp;
                self_.quad.is_color_bitmap = glyph.is_color_bitmap;
                // quad.x0 = ctx.x + glyph.x_offset * user_scale;
                // Snap to pixel for consistent glyph rendering.
                self_.quad.x0 = @round(self_.x + glyph.x_offset * scale);
                self_.quad.y0 = self_.y + glyph.y_offset * scale + self_.iter.state.primary_offset_y;
                self_.quad.x1 = self_.quad.x0 + glyph.dst_width * scale;
                self_.quad.y1 = self_.quad.y0 + glyph.dst_height * scale;
                self_.quad.u0 = glyph.u0;
                self_.quad.v0 = glyph.v0;
                self_.quad.u1 = glyph.u1;
                self_.quad.v1 = glyph.v1;
                // Advance draw x.
                self_.x += self_.iter.state.advance_width;
            }

            fn onGlyph(self_: *Self, glyph: Glyph) void {
                const scale = self_.iter.inner.user_scale;
                self_.x += self_.iter.state.kern;

                // Update quad result.
                self_.quad.image = glyph.image;
                self_.quad.cp = self_.iter.state.cp;
                self_.quad.is_color_bitmap = glyph.is_color_bitmap;
                self_.quad.x0 = self_.x + glyph.x_offset * scale;
                self_.quad.y0 = self_.y + glyph.y_offset * scale + self_.iter.state.primary_offset_y;
                self_.quad.x1 = self_.quad.x0 + glyph.dst_width * scale;
                self_.quad.y1 = self_.quad.y0 + glyph.dst_height * scale;
                self_.quad.u0 = glyph.u0;
                self_.quad.v0 = glyph.v0;
                self_.quad.u1 = glyph.u1;
                self_.quad.v1 = glyph.v1;
                // Advance draw x.
                self_.x += self_.iter.state.advance_width;
            }
        };
        const onGlyph = if (snap_to_grid) S.onGlyphSnap else S.onGlyph;
        return self.iter.inner.nextCodepoint(&self.iter.state, self, onGlyph);
    }
};

// Holds compact data relevant to adding texture vertex data.
pub const TextureQuad = struct {
    image: ImageTex,
    cp: u21,
    is_color_bitmap: bool,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};
