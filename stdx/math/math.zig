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

        pub fn init(x: T, y: T) @This() {
            return .{
                .x = x,
                .y = y,
            };
        }
    };
}

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }
};

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
        return .{ .x = x, .y = y };
    }

    pub fn initTo(from: Vec2, to: Vec2) Self {
        return .{ .x = to.x - from.x, .y = to.y - from.y };
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

    /// Cross product.
    /// Useful for determining the z direction.
    pub fn cross(self: Self, v: Vec2) f32 {
        return self.x * v.y - self.y * v.x;
    }

    /// Component addition.
    pub fn add(self: Self, v: Vec2) Vec2 {
        return vec2(self.x + v.x, self.y + v.y);
    }

    /// Dot product.
    pub fn dot(self: Self, v: Vec2) f32 {
        return self.x * v.x + self.y * v.y;
    }

    /// Component multiplication.
    pub fn mul(self: Self, s: f32) Vec2 {
        return Self.init(self.x * s, self.y * s);
    }

    /// Component division.
    pub fn div(self: Self, s: f32) Vec2 {
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
