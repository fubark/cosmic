const stdx = @import("../stdx.zig");
const t = stdx.testing;
const math = @import("math.zig");
const log = stdx.log.scoped(.matrix);

const Vec4 = [4]f32;
const Vec3 = [3]f32;

/// Row-major order.
pub const Mat3 = [9]f32;

pub fn mul3x3_3x1(a: Mat3, b: Vec3) Vec3 {
    const stride = 3;
    const r0 = 0 * stride;
    const r1 = 1 * stride;
    const r2 = 2 * stride;
    const a00 = a[r0 + 0];
    const a01 = a[r0 + 1];
    const a02 = a[r0 + 2];
    const a10 = a[r1 + 0];
    const a11 = a[r1 + 1];
    const a12 = a[r1 + 2];
    const a20 = a[r2 + 0];
    const a21 = a[r2 + 1];
    const a22 = a[r2 + 2];
    const b00 = b[0];
    const b10 = b[1];
    const b20 = b[2];
    return .{
        a00 * b00 + a01 * b10 + a02 * b20,
        a10 * b00 + a11 * b10 + a12 * b20,
        a20 * b00 + a21 * b10 + a22 * b20,
    };
}

pub fn mul3x3_3x3(a: Mat3, b: Mat3) Mat3 {
    const stride = 3;
    const r0 = 0 * stride;
    const r1 = 1 * stride;
    const r2 = 2 * stride;
    const a00 = a[r0 + 0];
    const a01 = a[r0 + 1];
    const a02 = a[r0 + 2];
    const a10 = a[r1 + 0];
    const a11 = a[r1 + 1];
    const a12 = a[r1 + 2];
    const a20 = a[r2 + 0];
    const a21 = a[r2 + 1];
    const a22 = a[r2 + 2];
    const b00 = b[r0 + 0];
    const b01 = b[r0 + 1];
    const b02 = b[r0 + 2];
    const b10 = b[r1 + 0];
    const b11 = b[r1 + 1];
    const b12 = b[r1 + 2];
    const b20 = b[r2 + 0];
    const b21 = b[r2 + 1];
    const b22 = b[r2 + 2];
    return .{
        // First row.
        a00 * b00 + a01 * b10 + a02 * b20,
        a00 * b01 + a01 * b11 + a02 * b21,
        a00 * b02 + a01 * b12 + a02 * b22,

        a10 * b00 + a11 * b10 + a12 * b20,
        a10 * b01 + a11 * b11 + a12 * b21,
        a10 * b02 + a11 * b12 + a12 * b22,

        a20 * b00 + a21 * b10 + a22 * b20,
        a20 * b01 + a21 * b11 + a22 * b21,
        a20 * b02 + a21 * b12 + a22 * b22,
    };
}

/// Row-major order.
pub const Mat4 = [16]f32;

// TODO: Is (4x4)(4x1) faster than (1x4)(4x4) for row major order?
pub fn mul4x4_4x1(a: Mat4, b: Vec4) Vec4 {
    const stride = 4;
    const r0 = 0 * stride;
    const r1 = 1 * stride;
    const r2 = 2 * stride;
    const r3 = 3 * stride;
    const a00 = a[r0 + 0];
    const a01 = a[r0 + 1];
    const a02 = a[r0 + 2];
    const a03 = a[r0 + 3];
    const a10 = a[r1 + 0];
    const a11 = a[r1 + 1];
    const a12 = a[r1 + 2];
    const a13 = a[r1 + 3];
    const a20 = a[r2 + 0];
    const a21 = a[r2 + 1];
    const a22 = a[r2 + 2];
    const a23 = a[r2 + 3];
    const a30 = a[r3 + 0];
    const a31 = a[r3 + 1];
    const a32 = a[r3 + 2];
    const a33 = a[r3 + 3];
    const b00 = b[0];
    const b10 = b[1];
    const b20 = b[2];
    const b30 = b[3];
    return .{
        a00 * b00 + a01 * b10 + a02 * b20 + a03 * b30,
        a10 * b00 + a11 * b10 + a12 * b20 + a13 * b30,
        a20 * b00 + a21 * b10 + a22 * b20 + a23 * b30,
        a30 * b00 + a31 * b10 + a32 * b20 + a33 * b30,
    };
}

