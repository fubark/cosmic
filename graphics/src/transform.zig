const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const math = stdx.math;
const Mat4 = math.Mat4;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

// TODO: Add transform just for 2D coords.

pub const Transform = struct {
    mat: Mat4,

    const Self = @This();

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

    pub fn getAppliedTransform(self: Transform, transform: Transform) Self {
        return .{
            .mat = math.mul4x4_4x4(transform.mat, self.mat),
        };
    }

    pub fn applyTransform(self: *Self, transform: Transform) void {
        self.mat = math.mul4x4_4x4(transform.mat, self.mat);
    }

    pub fn invert(self: *Self) bool {
        var res: Mat4 = undefined;
        if (!math.invert4x4(self.mat, &res)) {
            return false;
        }
        self.mat = res;
        return true;
    }

    pub fn scale(self: *Self, x: f32, y: f32) void {
        self.mat = math.mul4x4_4x4(getScaling(x, y), self.mat);
    }

    pub fn scale3D(self: *Self, x: f32, y: f32, z: f32) void {
        self.mat = math.mul4x4_4x4(getScaling3D(x, y, z), self.mat);
    }

    pub fn translate(self: *Self, x: f32, y: f32) void {
        self.mat = math.mul4x4_4x4(getTranslation(x, y), self.mat);
    }

    pub fn translate3D(self: *Self, x: f32, y: f32, z: f32) void {
        self.mat = math.mul4x4_4x4(getTranslation3D(x, y, z), self.mat);
    }

    pub fn translateVec3D(self: *Self, vec: Vec3) void {
        self.mat = math.mul4x4_4x4(getTranslation3D(vec.x, vec.y, vec.z), self.mat);
    }

    pub fn rotate3D(self: *Self, xvec: Vec3, yvec: Vec3, zvec: Vec3) void {
        self.mat = math.mul4x4_4x4(getRotation3D(xvec, yvec, zvec), self.mat);
    }

    pub fn rotateX(self: *Self, rad: f32) void {
        self.mat = math.mul4x4_4x4(getRotationX(rad), self.mat);
    }

    pub fn rotateY(self: *Self, rad: f32) void {
        self.mat = math.mul4x4_4x4(getRotationY(rad), self.mat);
    }

    pub fn rotateZ(self: *Self, rad: f32) void {
        self.mat = math.mul4x4_4x4(getRotationZ(rad), self.mat);
    }

    pub fn reset(self: *Self) void {
        self.mat = identity();
    }

    pub fn interpolatePt(self: Self, vec: Vec2) Vec2 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{vec.x, vec.y, 0, 1 });
        return Vec2.init(res[0], res[1]);
    }

    pub fn interpolate4(self: Self, x: f32, y: f32, z: f32, w: f32) Vec4 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{x, y, z, w });
        return Vec4{ .x = res[0], .y = res[1], .z = res[2], .w = res[3] };
    }

    pub fn interpolateVec3(self: Self, vec: Vec3) Vec3 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{vec.x, vec.y, vec.z, 1 });
        return Vec3{ .x = res[0], .y = res[1], .z = res[2] };
    }

    pub fn interpolateVec4(self: Self, vec: Vec4) Vec4 {
        const res = math.mul4x4_4x1(self.mat, .{ vec.x, vec.y, vec.z, vec.w });
        return .{ .x = res[0], .y = res[1], .z = res[2], .w = res[3] };
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

fn getTranslation3D(x: f32, y: f32, z: f32) Mat4 {
    return .{
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    };
}

fn getRotation3D(xvec: Vec3, yvec: Vec3, zvec: Vec3) Mat4 {
    return .{
        xvec.x, xvec.y, xvec.z, 0,
        yvec.x, yvec.y, yvec.z, 0,
        zvec.x, zvec.y, zvec.z, 0,
        0, 0, 0, 1,
    };
}

fn getRotationX(rad: f32) Mat4 {
    const c = @cos(rad);
    const s = @sin(rad);
    return .{
        1, 0,  0, 0,
        0, c,  s, 0,
        0, -s, c, 0,
        0, 0,  0, 1,
    };
}

fn getRotationY(rad: f32) Mat4 {
    const c = @cos(rad);
    const s = @sin(rad);
    return .{
        c, 0, -s, 0,
        0, 1, 0,  0,
        s, 0, c,  0,
        0, 0, 0,  1,
    };
}

fn getRotationZ(rad: f32) Mat4 {
    const c = @cos(rad);
    const s = @sin(rad);
    return .{
        c, -s, 0, 0,
        s, c,  0, 0,
        0, 0,  1, 0,
        0, 0,  0, 1,
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

fn getScaling3D(x: f32, y: f32, z: f32) Mat4 {
    return .{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, z, 0,
        0, 0, 0, 1,
    };
}

test "Interpolate" {
    var transform = Transform.initIdentity();
    transform.translate(10, 10);
    try t.eq(transform.interpolateVec4(Vec4.init(0, 0, 0, 1)), Vec4.init(10, 10, 0, 1));
    try t.eq(transform.interpolateVec4(Vec4.init(10, 10, 0, 1)), Vec4.init(20, 20, 0, 1));
}
