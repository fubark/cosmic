const std = @import("std");
const stdx = @import("stdx");
const stbtt = @import("stbtt");
const gl = @import("gl");

const graphics = @import("../../graphics.zig");
const TextMetrics = graphics.TextMetrics;
const FontGroupId = graphics.font.FontGroupId;
const FontGroup = graphics.font.FontGroup;
const Font = graphics.font.Font;
const BitmapFont = graphics.font.BitmapFont;
const graphics_gl = graphics.gl;
const ImageDesc = graphics_gl.ImageDesc;
const Graphics = graphics_gl.Graphics;
const font_cache = @import("font_cache.zig");

// Measures each char from start incrementally and sets result. Useful for computing layout.
pub fn measureTextIter(g: *Graphics, font_gid: FontGroupId, font_size: f32, str: []const u8, res: *MeasureTextIterator) void {
    const fgroup = g.font_cache.getFontGroup(font_gid);
    res.init(g, fgroup, font_size, str);
}

pub fn measureCharAdvance(g: *Graphics, font_gid: FontGroupId, font_size: f32, prev_cp: u21, cp: u21) f32 {
    const font_grp = g.font_cache.getFontGroup(font_gid);
    const to_user_scale = font_grp.getBackendToUserFontSizeScale(font_size);

    const glyph_info = g.getOrLoadFontGroupGlyph(font_grp, cp);
    const glyph = glyph_info.glyph;
    var advance = glyph.advance_width * to_user_scale;

    const prev_glyph_info = g.getOrLoadFontGroupGlyph(font_grp, prev_cp);
    const prev_glyph = prev_glyph_info.glyph;
    advance += computeKern(prev_glyph.glyph_id, prev_glyph_info.font, glyph.glyph_id, glyph_info.font, to_user_scale, cp);
    return std.math.round(advance);
}

pub fn measureText(g: *Graphics, group_id: FontGroupId, font_size: f32, str: []const u8, res: *TextMetrics) void {
    const font_grp = g.font_cache.getFontGroup(group_id);
    var req_font_size = font_size;
    const bm_font_size = font_cache.computeBitmapFontSize(&req_font_size);

    const primary = g.font_cache.getOrCreateBitmapFont(font_grp.fonts[0], bm_font_size);
    var scale = primary.getScaleToUserFontSize(req_font_size);
    res.height = primary.font_height * scale;

    res.width = 0;
    var prev_glyph_id: u16 = undefined;
    var prev_font: *Font = undefined;
    var iter = std.unicode.Utf8View.initUnchecked(str).iterator();

    if (iter.nextCodepoint()) |first_cp| {
        const glyph_info = g.font_cache.getOrLoadFontGroupGlyph(g, font_grp, bm_font_size, first_cp);
        const glyph = glyph_info.glyph;
        res.width += std.math.round(glyph.advance_width * scale);
        prev_glyph_id = glyph.glyph_id;
        prev_font = glyph_info.font;
    } else return;
    while (iter.nextCodepoint()) |it| {
        const glyph_res = g.font_cache.getOrLoadFontGroupGlyph(g, font_grp, bm_font_size, it);
        const glyph = glyph_res.glyph;

        if (prev_font != glyph_res.font) {
            scale = glyph_res.bm_font.getScaleToUserFontSize(req_font_size);
        }

        res.width += computeKern(prev_glyph_id, prev_font, glyph.glyph_id, glyph_res.font, glyph_res.bm_font, scale, it);

        // Add advance width.
        res.width += std.math.round(glyph.advance_width * scale);
        prev_glyph_id = glyph.glyph_id;
        prev_font = glyph_res.font;
    }
}

pub fn startRenderText(g: *Graphics, group_id: FontGroupId, font_size: f32, x: f32, y: f32, str: []const u8) RenderTextContext {
    const group = g.font_cache.getFontGroup(group_id);

    var req_font_size = font_size;
    const bm_font_size = font_cache.computeBitmapFontSize(&req_font_size);

    return .{
        .str = str,
        // Start at snapped pos.
        .x = std.math.round(x),
        .y = std.math.round(y),
        .font_group = group,
        .req_font_size = req_font_size,
        .bm_font_size = bm_font_size,
        .prev_glyph_id = null,
        .prev_font = null,
        .cp_iter = std.unicode.Utf8View.initUnchecked(str).iterator(),
        .g = g,
    };
}

