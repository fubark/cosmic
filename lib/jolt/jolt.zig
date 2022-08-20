const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const graphics = @import("graphics");
const StdVec3 = stdx.math.Vec3;
const StdVec4 = stdx.math.Vec4;
const Quaternion = stdx.math.Quaternion;

const log = stdx.log.scoped(.jolt);

const c = @cImport({
    @cInclude("cjolt.h");
});

const Vec4 = c.Vec4;
const Vec3 = c.Vec3;
const Quat = c.Quat;
pub const ObjectLayer = c.ObjectLayer;
pub const BroadPhaseLayer = c.BroadPhaseLayer;
pub const BodyId = c.BodyId;
pub const TempAllocator = c.TempAllocator;

pub const Layers = struct {
    pub const Unused1: u8 = 0;
    pub const Unused2: u8 = 1;
    pub const Unused3: u8 = 2;
    pub const Unused4: u8 = 3;
    pub const NonMoving: u8 = 4;
    pub const Moving: u8 = 5;
    pub const Debris: u8 = 6;
    pub const Sensor: u8 = 7;
    pub const NumLayers: u8 = 8;
};

pub const BroadPhaseLayers = struct {
    pub const NonMoving: u8 = 0;
    pub const Moving: u8 = 1;
    pub const Debris: u8 = 2;
    pub const Sensor: u8 = 3;
    pub const Unused: u8 = 4;
    pub const NumLayers: u32 = 5;
};

pub const EMotionType = enum(c.EMotionType) {
    Static = 0,
    Kinematic = 1,
    Dynamic = 2,
};

pub const EMotionQuality = enum(c.EMotionQuality) {
    Discrete = 0,
    LinearCast = 1,
};

pub const EOverrideMassProperties = enum(c.EOverrideMassProperties) {
    CalculateMassAndInertia = 0,
    CalculateInertia = 1,
    MassAndInertiaProvided = 2,
};

pub const EActivation = enum(c.EActivation) {
    Activate = 0,
    DontActivate = 1,
};

const ObjectVsBroadPhaseLayerFilter = fn (ObjectLayer, BroadPhaseLayer) bool;
const ObjectLayerPairFilter = fn (ObjectLayer, ObjectLayer) bool;

fn vec4(x: f32, y: f32, z: f32, w: f32) Vec3 {
    return .{
        .inner = .{
            .x = x, 
            .y = y,
            .z = z,
            .w = w,
        },
    };
}

pub const BodyCreationSettings = struct {
    inner: c.BodyCreationSettings,

    pub fn initDefault() BodyCreationSettings {
        return .{
            .inner = JPH__BodyCreationSettings__CONSTRUCT(),
        };
    }

    pub fn initShape(shape: *c.Shape, pos: StdVec3, rot: Quaternion, motion_type: EMotionType, object_layer: ObjectLayer) BodyCreationSettings {
        return .{
            .inner = JPH__BodyCreationSettings__CONSTRUCT2(shape, 
                &vec4(pos.x, pos.y, pos.z, undefined),
                &vec4(rot.vec.x, rot.vec.y, rot.vec.z, rot.vec.w),
                @enumToInt(motion_type), object_layer),
        };
    }
};

