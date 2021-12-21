const std = @import("std");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const BBox = struct {
    const Self = @This();

    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    pub fn init() Self {
        return .{
            .min_x = std.math.inf(f32),
            .min_y = std.math.inf(f32),
            .max_x = -std.math.inf(f32),
            .max_y = -std.math.inf(f32),
        };
    }

    pub fn encloseRect(self: *@This(), x: f32, y: f32, width: f32, height: f32) void {
        if (x < self.min_x) {
            self.min_x = x;
        }
        if (y < self.min_y) {
            self.min_y = y;
        }
        const end_x = x + width;
        if (end_x > self.max_x) {
            self.max_x = end_x;
        }
        const end_y = y + height;
        if (end_y > self.max_y) {
            self.max_y = end_y;
        }
    }

    pub fn computeWidth(self: *const Self) f32 {
        return self.max_x - self.min_x;
    }

    pub fn computeHeight(self: *const Self) f32 {
        return self.max_y - self.min_y;
    }
};
