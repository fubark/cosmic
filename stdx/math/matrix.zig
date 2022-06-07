const stdx = @import("../stdx.zig");
const t = stdx.testing;
const math = @import("math.zig");
const log = stdx.log.scoped(.matrix);

const Vec4 = [4]f32;

// Row-major order.
pub const Mat4 = [16]f32;

// Because we're using row major order, we prefer to do mat * vec where vec is on the right side.
// In theory it should be faster since more contiguous memory is accessed in order from the bigger matrix on the left.
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
