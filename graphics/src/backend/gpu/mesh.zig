const std = @import("std");
const stdx = @import("stdx");
const Vec3 = stdx.math.Vec3;
const Vec4 = stdx.math.Vec4;
const Mat4 = stdx.math.Mat4;
const gl = @import("gl");

const graphics = @import("../../graphics.zig");
const TexShaderVertex = graphics.gpu.TexShaderVertex;
const Color = graphics.Color;
const log = stdx.log.scoped(.mesh);

const StartVertexBufferSize = 20000;
const StartIndexBufferSize = StartVertexBufferSize * 8;

const MaxVertexBufferSize = 20000 * 4;
const MaxIndexBufferSize = MaxVertexBufferSize * 8;

// TODO: Move vertex and index buffer management to Batcher.
/// Vertex, index, mats, materials buffer.
/// Buffer slices can be mapped directly (zero copy) to the gpu for vulkan or desktop opengl.
/// Mesh doesn't care if the memory is mapped and just writes to buffer and advances the index.
pub const Mesh = struct {
    index_buffer_type: gl.GLenum = gl.GL_UNSIGNED_SHORT,
    alloc: std.mem.Allocator,
    index_buf: []u16,
    cur_index_buf_size: u32,
    vert_buf: []TexShaderVertex,
    cur_vert_buf_size: u32,

    mats_buf: []Mat4,
    cur_mats_buf_size: u32,
    materials_buf: []graphics.Material,
    cur_materials_buf_size: u32,

    pub fn init(alloc: std.mem.Allocator, mats_buf: []Mat4, materials_buf: []graphics.Material) Mesh {
        const vertex_buf = alloc.alloc(TexShaderVertex, StartVertexBufferSize) catch unreachable;
        const index_buf = alloc.alloc(u16, StartIndexBufferSize) catch unreachable;
        return Mesh{
            .alloc = alloc,
            .index_buffer_type = gl.GL_UNSIGNED_SHORT,
            .vert_buf = vertex_buf,
            .index_buf = index_buf,
            .mats_buf = mats_buf,
            .materials_buf = materials_buf,
            .cur_vert_buf_size = 0,
            .cur_index_buf_size = 0,
            .cur_mats_buf_size = 0,
            .cur_materials_buf_size = 0,
        };
    }

    pub fn deinit(self: Mesh) void {
        self.alloc.free(self.vert_buf);
        self.alloc.free(self.index_buf);
    }

    pub fn reset(self: *Mesh) void {
        self.cur_vert_buf_size = 0;
        self.cur_index_buf_size = 0;
        self.cur_mats_buf_size = 0;
        self.cur_materials_buf_size = 0;
    }

    pub fn pushMatrix(self: *Mesh, mat: Mat4) void {
        self.mats_buf[self.cur_mats_buf_size] = mat;
        self.cur_mats_buf_size += 1;
    }

    pub fn pushMaterial(self: *Mesh, material: graphics.Material) void {
        self.materials_buf[self.cur_materials_buf_size] = material;
        self.cur_materials_buf_size += 1;
    }

    pub fn pushVertex(self: *Mesh, vert: TexShaderVertex) void {
        self.vert_buf[self.cur_vert_buf_size] = vert;
        self.cur_vert_buf_size += 1;
    }

    // Assumes enough capacity.
    pub fn pushVertexGetIndex(self: *Mesh, vert: *TexShaderVertex) u16 {
        const idx = self.cur_vert_buf_size;
        self.vert_buf[self.cur_vert_buf_size] = vert.*;
        self.cur_vert_buf_size += 1;
        return @intCast(u16, idx);
    }

    // Returns the id of the first vertex added.
    pub fn pushVertexes(self: *Mesh, verts: []const TexShaderVertex) u16 {
        const first_idx = self.cur_vert_buf_size;
        for (verts) |it| {
            self.vert_buf[self.cur_vert_buf_size] = it;
            self.cur_vert_buf_size += 1;
        }
        return @intCast(u16, first_idx);
    }

    pub fn getNextIndexId(self: *const Mesh) u16 {
        return @intCast(u16, self.cur_vert_buf_size);
    }

    pub fn pushIndex(self: *Mesh, idx: u16) void {
        self.index_buf[self.cur_index_buf_size] = idx;
        self.cur_index_buf_size += 1;
    }

    pub fn pushDeltaIndexes(self: *Mesh, offset: u16, deltas: []const u16) void {
        for (deltas) |it| {
            self.pushIndex(offset + it);
        }
    }

    /// Assumes triangle in cw order. Pushes as ccw triangle.
    pub fn pushTriangle(self: *Mesh, v1: u16, v2: u16, v3: u16) void {
        self.index_buf[self.cur_index_buf_size] = v1;
        self.index_buf[self.cur_index_buf_size + 1] = v3;
        self.index_buf[self.cur_index_buf_size + 2] = v2;
        self.cur_index_buf_size += 3;
    }

    /// Assumes clockwise order of verts but pushes ccw triangles.
    pub fn pushQuad(self: *Mesh, v0: Vec4, v1: Vec4, v2: Vec4, v3: Vec4, base: TexShaderVertex) void {
        var vert = base;
        const start = @intCast(u16, self.cur_vert_buf_size);
        vert.pos = v0;
        self.pushVertex(vert);
        vert.pos = v1;
        self.pushVertex(vert);
        vert.pos = v2;
        self.pushVertex(vert);
        vert.pos = v3;
        self.pushVertex(vert);
        self.pushQuadIndexes(start, start + 1, start + 2, start + 3);
    }

    /// Assumes clockwise order of verts but pushes ccw triangles.
    pub fn pushQuadIndexes(self: *Mesh, idx1: u16, idx2: u16, idx3: u16, idx4: u16) void {
        // First triangle.
        self.index_buf[self.cur_index_buf_size] = idx1;
        self.index_buf[self.cur_index_buf_size + 1] = idx4;
        self.index_buf[self.cur_index_buf_size + 2] = idx2;

        // Second triangle.
        self.index_buf[self.cur_index_buf_size + 3] = idx2;
        self.index_buf[self.cur_index_buf_size + 4] = idx4;
        self.index_buf[self.cur_index_buf_size + 5] = idx3;
        self.cur_index_buf_size += 6;
    }

    // Add vertex data that should be together.
    pub fn pushVertexData(self: *Mesh, comptime num_verts: usize, comptime num_indices: usize, vdata: *VertexData(num_verts, num_indices)) void {
        const first_idx = self.pushVertexes(&vdata.verts);
        self.pushDeltaIndexes(first_idx, &vdata.indices);
    }

    pub fn ensureUnusedBuffer(self: *Mesh, vert_inc: usize, index_inc: usize) bool {
        if (self.cur_vert_buf_size + vert_inc > self.vert_buf.len) {
            // Grow buffer.
            var new_size = @floatToInt(u32, @intToFloat(f32, self.cur_vert_buf_size + vert_inc) * 1.5);
            if (new_size > MaxVertexBufferSize) {
                if (vert_inc > MaxVertexBufferSize) {
                    stdx.panicFmt("requesting buffer size {} that exceeds max {}", .{ vert_inc, MaxVertexBufferSize });
                }
                if (self.vert_buf.len < MaxVertexBufferSize) {
                    self.vert_buf = self.alloc.realloc(self.vert_buf, MaxVertexBufferSize) catch unreachable;
                }
                if (self.cur_vert_buf_size + vert_inc > MaxVertexBufferSize) {
                    return false;
                }
            } else {
                self.vert_buf = self.alloc.realloc(self.vert_buf, new_size) catch unreachable;
            }
        }
        if (self.cur_index_buf_size + index_inc > self.index_buf.len) {
            var new_size = @floatToInt(u32, @intToFloat(f32, self.cur_index_buf_size + index_inc) * 1.5);
            if (new_size > MaxIndexBufferSize) {
                if (index_inc > MaxIndexBufferSize) {
                    stdx.panicFmt("requesting buffer size {} that exceeds max {}", .{ index_inc, MaxIndexBufferSize });
                }
                if (self.index_buf.len < MaxIndexBufferSize) {
                    self.index_buf = self.alloc.realloc(self.index_buf, MaxIndexBufferSize) catch unreachable;
                }
                if (self.cur_index_buf_size + index_inc > MaxIndexBufferSize) {
                    return false;
                }
            } else {
                self.index_buf = self.alloc.realloc(self.index_buf, new_size) catch unreachable;
            }
        }
        return true;
    }
};

// Used to set a bunch of data in one go, reducing the number of batcher capacity checks.
pub fn VertexData(comptime num_verts: usize, comptime num_indices: usize) type {
    if (num_indices == 0 or num_indices % 3 != 0) {
        @panic("num_indices must be at least 3 and multiple of 3");
    }
    return struct {
        verts: [num_verts]TexShaderVertex,
        // index value references vertex idx.
        indices: [num_indices]u16,

        pub fn setRect(self: *@This(), offset: u16, tl: u16, tr: u16, br: u16, bl: u16) void {
            // Assumes ccw front face order.
            self.indices[offset .. offset + 6][0..6].* = .{
                // First triangle.
                tl, bl, br,
                // Second triangle.
                br, tr, tl,
            };
        }
    };
}