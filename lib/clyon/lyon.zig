const math = @import("stdx").math;

const c = @cImport({
    @cInclude("clyon.h");
});

pub fn init() void {
    c.lyon_init();
}

pub fn deinit() void {
    c.lyon_deinit();
}

pub fn initPt(x: f32, y: f32) c.LyonPoint {
    return c.LyonPoint{ .x = x, .y = y };
}

pub fn initBuilder() *c.LyonBuilder {
    return c.lyon_new_builder() orelse unreachable;
}

pub fn begin(b: *c.LyonBuilder, pt: *c.LyonPoint) void {
    c.lyon_begin(b, pt);
}

pub fn lineTo(b: *c.LyonBuilder, pt: *c.LyonPoint) void {
    c.lyon_line_to(b, pt);
}

pub fn quadraticBezierTo(b: *c.LyonBuilder, ctrl_pt: *c.LyonPoint, pt: *c.LyonPoint) void {
    c.lyon_quadratic_bezier_to(b, ctrl_pt, pt);
}

pub fn cubicBezierTo(b: *c.LyonBuilder, ca_pt: *c.LyonPoint, cb_pt: *c.LyonPoint, pt: *c.LyonPoint) void {
    c.lyon_cubic_bezier_to(b, ca_pt, cb_pt, pt);
}

// End must close a path. In some cases it may appear to work without it, but you can tell the end points are not completely tesselated.
pub fn end(b: *c.LyonBuilder, closed: bool) void {
    c.lyon_end(b, closed);
}

pub fn close(b: *c.LyonBuilder) void {
    c.lyon_end(b, true);
}

pub fn buildStroke(b: *c.LyonBuilder, line_width: f32) c.LyonVertexData {
    return c.lyon_build_stroke(b, line_width);
}

pub fn buildFill(b: *c.LyonBuilder) c.LyonVertexData {
    return c.lyon_build_fill(b);
}

pub fn addRectangle(b: *c.LyonBuilder, rect: *c.LyonRect) void {
    c.lyon_add_rectangle(b, rect);
}

pub fn addPolygon(b: *c.LyonBuilder, pts: []const math.Vec2, closed: bool) void {
    // Since vec2 is the same as LyonPoint just cast instead of copy.
    c.lyon_add_polygon(b, @ptrCast([*c]const c.LyonPoint, pts), pts.len, closed);
}

pub const VertexData = c.LyonVertexData;