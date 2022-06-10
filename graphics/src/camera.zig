const std = @import("std");
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const Vec3 = stdx.math.Vec3;
const Vec4 = stdx.math.Vec4;
const t = stdx.testing;
const graphics = @import("graphics.zig");
const Transform = graphics.transform.Transform;
const log = stdx.log.scoped(.camera);
const eqApproxVec2 = stdx.math.eqApproxVec2;
const eqApproxVec3 = stdx.math.eqApproxVec3;
const eqApproxVec4 = stdx.math.eqApproxVec4;

// Vulkan clip-space: [-1,1][-1,1][0,1]
// OpenGL clip-space: [-1,1][-1,1][-1,1]

pub const Camera = struct {
    proj_transform: Transform,
    view_transform: Transform,

    world_pos: Vec3,

    /// Used to do movement along axis.
    up_nvec: Vec3,
    right_nvec: Vec3,
    forward_nvec: Vec3,

    // TODO: Implement with geometric algebra.
    /// It's easier to deal with changing rotations by keeping the axis rotation values.
    rotate_x: f32,
    rotate_y: f32,

    /// Logical width and height.
    pub fn init2D(self: *Camera, width: u32, height: u32) void {
        self.proj_transform = initDisplayProjection(@intToFloat(f32, width), @intToFloat(f32, height));
        self.view_transform = Transform.initIdentity();
    }

    pub fn initPerspective3D(self: *Camera, vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) void {
        self.proj_transform = initPerspectiveProjection(vert_fov_deg, aspect_ratio, near, far);
        self.world_pos = stdx.math.Vec3.init(0, 0, 0);
        self.setRotation(0, -std.math.pi);
    }

    pub fn moveForward(self: *Camera, delta: f32) void {
        self.world_pos.x += self.forward_nvec.x * delta;
        self.world_pos.y += self.forward_nvec.y * delta;
        self.world_pos.z += self.forward_nvec.z * delta;
        self.computeViewTransform();
    }

    pub fn moveUp(self: *Camera, delta: f32) void {
        self.world_pos.x += self.up_nvec.x * delta;
        self.world_pos.y += self.up_nvec.y * delta;
        self.world_pos.z += self.up_nvec.z * delta;
        self.computeViewTransform();
    }

    pub fn moveRight(self: *Camera, delta: f32) void {
        self.world_pos.x += self.right_nvec.x * delta;
        self.world_pos.y += self.right_nvec.y * delta;
        self.world_pos.z += self.right_nvec.z * delta;
        self.computeViewTransform();
    }

    pub fn setPos(self: *Camera, x: f32, y: f32, z: f32) void {
        self.world_pos.x = x;
        self.world_pos.y = y;
        self.world_pos.z = z;
        self.computeViewTransform();
    }

    pub fn setRotation(self: *Camera, rotate_x: f32, rotate_y: f32) void {
        self.rotate_x = rotate_x;
        self.rotate_y = rotate_y;
        self.computeViewTransform();
    }

    // TODO: Convert to rotate_x, rotate_y.
    // pub fn setForward(self: *Camera, forward: Vec3) void {
    //     self.forward_nvec = forward.normalize();
    //     self.right_nvec = self.forward_nvec.cross(Vec3.init(0, 1, 0)).normalize();
    //     if (std.math.isNan(self.right_nvec.x)) {
    //         self.right_nvec = self.forward_nvec.cross(Vec3.init(0, 0, 1)).normalize();
    //     }
    //     self.up_nvec = self.right_nvec.cross(self.forward_nvec).normalize();
    //     self.computeViewTransform();
    // }

    fn computeViewTransform(self: *Camera) void {
        self.view_transform = Transform.initIdentity();
        self.view_transform.translate3D(-self.world_pos.x, -self.world_pos.y, -self.world_pos.z);
        var rotate_xform = Transform.initIdentity();
        rotate_xform.rotateY(self.rotate_y + std.math.pi);
        rotate_xform.rotateX(self.rotate_x);
        // Set forward, up, right vecs from rotation matrix.
        // Use opposite forward vector since eye defaults to looking behind.
        self.forward_nvec = Vec3.init(-rotate_xform.mat[8], -rotate_xform.mat[9], -rotate_xform.mat[10]);
        self.right_nvec = Vec3.init(rotate_xform.mat[0], rotate_xform.mat[1], rotate_xform.mat[2]);
        self.up_nvec = Vec3.init(rotate_xform.mat[4], rotate_xform.mat[5], rotate_xform.mat[6]);
        self.view_transform.applyTransform(rotate_xform);
    }
};