pub fn mul4x4_4x4(a: Mat4, b: Mat4) Mat4 {
    const stride = 4;
    const r0 = 0 * stride;
    const r1 = 1 * stride;
    const r2 = 2 * stride;
    const r3 = 3 * stride;
    const a00 = a[r0 + 0];
    const a01 = a[r0 + 1];
    const a02 = a[r0 + 2];
    const a03 = a[r0 + 3];
    const a10 = a[r1 + 0];
    const a11 = a[r1 + 1];
    const a12 = a[r1 + 2];
    const a13 = a[r1 + 3];
    const a20 = a[r2 + 0];
    const a21 = a[r2 + 1];
    const a22 = a[r2 + 2];
    const a23 = a[r2 + 3];
    const a30 = a[r3 + 0];
    const a31 = a[r3 + 1];
    const a32 = a[r3 + 2];
    const a33 = a[r3 + 3];
    const b00 = b[r0 + 0];
    const b01 = b[r0 + 1];
    const b02 = b[r0 + 2];
    const b03 = b[r0 + 3];
    const b10 = b[r1 + 0];
    const b11 = b[r1 + 1];
    const b12 = b[r1 + 2];
    const b13 = b[r1 + 3];
    const b20 = b[r2 + 0];
    const b21 = b[r2 + 1];
    const b22 = b[r2 + 2];
    const b23 = b[r2 + 3];
    const b30 = b[r3 + 0];
    const b31 = b[r3 + 1];
    const b32 = b[r3 + 2];
    const b33 = b[r3 + 3];
    return .{
        // First row.
        a00 * b00 + a01 * b10 + a02 * b20 + a03 * b30,
        a00 * b01 + a01 * b11 + a02 * b21 + a03 * b31,
        a00 * b02 + a01 * b12 + a02 * b22 + a03 * b32,
        a00 * b03 + a01 * b13 + a02 * b23 + a03 * b33,

        a10 * b00 + a11 * b10 + a12 * b20 + a13 * b30,
        a10 * b01 + a11 * b11 + a12 * b21 + a13 * b31,
        a10 * b02 + a11 * b12 + a12 * b22 + a13 * b32,
        a10 * b03 + a11 * b13 + a12 * b23 + a13 * b33,

        a20 * b00 + a21 * b10 + a22 * b20 + a23 * b30,
        a20 * b01 + a21 * b11 + a22 * b21 + a23 * b31,
        a20 * b02 + a21 * b12 + a22 * b22 + a23 * b32,
        a20 * b03 + a21 * b13 + a22 * b23 + a23 * b33,

        a30 * b00 + a31 * b10 + a32 * b20 + a33 * b30,
        a30 * b01 + a31 * b11 + a32 * b21 + a33 * b31,
        a30 * b02 + a31 * b12 + a32 * b22 + a33 * b32,
        a30 * b03 + a31 * b13 + a32 * b23 + a33 * b33,
    };
}

pub fn transpose3x3(m: Mat3) Mat3 {
    return .{
        m[0], m[3], m[6],
        m[1], m[4], m[7],
        m[2], m[5], m[8],
    };
}

test "transpose3x3" {
    const m = Mat3{
        0, 1, 2,
        3, 4, 5,
        6, 7, 8,
    };
    const mt = transpose3x3(m);
    try t.eq(mt, .{
        0, 3, 6, 
        1, 4, 7,
        2, 5, 8,
    });
    const mtt = transpose3x3(mt);
    try t.eq(mtt, m);
}

pub fn transpose4x4(m: Mat4) Mat4 {
    return .{
        m[0], m[4], m[8], m[12],
        m[1], m[5], m[9], m[13],
        m[2], m[6], m[10], m[14],
        m[3], m[7], m[11], m[15],
    };
}

test "transpose4x4" {
    const m = Mat4{
        0, 1, 2, 3,
        4, 5, 6, 7,
        8, 9, 10, 11,
        12, 13, 14, 15, 
    };
    const mt = transpose4x4(m);
    try t.eq(mt, .{
        0, 4, 8, 12,
        1, 5, 9, 13,
        2, 6, 10, 14,
        3, 7, 11, 15,
    });
    const mtt = transpose4x4(mt);
    try t.eq(mtt, m);
}

pub fn invert3x3(m: Mat3, out: *Mat3) bool {
    var inv: [9]f32 = undefined;

    inv[0] = m[4]*m[8] - m[5]*m[7];
    inv[1] = m[2]*m[7] - m[1]*m[8];
    inv[2] = m[1]*m[5] - m[2]*m[4];
    inv[3] = m[5]*m[6] - m[3]*m[8];
    inv[4] = m[0]*m[8] - m[2]*m[6];
    inv[5] = m[2]*m[3] - m[0]*m[5];
    inv[6] = m[3]*m[7] - m[4]*m[6];
    inv[7] = m[1]*m[6] - m[0]*m[7];
    inv[8] = m[0]*m[4] - m[1]*m[3];

    var det = m[0]*inv[0] + m[1]*inv[3] + m[2]*inv[6];
    if (det == 0) {
        return false;
    }
    det = 1.0 / det;

    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        out.*[i] = inv[i] * det;
    }
    return true;
}

test "invert3x3" {
    const a = Mat3{
        0, -3, -2,
        1, -4, -2,
        -3, 4, 1,
    };
    var inv: Mat3 = undefined;
    try t.eq(invert3x3(a, &inv), true);

    const exp = Mat3{
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    };
    const act = mul3x3_3x3(inv, a);
    for (act, 0..) |it, i| {
        try t.eqApproxEps(it, exp[i]);
    }
}

