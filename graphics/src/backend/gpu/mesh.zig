const std = @import("std");
const stdx = @import("stdx");
const gl = @import("gl");

const graphics = @import("../../graphics.zig");
const Color = graphics.Color;
const log = stdx.log.scoped(.mesh);

const StartVertexBufferSize = 2048;
const StartIndexBufferSize = StartVertexBufferSize * 4;

const MaxVertexBufferSize = 2048 * 10;
const MaxIndexBufferSize = MaxVertexBufferSize * 4;

// Vertex and index buffer.
pub const Mesh = struct {
    const Self = @This();

    index_buffer_type: gl.GLenum = gl.GL_UNSIGNED_SHORT,
    alloc: std.mem.Allocator,
    index_buf: []u16,
    cur_index_buf_size: u32,
    vert_buf: []TexShaderVertex,
    cur_vert_buf_size: u32,

    pub fn init(alloc: std.mem.Allocator) Self {
        const vertex_buf = alloc.alloc(TexShaderVertex, StartVertexBufferSize) catch unreachable;
        const index_buf = alloc.alloc(u16, StartIndexBufferSize) catch unreachable;
        return Mesh{
            .alloc = alloc,
            .index_buffer_type = gl.GL_UNSIGNED_SHORT,
            .vert_buf = vertex_buf,
            .index_buf = index_buf,
            .cur_vert_buf_size = 0,
            .cur_index_buf_size = 0,
        };
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.vert_buf);
        self.alloc.free(self.index_buf);
    }

    pub fn addVertex(self: *Self, vert: *TexShaderVertex) void {
        self.vert_buf[self.cur_vert_buf_size] = vert.*;
        self.cur_vert_buf_size += 1;
    }

    // Assumes enough capacity.
    pub fn addVertexGetIndex(self: *Self, vert: *TexShaderVertex) u16 {
        const idx = self.cur_vert_buf_size;
        self.vert_buf[self.cur_vert_buf_size] = vert.*;
        self.cur_vert_buf_size += 1;
        return @intCast(u16, idx);
    }

    // Returns the id of the first vertex added.
    pub fn addVertices(self: *Self, verts: []const TexShaderVertex) u16 {
        const first_idx = self.cur_vert_buf_size;
        for (verts) |it| {
            self.vert_buf[self.cur_vert_buf_size] = it;
            self.cur_vert_buf_size += 1;
        }
        return @intCast(u16, first_idx);
    }

    pub fn getNextIndexId(self: *const Self) u16 {
        return @intCast(u16, self.cur_vert_buf_size);
    }

    pub fn addIndex(self: *Self, idx: u16) void {
        self.index_buf[self.cur_index_buf_size] = idx;
        self.cur_index_buf_size += 1;
    }

    fn addDeltaIndices(self: *Self, offset: u16, deltas: []const u16) void {
        for (deltas) |it| {
            self.addIndex(offset + it);
        }
    }

    // Adds ccw triangle with vertex indices.
    pub fn addTriangle(self: *Self, v1: u16, v2: u16, v3: u16) void {
        self.index_buf[self.cur_index_buf_size] = v1;
        self.index_buf[self.cur_index_buf_size + 1] = v2;
        self.index_buf[self.cur_index_buf_size + 2] = v3;
        self.cur_index_buf_size += 3;
    }

    // Assumes indices are ccw order.
    pub fn addQuad(self: *Self, idx1: u16, idx2: u16, idx3: u16, idx4: u16) void {
        // First triangle.
        self.index_buf[self.cur_index_buf_size] = idx1;
        self.index_buf[self.cur_index_buf_size + 1] = idx2;
        self.index_buf[self.cur_index_buf_size + 2] = idx3;

        // Second triangle.
        self.index_buf[self.cur_index_buf_size + 3] = idx3;
        self.index_buf[self.cur_index_buf_size + 4] = idx4;
        self.index_buf[self.cur_index_buf_size + 5] = idx1;
        self.cur_index_buf_size += 6;
    }

    // Add vertex data that should be together.
    pub fn addVertexData(self: *Self, comptime num_verts: usize, comptime num_indices: usize, vdata: *VertexData(num_verts, num_indices)) void {
        const first_idx = self.addVertices(&vdata.verts);
        self.addDeltaIndices(first_idx, &vdata.indices);
    }

    pub fn ensureUnusedBuffer(self: *Self, vert_inc: usize, index_inc: usize) bool {
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

pub const TexShaderVertex = packed struct {
    const Self = @This();

    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    pos_w: f32,
    uv_x: f32,
    uv_y: f32,
    color_r: f32,
    color_g: f32,
    color_b: f32,
    color_a: f32,

    pub fn setXY(self: *Self, x: f32, y: f32) void {
        self.pos_x = x;
        self.pos_y = y;
        self.pos_z = 0;
        self.pos_w = 1;
    }

    pub fn setColor(self: *Self, color: Color) void {
        self.color_r = @intToFloat(f32, color.channels.r) / 255;
        self.color_g = @intToFloat(f32, color.channels.g) / 255;
        self.color_b = @intToFloat(f32, color.channels.b) / 255;
        self.color_a = @intToFloat(f32, color.channels.a) / 255;
    }

    pub fn setUV(self: *Self, u: f32, v: f32) void {
        self.uv_x = u;
        self.uv_y = v;
    }
};