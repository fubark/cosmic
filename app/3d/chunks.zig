const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const fatal = stdx.fatal;
const NullId = std.math.maxInt(u32);

const world_ = @import("world.zig");
const World = world_.World;
const VoxelPt = world_.VoxelPt;
const VoxelId = world_.VoxelId;
const VoxelMaterial = world_.VoxelMaterial;
const Voxel = world_.Voxel;
pub const ChunkPt = stdx.math.Point3(i32);
pub const OctRegionId = u32;
pub const OctRegionOrVoxelId = u32;
const log = stdx.log.scoped(.chunks);

/// Chunk ops that depend on ChunkSize.
pub fn Chunks(comptime ChunkSize: u32) type {
    return struct {
        pub const MaxDepth = std.math.log2(ChunkSize)-1;
        var oct_path_buf: [MaxDepth+1]OctPathItem = undefined;

        inline fn voxelToChunkPt(pt: VoxelPt) ChunkPt {
            return ChunkPt.init(@divFloor(pt.x, ChunkSize), @divFloor(pt.y, ChunkSize), @divFloor(pt.z, ChunkSize));
        }

        inline fn getChunkStartPt(pt: ChunkPt) VoxelPt {
            return VoxelPt.init(pt.x * ChunkSize, pt.y * ChunkSize, pt.z * ChunkSize);
        }

        /// An experimental version of greedy meshing which uses a priority queue to process each voxel space. Not done.
        /// The idea is that it would save time by not querying empty space from the octree.
        /// It would need to track in-progress voxels and their current expansion state (eg. expanding +x, expanding +z, expanding +y)
        fn genChunkMeshes2(world: *World, chunk: *Chunk) void {
            chunk.meshes.clearRetainingCapacity();

            // Check for no voxels case.
            if (chunk.is_voxel_mask == 0 and
                chunk.children[0] == NullId and 
                chunk.children[1] == NullId and 
                chunk.children[2] == NullId and 
                chunk.children[3] == NullId and 
                chunk.children[4] == NullId and 
                chunk.children[5] == NullId and 
                chunk.children[6] == NullId and 
                chunk.children[7] == NullId
            ) {
                return;
            }

            world.gen_mesh_start_buf.len = 0;
            const start_pt = chunk.start_pt;

            // Add initial voxel start pts into priority queue.
            const S = struct {
                fn addVoxelStartPts(worldS: *World, region_id: OctRegionId, start_pt_: VoxelPt, subregion_size: i32) void {
                    const region = worldS.oct_regions.getNoCheck(region_id);
                    inline for (idx_to_octant) |octant| {
                        if (region.is_voxel_mask & @enumToInt(octant) > 0) {
                            worldS.gen_mesh_start_buf.add(.{
                                .voxel_id = region.children[ctGetOctantIdx(octant)],
                                .start_pt = getNextStartPt(octant, start_pt_, subregion_size),
                                .size = subregion_size,
                            }) catch fatal();
                        } else if (region.children[ctGetOctantIdx(octant)] != NullId) {
                            addVoxelStartPts(worldS, region.children[ctGetOctantIdx(octant)], getNextStartPt(octant, start_pt_, subregion_size), subregion_size >> 1);
                        }
                    }
                }
            };
            const subregion_size = ChunkSize >> 1;
            inline for (idx_to_octant) |octant| {
                if (chunk.is_voxel_mask & @enumToInt(octant) > 0) {
                    world.gen_mesh_start_buf.add(.{
                        .voxel_id = chunk.children[ctGetOctantIdx(octant)],
                        .start_pt = getNextStartPt(octant, start_pt, subregion_size),
                        .size = subregion_size,
                    }) catch fatal();
                } else if (chunk.children[ctGetOctantIdx(octant)] != NullId) {
                    S.addVoxelStartPts(world, chunk.children[ctGetOctantIdx(octant)], getNextStartPt(octant, start_pt, subregion_size), subregion_size >> 1);
                }
            }

            // Perform greedy meshing sorted by ascending y, z, x.
            while (world.gen_mesh_start_buf.removeOrNull()) |start| {
                _ = start;
            }
        }

        /// Greedy meshing.
        pub fn genChunkMeshes(world: *World, chunk: *Chunk) void {
            chunk.meshes.clearRetainingCapacity();

            // Check for no voxels case.
            if (chunk.is_voxel_mask == 0 and
                chunk.children[0] == NullId and 
                chunk.children[1] == NullId and 
                chunk.children[2] == NullId and 
                chunk.children[3] == NullId and 
                chunk.children[4] == NullId and 
                chunk.children[5] == NullId and 
                chunk.children[6] == NullId and 
                chunk.children[7] == NullId
            ) {
                return;
            }

            // The skip array indicates where the next x should begin to speed up iteration. When voxels are merged or empty voxel spaces are detected they update the relevant cells.
            var skip_grid = std.mem.zeroes([ChunkSize*ChunkSize*ChunkSize]u8);

            // Main loop looking for a start point.
            var skip_idx: u32 = 0;
            var y: i32 = 0;
            while (y < ChunkSize) : (y += 1) {
                var z: i32 = 0;
                while (z < ChunkSize) : (z += 1) {
                    var x: i32 = 0;
                    while (x < ChunkSize) {
                        const skip = skip_grid[skip_idx];
                        if (skip > 0) {
                            skip_idx += skip - @intCast(u8, x);
                            x = skip;
                            continue;
                        } else {
                            // Query voxel space.
                            const start_pt = VoxelPt.init(x, y, z);
                            const res = getChunkVoxelBounds(world.*, chunk, start_pt);
                            if (!res.is_empty) {
                                const last_x = x;
                                x = expandVoxelMesh(world, chunk, &skip_grid, start_pt, res.end_pt, res.voxel_id);
                                skip_idx += @intCast(u32, x - last_x);
                            } else {
                                // Fill skip with empty space.
                                fillSkipGrid(&skip_grid, start_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                                const last_x = x;
                                x = res.end_pt.x;
                                skip_idx += @intCast(u32, x - last_x);
                            }
                            continue;
                        }
                        x += 1;
                        skip_idx += 1;
                    }
                }
            }
        }

        fn expandVoxelMesh(world: *World, chunk: *Chunk, skip_grid: *[ChunkSize*ChunkSize*ChunkSize]u8, start_pt: VoxelPt, end_pt: VoxelPt, voxel_id: VoxelId) i32 {
            const mat_type = world.voxels.getNoCheck(voxel_id).mat_type;

            // Expand +x.
            var x = end_pt.x;
            var skip_idx = @intCast(u32, start_pt.y * ChunkSize * ChunkSize + start_pt.z * ChunkSize + end_pt.x);
            while (x < ChunkSize) : (x += 1) {
                const skip = skip_grid[skip_idx];
                if (skip > 0) {
                    break;
                }
                const expand_pt = VoxelPt.init(x, start_pt.y, start_pt.z);
                const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                if (res.is_empty) {
                    fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                    break;
                }
                const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                if (expand_mat_type != mat_type) {
                    break;
                }
                skip_idx += 1;
            }

            // Expand +z from (end.x, start.y, start.z + 1) up to (x, start.y+1, end.z).
            var expand_z_to_end = true;
            skip_idx = @intCast(u32, start_pt.y * ChunkSize * ChunkSize + (start_pt.z + 1) * ChunkSize + end_pt.x);
            var z = start_pt.z + 1;
            const advance_z_skip_inc = ChunkSize - @intCast(u8, x - end_pt.x);
            b: while (z < end_pt.z) : (z += 1) {
                var tx = end_pt.x;
                while (tx < x) : (tx += 1) {
                    const skip = skip_grid[skip_idx];
                    if (skip > 0) {
                        expand_z_to_end = false;
                        break :b;
                    }
                    const expand_pt = VoxelPt.init(tx, start_pt.y, z);
                    const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                    if (res.is_empty) {
                        fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                        expand_z_to_end = false;
                        break :b;
                    }

                    const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                    if (expand_mat_type != mat_type) {
                        expand_z_to_end = false;
                        break :b;
                    }
                    skip_idx += 1;
                }
                skip_idx += advance_z_skip_inc;
            }

            // Expand +z from (start.x, start.y, end.z) up to (x, start.y+1, ChunkSize)
            if (expand_z_to_end) {
                skip_idx = @intCast(u32, start_pt.y * ChunkSize * ChunkSize + end_pt.z * ChunkSize + start_pt.x);
                z = end_pt.z;
                const advance_z_skip_inc2 = ChunkSize - @intCast(u8, x - start_pt.x);
                b: while (z < ChunkSize) : (z += 1) {
                    var tx = start_pt.x;
                    while (tx < x) : (tx += 1) {
                        const skip = skip_grid[skip_idx];
                        if (skip > 0) {
                            break :b;
                        }
                        const expand_pt = VoxelPt.init(tx, start_pt.y, z);
                        const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                        if (res.is_empty) {
                            fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                            break :b;
                        }

                        const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                        if (expand_mat_type != mat_type) {
                            break :b;
                        }
                        skip_idx += 1;
                    }
                    skip_idx += advance_z_skip_inc2;
                }
            }

            var expand_y_to_end = true;
            var y = start_pt.y + 1;
            b: while (y < end_pt.y) : (y += 1) {
                // Expand +y from (end.x, start.y+1, start.z) to (x, end.y, z)
                skip_idx = @intCast(u32, y * ChunkSize * ChunkSize + start_pt.z * ChunkSize + end_pt.x);
                const advance_z_skip_inc2 = ChunkSize - @intCast(u8, x - end_pt.x);
                var tz = start_pt.z;
                while (tz < z) : (tz += 1) {
                    var tx = end_pt.x;
                    while (tx < x) : (tx += 1) {
                        const skip = skip_grid[skip_idx];
                        if (skip > 0) {
                            expand_y_to_end = false;
                            break :b;
                        }
                        const expand_pt = VoxelPt.init(tx, y, tz);
                        const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                        if (res.is_empty) {
                            fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                            expand_y_to_end = false;
                            break :b;
                        }
                        const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                        if (expand_mat_type != mat_type) {
                            expand_y_to_end = false;
                            break :b;
                        }
                        skip_idx += 1;
                    }
                    skip_idx += advance_z_skip_inc2;
                }

                // Expand +y from (start.x, start.y+1, end.z) to (end.x, start.y+1, z)
                if (z > end_pt.z) {
                    skip_idx = @intCast(u32, y * ChunkSize * ChunkSize + end_pt.z * ChunkSize + start_pt.x);
                    const advance_z_skip_inc3 = ChunkSize - @intCast(u8, end_pt.x - start_pt.x);
                    tz = end_pt.z;
                    while (tz < z) : (tz += 1) {
                        var tx = start_pt.x;
                        while (tx < x) : (tx += 1) {
                            const skip = skip_grid[skip_idx];
                            if (skip > 0) {
                                expand_y_to_end = false;
                                break :b;
                            }
                            const expand_pt = VoxelPt.init(tx, y, tz);
                            const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                            if (res.is_empty) {
                                fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                                expand_y_to_end = false;
                                break :b;
                            }
                            const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                            if (expand_mat_type != mat_type) {
                                expand_y_to_end = false;
                                break :b;
                            }
                            skip_idx += 1;
                        }
                        skip_idx += advance_z_skip_inc3;
                    }
                }
            }

            if (expand_y_to_end) {
                // Expand +y from (start.x, end.y, start.z) to (x, ChunkSize, z)
                y = end_pt.y;
                skip_idx = @intCast(u32, y * ChunkSize * ChunkSize + start_pt.z * ChunkSize + start_pt.x);
                const advance_z_skip_inc2 = ChunkSize - @intCast(u8, x - start_pt.x);
                const advance_y_skip_inc = ChunkSize * (ChunkSize - @intCast(u32, z - start_pt.z));
                b: while (y < ChunkSize) : (y += 1) {
                    var tz = start_pt.z;
                    while (tz < z) : (tz += 1) {
                        var tx = start_pt.x;
                        while (tx < x) : (tx += 1) {
                            const skip = skip_grid[skip_idx];
                            if (skip > 0) {
                                break :b;
                            }
                            const expand_pt = VoxelPt.init(tx, y, tz);
                            const res = getChunkVoxelBounds(world.*, chunk, expand_pt);
                            if (res.is_empty) {
                                fillSkipGrid(skip_grid, expand_pt, res.end_pt, @intCast(u8, res.end_pt.x));
                                break :b;
                            }
                            const expand_mat_type = world.voxels.getNoCheck(res.voxel_id).mat_type;
                            if (expand_mat_type != mat_type) {
                                break :b;
                            }
                            skip_idx += 1;
                        }
                        skip_idx += advance_z_skip_inc2;
                    }
                    skip_idx += advance_y_skip_inc;
                }
            }

            const mesh_end_pt = VoxelPt.init(x, y, z);
            chunk.meshes.append(world.alloc, .{
                .start_pt = start_pt,
                .end_pt = mesh_end_pt,
            }) catch fatal();

            // Mark to skip generated mesh bounds.
            fillSkipGrid(skip_grid, start_pt, mesh_end_pt, @intCast(u8, mesh_end_pt.x));
            return mesh_end_pt.x;
        }

        pub fn getOrCreateChunk(self: *World, chunk_pt: ChunkPt) *Chunk {
            const chunk_res = self.chunks.getOrPut(chunk_pt) catch fatal();
            if (!chunk_res.found_existing) {
                chunk_res.value_ptr.* = .{
                    .meshes = .{},
                    .children = .{ NullId, NullId, NullId, NullId, NullId, NullId, NullId, NullId },
                    .is_voxel_mask = 0,
                    .start_pt = getChunkStartPt(chunk_pt),
                };
            }
            return chunk_res.value_ptr;
        }

        fn fillSkipGrid(skip_grid: *[ChunkSize*ChunkSize*ChunkSize]u8, start_pt: VoxelPt, end_pt: VoxelPt, value: u8) void {
            // TODO: don't fill the current x line since greedy mesh advances past end_pt.x.
            var skip_idx = @intCast(u32, start_pt.y * ChunkSize * ChunkSize + start_pt.z * ChunkSize + start_pt.x);
            var y = start_pt.y;
            const advance_z_skip_inc = ChunkSize - @intCast(u32, end_pt.x - start_pt.x);
            const advance_y_skip_inc = ChunkSize * (ChunkSize - @intCast(u32, end_pt.z - start_pt.z));
            while (y < end_pt.y) : (y += 1) {
                var z = start_pt.z;
                while (z < end_pt.z) : (z += 1) {
                    var x = start_pt.x;
                    while (x < end_pt.x) : (x += 1) {
                        skip_grid[skip_idx] = value;
                        skip_idx += 1;
                    }
                    skip_idx += advance_z_skip_inc;
                }
                skip_idx += advance_y_skip_inc;
            }
        }

        /// pt is relative. Used by mesh generation.
        fn getChunkVoxelBounds(world: World, chunk: *Chunk, pt: VoxelPt) ChunkVoxelBounds {
            var cur_pos = VoxelPt.init(0, 0, 0);
            var cur_subregion_size: i32 = ChunkSize/2; // i32 to avoid casting.
            var oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
            var octant = idx_to_octant[oct_res.oct_idx];
            if (chunk.is_voxel_mask & @enumToInt(octant) > 0) {
                // Octant contains voxel.
                return .{
                    .voxel_id = chunk.children[oct_res.oct_idx],
                    .end_pt = VoxelPt.init(oct_res.new_pt.x + cur_subregion_size, oct_res.new_pt.y + cur_subregion_size, oct_res.new_pt.z + cur_subregion_size),
                    .is_empty = false,
                };
            } else {
                if (chunk.children[oct_res.oct_idx] == NullId) {
                    return .{
                        .voxel_id = undefined,
                        .end_pt = VoxelPt.init(oct_res.new_pt.x + cur_subregion_size, oct_res.new_pt.y + cur_subregion_size, oct_res.new_pt.z + cur_subregion_size),
                        .is_empty = true,
                    };
                }
            }

            var cur_region_id = chunk.children[oct_res.oct_idx];

            var i: u32 = 1;
            while (i < MaxDepth) : (i += 1) {
                cur_pos = oct_res.new_pt;
                cur_subregion_size = cur_subregion_size >> 1;

                // Find the next sub-region or voxel-region.
                oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
                octant = idx_to_octant[oct_res.oct_idx];
                const subregion = world.oct_regions.getNoCheck(cur_region_id);
                var next_subregion_id = subregion.children[oct_res.oct_idx];
                if (subregion.is_voxel_mask & @enumToInt(octant) > 0) {
                    // Octant contains voxel.
                    return .{
                        .voxel_id = next_subregion_id,
                        .end_pt = VoxelPt.init(oct_res.new_pt.x + cur_subregion_size, oct_res.new_pt.y + cur_subregion_size, oct_res.new_pt.z + cur_subregion_size),
                        .is_empty = false,
                    };
                } else {
                    if (next_subregion_id == NullId) {
                        return .{
                            .voxel_id = undefined,
                            .end_pt = VoxelPt.init(oct_res.new_pt.x + cur_subregion_size, oct_res.new_pt.y + cur_subregion_size, oct_res.new_pt.z + cur_subregion_size),
                            .is_empty = true,
                        };
                    }
                }
                cur_region_id = next_subregion_id;
            }

            cur_pos = oct_res.new_pt;
            const oct_idx = getLeafVoxelIdx(cur_pos, 1, pt);
            const subregion = world.oct_regions.getNoCheck(cur_region_id);
            const voxel_id = subregion.children[oct_idx];
            if (voxel_id == NullId) {
                return .{
                    .voxel_id = undefined,
                    .end_pt = VoxelPt.init(pt.x + 1, pt.y + 1, pt.z + 1),
                    .is_empty = true,
                };
            } else {
                return .{
                    .voxel_id = voxel_id,
                    .end_pt = VoxelPt.init(pt.x + 1, pt.y + 1, pt.z + 1),
                    .is_empty = false,
                };
            }
        }

        fn getVoxel(world: World, pt: VoxelPt) ?Voxel {
            const chunk_pt = voxelToChunkPt(pt);
            const chunk = world.getChunk(chunk_pt) orelse return null;

            // First index from chunk root.
            var cur_pos = VoxelPt.init(chunk_pt.x * ChunkSize, chunk_pt.y * ChunkSize, chunk_pt.z * ChunkSize);
            var cur_subregion_size: i32 = ChunkSize/2; // i32 to avoid casting.
            var oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
            var octant = idx_to_octant[oct_res.oct_idx];
            if (chunk.is_voxel_mask & @enumToInt(octant) > 0) {
                // Octant contains voxel.
                const voxel_id = chunk.children[oct_res.oct_idx];
                return world.voxels.getNoCheck(voxel_id);
            } else {
                if (chunk.children[oct_res.oct_idx] == NullId) {
                    return null;
                }
            }

            var cur_region_id = chunk.children[oct_res.oct_idx];

            // Skip 1 iteration since first is done outside the loop. Can break out early if an oct child points to the same voxel type.
            var i: u32 = 1;
            while (i < MaxDepth) : (i += 1) {
                cur_pos = oct_res.new_pt;
                cur_subregion_size = cur_subregion_size >> 1;

                // Find the next sub-region or voxel-region.
                oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
                octant = idx_to_octant[oct_res.oct_idx];
                const subregion = world.oct_regions.getNoCheck(cur_region_id);
                var next_subregion_id = subregion.children[oct_res.oct_idx];
                if (subregion.is_voxel_mask & @enumToInt(octant) > 0) {
                    // Octant contains voxel.
                    return world.voxels.getNoCheck(next_subregion_id);
                } else {
                    if (next_subregion_id == NullId) {
                        return null;
                    }
                }
                cur_region_id = next_subregion_id;
            }

            cur_pos = oct_res.new_pt;
            const oct_idx = getLeafVoxelIdx(cur_pos, 1, pt);
            const subregion = world.oct_regions.getNoCheck(cur_region_id);
            const voxel_id = subregion.children[oct_idx];
            if (voxel_id == NullId) {
                return null;
            } else {
                return world.voxels.getNoCheck(voxel_id);
            }
        }

        fn rremoveVoxelRegion(world: *World, region_id: OctRegionId) void {
            if (region_id == NullId) {
                return;
            }
            const region = world.oct_regions.getNoCheck(region_id);
            inline for (idx_to_octant) |octant, i| {
                if (region.is_voxel_mask & @enumToInt(octant) > 0) {
                    world.voxels.remove(region.children[i]);
                } else {
                    rremoveVoxelRegion(world, region.children[i]);
                }
            }
            world.oct_regions.remove(region_id);
        }

        pub fn fillVoxelRegion(world: *World, chunk_pt: ChunkPt, path: []const Octant, mat_type: VoxelMaterial) void {
            const chunk = getOrCreateChunk(world, chunk_pt);

            if (path.len == 0) {
                inline for (idx_to_octant) |octant, i| {
                    if (chunk.is_voxel_mask & @enumToInt(octant) > 0) {
                        const voxel_id = chunk.children[i];
                        const voxel = world.voxels.getPtrNoCheck(voxel_id);
                        if (voxel.mat_type != mat_type) {
                            voxel.mat_type = mat_type;
                        }
                    } else {
                        rremoveVoxelRegion(world, chunk.children[i]);
                        chunk.children[i] = world.voxels.add(.{
                            .mat_type = mat_type,
                        }) catch fatal();
                        chunk.is_voxel_mask |= @enumToInt(octant);
                    }
                }
                return;
            }

            var oct_idx = getOctantIdx(path[0]);
            if (chunk.is_voxel_mask & @enumToInt(path[0]) > 0) {
                const voxel_id = chunk.children[oct_idx];
                const voxel = world.voxels.getPtrNoCheck(voxel_id);
                if (voxel.mat_type == mat_type) {
                    return;
                } else {
                    if (path.len == 1) {
                        // Change the mat type.
                        voxel.mat_type = mat_type;
                        return;
                    } else {
                        // Break voxel into octs.
                        world.voxels.remove(voxel_id);
                        chunk.children[oct_idx] = world.oct_regions.add(.{
                            .children = .{ voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id },
                            .is_voxel_mask = @enumToInt(Octant.All),
                        }) catch fatal();
                        chunk.is_voxel_mask &= ~@enumToInt(path[0]);
                    }
                }
            } else {
                if (path.len == 1) {
                    if (chunk.children[oct_idx] != NullId) {
                        rremoveVoxelRegion(world, chunk.children[oct_idx]);
                    }
                    // Insert voxel.
                    chunk.children[oct_idx] = world.voxels.add(.{
                        .mat_type = mat_type,
                    }) catch fatal();
                    chunk.is_voxel_mask |= @enumToInt(path[0]);
                    return;
                }
            }

            var region_id = chunk.children[oct_idx];
            var region = world.oct_regions.getPtrNoCheck(region_id);

            if (path.len > 2) {
                var path_idx: u32 = 1;
                for (path[1..path.len-1]) |octant| {
                    oct_idx = getOctantIdx(octant);
                    if (region.is_voxel_mask & @enumToInt(octant) > 0) {
                        const voxel_id = region.children[oct_idx];
                        const voxel = world.voxels.getPtrNoCheck(voxel_id);
                        if (voxel.mat_type == mat_type) {
                            return;
                        } else {
                            // Break voxel into octs.
                            world.voxels.remove(voxel_id);
                            const new_region_id = world.oct_regions.add(.{
                                .children = .{ voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id },
                                .is_voxel_mask = @enumToInt(Octant.All),
                            }) catch fatal();
                            region = world.oct_regions.getPtrNoCheck(region_id);
                            region.children[oct_idx] = new_region_id;
                            region.is_voxel_mask &= ~@enumToInt(octant);
                        }
                    } 
                    region_id = region.children[oct_idx];
                    path_idx += 1;
                }
            }

            const octant = path[path.len-1];
            oct_idx = getOctantIdx(octant);
            region = world.oct_regions.getPtrNoCheck(region_id);
            if (region.is_voxel_mask & @enumToInt(octant) > 0) {
                const voxel_id = region.children[oct_idx];
                const voxel = world.voxels.getPtrNoCheck(voxel_id);
                if (voxel.mat_type == mat_type) {
                    return;
                } else {
                    // Change the mat type.
                    voxel.mat_type = mat_type;
                    return;
                }
            } else {
                if (region.children[oct_idx] != NullId) {
                    rremoveVoxelRegion(world, region.children[oct_idx]);
                }
                // Insert voxel.
                region.children[oct_idx] = world.voxels.add(.{
                    .mat_type = mat_type,
                }) catch fatal();
                region.is_voxel_mask |= @enumToInt(octant);
            }
        }

        pub fn setVoxel(world: *World, pt: VoxelPt, mat_type: VoxelMaterial) void {
            const chunk_pt = voxelToChunkPt(pt);
            const chunk = getOrCreateChunk(world, chunk_pt);

            const path = setVoxelDownward(world, chunk, chunk_pt, pt, mat_type);
            if (path.len == MaxDepth+1) {
                world.compressUpwards(chunk, path);
            }
        }

        /// Set's the voxel at a position but doesn't perform the upward optimize step.
        fn setVoxelDownward(self: *World, chunk: *Chunk, chunk_pt: ChunkPt, pt: VoxelPt, mat_type: VoxelMaterial) []const OctPathItem {
            // First index from chunk root.
            var cur_pos = VoxelPt.init(chunk_pt.x * ChunkSize, chunk_pt.y * ChunkSize, chunk_pt.z * ChunkSize);
            var cur_subregion_size: i32 = ChunkSize/2; // i32 to avoid casting.
            var oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
            var octant = idx_to_octant[oct_res.oct_idx];
            if (chunk.is_voxel_mask & @enumToInt(octant) > 0) {
                // Octant contains voxel.
                const voxel_id = chunk.children[oct_res.oct_idx];
                const voxel = self.voxels.getNoCheck(voxel_id);
                if (cur_subregion_size > 1 and voxel.mat_type != mat_type) {
                    // Break the voxel into an oct region.
                    chunk.children[oct_res.oct_idx] = self.oct_regions.add(.{
                        .children = .{ voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id },
                        .is_voxel_mask = @enumToInt(Octant.All),
                    }) catch fatal();
                } else {
                    // At leaf subregion. Just update the voxel.
                    self.voxels.getPtrNoCheck(voxel_id).mat_type = mat_type;
                    oct_path_buf[0] = .{
                        .item_id = voxel_id,
                        .oct_idx = oct_res.oct_idx,
                    };
                    return oct_path_buf[0..1];
                }
            } else {
                if (chunk.children[oct_res.oct_idx] == NullId) {
                    if (cur_subregion_size == 1) {
                        // At leaf region. Add voxel.
                        chunk.children[oct_res.oct_idx] = self.voxels.add(.{ .mat_type = mat_type }) catch fatal();
                        chunk.is_voxel_mask |= @enumToInt(octant);
                        oct_path_buf[0] = .{
                            .item_id = chunk.children[oct_res.oct_idx],
                            .oct_idx = oct_res.oct_idx,
                        };
                        return oct_path_buf[0..1];
                    } else {
                        // Create subregion.
                        chunk.children[oct_res.oct_idx] = self.oct_regions.add(.{
                            .children = .{ NullId, NullId, NullId, NullId, NullId, NullId, NullId, NullId },
                            .is_voxel_mask = 0,
                        }) catch fatal();
                    }
                }
            }

            var cur_region_id = chunk.children[oct_res.oct_idx];
            oct_path_buf[0] = .{
                .item_id = cur_region_id,
                .oct_idx = oct_res.oct_idx,
            };
            var path_idx: u32 = 1;

            // Skip 1 iteration since first is done outside the loop. Can break out early if an oct child points to the same voxel type.
            var i: u32 = 1;
            while (i < MaxDepth) : (i += 1) {
                cur_pos = oct_res.new_pt;
                cur_subregion_size = cur_subregion_size >> 1;

                // Find the next sub-region or voxel-region.
                oct_res = getChildOct(cur_pos, cur_subregion_size, pt);
                octant = idx_to_octant[oct_res.oct_idx];
                const subregion = self.oct_regions.getPtrNoCheck(cur_region_id);
                var next_subregion_id: u32 = subregion.children[oct_res.oct_idx];
                if (subregion.is_voxel_mask & @enumToInt(octant) > 0) {
                    // Octant contains voxel.
                    const voxel_id = subregion.children[oct_res.oct_idx];
                    const voxel = self.voxels.getNoCheck(voxel_id);
                    if (cur_subregion_size > 1 and voxel.mat_type != mat_type) {
                        // Break the voxel into an oct region.
                        next_subregion_id = self.oct_regions.add(.{
                            .children = .{ voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id, voxel_id },
                            .is_voxel_mask = 0,
                        }) catch fatal();
                        // subregion is invalidated.
                        self.oct_regions.getPtrNoCheck(cur_region_id).children[oct_res.oct_idx] = next_subregion_id;
                    } else {
                        // At leaf subregion. Just update the voxel.
                        self.voxels.getPtrNoCheck(voxel_id).mat_type = mat_type;
                        oct_path_buf[path_idx] = .{
                            .item_id = voxel_id,
                            .oct_idx = oct_res.oct_idx,
                        };
                        return oct_path_buf[0..path_idx+1];
                    }
                } else {
                    if (next_subregion_id == NullId) {
                        // Create subregion.
                        next_subregion_id = self.oct_regions.add(.{
                            .children = .{ NullId, NullId, NullId, NullId, NullId, NullId, NullId, NullId },
                            .is_voxel_mask = 0,
                        }) catch fatal();
                        // subregion is invalidated.
                        self.oct_regions.getPtrNoCheck(cur_region_id).children[oct_res.oct_idx] = next_subregion_id;
                    }
                }

                cur_region_id = next_subregion_id;
                oct_path_buf[path_idx] = .{
                    .item_id = cur_region_id,
                    .oct_idx = oct_res.oct_idx,
                };
                path_idx += 1;
            }

            // Leaf subregion.
            cur_pos = oct_res.new_pt;
            const oct_idx = getLeafVoxelIdx(cur_pos, 1, pt);
            octant = idx_to_octant[oct_idx];
            const subregion = self.oct_regions.getPtrNoCheck(cur_region_id);
            const voxel_id = subregion.children[oct_idx];
            if (voxel_id == NullId) {
                subregion.children[oct_idx] = self.voxels.add(.{ .mat_type = mat_type }) catch fatal();
                subregion.is_voxel_mask |= @enumToInt(octant);
                oct_path_buf[path_idx] = .{
                    .item_id = subregion.children[oct_idx],
                    .oct_idx = oct_idx,
                };
                return oct_path_buf[0..path_idx+1];
            } else {
                self.voxels.getPtrNoCheck(voxel_id).mat_type = mat_type;
                oct_path_buf[path_idx] = .{
                    .item_id = voxel_id,
                    .oct_idx = oct_idx,
                };
                return oct_path_buf[0..path_idx+1];
            }

            // Select voxel.
            // cur_pos = oct_res.new_pt;
            // const voxel_id = cur_region_id;
            // if (mat_type == .Empty) {
            //     if (voxel_id != NullId) {
            //         // Remove voxel.
            //         self.voxels.remove(voxel_id);
            //         const idx = voxel_ref.chunk_voxel_idx;
            //         _ = chunk.voxel_ids.swapRemove(idx);
            //         _ = chunk.voxel_pts.swapRemove(idx);
            //         if (idx != chunk.voxel_ids.items.len) {
            //             // Check if there was a swap and update swapped item's mapping.
            //             const swapped_leaf_id = chunk.parent_leaves.items[idx];
            //             const swapped_leaf_voxel_idx = chunk.parent_leaf_ref_idxes.items[idx];
            //             self.oct_leaves.items[swapped_leaf_id].voxel_refs[swapped_leaf_voxel_idx].chunk_voxel_idx = idx;
            //         }
            //         leaf.voxel_refs[local_voxel_idx].voxel_id = NullId;
            //     }
            // } else {
            //     if (voxel_id == NullId) {
            //         // Add voxel.
            //         const new_id = self.voxels.add(.{
            //             .mat_type = mat_type,
            //         }) catch fatal();
            //         leaf.voxel_refs[local_voxel_idx].voxel_id = new_id;
            //         chunk.voxel_ids.append(self.alloc, new_id) catch fatal();
            //     } else {
            //         // Update voxel.
            //         self.voxels.getPtrNoCheck(voxel_id).mat_type = mat_type;
            //     }
            // }
        }
    };
}

const TestChunks = Chunks(8);
const TestChunks4 = Chunks(4);

test "voxelToChunk" {
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(0, 0, 0)), ChunkPt.init(0, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(1, 0, 0)), ChunkPt.init(0, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(4, 0, 0)), ChunkPt.init(0, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(7, 0, 0)), ChunkPt.init(0, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(8, 0, 0)), ChunkPt.init(1, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(-1, 0, 0)), ChunkPt.init(-1, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(-4, 0, 0)), ChunkPt.init(-1, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(-8, 0, 0)), ChunkPt.init(-1, 0, 0));
    try t.eq(TestChunks.voxelToChunkPt(VoxelPt.init(-9, 0, 0)), ChunkPt.init(-2, 0, 0));
}

