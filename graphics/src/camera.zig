const std = @import("std");
const build_options = @import("build_options");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const Vec3 = stdx.math.Vec3;
const Vec4 = stdx.math.Vec4;
const Transform = stdx.math.Transform;
const t = stdx.testing;
const platform = @import("platform");
const GraphicsBackend = platform.GraphicsBackend;
const gfx_backend = std.enums.nameCast(GraphicsBackend, build_options.GraphicsBackend);
const graphics = @import("graphics.zig");
const log = stdx.log.scoped(.camera);
const eqApproxVec2 = stdx.math.eqApproxVec2;
const eqApproxVec3 = stdx.math.eqApproxVec3;
const eqApproxVec4 = stdx.math.eqApproxVec4;

// Vulkan clip-space: [-1,1][-1,1][0,1]
// OpenGL clip-space: [-1,1][1,-1][-1,1]

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

    /// For perspective view. Used to compute partitions quickly.
    aspect_ratio: f32,
    vert_fov_rad: f32,
    near: f32,
    far: f32,

    /// Logical width and height.
    pub fn init2D(self: *Camera, width: u32, height: u32) void {
        self.proj_transform = initDisplayProjection(@intToFloat(f32, width), @intToFloat(f32, height));
        self.view_transform = Transform.initIdentity();
    }

    pub fn initPerspective3D(self: *Camera, vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) void {
        initPerspective3Dinternal(self, vert_fov_deg, aspect_ratio, near, far, gfx_backend);
    }

    fn initPerspective3Dinternal(self: *Camera, vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32, comptime backend: GraphicsBackend) void {
        self.updatePerspective3D(vert_fov_deg, aspect_ratio, near, far, backend);
        self.world_pos = stdx.math.Vec3.init(0, 0, 0);
        self.setRotation(0, -std.math.pi);
    }

    pub fn updatePerspective3D(self: *Camera, vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32, comptime backend: GraphicsBackend) void {
        self.vert_fov_rad = vert_fov_deg * 2 * std.math.pi / 360;
        self.aspect_ratio = aspect_ratio;
        self.near = near;
        self.far = far;
        if (backend == .OpenGL) {
            self.proj_transform = initPerspectiveProjectionGL(vert_fov_deg, aspect_ratio, near, far);
        } else {
            self.proj_transform = initPerspectiveProjectionVK(vert_fov_deg, aspect_ratio, near, far);
        }
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

    /// Useful for partitioning the camera's frustum for shadow maps.
    pub fn computePartitionCorners(self: Camera, near: f32, far: f32) [8]Vec3 {
        const tan_v = std.math.tan(self.vert_fov_rad/2);
        const near_dy = tan_v * near;
        const far_dy = tan_v * far;
        const near_dx = near_dy * self.aspect_ratio;
        const far_dx = far_dy * self.aspect_ratio;

        const near_forward = self.forward_nvec.mul(near);
        const near_up = self.up_nvec.mul(near_dy);
        const near_right = self.right_nvec.mul(near_dx);
        const far_forward = self.forward_nvec.mul(far);
        const far_up = self.up_nvec.mul(far_dy);
        const far_right = self.right_nvec.mul(far_dx);
        return .{
            // near top-left.
            self.world_pos.add3(near_forward.x + near_up.x - near_right.x, near_forward.y + near_up.y - near_right.y, near_forward.z + near_up.z - near_right.z),
            // near top-right.
            self.world_pos.add3(near_forward.x + near_up.x + near_right.x, near_forward.y + near_up.y + near_right.y, near_forward.z + near_up.z + near_right.z),
            // near bottom-right.
            self.world_pos.add3(near_forward.x - near_up.x + near_right.x, near_forward.y - near_up.y + near_right.y, near_forward.z - near_up.z + near_right.z),
            // near bottom-left.
            self.world_pos.add3(near_forward.x - near_up.x - near_right.x, near_forward.y - near_up.y - near_right.y, near_forward.z - near_up.z - near_right.z),
            // far top-left.
            self.world_pos.add3(far_forward.x + far_up.x - far_right.x, far_forward.y + far_up.y - far_right.y, far_forward.z + far_up.z - far_right.z),
            // far top-right.
            self.world_pos.add3(far_forward.x + far_up.x + far_right.x, far_forward.y + far_up.y + far_right.y, far_forward.z + far_up.z + far_right.z),
            // far bottom-right.
            self.world_pos.add3(far_forward.x - far_up.x + far_right.x, far_forward.y - far_up.y + far_right.y, far_forward.z - far_up.z + far_right.z),
            // far bottom-left.
            self.world_pos.add3(far_forward.x - far_up.x - far_right.x, far_forward.y - far_up.y - far_right.y, far_forward.z - far_up.z - far_right.z),
        };
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
    return initDisplayProjection2(width, height, gfx_backend);
}

/// Expose for testing.
inline fn initDisplayProjection2(width: f32, height: f32, comptime backend: GraphicsBackend) Transform {
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
    if (gfx_backend == .OpenGL) {
        res.scale(1.0, -1.0);
    }
    return res;
}

/// Transformed points will have:
/// -x to the left, +x to the right
/// +y upwards, -y downwards,
/// -z in front, +z behind.
pub fn initLookAt(from: Vec3, to: Vec3, up_ref: Vec3) Transform {
    const forward = to.add3(-from.x, -from.y, -from.z).normalize();
    const right = forward.cross(up_ref).normalize();
    const up = right.cross(forward);
    return Transform.initRowMajor(.{
        right.x, right.y, right.z, -right.dot(from),
        up.x, up.y, up.z, -up.dot(from),
        -forward.x, -forward.y, -forward.z, forward.dot(from),
        0, 0, 0, 1,
    });
}

test "initLookAt" {
    // Look toward origin on x axis.
    const xform = initLookAt(Vec3.init(3, 0, 0), Vec3.init(2, 0, 0), Vec3.init(0, 1, 0));
    try eqApproxVec3(xform.interpolate3(2, 0, 0), Vec3.init(0, 0, -1));
    try eqApproxVec3(xform.interpolate3(3, 0, 1), Vec3.init(-1, 0, 0));
    try eqApproxVec3(xform.interpolate3(3, 0, -1), Vec3.init(1, 0, 0));
    try eqApproxVec3(xform.interpolate3(3, 1, 0), Vec3.init(0, 1, 0));
    try eqApproxVec3(xform.interpolate3(3, -1, 0), Vec3.init(0, -1, 0));
}

pub fn initOrthographicProjection(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) Transform {
    const dx = right - left;
    const dy = bottom - top;
    const dz = near - far;
    return Transform.initRowMajor(.{
        2.0 / dx, 0, 0, -(right + left) / dx,
        0, 2.0 / dy, 0, -(bottom + top) / dy,
        0, 0, 1.0 / dz, near / dz,
        0, 0, 0, 1,
    });
}

test "initOrthographicProjection" {
    const xform = initOrthographicProjection(-10, 10, 10, -10, 10, -10);
    // far top left.
    try eqApproxVec3(xform.interpolate3(-10, 10, -10), Vec3.init(-1, -1, 0));
    // far bottom right.
    try eqApproxVec3(xform.interpolate3(10, -10, -10), Vec3.init(1, 1, 0));
    // near top left.
    try eqApproxVec3(xform.interpolate3(-10, 10, 10), Vec3.init(-1, -1, 1));
    // near bottom right.
    try eqApproxVec3(xform.interpolate3(10, -10, 10), Vec3.init(1, 1, 1));
    // center.
    try eqApproxVec3(xform.interpolate3(0, 0, 0), Vec3.init(0, 0, 0.5));
}

pub fn initPerspectiveProjection(vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) Transform {
    if (gfx_backend == .OpenGL) {
        return initPerspectiveProjectionGL(vert_fov_deg, aspect_ratio, near, far);
    } else {
        return initPerspectiveProjectionVK(vert_fov_deg, aspect_ratio, near, far);
    }
}

/// Projects to clip space: x[-1,1] y[1,-1] z[-1,1]
inline fn initPerspectiveProjectionGL(vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) Transform {
    const fov_rad = vert_fov_deg * 2 * std.math.pi / 360;
    const focal_length = 1 / std.math.tan(fov_rad * 0.5);
    const x = focal_length / aspect_ratio;
    const y = focal_length;

    const a = (far + near) / (near - far);
    const b = (2 * far * near) / (near - far);
    return Transform.initRowMajor(.{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, a, b,
        0, 0, -1, 0,
    });
}

test "OpenGL perspective projection" {
    const proj = initPerspectiveProjectionGL(60, 2, 0.1, 100);
    try eqApproxVec4(proj.interpolate4(0, 0, -0.1, 1).divW(), Vec4.init(0, 0, -1, 1));
    try eqApproxVec4(proj.interpolate4(0, 0, -100, 1).divW(), Vec4.init(0, 0, 1, 1));
}

/// https://vincent-p.github.io/posts/vulkan_perspective_matrix/
/// Projects to clip space: x[-1,1] y[-1,1] z[1,0]
inline fn initPerspectiveProjectionVK(vert_fov_deg: f32, aspect_ratio: f32, near: f32, far: f32) Transform {
    const fov_rad = vert_fov_deg * 2 * std.math.pi / 360;
    const focal_length = 1 / std.math.tan(fov_rad * 0.5);
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

test "Vulkan perspective projection" {
    const proj = initPerspectiveProjectionVK(60, 2, 0.1, 100);
    try eqApproxVec4(proj.interpolate4(0, 0, -0.1, 1).divW(), Vec4.init(0, 0, 1, 1));
    try eqApproxVec4(proj.interpolate4(0, 0, -100, 1).divW(), Vec4.init(0, 0, 0, 1));
}

test "Perspective camera." {
    const pif = @as(f32, std.math.pi);
    var cam: Camera = undefined;
    cam.initPerspective3Dinternal(60, 2, 0.1, 100, .Vulkan);

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

/// Binds to the event dispatcher and allows camera movement with mouse and keyboard events.
pub const CameraModule = struct {
    cam: *Camera,
    move_forward: bool,
    move_backward: bool,
    move_left: bool,
    move_right: bool,
    move_up: bool,
    move_down: bool,

    dragging: bool,
    drag_start_rotate_x: f32,
    drag_start_rotate_y: f32,
    drag_start_x: f32,
    drag_start_y: f32,

    const Self = @This();

    pub fn init(self_: *Self, cam: *Camera, dispatcher: *platform.EventDispatcher) void {
        const S = struct {
            fn onKeyDown(ptr: ?*anyopaque, ke: platform.KeyDownEvent) void {
                const self = stdx.mem.ptrCastAlign(*Self, ptr);
                switch (ke.code) {
                    .W => self.move_forward = true,
                    .S => self.move_backward = true,
                    .A => self.move_left = true,
                    .D => self.move_right = true,
                    .R => self.move_up = true,
                    .F => self.move_down = true,
                    else => {},
                }
            }
            fn onKeyUp(ptr: ?*anyopaque, ke: platform.KeyUpEvent) void {
                const self = stdx.mem.ptrCastAlign(*Self, ptr);
                switch (ke.code) {
                    .W => self.move_forward = false,
                    .S => self.move_backward = false,
                    .A => self.move_left = false,
                    .D => self.move_right = false,
                    .R => self.move_up = false,
                    .F => self.move_down = false,
                    else => {},
                }
            }
            fn onMouseDown(ptr: ?*anyopaque, me: platform.MouseDownEvent) platform.EventResult {
                const self = stdx.mem.ptrCastAlign(*Self, ptr);
                if (me.button == .Left) {
                    self.dragging = true;
                    self.drag_start_x = @intToFloat(f32, me.x);
                    self.drag_start_y = @intToFloat(f32, me.y);
                    self.drag_start_rotate_x = self.cam.rotate_x;
                    self.drag_start_rotate_y = self.cam.rotate_y;
                }
                return .Continue;
            }
            fn onMouseUp(ptr: ?*anyopaque, me: platform.MouseUpEvent) void {
                const self = stdx.mem.ptrCastAlign(*Self, ptr);
                if (me.button == .Left) {
                    self.dragging = false;
                }
            }
            fn onMouseMove(ptr: ?*anyopaque, me: platform.MouseMoveEvent) void {
                const self = stdx.mem.ptrCastAlign(*Self, ptr);
                if (self.dragging) {
                    const delta_x = @intToFloat(f32, me.x) - self.drag_start_x;
                    const delta_y = -(@intToFloat(f32, me.y) - self.drag_start_y);

                    const delta_pitch = delta_y * 0.005;
                    const delta_yaw = delta_x * 0.005;
                    self.cam.setRotation(self.drag_start_rotate_x + delta_pitch, self.drag_start_rotate_y - delta_yaw);
                }
            }
        };
        dispatcher.addOnKeyDown(self_, S.onKeyDown);
        dispatcher.addOnKeyUp(self_, S.onKeyUp);
        dispatcher.addOnMouseDown(self_, S.onMouseDown);
        dispatcher.addOnMouseUp(self_, S.onMouseUp);
        dispatcher.addOnMouseMove(self_, S.onMouseMove);
        self_.* = .{
            .cam = cam,
            .move_forward = false,
            .move_backward = false,
            .move_left = false,
            .move_right = false,
            .move_up = false,
            .move_down = false,
            .dragging = false,
            .drag_start_rotate_x = undefined,
            .drag_start_rotate_y = undefined,
            .drag_start_x = undefined,
            .drag_start_y = undefined,
        };
    }

    pub fn update(self: *Self, delta_ms: f32) void {
        if (self.move_backward) {
            self.cam.moveForward(-0.05 * delta_ms);
        }
        if (self.move_forward) {
            self.cam.moveForward(0.05 * delta_ms);
        }
        if (self.move_left) {
            self.cam.moveRight(-0.05 * delta_ms);
        }
        if (self.move_right) {
            self.cam.moveRight(0.05 * delta_ms);
        }
        if (self.move_up) {
            self.cam.moveUp(0.05 * delta_ms);
        }
        if (self.move_down) {
            self.cam.moveUp(-0.05 * delta_ms);
        }
    }
};