/// From Mesa's implementation of GLU.
/// https://stackoverflow.com/questions/1148309/inverting-a-4x4-matrix
pub fn invert4x4(m: Mat4, out: *Mat4) bool {
    var inv: [16]f32 = undefined;

    inv[0] = m[5]  * m[10] * m[15] - 
             m[5]  * m[11] * m[14] - 
             m[9]  * m[6]  * m[15] + 
             m[9]  * m[7]  * m[14] +
             m[13] * m[6]  * m[11] - 
             m[13] * m[7]  * m[10];

    inv[4] = -m[4]  * m[10] * m[15] + 
              m[4]  * m[11] * m[14] + 
              m[8]  * m[6]  * m[15] - 
              m[8]  * m[7]  * m[14] - 
              m[12] * m[6]  * m[11] + 
              m[12] * m[7]  * m[10];

    inv[8] = m[4]  * m[9] * m[15] - 
             m[4]  * m[11] * m[13] - 
             m[8]  * m[5] * m[15] + 
             m[8]  * m[7] * m[13] + 
             m[12] * m[5] * m[11] - 
             m[12] * m[7] * m[9];

    inv[12] = -m[4]  * m[9] * m[14] + 
               m[4]  * m[10] * m[13] +
               m[8]  * m[5] * m[14] - 
               m[8]  * m[6] * m[13] - 
               m[12] * m[5] * m[10] + 
               m[12] * m[6] * m[9];

    inv[1] = -m[1]  * m[10] * m[15] + 
              m[1]  * m[11] * m[14] + 
              m[9]  * m[2] * m[15] - 
              m[9]  * m[3] * m[14] - 
              m[13] * m[2] * m[11] + 
              m[13] * m[3] * m[10];

    inv[5] = m[0]  * m[10] * m[15] - 
             m[0]  * m[11] * m[14] - 
             m[8]  * m[2] * m[15] + 
             m[8]  * m[3] * m[14] + 
             m[12] * m[2] * m[11] - 
             m[12] * m[3] * m[10];

    inv[9] = -m[0]  * m[9] * m[15] + 
              m[0]  * m[11] * m[13] + 
              m[8]  * m[1] * m[15] - 
              m[8]  * m[3] * m[13] - 
              m[12] * m[1] * m[11] + 
              m[12] * m[3] * m[9];

    inv[13] = m[0]  * m[9] * m[14] - 
              m[0]  * m[10] * m[13] - 
              m[8]  * m[1] * m[14] + 
              m[8]  * m[2] * m[13] + 
              m[12] * m[1] * m[10] - 
              m[12] * m[2] * m[9];

    inv[2] = m[1]  * m[6] * m[15] - 
             m[1]  * m[7] * m[14] - 
             m[5]  * m[2] * m[15] + 
             m[5]  * m[3] * m[14] + 
             m[13] * m[2] * m[7] - 
             m[13] * m[3] * m[6];

    inv[6] = -m[0]  * m[6] * m[15] + 
              m[0]  * m[7] * m[14] + 
              m[4]  * m[2] * m[15] - 
              m[4]  * m[3] * m[14] - 
              m[12] * m[2] * m[7] + 
              m[12] * m[3] * m[6];

    inv[10] = m[0]  * m[5] * m[15] - 
              m[0]  * m[7] * m[13] - 
              m[4]  * m[1] * m[15] + 
              m[4]  * m[3] * m[13] + 
              m[12] * m[1] * m[7] - 
              m[12] * m[3] * m[5];

    inv[14] = -m[0]  * m[5] * m[14] + 
               m[0]  * m[6] * m[13] + 
               m[4]  * m[1] * m[14] - 
               m[4]  * m[2] * m[13] - 
               m[12] * m[1] * m[6] + 
               m[12] * m[2] * m[5];

    inv[3] = -m[1] * m[6] * m[11] + 
              m[1] * m[7] * m[10] + 
              m[5] * m[2] * m[11] - 
              m[5] * m[3] * m[10] - 
              m[9] * m[2] * m[7] + 
              m[9] * m[3] * m[6];

    inv[7] = m[0] * m[6] * m[11] - 
             m[0] * m[7] * m[10] - 
             m[4] * m[2] * m[11] + 
             m[4] * m[3] * m[10] + 
             m[8] * m[2] * m[7] - 
             m[8] * m[3] * m[6];

    inv[11] = -m[0] * m[5] * m[11] + 
               m[0] * m[7] * m[9] + 
               m[4] * m[1] * m[11] - 
               m[4] * m[3] * m[9] - 
               m[8] * m[1] * m[7] + 
               m[8] * m[3] * m[5];

    inv[15] = m[0] * m[5] * m[10] - 
              m[0] * m[6] * m[9] - 
              m[4] * m[1] * m[10] + 
              m[4] * m[2] * m[9] + 
              m[8] * m[1] * m[6] - 
              m[8] * m[2] * m[5];

    var det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];

    if (det == 0) {
        return false;
    }
    det = 1.0 / det;

    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        out.*[i] = inv[i] * det;
    }
    return true;
}

test "invert4x4" {
    const a = Mat4{
        5, 2, 6, 2,
        6, 2, 6, 3,
        6, 2, 2, 6,
        8, 8, 8, 7,
    };
    var inv: Mat4 = undefined;
    try t.eq(invert4x4(a, &inv), true);

    const exp = Mat4{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
    const act = mul4x4_4x4(inv, a);
    for (act, 0..) |it, i| {
        try t.eqApproxEps(it, exp[i]);
    }
}