test "setVoxel" {
    var world = World.init(t.alloc);
    defer world.deinit();

    // Place single voxel.
    TestChunks.setVoxel(&world, VoxelPt.init(10, 10, 10), .Block);
    try t.eq(world.voxels.size(), 1);
    var voxel = TestChunks.getVoxel(world, VoxelPt.init(10, 10, 10)).?;
    try t.eq(voxel.mat_type, .Block);

    // Placing eight voxels merges into one.
    world.clearVoxels();
    TestChunks.setVoxel(&world, VoxelPt.init(4, 4, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 4, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 4, 5), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 4, 5), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 5, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 5, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 5, 5), .Block);
    try t.eq(world.voxels.size(), 7);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 5, 5), .Block);
    try t.eq(world.voxels.size(), 1);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(4, 4, 4)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(5, 4, 4)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(4, 4, 5)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(5, 4, 5)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(4, 5, 4)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(5, 5, 4)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(4, 5, 5)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks.getVoxel(world, VoxelPt.init(5, 5, 5)).?;
    try t.eq(voxel.mat_type, .Block);

    // Merge into root.
    t.setLogLevel(.debug);
    var world2 = World.init(t.alloc);
    defer world2.deinit();
    TestChunks4.setVoxel(&world2, VoxelPt.init(0, 0, 0), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(1, 0, 0), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(0, 0, 1), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(1, 0, 1), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(0, 1, 0), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(1, 1, 0), .Block);
    TestChunks4.setVoxel(&world2, VoxelPt.init(0, 1, 1), .Block);
    try t.eq(world2.voxels.size(), 7);
    TestChunks4.setVoxel(&world2, VoxelPt.init(1, 1, 1), .Block);
    try t.eq(world2.voxels.size(), 1);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(0, 0, 0)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(1, 0, 0)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(0, 0, 1)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(1, 0, 1)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(0, 1, 0)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(1, 1, 0)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(0, 1, 1)).?;
    try t.eq(voxel.mat_type, .Block);
    voxel = TestChunks4.getVoxel(world2, VoxelPt.init(1, 1, 1)).?;
    try t.eq(voxel.mat_type, .Block);
}