pub const PhysicsSystem = struct {
    handle: *c.PhysicsSystem,

    pub fn init(maxBodies: u32, numBodiesMutexes: u32, maxBodyPairs: u32, maxContactConstraints: u32,
        broadPhaseLayerInterface: *c.BroadPhaseLayerInterface, comptime OvbFilter: ObjectVsBroadPhaseLayerFilter, comptime OpFilter: ObjectLayerPairFilter,
    ) PhysicsSystem {
        const ret = PhysicsSystem{
            .handle = JPH__PhysicsSystem__NEW().?,
        };
        const S = struct {
            fn ovbFilter(layer1: ObjectLayer, layer2: BroadPhaseLayer) callconv(.C) c_int {
                if (OvbFilter(layer1, layer2)) return 1 else return 0;
            }
            fn opFilter(obj1: ObjectLayer, obj2: ObjectLayer) callconv(.C) c_int {
                if (OpFilter(obj1, obj2)) return 1 else return 0;
            }
        };
        c.JPH__PhysicsSystem__Init(ret.handle, maxBodies, numBodiesMutexes, maxBodyPairs, maxContactConstraints, broadPhaseLayerInterface, S.ovbFilter, S.opFilter);
        return ret;
    }

    pub fn deinit(self: PhysicsSystem) void {
        c.JPH__PhysicsSystem__DELETE(self.handle);
    } 

    pub fn getBodyInterface(self: PhysicsSystem) BodyInterface {
        return .{
            .handle = c.JPH__PhysicsSystem__GetBodyInterface(self.handle).?,
        };
    }

    pub fn getBodyInterfaceNoLock(self: PhysicsSystem) BodyInterface {
        return .{
            .handle = c.JPH__PhysicsSystem__GetBodyInterfaceNoLock(self.handle).?,
        };
    }

    pub fn getBodyLockInterface(self: PhysicsSystem) BodyLockInterface {
        return .{
            .handle = c.JPH__PhysicsSystem__GetBodyLockInterface(self.handle).?,
        };
    }

    pub fn getBodyLockInterfaceNoLock(self: PhysicsSystem) BodyLockInterface {
        return .{
            .handle = c.JPH__PhysicsSystem__GetBodyLockInterfaceNoLock(self.handle).?,
        };
    }

    pub fn getNumActiveBodies(self: PhysicsSystem) usize {
        return c.JPH__PhysicsSystem__GetNumActiveBodies(self.handle);
    }

    pub fn getActiveBodies(self: PhysicsSystem, out: []BodyId) void {
        c.JPH__PhysicsSystem__GetActiveBodies(self.handle, out.ptr);
    }

    pub fn getGravity(self: PhysicsSystem) StdVec3 {
        const res = c.JPH__PhysicsSystem__GetGravity(self.handle);
        return StdVec3.init(res.x, res.y, res.z);
    }

    pub fn update(self: PhysicsSystem, delta_s: f32, collision_steps: u32, integration_substeps: u32, alloc: *c.TempAllocator, job_sys: JobSystem) void {
        c.JPH__PhysicsSystem__Update(self.handle, delta_s, @intCast(c_int, collision_steps), @intCast(c_int, integration_substeps), alloc, job_sys.handle);
    }
};

pub const BodyLockInterface = struct {
    handle: *c.BodyLockInterface,

    pub fn tryGetBody(self: BodyLockInterface, body_id: BodyId) !Body {
        if (c.JPH__BodyLockInterface__TryGetBody(self.handle, &body_id)) |body| {
            return Body{ .handle = body };
        } else return error.InvalidId;
    }
};

pub const BodyInterface = struct {
    handle: *c.BodyInterface,

    pub fn createBody(self: BodyInterface, settings: BodyCreationSettings) !Body {
        if (c.JPH__BodyInterface__CreateBody(self.handle, &settings.inner)) |body| {
            return Body{ .handle = body };
        } else return error.LimitReached;
    }

    pub fn addBody(self: BodyInterface, body_id: c.BodyId, activation_mode: EActivation) void {
        c.JPH__BodyInterface__AddBody(self.handle, &body_id, @enumToInt(activation_mode));
    }

    pub fn setLinearVelocity(self: BodyInterface, body_id: c.BodyId, vel: StdVec3) void {
        c.JPH__BodyInterface__SetLinearVelocity(self.handle, &body_id, vec4(vel.x, vel.y, vel.z, undefined));
    }
};

pub const BodyLockRead = struct {
    inner: c.BodyLock,

    pub fn init(body_iface: BodyLockInterface, body_id: c.BodyId) BodyLockRead {
        var ret = BodyLockRead{
            .inner = undefined,
        };
        c.JPH__BodyLockRead__CONSTRUCT(&ret.inner, body_iface.handle, &body_id);
        return ret;
    }

    pub fn deinit(self: *BodyLockRead) void {
        c.JPH__BodyLockRead__DESTRUCT(&self.inner);
    }

    pub fn succeededAndIsInBroadPhase(self: *BodyLockRead) bool {
        return c.JPH__BodyLockRead__SucceededAndIsInBroadPhase(&self.inner);
    }

    pub fn succeeded(self: *BodyLockRead) bool {
        return c.JPH__BodyLockRead__Succeeded(&self.inner);
    }

    pub fn getBody(self: *BodyLockRead) Body {
        return .{
            .handle = c.JPH__BodyLockRead__GetBody(&self.inner).?,
        };
    }
};

pub const Body = struct {
    handle: *c.Body,

    pub fn getId(self: Body) c.BodyId {
        return c.JPH__Body__GetID(self.handle);
    }

    pub fn getPosition(self: Body) StdVec3 {
        const res = c.JPH__Body__GetPosition(self.handle);
        return StdVec3.init(res.inner.x, res.inner.y, res.inner.z);
    }

    pub fn getRotation(self: Body) Quaternion {
        const res = c.JPH__Body__GetRotation(self.handle);
        return Quaternion.init(StdVec4.init(res.inner.x, res.inner.y, res.inner.z, res.inner.w));
    }

    pub fn isActive(self: Body) bool {
        return c.JPH__Body__IsActive(self.handle);
    }

    pub fn getUserData(self: Body) u64 {
        return c.JPH__Body__GetUserData(self.handle);
    }

    pub fn setUserData(self: Body, user_data: u64) void {
        c.JPH__Body__SetUserData(self.handle, user_data);
    }
};

