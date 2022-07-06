const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const fatal = stdx.fatal;
const Vec3 = stdx.math.Vec3;
const Quaternion = stdx.math.Quaternion;
const Transform = stdx.math.Transform;
const jolt = @import("jolt");
const graphics = @import("graphics");
const Color = graphics.Color;

const log = stdx.log.scoped(.world);

pub const VoxelPt = stdx.math.Point3(i32);
const ChunkSize: u32 = 32;
const NullId = std.math.maxInt(u32);
const chunks = @import("chunks.zig");
const OctRegionOrVoxelId = chunks.OctRegionOrVoxelId;
const Octant = chunks.Octant;
const OctRegionId = chunks.OctRegionId;
const OctPathItem = chunks.OctPathItem;
const Chunk = chunks.Chunk;
const ChunkPt = chunks.ChunkPt;
const Chunks = chunks.Chunks(ChunkSize);
pub const VoxelId = u32;

pub const VoxelMaterial = enum(u1) {
    Block = 1,
};

const EmptyVoxel = Voxel{
    .mat_type = .Empty,
};

pub const Voxel = struct {
    mat_type: VoxelMaterial,
};

/// Regions are partitioned into 8 subregions or 8 voxels or a mixture.
/// The indexes correspond to these sub regions using a camera facing the origin where +z is toward the camera and +y is up.
/// 0 - far bottom left
/// 1 - far bottom right
/// 2 - near bottom left
/// 3 - near bottom right
/// 4 - far top left
/// 5 - far top right
/// 6 - near top left
/// 7 - near top right
const OctRegion = struct {
    children: [8]OctRegionOrVoxelId,
    /// Each bit indicates whether the corresponding child is a voxel id or a subregion id.
    is_voxel_mask: u8,
};