test "genChunkMeshes" {
    var world = World.init(t.alloc);
    defer world.deinit();

    const chunk = TestChunks.getOrCreateChunk(&world, ChunkPt.init(0, 0, 0));
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 0);

    // Single voxel.
    TestChunks.setVoxel(&world, VoxelPt.init(4, 4, 4), .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(4, 4, 4));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(5, 5, 5));

    // Expand voxels in +x direction.
    world.clearVoxels();
    TestChunks.setVoxel(&world, VoxelPt.init(2, 0, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 0), .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(2, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(5, 1, 1));

    // Expand voxels in +x, +z direction.
    TestChunks.setVoxel(&world, VoxelPt.init(2, 0, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 1), .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(2, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(5, 1, 2));

    // Expand voxels in +x, +z, +y direction
    TestChunks.setVoxel(&world, VoxelPt.init(2, 1, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 1, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 1, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(2, 1, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 1, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 1, 1), .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(2, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(5, 2, 2));

    // Fill whole chunk.
    world.clearVoxels();
    TestChunks.fillVoxelRegion(&world, ChunkPt.init(0, 0, 0), &.{}, .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(0, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(8, 8, 8));

    // Fill subregion.
    world.clearVoxels();
    TestChunks.fillVoxelRegion(&world, ChunkPt.init(0, 0, 0), &.{ .FarBottomLeft }, .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 1);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(0, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(4, 4, 4));

    // Fill T-shape
    world.clearVoxels();
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 0), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 1), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 2), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 2), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 3), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 3), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 4), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 5), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 5), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(3, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(4, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(2, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(2, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(1, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(1, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(0, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(0, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(5, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(6, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(6, 0, 7), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(7, 0, 6), .Block);
    TestChunks.setVoxel(&world, VoxelPt.init(7, 0, 7), .Block);
    TestChunks.genChunkMeshes(&world, chunk);
    try t.eq(chunk.meshes.items.len, 3);
    try t.eq(chunk.meshes.items[0].start_pt, VoxelPt.init(3, 0, 0));
    try t.eq(chunk.meshes.items[0].end_pt, VoxelPt.init(5, 1, 8));
    try t.eq(chunk.meshes.items[1].start_pt, VoxelPt.init(0, 0, 6));
    try t.eq(chunk.meshes.items[1].end_pt, VoxelPt.init(3, 1, 8));
    try t.eq(chunk.meshes.items[2].start_pt, VoxelPt.init(5, 0, 6));
    try t.eq(chunk.meshes.items[2].end_pt, VoxelPt.init(8, 1, 8));
}

pub const Chunk = struct {
    /// Generated meshes for rendering.
    meshes: std.ArrayListUnmanaged(ChunkMesh),

    start_pt: VoxelPt,

    children: [8]OctRegionOrVoxelId,
    is_voxel_mask: u8,

    pub fn deinit(self: *Chunk, alloc: std.mem.Allocator) void {
        self.meshes.deinit(alloc);
    }
};

const ChunkMesh = struct {
    // Far bottom left.
    start_pt: VoxelPt,
    // Near top right. Exclusive.
    end_pt: VoxelPt,
};

pub const idx_to_octant: [8]Octant = .{
    .FarBottomLeft,
    .FarBottomRight,
    .NearBottomLeft,
    .NearBottomRight,
    .FarTopLeft,
    .FarTopRight,
    .NearTopLeft,
    .NearTopRight,
};

inline fn ctGetOctantIdx(comptime O: Octant) u3 {
    switch (O) {
        .FarBottomLeft => return 0,
        .FarBottomRight => return 1,
        .NearBottomLeft => return 2,
        .NearBottomRight => return 3,
        .FarTopLeft => return 4,
        .FarTopRight => return 5,
        .NearTopLeft => return 6,
        .NearTopRight => return 7,
        else => unreachable,
    }
}

inline fn getNextStartPt(comptime O: Octant, start_pt: VoxelPt, subregion_size: i32) VoxelPt {
    switch (O) {
        .FarBottomLeft => return VoxelPt.init(start_pt.x, start_pt.y, start_pt.z),
        .FarBottomRight => return VoxelPt.init(start_pt.x + subregion_size, start_pt.y, start_pt.z),
        .NearBottomLeft => return VoxelPt.init(start_pt.x, start_pt.y, start_pt.z + subregion_size),
        .NearBottomRight => return VoxelPt.init(start_pt.x + subregion_size, start_pt.y, start_pt.z + subregion_size),
        .FarTopLeft => return VoxelPt.init(start_pt.x, start_pt.y + subregion_size, start_pt.z),
        .FarTopRight => return VoxelPt.init(start_pt.x + subregion_size, start_pt.y + subregion_size, start_pt.z),
        .NearTopLeft => return VoxelPt.init(start_pt.x, start_pt.y + subregion_size, start_pt.z + subregion_size),
        .NearTopRight => return VoxelPt.init(start_pt.x + subregion_size, start_pt.y + subregion_size, start_pt.z + subregion_size),
        else => unreachable,
    }
}

const ChunkVoxelBounds = struct {
    voxel_id: VoxelId,
    end_pt: VoxelPt, // Exclusive.
    is_empty: bool,
};

inline fn getChildOct(start_pt: VoxelPt, subregion_size: i32, target_pt: VoxelPt) OctResult {
    var new_pt = start_pt;
    const left = if (target_pt.x < start_pt.x + subregion_size) OctLeft else b: {
        new_pt.x += subregion_size;
        break :b 0;
    };
    const bottom = if (target_pt.y < start_pt.y + subregion_size) OctBottom else b: {
        new_pt.y += subregion_size;
        break :b 0;
    };
    const far = if (target_pt.z < start_pt.z + subregion_size) OctFar else b: {
        new_pt.z += subregion_size;
        break :b 0;
    };
    return .{
        .oct_idx = switch (left | bottom | far) {
            OctLeft | OctBottom | OctFar => 0,
            OctBottom | OctFar => 1,
            OctLeft | OctBottom => 2,
            OctBottom => 3,
            OctLeft | OctFar => 4,
            OctFar => 5,
            OctLeft => 6,
            0 => 7,
        },
        .new_pt = new_pt,
    };
}

/// Like getChildOct but doesn't return a new position.
inline fn getLeafVoxelIdx(start_pt: VoxelPt, subregion_size: i32, target_pt: VoxelPt) u3 {
    const left = if (target_pt.x < start_pt.x + subregion_size) OctLeft else 0;
    const bottom = if (target_pt.y < start_pt.y + subregion_size) OctBottom else 0;
    const far = if (target_pt.z < start_pt.z + subregion_size) OctFar else 0;
    return switch (left | bottom | far) {
        OctLeft | OctBottom | OctFar => 0,
        OctBottom | OctFar => 1,
        OctLeft | OctBottom => 2,
        OctBottom => 3,
        OctLeft | OctFar => 4,
        OctFar => 5,
        OctLeft => 6,
        0 => 7,
    };
}

pub const Octant = enum(u8) {
    FarBottomLeft   = 0b00000001,
    FarBottomRight  = 0b00000010,
    NearBottomLeft  = 0b00000100,
    NearBottomRight = 0b00001000,
    FarTopLeft      = 0b00010000,
    FarTopRight     = 0b00100000,
    NearTopLeft     = 0b01000000,
    NearTopRight    = 0b10000000,
    All             = 0b11111111,
};

const OctResult = struct {
    new_pt: VoxelPt,
    oct_idx: u3,
};

const OctLeft: u3 = 1;
const OctBottom: u3 = 2;
const OctFar: u3 = 4; 

pub const OctPathItem = struct {
    item_id: OctRegionOrVoxelId,

    /// Octant from the parent this item belongs to.
    oct_idx: u3,
};

inline fn getOctantIdx(octant: Octant) u3 {
    switch (octant) {
        .FarBottomLeft => return 0,
        .FarBottomRight => return 1,
        .NearBottomLeft => return 2,
        .NearBottomRight => return 3,
        .FarTopLeft => return 4,
        .FarTopRight => return 5,
        .NearTopLeft => return 6,
        .NearTopRight => return 7,
        else => unreachable,
    }
}

pub const MeshStartPt = struct {
    voxel_id: VoxelId,
    start_pt: VoxelPt,
    size: i32,
};

pub fn compareStartPt(_: void, a: MeshStartPt, b: MeshStartPt) std.math.Order {
    if (a.start_pt.y < b.start_pt.y) {
        return .lt;
    } else if (a.start_pt.y > b.start_pt.y) {
        return .gt;
    }
    if (a.start_pt.z < b.start_pt.z) {
        return .lt;
    } else if (a.start_pt.z > b.start_pt.z) {
        return .gt;
    }
    if (a.start_pt.x < b.start_pt.x) {
        return .lt;
    } else return .gt;
    // Assume no equal points.
}