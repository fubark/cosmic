const std = @import("std");
const stdx = @import("../stdx.zig");

const t = stdx.testing;
const vec2 = Vec2.init;
pub const geom = @import("geom.zig");

usingnamespace @import("matrix.zig");

pub fn Point2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn init(x: f32, y: f32, z: f32, w: f32) @This() {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

pub const Vec2 = struct {
    const Self = @This();

    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Self {
        return @This(){ .x = x, .y = y };
    }

    pub fn squareLength(self: Self) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub fn length(self: Self) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Self) Vec2 {
        const len = self.length();
        return Self.init(self.x / len, self.y / len);
    }

    pub fn toLength(self: Self, len: f32) Vec2 {
        const factor = len / self.length();
        return Self.init(self.x * factor, self.y * factor);
    }

    pub fn normalizeWith(self: Self, factor: f32) Vec2 {
        return Self.init(self.x / factor, self.y / factor);
    }

    pub fn neg(self: Self) Vec2 {
        return Self.init(-self.x, -self.y);
    }

    // Useful for determining the z direction.
    pub fn cross(self: Self, v: Vec2) f32 {
        return self.x * v.y - self.y * v.x;
    }

    pub fn dot(self: Self, v: Vec2) f32 {
        return self.x * v.x + self.y * v.y;
    }

    pub fn mul(self: Self, s: f32) Vec2 {
        return Self.init(self.x * s, self.y * s);
    }

    fn div(self: Self, s: f32) Vec2 {
        return Self.init(self.x / s, self.y / s);
    }
};

pub const Counter = struct {
    c: usize,

    pub fn init(start_count: usize) Counter {
        return .{
            .c = start_count,
        };
    }

    pub fn inc(self: *@This()) usize {
        self.c += 1;
        return self.c;
    }

    pub fn get(self: *const @This()) usize {
        return self.c;
    }
};

pub const pi = std.math.pi;
pub const pi_2 = std.math.pi * 2.0;
pub const pi_half = std.math.pi * 0.5;

pub fn degToRad(deg: f32) f32 {
    return deg * pi_2 / 360;
}