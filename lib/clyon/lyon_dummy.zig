const math = @import("stdx").math;

const c = @cImport({
    @cInclude("clyon.h");
});

pub fn init() void {}

pub fn initBuilder() *c.LyonBuilder {
    return undefined;
}

pub fn deinit() void {}

pub fn initPt(x: f32, y: f32) c.LyonPoint {
    _ = x;
    _ = y;
    return undefined;
}

pub fn begin(b: *c.LyonBuilder, pt: *c.LyonPoint) void {
    _ = b;
    _ = pt;
}

pub fn end(b: *c.LyonBuilder, closed: bool) void {
    _ = b;
    _ = closed;
}

pub fn close(b: *c.LyonBuilder) void {
    _ = b;
}

pub fn lineTo(b: *c.LyonBuilder, pt: *c.LyonPoint) void {
    _ = b;
    _ = pt;
}

pub fn addPolygon(b: *c.LyonBuilder, pts: []const math.Vec2, closed: bool) void {
    _ = b;
    _ = pts;
    _ = closed;
}

pub fn buildStroke(b: *c.LyonBuilder, line_width: f32) c.LyonVertexData {
    _ = b;
    _ = line_width;
    return undefined;
}

pub fn buildFill(b: *c.LyonBuilder) c.LyonVertexData {
    _ = b;
    return undefined;
}

pub fn quadraticBezierTo(b: *c.LyonBuilder, ctrl_pt: *c.LyonPoint, pt: *c.LyonPoint) void {
    _ = b;
    _ = ctrl_pt;
    _ = pt;
}

pub fn cubicBezierTo(b: *c.LyonBuilder, ca_pt: *c.LyonPoint, cb_pt: *c.LyonPoint, pt: *c.LyonPoint) void {
    _ = b;
    _ = ca_pt;
    _ = cb_pt;
    _ = pt;
}

pub const VertexData = c.LyonVertexData;