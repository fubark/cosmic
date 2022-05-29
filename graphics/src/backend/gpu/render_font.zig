const std = @import("std");
const stdx = @import("stdx");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const OpenTypeFont = graphics.font.OpenTypeFont;
const Glyph = gpu.Glyph;
const FontId = graphics.font.FontId;
const VMetrics = graphics.font.VMetrics;
const log = std.log.scoped(.font);

// Represents a font rendered at a specific bitmap font size.
pub const RenderFont = struct {
    const Self = @This();

    font_id: FontId,

    // The font size of the underlying bitmap data.
    render_font_size: u16,

    glyphs: std.AutoHashMap(u21, Glyph),

    // Special missing glyph, every font should have this. glyph_id = 0.
    missing_glyph: ?Glyph,

    // From design units to px. Calculated with render_font_size.
    scale_from_ttf: f32,

    // max distance above baseline (positive px)
    ascent: f32,

    // max distance below baseline (negative px)
    descent: f32,

    // gap between the previous row's decent and current row's ascent.
    line_gap: f32,

    // should just be ascent + descent amounts.
    font_height: f32,

    pub fn initOutline(self: *Self, alloc: std.mem.Allocator, font_id: FontId, ot_font: OpenTypeFont, render_font_size: u16) void {
        const scale = ot_font.getScaleToUserFontSize(@intToFloat(f32, render_font_size));

        const v_metrics = ot_font.getVerticalMetrics();
        const s_ascent = scale * @intToFloat(f32, v_metrics.ascender);
        const s_descent = scale * @intToFloat(f32, v_metrics.descender);
        const s_line_gap = scale * @intToFloat(f32, v_metrics.line_gap);

        self.* = .{
            .font_id = font_id,
            .render_font_size = render_font_size,
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

    pub fn initBitmap(self: *Self, alloc: std.mem.Allocator, font_id: FontId, ot_font: OpenTypeFont, render_font_size: u16) void {
        const v_metrics = ot_font.getBitmapVerticalMetrics();
        self.* = .{
            .font_id = font_id,
            .render_font_size = render_font_size,
            .scale_from_ttf = 1,
            .ascent = @intToFloat(f32, v_metrics.ascender),
            .descent = @intToFloat(f32, v_metrics.descender),
            .line_gap = @intToFloat(f32, v_metrics.line_gap),
            .font_height = @intToFloat(f32, v_metrics.ascender - v_metrics.descender),
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
        return size / @intToFloat(f32, self.render_font_size);
    }

    pub fn getVerticalMetrics(self: *Self, font_size: f32) VMetrics {
        const scale = font_size / @intToFloat(f32, self.render_font_size);
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
