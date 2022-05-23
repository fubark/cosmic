const std = @import("std");
const stdx = @import("stdx");
const log = stdx.log.scoped(.graphics_test);

const graphics = @import("../../graphics.zig");
const _font = graphics.font;
const Font = _font.Font;
const FontGroup = _font.FontGroup;
const FontCache = _font.FontCache;
const FontId = _font.FontId;
const Glyph = _font.Glyph;
const VMetrics = _font.VMetrics;
const FontGroupId = _font.FontGroupId;
const Tessellator = graphics.tessellator.Tessellator;

pub const Graphics = struct {
    const Self = @This();

    default_font_id: FontId,
    default_font_gid: FontGroupId,
    default_font_size: f32,
    default_font_glyph_advance_width: f32,
    default_font_metrics: VMetrics,
    tessellator: Tessellator,

    getOrLoadFontGlyphFn: fn (*Self, font: *Font, cp: u21) ?*Glyph,

    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        _ = alloc;
        self.* = .{
            .default_font_id = 1,
            .default_font_gid = 1,
            .default_font_size = 20,
            .getOrLoadFontGlyphFn = undefined,
            .default_font_glyph_advance_width = 10,
            .default_font_metrics = .{
                .ascender = 10,
                .descender = 0,
                .line_gap = 0,
                .height = 10,
            },
            .tessellator = undefined,
        };
    }

    fn getOrLoadFontGlyph(self: *Self, font: *Font, cp: u21) ?*Glyph {
        return self.getOrLoadFontGlyphFn(font, cp);
    }

    pub fn getFontGroupBySingleFontName(self: *Self, name: []const u8) FontGroupId {
        _ = name;
        return self.default_font_gid;
    }
};

pub const TextGlyphIterator = struct {
    cp_iter: std.unicode.Utf8Iterator,

    g: *Graphics,
    font_size: f32,

    const Self = @This();

    pub fn init(str: []const u8, font_size: f32, g: *Graphics) Self {
        return .{
            .cp_iter = std.unicode.Utf8View.initUnchecked(str).iterator(),
            .g = g,
            .font_size = font_size,
        };
    }

    pub fn nextCodepoint(self: *Self, state: *graphics.TextGlyphIterator.State) bool {
        state.start_idx = self.cp_iter.i;
        state.cp = self.cp_iter.nextCodepoint() orelse return false;
        state.end_idx = self.cp_iter.i;

        state.kern = 0;
        const factor = self.font_size / self.g.default_font_size;
        state.advance_width = factor * self.g.default_font_glyph_advance_width;
        state.ascent = factor * self.g.default_font_metrics.ascender;
        state.descent = 0;
        state.height = factor * self.g.default_font_metrics.height;
        return true;
    }

    pub fn setIndex(self: *Self, i: usize) void {
        self.cp_iter.i = i;
    }
};