pub const World = struct {
    alloc: std.mem.Allocator,
    objects: stdx.ds.DenseHandleList(u32, WorldObject),

    // Voxels.
    chunks: std.AutoHashMap(ChunkPt, Chunk),
    oct_regions: stdx.ds.PooledHandleList(OctRegionId, OctRegion),
    voxels: stdx.ds.PooledHandleList(VoxelId, Voxel),
    gen_mesh_start_buf: std.PriorityQueue(chunks.MeshStartPt, void, chunks.compareStartPt), // Only used for experimental mesh generation algo.

    // Physics.
    physics_sys: jolt.PhysicsSystem,
    body_iface: jolt.BodyInterface,
    bp_layer_iface: jolt.BPLayerInterfaceImpl,
    temp_alloc: *jolt.TempAllocator,
    job_sys: jolt.JobSystem,
    bodies: std.ArrayList(jolt.BodyId),

    const WorldToPhysicsScale = 0.5;
    const PhysicsToWorldScale = 1 / WorldToPhysicsScale;
    pub var inited_jolt = false;

    pub fn init(alloc: std.mem.Allocator) World {
        var ret = World{
            .alloc = alloc,
            .objects = stdx.ds.DenseHandleList(u32, WorldObject).init(alloc),
            .physics_sys = undefined,
            .body_iface = undefined,
            .bp_layer_iface = undefined,
            .temp_alloc = undefined,
            .job_sys = undefined,
            .bodies = undefined,
            .chunks = std.AutoHashMap(ChunkPt, Chunk).init(alloc),
            .oct_regions = stdx.ds.PooledHandleList(OctRegionId, OctRegion).init(alloc),
            .voxels = stdx.ds.PooledHandleList(VoxelId, Voxel).init(alloc),
            .gen_mesh_start_buf = std.PriorityQueue(chunks.MeshStartPt, void, chunks.compareStartPt).init(alloc, {}),
        };
        ret.initPhysics(alloc);
        return ret;
    }

    pub fn initPhysics(self: *World, alloc: std.mem.Allocator) void {
        if (!inited_jolt) {
            jolt.init();
            inited_jolt = true;
        }
        const max_bodies = 10240;
        const num_body_mutexes = 0; // Autodetect
        const max_body_pairs = 65536;
        const max_contact_constraints = 10240;
        self.bp_layer_iface = jolt.BPLayerInterfaceImpl.init();

        const S = struct {
            /// Function that determines if two broadphase layers can collide
            fn broadPhaseCanCollide(layer1: jolt.ObjectLayer, layer2_: jolt.BroadPhaseLayer) bool {
                const layer2 = layer2_.mValue;
                switch (layer1) {
                    jolt.Layers.NonMoving => return layer2 == jolt.BroadPhaseLayers.Moving,
                    jolt.Layers.Moving => return layer2 == jolt.BroadPhaseLayers.NonMoving or layer2 == jolt.BroadPhaseLayers.Moving or layer2 == jolt.BroadPhaseLayers.Sensor,
                    jolt.Layers.Debris => return layer2 == jolt.BroadPhaseLayers.NonMoving,
                    jolt.Layers.Sensor => return layer2 == jolt.BroadPhaseLayers.Moving,
                    jolt.Layers.Unused1,
                    jolt.Layers.Unused2,
                    jolt.Layers.Unused3,
                    jolt.Layers.Unused4 => return false,
                    else => unreachable,
                }
            }
            /// Function that determines if two object layers can collide
            fn objectCanCollide(obj1: jolt.ObjectLayer, obj2: jolt.ObjectLayer) bool {
                switch (obj1) {
                    jolt.Layers.Unused1,
                    jolt.Layers.Unused2,
                    jolt.Layers.Unused3,
                    jolt.Layers.Unused4 => return false,
                    jolt.Layers.NonMoving => return obj2 == jolt.Layers.Moving or obj2 == jolt.Layers.Debris,
                    jolt.Layers.Moving => return obj2 == jolt.Layers.NonMoving or obj2 == jolt.Layers.Moving or obj2 == jolt.Layers.Sensor,
                    jolt.Layers.Debris => return obj2 == jolt.Layers.NonMoving,
                    jolt.Layers.Sensor => return obj2 == jolt.Layers.Moving,
                    else => unreachable,
                }
            }
        };
        self.physics_sys = jolt.PhysicsSystem.init(max_bodies, num_body_mutexes, max_body_pairs, max_contact_constraints, self.bp_layer_iface.handle, S.broadPhaseCanCollide, S.objectCanCollide);
        self.temp_alloc = jolt.initTempAllocatorImpl(20 * 1024 * 1024);
        self.job_sys = jolt.JobSystem.initThreadPool(2048, 8, 1);
        self.bodies = std.ArrayList(jolt.BodyId).init(alloc);
        self.body_iface = self.physics_sys.getBodyInterface();
    }

    pub fn deinit(self: *World) void {
        self.objects.deinit();

        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk| {
            chunk.deinit(self.alloc);
        }
        self.chunks.deinit();
        self.oct_regions.deinit();
        self.voxels.deinit();
        self.gen_mesh_start_buf.deinit();

        // Physics
        self.bodies.deinit();
        self.job_sys.deinitJobSystemThreadPool();
        jolt.deinitTempAllocatorImpl(self.temp_alloc);
        self.bp_layer_iface.deinit();
        self.physics_sys.deinit();
    }

    pub fn genTerrain(self: *World) void {
        const scale = 0.01;

        var x: i32 = -5;
        while (x < 10) : (x += 1) {
            var z: i32 = -5;
            while (z < 5) : (z += 1) {
                const noise = graphics.perlinNoise(@intToFloat(f32, x) * scale, @intToFloat(f32, z) * scale, 0);
                var y = @floatToInt(i32, noise * 100);
                while (y > -5) : (y -= 1) {
                    const pt = VoxelPt.init(x, y, z);
                    // log.debug("setVoxel {}", .{pt});
                    Chunks.setVoxel(self, pt, .Block);
                }
            }
        }
        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk| {
            Chunks.genChunkMeshes(self, chunk);
        }
    }

    pub fn getChunk(self: World, chunk_pt: ChunkPt) ?*Chunk {
        return self.chunks.getPtr(chunk_pt) orelse return null;
    }

    fn deleteVoxel(self: *World, pt: VoxelPt) void {
        _ = self;
        _ = pt;
    }

    pub fn clearVoxels(self: *World) void {
        self.voxels.clearRetainingCapacity();
        self.oct_regions.clearRetainingCapacity();

        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk| {
            chunk.deinit(self.alloc);
        }
        self.chunks.clearRetainingCapacity();
    }

    /// Goes up the octree path and reduces equal voxels. Should only be done when the voxel was inserted in a leaf oct region.
    pub fn compressUpwards(self: *World, chunk: *Chunk, path: []const OctPathItem) void {
        // Start at the leaf region.
        var i: u32 = @intCast(u32, path.len-1);
        while (i > 0) {
            i -= 1;
            const item = path[i];
            const region = self.oct_regions.getNoCheck(item.item_id);
            if (region.is_voxel_mask == @enumToInt(Octant.All)) {
                const mat_type = self.voxels.getNoCheck(region.children[0]).mat_type;
                if (self.voxels.getNoCheck(region.children[1]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[2]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[3]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[4]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[5]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[6]).mat_type == mat_type and
                    self.voxels.getNoCheck(region.children[7]).mat_type == mat_type) {
                    // Matching material type. Merge.
                    self.voxels.remove(region.children[1]);
                    self.voxels.remove(region.children[2]);
                    self.voxels.remove(region.children[3]);
                    self.voxels.remove(region.children[4]);
                    self.voxels.remove(region.children[5]);
                    self.voxels.remove(region.children[6]);
                    self.voxels.remove(region.children[7]);
                    if (i > 0) {
                        const parent_region = self.oct_regions.getPtrNoCheck(path[i - 1].item_id);
                        parent_region.children[item.oct_idx] = region.children[0];
                        parent_region.is_voxel_mask |= @enumToInt(chunks.idx_to_octant[item.oct_idx]);
                    } else {
                        chunk.children[item.oct_idx] = region.children[0];
                        chunk.is_voxel_mask |= @enumToInt(chunks.idx_to_octant[item.oct_idx]);
                    }
                    self.oct_regions.remove(item.item_id);
                }
            }
        }
    }

    pub fn addCuboid(self: *World, pos: Vec3, dim: Vec3, rot: Quaternion, static: bool) void {
        const shape = jolt.BoxShape.init(dim.mul(0.5 * WorldToPhysicsScale), 0, null).shape();
        const motion_type: jolt.EMotionType = if (static) .Static else .Dynamic;
        const layer: u8 = if (static) jolt.Layers.NonMoving else jolt.Layers.Moving;
        const opts = jolt.BodyCreationSettings.initShape(shape, pos.mul(WorldToPhysicsScale), rot, motion_type, layer);
        const body = self.body_iface.createBody(opts) catch fatal();
        const body_id = body.getId();
        if (static) {
            self.body_iface.addBody(body_id, .DontActivate);
        } else {
            self.body_iface.addBody(body_id, .Activate);
        }
        const eid = self.objects.add(.{
            .obj_type = .Cuboid,
            .scale = dim,
            .pos = pos,
            .rot = rot,
            .body_id = body_id,
            .inner = .{
                .cuboid = {},
            },
        }) catch fatal();
        body.setUserData(eid);
    }

    pub fn setLinearVelocity(self: *World, eid: EntityId, vel: Vec3) void {
        const obj = self.objects.get(eid).?;
        self.body_iface.setLinearVelocity(obj.body_id, vel.mul(WorldToPhysicsScale));
    }

    pub fn update(self: *World, delta_ms: f32, gctx: *graphics.Graphics) void {
        self.bodies.resize(self.physics_sys.getNumActiveBodies()) catch fatal();
        if (self.bodies.items.len > 0) {
            self.physics_sys.getActiveBodies(self.bodies.items);
        }
        self.physics_sys.update(delta_ms * 0.001, 1, 1, self.temp_alloc, self.job_sys);

        const body_iface = self.physics_sys.getBodyLockInterfaceNoLock();
        for (self.bodies.items) |body_id| {
            const body = body_iface.tryGetBody(body_id) catch fatal();
            // Sync physics position to world.
            const eid = @intCast(EntityId, body.getUserData());
            const obj = self.objects.getPtr(eid).?;
            obj.pos = body.getPosition().mul(PhysicsToWorldScale);
            obj.rot = body.getRotation();
        }

        // Draw terrain.
        const material = gctx.pushMaterial(graphics.Material.initAlbedoColor(Color.Green));
        var chunk_x: i32 = -3;
        var voxels: u32 = 0;
        while (chunk_x < 3) : (chunk_x += 1) {
            var chunk_y: i32 = -3;
            while (chunk_y < 3) : (chunk_y += 1) {
                var chunk_z: i32 = -3;
                while (chunk_z < 3) : (chunk_z += 1) {
                    if (self.chunks.get(ChunkPt.init(chunk_x, chunk_y, chunk_z))) |chunk| {
                        for (chunk.meshes.items) |mesh| {
                            var xform = Transform.initIdentity();
                            const width = VoxelSize * @intToFloat(f32, mesh.end_pt.x - mesh.start_pt.x);
                            const height = VoxelSize * @intToFloat(f32, mesh.end_pt.y - mesh.start_pt.y);
                            const depth = VoxelSize * @intToFloat(f32, mesh.end_pt.z - mesh.start_pt.z);
                            const start_x = chunk_x * ChunkSize + mesh.start_pt.x;
                            const start_y = chunk_y * ChunkSize + mesh.start_pt.y;
                            const start_z = chunk_z * ChunkSize + mesh.start_pt.z;
                            xform.scale3D(width, height, depth);
                            xform.translate3D(
                                VoxelSize * @intToFloat(f32, start_x) + width * 0.5,
                                VoxelSize * @intToFloat(f32, start_y) + height * 0.5,
                                VoxelSize * @intToFloat(f32, start_z) + depth * 0.5,
                            );
                            voxels += 1;
                            gctx.drawCuboidPbr3D(xform, material);
                            // log.debug("draw voxel {}", .{voxels});
                        }
                    }
                }
            }
        }

        // TODO: Draw objects.
        for (self.objects.items()) |obj| {
            var xform = Transform.initIdentity();
            xform.scale3D(obj.scale.x, obj.scale.y, obj.scale.z);
            xform.rotateQuat(obj.rot);
            xform.translate3D(obj.pos.x, obj.pos.y, obj.pos.z);
            gctx.drawSingleCuboidPbr3D(xform, graphics.Material.initAlbedoColor(Color.Gray));
        }
    }
};

const VoxelSize = 20;

const WorldObjectType = enum(u1) {
    Cuboid = 0,
};

const WorldObject = struct {
    pos: Vec3,
    scale: Vec3,
    rot: Quaternion,
    inner: union {
        cuboid: void,
    },
    body_id: jolt.BodyId,
    obj_type: WorldObjectType,
};

const EntityId = u32;
