const std = @import("std");

const graphics = @import("graphics.zig");
const FontId = graphics.font.FontId;

// Currently keeps a seq of fonts to do fallback logic. Similar to css font-family.
pub const FontGroup = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    // Ordered by font fallback priority.
    // There are also library fallback fonts, that FontCache will use.
    // TODO: store in a compact many linked list.
    fonts: []const FontId,

    primary_font: FontId,

    pub fn init(self: *Self, alloc: std.mem.Allocator, fonts: []const FontId) void {
        const _fonts = alloc.dupe(FontId, fonts) catch unreachable;
        self.* = .{
            .alloc = alloc,
            .fonts = _fonts,
            .primary_font = _fonts[0],
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.fonts);
    }

    pub fn getPrimaryFont(self: *const Self) FontId {
        return self.fonts[0];
    }
};