const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const math = std.math;

pub const QuadBez = struct {
    const Self = @This();

    const BasicTransform = struct {
        x0: f32,
        x1: f32,
        scale: f32,
        cross: f32,
    };

    x0: f32,
    y0: f32,
    cx: f32,
    cy: f32,
    x1: f32,
    y1: f32,

    /// Return transform values to map from the quadratic bezier to the basic parabola.
    fn mapToBasic(self: Self) BasicTransform {
        const ddx = 2 * self.cx - self.x0 - self.x1;
        const ddy = 2 * self.cy - self.y0 - self.y1;
        const r0 = (self.cx - self.x0) * ddx + (self.cy - self.y0) * ddy;
        const r1 = (self.x1 - self.cx) * ddx + (self.y1 - self.cy) * ddy;
        const cross = (self.x1 - self.x0) * ddy - (self.y1 - self.y0) * ddx;
        const x0 = r0 / cross;
        const x1 = r1 / cross;
        // There's probably a more elegant formulation of this...
        const scale = math.absFloat(cross) / (math.hypot(f32, ddx, ddy) * math.absFloat(x1 - x0));
        return BasicTransform{
            .x0 = x0,
            .x1 = x1,
            .scale = scale,
            .cross = cross,
        };
    }

    /// Given t, return the (x, y) along the curve.
    pub fn eval(self: Self, t: f32) Vec2 {
        const mt = 1 - t;
        const x = self.x0 * mt * mt + 2 * self.cx * t * mt + self.x1 * t * t;
        const y = self.y0 * mt * mt + 2 * self.cy * t * mt + self.y1 * t * t;
        return Vec2.init(x, y);
    }

    /// Given error tolerance, output the minimum points needed to flatten the curve.
    /// The algorithm was developed by Raph Levien.
    /// This has an advantage over other methods since it determines the t values beforehand
    /// so that each t value can be evaluated in parallel, although the implementation is not taking advantage of that right now.
    pub fn flatten(self: Self, tol: f32, buf: *std.ArrayList(Vec2)) void {
        const params = self.mapToBasic();
        const a0 = approx_myint(params.x0);
        const a1 = approx_myint(params.x1);
        var count =  0.5 * math.absFloat(a1 - a0) * math.sqrt(params.scale / tol);
        // If count is NaN the curve can be approximated by a single straight line or a point.
        if (!math.isFinite(count)) {
            count = 1;
        }
        const n = @floatToInt(u32, math.ceil(count));
        buf.ensureTotalCapacity(n) catch unreachable;
        buf.items.len = n + 1;
        const r0 = approx_inv_myint(a0);
        const r1 = approx_inv_myint(a1);
        buf.items[0] = self.eval(0);
        var i: u32 = 1;
        while (i < n) : (i += 1) {
            const r = approx_inv_myint(a0 + ((a1 - a0) * @intToFloat(f32, i)) / @intToFloat(f32, n));
            const t = (r - r0) / (r1 - r0);
            buf.items[i] = self.eval(t);
        }
        buf.items[n] = self.eval(1);
    }
};

// Compute an approximation to int (1 + 4x^2) ^ -0.25 dx
// This isn't especially good but will do.
fn approx_myint(x: f32) f32 {
    const d = 0.67;
    return x / (1 - d + math.pow(f32, math.pow(f32, d, 4) + 0.25 * x * x, 0.25));
}

// Approximate the inverse of the function above.
// This is better.
fn approx_inv_myint(x: f32) f32 {
    const b = 0.39;
    return x * (1 - b + math.sqrt(b * b + 0.25 * x * x));
}

pub const CubicBez = struct {
    x0: f32,
    y0: f32,
    cx0: f32,
    cy0: f32,
    cx1: f32,
    cy1: f32,
    x1: f32,
    y1: f32,
};