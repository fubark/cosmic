const std = @import("std");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const BBox = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    pub fn init(min_x: f32, min_y: f32, max_x: f32, max_y: f32) BBox {
        return .{
            .min_x = min_x,
            .min_y = min_y,
            .max_x = max_x,
            .max_y = max_y,
        };
    }

    pub fn initZero() BBox {
        return .{
            .min_x = 0,
            .min_y = 0,
            .max_x = 0,
            .max_y = 0,
        };
    }

    pub fn encloseRect(self: *BBox, x: f32, y: f32, width: f32, height: f32) void {
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

    pub fn computeCenterX(self: BBox) f32 {
        return (self.min_x + self.max_x) * 0.5;
    }

    pub fn computeCenterY(self: BBox) f32 {
        return (self.min_y + self.max_y) * 0.5;
    }

    pub fn computeWidth(self: BBox) f32 {
        return self.max_x - self.min_x;
    }

    pub fn computeHeight(self: BBox) f32 {
        return self.max_y - self.min_y;
    }

    pub fn containsPt(self: BBox, x: f32, y: f32) bool {
        return x >= self.min_x and x <= self.max_x and y >= self.min_y and y <= self.max_y;
    }
};
