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

    /// Uses rotors to rotate the 3d vector around the y axis.
    pub fn rotateY(self: Vec3, rad: f32) Vec3 {
        const half_rad = rad * 0.5;
        const a = Vec3.init(1, 0, 0);
        const b = Vec3.init(std.math.cos(half_rad), 0, std.math.sin(half_rad));
        const ra_dot = a.mul(self.dot(a) * -2);
        const ra = self.add(ra_dot);
        const rb_dot = b.mul(ra.dot(b) * -2);
        const rba = ra.add(rb_dot);
        return rba;
    }

    /// Rotates the vector along an arbitrary axis. Assumes axis vector is normalized.
    pub fn rotateAxis(self: Vec3, axis: Vec3, rad: f32) Vec3 {
        const v_para = axis.mul(self.dot(axis));
        const v_perp = self.add(v_para.mul(-1));
        const v_perp_term = v_perp.mul(std.math.cos(rad));
        const axv_term = axis.cross(self).mul(std.math.sin(rad));
        return Vec3.init(
            v_para.x + v_perp_term.x + axv_term.x,
            v_para.y + v_perp_term.y + axv_term.y,
            v_para.z + v_perp_term.z + axv_term.z,
        );
    }

    pub fn dot(self: Vec3, v: Vec3) f32 {
        return self.x * v.x + self.y * v.y + self.z * v.z;
    }

    pub fn cross(self: Vec3, v: Vec3) Vec3 {
        const x = self.y * v.z - self.z * v.y;
        const y = self.z * v.x - self.x * v.z;
        const z = self.x * v.y - self.y * v.x;
        return Vec3.init(x, y, z);
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        return Vec3.init(self.x / len, self.y / len, self.z / len);
    }

    /// Component multiplication.
    pub fn mul(self: Vec3, s: f32) Vec3 {
        return Vec3.init(self.x * s, self.y * s, self.z * s);
    }

    /// Component addition.
    pub fn add(self: Vec3, v: Vec3) Vec3 {
        return Vec3.init(self.x + v.x, self.y + v.y, self.z + v.z);
    }

    pub fn length(self: Vec3) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
};

test "Vec3.rotateY" {
    const pif = @as(f32, pi);
    // On xz plane.
    var v = Vec3.init(1, 0, 0);
    try eqApproxVec3(v.rotateY(0), Vec3.init(1, 0, 0));
    try eqApproxVec3(v.rotateY(pif*0.5), Vec3.init(0, 0, 1));
    try eqApproxVec3(v.rotateY(pif), Vec3.init(-1, 0, 0));
    try eqApproxVec3(v.rotateY(pif*1.5), Vec3.init(0, 0, -1));

    // Tilted into y.
    v = Vec3.init(1, 1, 0);
    try eqApproxVec3(v.rotateY(0), Vec3.init(1, 1, 0));
    try eqApproxVec3(v.rotateY(pif*0.5), Vec3.init(0, 1, 1));
    try eqApproxVec3(v.rotateY(pif), Vec3.init(-1, 1, 0));
    try eqApproxVec3(v.rotateY(pif*1.5), Vec3.init(0, 1, -1));
}

test "Vec3.rotateAxis" {
    const pif = @as(f32, pi);
    // Rotate from +y toward +z
    var v = Vec3.init(0, 1, 0);
    try eqApproxVec3(v.rotateAxis(Vec3.init(1, 0, 0), 0), Vec3.init(0, 1, 0));
    try eqApproxVec3(v.rotateAxis(Vec3.init(1, 0, 0), pif*0.5), Vec3.init(0, 0, 1));
    try eqApproxVec3(v.rotateAxis(Vec3.init(1, 0, 0), pif), Vec3.init(0, -1, 0));
    try eqApproxVec3(v.rotateAxis(Vec3.init(1, 0, 0), pif*1.5), Vec3.init(0, 0, -1));
}

pub fn eqApproxVec2(act: Vec2, exp: Vec2) !void {
    try t.eqApproxEps(act.x, exp.x);
    try t.eqApproxEps(act.y, exp.y);
}

pub fn eqApproxVec3(act: Vec3, exp: Vec3) !void {
    try t.eqApprox(act.x, exp.x, 1e-4);
    try t.eqApprox(act.y, exp.y, 1e-4);
    try t.eqApprox(act.z, exp.z, 1e-4);
}

pub fn eqApproxVec4(act: Vec4, exp: Vec4) !void {
    try t.eqApprox(act.x, exp.x, 1e-4);
    try t.eqApprox(act.y, exp.y, 1e-4);
    try t.eqApprox(act.z, exp.z, 1e-4);
    try t.eqApprox(act.w, exp.w, 1e-4);
}

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    /// Component division.
    pub fn div(self: Vec4, s: f32) Vec4 {
        return Vec4.init(self.x / s, self.y / s, self.z / s, self.w / s);
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
