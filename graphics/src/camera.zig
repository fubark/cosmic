const std = @import("std");
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const stdx = @import("stdx");
const t = stdx.testing;
const graphics = @import("graphics.zig");
const Transform = graphics.transform.Transform;
const log = stdx.log.scoped(.camera);

// Vulkan clip-space: [-1,1][-1,1][0,1]
// OpenGL clip-space: [-1,1][-1,1][-1,1]

pub const Camera = struct {
    proj_transform: Transform,
    view_transform: Transform,

    /// Logical width and height.
    pub fn init2D(self: *Camera, width: u32, height: u32) void {
        self.proj_transform = initDisplayProjection(@intToFloat(f32, width), @intToFloat(f32, height));
        self.view_transform = Transform.initIdentity();
    }

    pub fn initPerspective3D(self: *Camera, vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) void {
        self.proj_transform = initPerspectiveProjection(vert_fov_deg, aspect_ratio, near, far);
        self.view_transform = Transform.initIdentity();
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
    if (Backend == .OpenGL) {
        // flip y since clip space is based on cartesian
        res.scale(1.0, -1.0);
    }
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

/// https://vincent-p.github.io/posts/vulkan_perspective_matrix/
pub fn initPerspectiveProjection(vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) Transform {
    const fov_rad = vert_fov_deg * 2 * std.math.pi / 360;
    const focal_length = 1 / std.math.tan(fov_rad / 2);
    const x = focal_length / aspect_ratio;
    const y = -focal_length;
    const a = near / (far - near);
    const b = far * a;
    return Transform.initRowMajor(.{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, a, b,
        0, 0, -1, 0,
    });
}

/// near and far are towards -z.
pub fn initFrustumProjection(near: f32, far: f32, left: f32, right: f32, top: f32, bottom: f32) Transform {
    const width = right - left;
    const height = top - bottom;
    return Transform.initRowMajor(.{
        2 * near / width, 0, (right + left) / width, 0,
        0, -2 * near / height, -(top + bottom) / height, 0,
        0, 0,  near / (far - near), far * near / (far - near),
        0, 0, -1, 0,
    });
}