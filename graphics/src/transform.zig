const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const math = stdx.math;
const Mat4 = math.Mat4;

const Vec4 = [4]f32;

// TODO: Add transform just for 2D coords.

pub const Transform = struct {
    const Self = @This();

    mat: Mat4,

    pub fn initIdentity() Self {
        return .{
            .mat = identity(),
        };
    }

    pub fn initRowMajor(mat: Mat4) Self {
        return .{
            .mat = mat,
        };
    }

    pub fn scale(self: *Self, x: f32, y: f32) void {
        self.mat = math.Mul4x4_4x4(getScaling(x, y), self.mat);
    }

    pub fn translate(self: *Self, x: f32, y: f32) void {
        self.mat = math.Mul4x4_4x4(getTranslation(x, y), self.mat);
    }

    pub fn rotateX(self: *Self, rad: f32) void {
        self.mat = math.Mul4x4_4x4(getRotationX(rad), self.mat);
    }

    pub fn rotateY(self: *Self, rad: f32) void {
        self.mat = math.Mul4x4_4x4(getRotationY(rad), self.mat);
    }

    pub fn rotateZ(self: *Self, rad: f32) void {
        self.mat = math.Mul4x4_4x4(getRotationZ(rad), self.mat);
    }

    pub fn reset(self: *Self) void {
        self.mat = identity();
    }

    pub fn transformPoint(self: *Self, vec: Vec4) Vec4 {
        return math.Mul4x4_4x1(self.mat, vec);
    }
};

pub fn identity() Mat4 {
    return .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

fn getTranslation(x: f32, y: f32) Mat4 {
    return .{
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

fn getRotationX(rad: f32) Mat4 {
    const c = std.math.cos(rad);
    const s = std.math.sin(rad);
    return .{
        1, 0, 0, 0,
        0, c, s, 0,
        0, -s, c, 0,
        0, 0, 0, 1,
    };
}

fn getRotationY(rad: f32) Mat4 {
    const c = std.math.cos(rad);
    const s = std.math.sin(rad);
    return .{
        c, 0, -s, 0,
        0, 1, 0, 0,
        s, 0, c, 0,
        0, 0, 0, 1,
    };
}

fn getRotationZ(rad: f32) Mat4 {
    const c = std.math.cos(rad);
    const s = std.math.sin(rad);
    return .{
        c, -s, 0, 0,
        s, c, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

fn getScaling(x: f32, y: f32) Mat4 {
    return .{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

test "Apply Translation" {
    var transform = Transform.initIdentity();
    transform.translate(10, 10);
    try t.eq(transform.transformPoint(.{ 0, 0, 0, 1 }), .{10, 10, 0, 1});
    try t.eq(transform.transformPoint(.{ 10, 10, 0, 1 }), .{20, 20, 0, 1});
}