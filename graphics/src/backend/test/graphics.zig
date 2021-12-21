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

pub const Graphics = struct {
    const Self = @This();

    default_font_id: FontId,
    default_font_gid: FontGroupId,
    default_font_size: f32,
    default_font_glyph_advance_width: f32,
    default_font_metrics: VMetrics,

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

pub const MeasureTextIterator = struct {
    const Self = @This();

    cp_iter: std.unicode.Utf8Iterator,

    g: *Graphics,
    font_size: f32,

    pub fn init(str: []const u8, font_size: f32, g: *Graphics) Self {
        return .{
            .cp_iter = std.unicode.Utf8View.initUnchecked(str).iterator(),
            .g = g,
            .font_size = font_size,
        };
    }

    pub fn nextCodepoint(self: *Self) bool {
        const parent = @fieldParentPtr(graphics.MeasureTextIterator, "inner", self);

        parent.state.start_idx = self.cp_iter.i;
        parent.state.cp = self.cp_iter.nextCodepoint() orelse return false;
        parent.state.end_idx = self.cp_iter.i;

        parent.state.kern = 0;
        const factor = self.font_size / self.g.default_font_size;
        parent.state.advance_width = factor * self.g.default_font_glyph_advance_width;
        parent.state.ascent = factor * self.g.default_font_metrics.ascender;
        parent.state.descent = 0;
        parent.state.height = factor * self.g.default_font_metrics.height;
        return true;
    }

    pub fn setIndex(self: *Self, i: usize) void {
        self.cp_iter.i = i;
    }
};