// Writes the vertex data of the next codepoint to ctx.quad
pub fn renderNextCodepoint(ctx: *RenderTextContext, res_quad: *TextureQuad) bool {
    const code_pt = ctx.cp_iter.nextCodepoint() orelse return false;

    const glyph_info = ctx.g.font_cache.getOrLoadFontGroupGlyph(ctx.g, ctx.font_group, ctx.bm_font_size, code_pt);
    const glyph = glyph_info.glyph;

    const user_scale = ctx.req_font_size / @intToFloat(f32, ctx.bm_font_size);

    // Advance kerning from previous codepoint.
    if (ctx.prev_glyph_id) |prev_glyph_id| {
        const prev_font = ctx.prev_font.?;
        if (prev_font == glyph_info.font) {
            // prev codepoint used the same font.
            ctx.x += computeKern(prev_glyph_id, ctx.prev_font.?, glyph.glyph_id, glyph_info.font, glyph_info.bm_font, user_scale, code_pt);
        } else {
            // TODO: What to do for kerning between two different fonts?
        }
    }

    // Snap to pixel after applying advance and kern.
    ctx.x = std.math.round(ctx.x);

    // Update quad result.
    res_quad.image = glyph.image;
    res_quad.cp = code_pt;
    res_quad.is_color_bitmap = glyph.is_color_bitmap;
    // res_quad.x0 = ctx.x + glyph.x_offset * user_scale;
    // Snap to pixel for consistent glyph rendering.
    res_quad.x0 = std.math.round(ctx.x + glyph.x_offset * user_scale);
    res_quad.y0 = ctx.y + glyph.y_offset * user_scale;
    res_quad.x1 = res_quad.x0 + glyph.dst_width * user_scale;
    res_quad.y1 = res_quad.y0 + glyph.dst_height * user_scale;
    res_quad.u0 = glyph.u0;
    res_quad.v0 = glyph.v0;
    res_quad.u1 = glyph.u1;
    res_quad.v1 = glyph.v1;

    // Advance draw x.
    ctx.x += glyph.advance_width * user_scale;
    ctx.prev_glyph_id = glyph.glyph_id;
    ctx.prev_font = glyph_info.font;
    return true;
}

pub const MeasureTextIterator = struct {
    const Self = @This();

    g: *Graphics,
    fgroup: *FontGroup,

    cp_iter: std.unicode.Utf8Iterator,
    user_scale: f32,

    prev_glyph_id_opt: ?u16,
    prev_glyph_font: *Font,

    fn init(self: *Self, g: *Graphics, fgroup: *FontGroup, font_size: f32, str: []const u8) void {
        const user_scale = fgroup.getBackendToUserFontSizeScale(font_size);

        const parent = @fieldParentPtr(graphics.MeasureTextIterator, "inner", self);
        parent.state = .{
            // TODO: Currently fontgroup just uses the primary font's height. We'll need to update height for every character.
            .ascent = fgroup.getAscent() * user_scale,
            .descent = -fgroup.getDescent() * user_scale,
            .height = fgroup.getFontHeight() * user_scale,
            .start_idx = 0,
            .end_idx = 0,
            .cp = undefined,
            .kern = undefined,
            .advance_width = undefined,
        };
        self.* = .{
            .g = g,
            .fgroup = fgroup,
            .user_scale = user_scale,
            .cp_iter = std.unicode.Utf8View.initUnchecked(str).iterator(),
            .prev_glyph_id_opt = null,
            .prev_glyph_font = undefined,
        };
    }

    pub fn setIndex(self: *Self, i: usize) void {
        self.cp_iter.i = i;
    }

    pub fn nextCodepoint(self: *Self) bool {
        const parent = @fieldParentPtr(graphics.MeasureTextIterator, "inner", self);
        parent.state.start_idx = self.cp_iter.i;
        parent.state.cp = self.cp_iter.nextCodepoint() orelse return false;
        parent.state.end_idx = self.cp_iter.i;

        const glyph_info = self.g.getOrLoadFontGroupGlyph(self.fgroup, parent.state.cp);
        const glyph = glyph_info.glyph;

        if (self.prev_glyph_id_opt) |prev_glyph_id| {
            parent.state.kern = computeKern(prev_glyph_id, self.prev_glyph_font, glyph.glyph_id, glyph_info.font, self.user_scale, parent.state.cp);
        } else {
            parent.state.kern = 0;
        }

        parent.state.advance_width = glyph.advance_width * self.user_scale;
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

// Add kerning from previous codepoint.
inline fn computeKern(prev_glyph_id: u16, prev_font: *Font, glyph_id: u16, fnt: *Font, bm_font: *BitmapFont, user_scale: f32, cp: u21) f32 {
    _ = glyph_id;
    if (prev_font == fnt) {
        const kern = stbtt.stbtt_GetGlyphKernAdvance(&fnt.stbtt_font, prev_glyph_id, cp);
        return @intToFloat(f32, kern) * bm_font.scale_from_ttf * user_scale;
    } else {
        // TODO, maybe it's best to just always return the current font kerning.
    }
    return 0;
}

const RenderTextContext = struct {
    // Not managed.
    str: []const u8,
    // cur top left position for next codepoint to be drawn.
    x: f32,
    y: f32,
    cp_iter: std.unicode.Utf8Iterator,
    font_group: *FontGroup,
    g: *Graphics,

    // The final user requested font size after validation.
    req_font_size: f32,

    bm_font_size: u16,

    // Keep track of the last codepoint to compute kerning.
    prev_glyph_id: ?u16,
    prev_font: ?*Font,
};

// Holds compact data relevant to adding texture vertex data.
pub const TextureQuad = struct {
    image: ImageDesc,
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
