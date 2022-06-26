const std = @import("std");

const stdx = @import("../stdx.zig");
const t = stdx.testing;
const math = stdx.math;
const Mat4 = math.Mat4;
const eqApproxVec4 = math.eqApproxVec4;
const eqApproxVec3 = math.eqApproxVec3;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

// Contains abstractions to represent transformations that transforms points from one space to another using matrices and vectors.
// TODO: Add transform just for 2D coords.

pub const Transform = struct {
    mat: Mat4,

    const Self = @This();

    pub fn initZero() Self {
        return .{
            .mat = std.mem.zeroes(Mat4),
        };
    }

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

    /// To RHS.
    pub fn initQuaternion(q: Quaternion) Self {
        const x2 = q.vec.x*q.vec.x;
        const y2 = q.vec.y*q.vec.y;
        const z2 = q.vec.z*q.vec.z;
        const xy = q.vec.x*q.vec.y;
        const yz = q.vec.y*q.vec.z;
        const xz = q.vec.x*q.vec.z;
        const wx = q.vec.w*q.vec.x;
        const wy = q.vec.w*q.vec.y;
        const wz = q.vec.w*q.vec.z;
        return .{
            .mat = .{
                1 - 2 * (y2 + z2), 2 * (xy - wz), 2 * (xz + wy), 0,
                2 * (xy + wz), 1 - 2 * (x2 + z2), 2 * (yz - wx), 0,
                2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (x2 + y2), 0,
                0, 0, 0, 1,
            },
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

    /// Convenience for perspective divide. Performs interpolate and divides result by the last component.
    pub fn interpolate4div(self: Self, x: f32, y: f32, z: f32, w: f32) Vec4 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{x, y, z, w });
        return Vec4{ .x = res[0] / res[3], .y = res[1] / res[3], .z = res[2] / res[3], .w = res[3] / res[3] };
    }

    pub fn interpolate3(self: Self, x: f32, y: f32, z: f32) Vec3 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{x, y, z, 1 });
        return Vec3{ .x = res[0], .y = res[1], .z = res[2] };
    }

    pub fn interpolateVec3(self: Self, vec: Vec3) Vec3 {
        const res = math.mul4x4_4x1(self.mat, [4]f32{vec.x, vec.y, vec.z, 1 });
        return Vec3{ .x = res[0], .y = res[1], .z = res[2] };
    }

    pub fn interpolateVec4(self: Self, vec: Vec4) Vec4 {
        const res = math.mul4x4_4x1(self.mat, .{ vec.x, vec.y, vec.z, vec.w });
        return .{ .x = res[0], .y = res[1], .z = res[2], .w = res[3] };
    }

    /// Useful for getting the normal matrix when the scale is known to be uniform.
    pub fn toRotationUniformScaleMat(self: Self) stdx.math.Mat3 {
        return .{
            self.mat[0], self.mat[1], self.mat[2],
            self.mat[4], self.mat[5], self.mat[6],
            self.mat[8], self.mat[9], self.mat[10],
        };
    }

    pub fn toRotationMat(self: Self) stdx.math.Mat3 {
        const mat = self.toRotationUniformScaleMat();
        var inverted: stdx.math.Mat3 = undefined;
        _ = stdx.math.invert3x3(mat, &inverted);
        return stdx.math.transpose3x3(inverted);
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

pub const Quaternion = struct {
    /// Unit quaternion.
    vec: Vec4,

    pub fn init(vec: Vec4) Quaternion {
        return .{
            .vec = vec,
        };
    }

    pub fn rotate(self: Quaternion, v: Vec3) Vec3 {
        const q = Vec3.init(self.vec.x, self.vec.y, self.vec.z);
        const qdotq = q.dot(q);
        const qdotv = q.dot(v);
        const cross = q.cross(v);
        const ww = self.w * self.w;
        const w2 = self.w * 2;
        return .{
            .x = v.x * (ww - qdotq.x) + self.x * qdotv.x * 2 + cross.x * w2,
            .y = v.y * (ww - qdotq.y) + self.y * qdotv.y * 2 + cross.y * w2,
            .z = v.z * (ww - qdotq.z) + self.z * qdotv.z * 2 + cross.z * w2,
        };
    }

    /// Spherical Linear Interpolation
    /// https://www.khronos.org/registry/glTF/specs/2.0/glTF-2.0.html#interpolation-slerp
    pub fn slerp(self: Quaternion, to: Quaternion, tt: f32) Quaternion {
        const d = self.dot(to);
        const adot = std.math.fabs(d);
        const a = std.math.acos(adot);
        if (adot >= 1) {
            // Prevent divide by 0 from sin(a).
            return self;
        }
        const s = d/adot;

        const from_vec = self.vec.mul(std.math.sin(a * (1-tt))/std.math.sin(a));
        const to_vec = to.vec.mul(s * std.math.sin(a * tt)/std.math.sin(a));
        return .{
            .vec = from_vec.add(to_vec),
        };
    }

    pub fn dot(self: Quaternion, q: Quaternion) f32 {
        return self.vec.dot(q.vec);
    }

    pub fn mul(self: Quaternion, q: Quaternion) Quaternion {
        return Quaternion{
            .vec = .{
                .x = self.vec.w * q.vec.x + self.vec.x * q.vec.w + self.vec.y * q.vec.z - self.vec.z * q.vec.y,
                .y = self.vec.w * q.vec.y - self.vec.x * q.vec.z + self.vec.y * q.vec.w + self.vec.z * q.vec.x,
                .z = self.vec.w * q.vec.z + self.vec.x * q.vec.y - self.vec.y * q.vec.x + self.vec.z * q.vec.w,
                .w = self.vec.w * q.vec.w - self.vec.x * q.vec.x - self.vec.y * q.vec.y - self.vec.z * q.vec.z,
            },
        };
    }
};

test "Quaternion.slerp" {
    // slerp with self.
    try eqApproxVec4(Quaternion.init(Vec4.init(0, 0, 0, 1)).slerp(Quaternion.init(Vec4.init(0, 0, 0, 1)), 0).vec, Vec4.init(0, 0, 0, 1));
}

test "Extracting rotate + uniform scale matrix from transform matrix." {
    var xform = Transform.initIdentity();
    xform.rotateY(std.math.pi/2.0);

    const pos = Vec3.init(1, 0, 0);
    try eqApproxVec3(xform.interpolateVec3(pos), Vec3.init(0, 0, 1));

    const mat = xform.toRotationUniformScaleMat();
    const res = stdx.math.mul3x3_3x1(mat, .{pos.x, pos.y, pos.z});
    try eqApproxVec3(Vec3.init(res[0], res[1], res[2]), Vec3.init(0, 0, 1));
}