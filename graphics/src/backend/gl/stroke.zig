const std = @import("std");
const math = std.math;
const stdx = @import("stdx");
const t = stdx.testing;
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;
const graphics = @import("../../graphics.zig");
const QuadBez = graphics.curve.QuadBez;
const SubQuadBez = graphics.curve.SubQuadBez;
const CubicBez = graphics.curve.CubicBez;
const Color = graphics.Color;
const Mesh = @import("mesh.zig").Mesh;
const TexShaderVertex = @import("mesh.zig").TexShaderVertex;
const Graphics = @import("graphics.zig").Graphics;

const log = std.log.scoped(.stroke);

/// Given quadratic bezier curve, generate triangles along the inner and outer offset paths.
pub fn strokeQuadBez(mesh: *Mesh, buf: *std.ArrayList(Vec2), q_bez: QuadBez, half_width: f32, color: Color) void {
    q_bez.flatten(0.5, buf);
    strokePath(mesh, buf.items, half_width, color);
}

/// Given cubic bezier curve, generate triangles along the inner and outer offset paths.
pub fn strokeCubicBez(mesh: *Mesh, buf: *std.ArrayList(Vec2), qbez_buf: *std.ArrayList(SubQuadBez), c_bez: CubicBez, half_width: f32, color: Color) void {
    c_bez.flatten(0.5, buf, qbez_buf);
    strokePath(mesh, buf.items, half_width, color);
}

fn strokePath(mesh: *Mesh, pts: []const Vec2, half_width: f32, color: Color) void {
    var vert: TexShaderVertex = undefined;
    vert.setUV(0, 0);
    vert.setColor(color);

    var last_uvec = Vec2.initTo(pts[0], pts[1]).normalize();
    var i: u32 = 0;
    while (i < pts.len - 1) : (i += 1) {
        const uvec = Vec2.initTo(pts[i], pts[i+1]).normalize();
        const right_off_nvec = computeOffsetNormal(last_uvec, uvec).mul(half_width);
        const right_pt = pts[i].add(right_off_nvec);
        const left_pt = pts[i].add(right_off_nvec.neg());
        const pt = pts[i];

        const start_idx = mesh.getNextIndexId();
        vert.setXY(left_pt.x, left_pt.y);
        _ = mesh.addVertex(&vert);
        vert.setXY(pt.x, pt.y);
        _ = mesh.addVertex(&vert);
        vert.setXY(right_pt.x, right_pt.y);
        _ = mesh.addVertex(&vert);

        // Left side quad.
        mesh.addQuad(start_idx, start_idx + 1, start_idx + 4, start_idx + 3);
        // Right side quad.
        mesh.addQuad(start_idx+1, start_idx + 2, start_idx + 5, start_idx + 4);
        last_uvec = uvec;
    }
    {
        const uvec = last_uvec;
        const right_off_nvec = computeOffsetNormal(last_uvec, uvec).mul(half_width);
        const right_pt = pts[i].add(right_off_nvec);
        const left_pt = pts[i].add(right_off_nvec.neg());
        const pt = pts[i];

        vert.setXY(left_pt.x, left_pt.y);
        _ = mesh.addVertex(&vert);
        vert.setXY(pt.x, pt.y);
        _ = mesh.addVertex(&vert);
        vert.setXY(right_pt.x, right_pt.y);
        _ = mesh.addVertex(&vert);
    }
}

/// Compute a normal vector at point P where --v1--> P --v2-->
/// The resulting vector is not normalized, rather the length is such that extruding the shape
/// would yield parallel segments exactly 1 unit away from v1 and v2. (useful for generating strokes and vertex-aa).
/// The normal points towards the positive side of v1.
/// v1 and v2 are expected to be normalized.
pub fn computeOffsetNormal(v1: Vec2, v2: Vec2) Vec2 {
    const epsilon = 1e-4;

    const v12 = v1.add(v2);
    if (v12.squareLength() < epsilon) {
        return vec2(0, 0);
    }

    const tangent = v12.normalize();
    const n = vec2(-tangent.y, tangent.x);
    const n1 = vec2(-v1.y, v1.x);
    const inv_len = n.dot(n1);

    if (@fabs(inv_len) < epsilon) {
        return n1;
    }
    return n.div(inv_len);
}

test "computeOffsetNormal" {
    try t.eq(computeOffsetNormal(vec2(1, 0), vec2(-1, 0)), vec2(0, 0));
    try t.eq(computeOffsetNormal(vec2(1, 0), vec2(0, 1)), vec2(-1, 1));
    try t.eq(computeOffsetNormal(vec2(1, 0), vec2(0, -1)), vec2(1, 1));
    try t.eq(computeOffsetNormal(vec2(1, 0), vec2(1, 0)), vec2(0, 1));
    try t.eq(computeOffsetNormal(vec2(1, 0), vec2(1, 0)), vec2(0, 1));
}