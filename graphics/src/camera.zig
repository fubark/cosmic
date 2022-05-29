const stdx = @import("stdx");
const t = stdx.testing;
const graphics = @import("graphics.zig");
const Transform = graphics.transform.Transform;

pub const Camera = struct {
    proj_transform: Transform,
    initial_mvp: stdx.math.Mat4,

    /// Logical width and height.
    pub fn init2D(self: *Camera, width: u32, height: u32) void {
        self.proj_transform = initDisplayProjection(@intToFloat(f32, width), @intToFloat(f32, height));
        const view_transform = Transform.initIdentity();
        self.initial_mvp = stdx.math.Mul4x4_4x4(self.proj_transform.mat, view_transform.mat);
    }
};

pub fn initDisplayProjection(width: f32, height: f32) Transform {
    var res = Transform.initIdentity();
    // first reduce to [0,1] values
    res.scale(1.0 / width, 1.0 / height);
    // to [0,2] values
    res.scale(2.0, 2.0);
    // to clip space [-1,1]
    res.translate(-1.0, -1.0);
    // flip y since clip space is based on cartesian
    res.scale(1.0, -1.0);
    return res;
}

test "initDisplayProjection" {
    var transform = initDisplayProjection(800, 600);
    try t.eq(transform.transformPoint(.{ 0, 0, 0, 1 }), .{ -1, 1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 800, 0, 0, 1 }), .{ 1, 1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 800, 600, 0, 1 }), .{ 1, -1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 0, 600, 0, 1 }), .{ -1, -1, 0, 1 });
}

/// For drawing to textures. Similar to display projection but y isn't flipped.
pub fn initTextureProjection(width: f32, height: f32) Transform {
    var res = Transform.initIdentity();
    // first reduce to [0,1] values
    res.scale(1.0 / width, 1.0 / height);
    // to [0,2] values
    res.scale(2.0, 2.0);
    // to clip space [-1,1]
    res.translate(-1.0, -1.0);
    return res;
}