pub const BPLayerInterfaceImpl = struct {
    handle: *c.BroadPhaseLayerInterface,

    pub fn init() BPLayerInterfaceImpl {
        return .{
            .handle = @ptrCast(*c.BroadPhaseLayerInterface, JPH__BPLayerInterfaceImpl__NEW().?),
        };
    }

    pub fn deinit(self: BPLayerInterfaceImpl) void {
        c.JPH__BPLayerInterfaceImpl__DELETE(@ptrCast(*c.BPLayerInterfaceImpl, self.handle));
    }
};

pub const BoxShape = struct {
    handle: *c.BoxShape,

    pub fn init(halfExtent: StdVec3, convexRadius: f32, material: ?*c.PhysicsMaterial) BoxShape {
        return .{
            .handle = JPH__BoxShape__NEW(&vec4(halfExtent.x, halfExtent.y, halfExtent.z, undefined), convexRadius, material).?,
        };
    }

    pub fn shape(self: BoxShape) *c.Shape {
        return @ptrCast(*c.Shape, self.handle);
    }
};

pub fn registerDefaultAllocator() void {
    JPH__RegisterDefaultAllocator();
}

pub fn registerTypes() void {
    JPH__RegisterTypes();
}

pub fn init() void {
    if (!builtin.is_test) {
        // Verify struct sizes.
        std.debug.assert(JPH__BodyCreationSettings__SIZEOF() == @sizeOf(BodyCreationSettings));
        std.debug.assert(JPH__BodyLockRead__SIZEOF() == @sizeOf(c.BodyLock));
    }

    // Set assert failed callback.
    if (builtin.mode == .Debug) {
        const S = struct {
            fn assertFailed(expr: [*c]const u8, msg: [*c]const u8, file: [*c]const u8, line: c_uint) callconv(.C) u8 {
                log.debug("jolt: {s} {s} {s}:{d}", .{expr, stdx.cstr.spanOrEmpty(msg), file, line});
                @panic("assert failed");
                // return 0;
            }

        };
        c.JPH__SetAssertFailed(S.assertFailed);
    }

    // Use default allocator.
    registerDefaultAllocator();

    // Initialize factory global before register types.
    JPH__InitDefaultFactory();

    // Register all jolt physics types.
    registerTypes();
}

pub fn initTempAllocatorImpl(size: usize) *c.TempAllocator {
    return c.JPH__TempAllocatorImpl__NEW(@intCast(c_uint, size)).?;
}

pub fn deinitTempAllocatorImpl(self: *c.TempAllocator) void {
    return c.JPH__TempAllocatorImpl__DELETE(self);
}

pub const JobSystem = struct {
    handle: *c.JobSystem,

    /// Set numThreads to null for autodetect from num of cpus.
    pub fn initThreadPool(maxJobs: u32, maxBarriers: u32, numThreads: ?u32) JobSystem {
        return .{
            .handle = c.JPH__JobSystemThreadPool__NEW(maxJobs, maxBarriers, if (numThreads) |num| @intCast(c_int, num) else -1).?,
        };
    }

    pub fn deinitJobSystemThreadPool(self: JobSystem) void {
        c.JPH__JobSystemThreadPool__DELETE(self.handle);
    }
};

pub extern fn JPH__BodyCreationSettings__CONSTRUCT2(shape: ?*c.Shape, pos: [*c]Vec3, rot: [*c]Quat, motion_type: c.EMotionType, object_layer: c.ObjectLayer) c.BodyCreationSettings;
pub extern fn JPH__BoxShape__NEW(inHalfExtent: [*c]Vec3, inConvexRadius: f32, inMaterial: ?*const c.PhysicsMaterial) ?*c.BoxShape;

/// cImport generates extern function declarations with ... if the function is has no params.
/// This still links correctly for desktop but wasm will complain. For now, explicitly declare these no param functions.
pub extern fn JPH__RegisterDefaultAllocator() void;
pub extern fn JPH__BPLayerInterfaceImpl__NEW() ?*c.BPLayerInterfaceImpl;
pub extern fn JPH__InitDefaultFactory() void;
pub extern fn JPH__RegisterTypes() void;
pub extern fn JPH__BodyCreationSettings__SIZEOF() usize;
pub extern fn JPH__PhysicsSystem__NEW() ?*c.PhysicsSystem;
pub extern fn JPH__BodyCreationSettings__CONSTRUCT() c.BodyCreationSettings;
pub extern fn JPH__BodyLockRead__SIZEOF() usize;