const std = @import("std");
const stdx = @import("stdx");
const stbtt = @import("stbtt");

const graphics = @import("../../graphics.zig");
const TTF_Font = graphics.font.TTF_Font;
const Glyph = graphics.font.Glyph;
const FontId = graphics.font.FontId;
const VMetrics = graphics.font.VMetrics;
const log = std.log.scoped(.font);

// Represents a font rendered at a specific bitmap font size.
pub const BitmapFont = struct {
    const Self = @This();

    font_id: FontId,

    // The font size of the underlying bitmap data.
    bm_font_size: u16,

    glyphs: std.AutoHashMap(u21, Glyph),

    // Special missing glyph, every font should have this. glyph_id = 0.
    missing_glyph: ?Glyph,

    // From design units to px. Calculated with bm_font_size.
    scale_from_ttf: f32,

    // max distance above baseline (positive px)
    ascent: f32,

    // max distance below baseline (negative px)
    descent: f32,

    // gap between the previous row's decent and current row's ascent.
    line_gap: f32,

    // should just be ascent + descent amounts.
    font_height: f32,

    pub fn init(self: *Self, alloc: std.mem.Allocator, font: *Font, bm_font_size: u16) void {
        const scale = font.ttf_font.getScaleToUserFontSize(@intToFloat(f32, bm_font_size));

        const v_metrics = font.ttf_font.getVerticalMetrics();
        const s_ascent = scale * @intToFloat(f32, v_metrics.ascender);
        const s_descent = scale * @intToFloat(f32, v_metrics.descender);
        const s_line_gap = scale * @intToFloat(f32, v_metrics.line_gap);

        self.* = .{
            .font_id = font.id,
            .bm_font_size = bm_font_size,
            .scale_from_ttf = scale,
            .ascent = s_ascent,
            .descent = s_descent,
            .line_gap = s_line_gap,
            .font_height = s_ascent - s_descent,
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
            .missing_glyph = null,
        };
        // Start with enough memory for ascii codepoints.
        self.glyphs.ensureTotalCapacity(256) catch unreachable;
    }

    pub fn deinit(self: *Self) void {
        self.glyphs.deinit();
    }

    pub fn getScaleToUserFontSize(self: *const Self, size: f32) f32 {
        return size / @intToFloat(f32, self.bm_font_size);
    }

    pub fn getVerticalMetrics(self: *Self, font_size: f32) VMetrics {
        const scale = font_size / @intToFloat(f32, self.bm_font_size);
        const ascender = self.ascent * scale;
        const descender = self.descent * scale;
        return .{
            .ascender = ascender,
            .descender = descender,
            .line_gap = self.line_gap * scale,
            // subtract descender since it's negative
            .height = ascender - descender,
        };
    }
};

// Contains rendering metadata about one font. Glyphs metadata are also stored here.
// Contains the backing bitmap font size to scale to user requested font size.
pub const Font = struct {
    const Self = @This();

    id: FontId,
    ttf_font: TTF_Font,
    stbtt_font: stbtt.fontinfo,
    name: stdx.string.BoxString,
    data: []const u8,
    alloc: std.mem.Allocator,

    pub fn init(self: *Self, alloc: std.mem.Allocator, id: FontId, data: []const u8) void {
        // Dupe font data since we will be continually querying data from it.
        const own_data = alloc.dupe(u8, data) catch unreachable;

        const ttf_font = TTF_Font.init(alloc, own_data, 0) catch unreachable;

        var stbtt_font: stbtt.fontinfo = undefined;
        if (ttf_font.hasGlyphOutlines()) {
            stbtt.InitFont(&stbtt_font, own_data, 0) catch @panic("failed to load font");
        }

        const family_name = ttf_font.getFontFamilyName(alloc) orelse unreachable;

        self.* = .{
            .id = id,
            .ttf_font = ttf_font,
            .stbtt_font = stbtt_font,
            .name = family_name,
            .data = own_data,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ttf_font.deinit();
        self.name.deinit();
        self.alloc.free(self.data);
    }
};