pub fn initDisplayProjection(width: f32, height: f32) Transform {
    return initDisplayProjection2(width, height, Backend);
}

/// Expose for testing.
inline fn initDisplayProjection2(width: f32, height: f32, comptime backend: @TypeOf(Backend)) Transform {
    var res = Transform.initIdentity();
    // first reduce to [0,1] values
    res.scale(1.0 / width, 1.0 / height);
    // to [0,2] values
    res.scale(2.0, 2.0);
    // to clip space [-1,1]
    res.translate(-1.0, -1.0);
    if (backend == .OpenGL) {
        // flip y since clip space is based on cartesian
        res.scale(1.0, -1.0);
    }
    return res;
}

test "initDisplayProjection" {
    var transform = initDisplayProjection2(800, 600, .OpenGL);
    try t.eq(transform.interpolatePt(Vec2.init(0, 0)), Vec2.init(-1, 1));
    try t.eq(transform.interpolatePt(Vec2.init(800, 0)), Vec2.init(1, 1));
    try t.eq(transform.interpolatePt(Vec2.init(800, 600)), Vec2.init(1, -1));
    try t.eq(transform.interpolatePt(Vec2.init(0, 600)), Vec2.init(-1, -1));
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

test "Perspective camera." {
    const pif = @as(f32, std.math.pi);
    var cam: Camera = undefined;
    cam.initPerspective3D(60, 2, 0.1, 100);

    try eqApproxVec3(cam.forward_nvec, Vec3.init(0, 0, -1));
    try eqApproxVec3(cam.right_nvec, Vec3.init(1, 0, 0));
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, 1, 0));
    try eqApproxVec4(cam.view_transform.interpolate4(0, 0, -10, 1), Vec4.init(0, 0, -10, 1));

    // Look tilted downward.
    cam.setRotation(-pif * 0.25, -pif);
    try eqApproxVec3(cam.forward_nvec, Vec3.init(0, -1, -1).normalize());
    try eqApproxVec3(cam.right_nvec, Vec3.init(1, 0, 0));
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, 1, -1).normalize());
    try eqApproxVec4(cam.view_transform.interpolate4(0, 0, -10, 1), Vec4.init(0, std.math.sqrt(50.0), -std.math.sqrt(50.0), 1));

    // Look tilted upward.
    cam.setRotation(pif * 0.25, -pif);
    try eqApproxVec3(cam.forward_nvec, Vec3.init(0, 1, -1).normalize());
    try eqApproxVec3(cam.right_nvec, Vec3.init(1, 0, 0));
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, 1, 1).normalize());
    try eqApproxVec4(cam.view_transform.interpolate4(0, 0, -10, 1), Vec4.init(0, -std.math.sqrt(50.0), -std.math.sqrt(50.0), 1));

    // Look tilted to the left.
    cam.setRotation(0, -pif * 0.75);
    try eqApproxVec3(cam.forward_nvec, Vec3.init(-1, 0, -1).normalize());
    try eqApproxVec3(cam.right_nvec, Vec3.init(1, 0, -1).normalize());
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, 1, 0));
    try eqApproxVec4(cam.view_transform.interpolate4(0, 0, -10, 1), Vec4.init(std.math.sqrt(50.0), 0, -std.math.sqrt(50.0), 1));

    // Look tilted to the right.
    cam.setRotation(0, pif * 0.75);
    try eqApproxVec3(cam.forward_nvec, Vec3.init(1, 0, -1).normalize());
    try eqApproxVec3(cam.right_nvec, Vec3.init(1, 0, 1).normalize());
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, 1, 0));
    try eqApproxVec4(cam.view_transform.interpolate4(0, 0, -10, 1), Vec4.init(-std.math.sqrt(50.0), 0, -std.math.sqrt(50.0), 1));

    // Look downwards.
    cam.setRotation(pif, 0);
    try eqApproxVec3(cam.forward_nvec, Vec3.init(0, 0, -1));
    try eqApproxVec3(cam.right_nvec, Vec3.init(-1, 0, 0));
    try eqApproxVec3(cam.up_nvec, Vec3.init(0, -1, 0));
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