const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;

/// Given a y-monotone polygon, compute the triangles that would fit the polygon.
pub fn triangulatePolygon(polygon: []const Vec2, out: *std.ArrayList([3]Vec2)) void {
    _ = out;
    _ = polygon;

    // TODO: Port over code from graphics/src/x/tessellator.js

    // out.clearRetainingCapacity();

    // out.append(tri(vec2(0, 0), vec2(0, 0), vec2(0, 0))) catch unreachable;
}

// TODO: port over test cases from graphics/src/x/tessellator.js
test {
    var out = std.ArrayList([3]Vec2).init(t.alloc);
    defer out.deinit();
}

fn tri(p1: Vec2, p2: Vec2, p3: Vec2) [3]Vec2 {
    return .{ p1, p2, p3 };
}