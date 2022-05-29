const std = @import("std");

const graphics = @import("graphics.zig");
const FontId = graphics.font.FontId;
const font = @import("font.zig");
const Font = font.Font;
const FontDesc = font.FontDesc;

// Currently keeps a seq of fonts to do fallback logic. Similar to css font-family.
pub const FontGroup = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    // Ordered by font fallback priority.
    // There are also library fallback fonts, that FontCache will use.
    // TODO: store in a compact many linked list.
    fonts: []const FontId,

    primary_font: FontId,
    primary_font_desc: FontDesc,

    pub fn init(self: *Self, alloc: std.mem.Allocator, font_ids_: []const FontId, fonts: []const Font) void {
        const font_ids = alloc.dupe(FontId, font_ids_) catch unreachable;
        const primary_font = fonts[font_ids_[0]];
        self.* = .{
            .alloc = alloc,
            .fonts = font_ids,
            .primary_font = font_ids[0],
            .primary_font_desc = .{
                .font_type = primary_font.font_type,
                .bmfont_scaler = undefined,
            },
        };
        if (primary_font.font_type == .Bitmap) {
            self.primary_font_desc.bmfont_scaler = primary_font.bmfont_scaler;
        }
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.fonts);
    }

    pub fn getPrimaryFont(self: Self) FontId {
        return self.fonts[0];
    }
};