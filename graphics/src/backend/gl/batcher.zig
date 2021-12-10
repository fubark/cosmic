const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const Mat4 = stdx.math.Mat4;
const gl = @import("gl");
const lyon = @import("lyon");

const graphics = @import("../../graphics.zig");
const ImageId = graphics.ImageId;
const ImageDesc = graphics.gl.ImageDesc;
const GLTextureId = graphics.gl.GLTextureId;
const Color = graphics.Color;
const _mesh = @import("mesh.zig");
const VertexData = _mesh.VertexData;
const TexShaderVertex = _mesh.TexShaderVertex;
const Mesh = _mesh.Mesh;
const log = stdx.log.scoped(.batcher);
const Shader = @import("shader.zig").Shader;

// User must check for buffer space before pushing data into batcher. This allows the caller
// to determine when to flush and run custom logic.
pub const Batcher = struct {
    const Self = @This();

    vert_buf_id: gl.GLuint,
    index_buf_id: gl.GLuint,

    mesh: Mesh,
    mvp: Mat4,
    tex_shader: Shader,

    cur_tex_image: ImageDesc,

    pub fn init(alloc: std.mem.Allocator, tex_shader: Shader) Self {
        var new = Self{
            .mesh = Mesh.init(alloc),
            .vert_buf_id = undefined,
            .index_buf_id = undefined,
            .mvp = undefined,
            .tex_shader = tex_shader,
            .cur_tex_image = .{
                .image_id = 0,
                .tex_id = 0,
            },
        };
        // Generate buffers.
        var buf_ids: [2]gl.GLuint = undefined;
        gl.genBuffers(2, &buf_ids);
        new.vert_buf_id = buf_ids[0];
        new.index_buf_id = buf_ids[1];
        return new;
    }

    pub fn deinit(self: *Self) void {
        self.mesh.deinit();

        const bufs = [_]gl.GLuint{self.vert_buf_id, self.index_buf_id};
        gl.deleteBuffers(2, &bufs);
    }

    pub fn shouldFlushBeforeSetCurrentTexture(self: *Self, tex_id: GLTextureId) bool {
        return tex_id != self.cur_tex_image.tex_id;
    }

    // Caller must check shouldFlushBeforeSetCurrentTexture prior.
    // TODO: we can use sample2d arrays and pass active tex ids in vertex data to further reduce number of flushes.
    pub fn setCurrentTexture(self: *Self, image: ImageDesc) void {
        self.cur_tex_image = image;
    }

    pub fn setMvp(self: *Self, mvp: Mat4) void {
        self.mvp = mvp;
    }

    pub fn ensureUnusedBuffer(self: *Self, vert_inc: usize, index_inc: usize) bool {
        return self.mesh.ensureUnusedBuffer(vert_inc, index_inc);
    }

    // Caller must check if there is enough buffer space prior.
    pub fn pushLyonVertexData(self: *Self, data: *lyon.VertexData, color: Color) void {
        var vert: TexShaderVertex = undefined;
        vert.setColor(color);
        const vert_offset_id = self.mesh.getNextIndexId();
        for (data.vertex_buf[0..data.vertex_len]) |pos| {
            vert.setXY(pos.x, pos.y);
            vert.setUV(0, 0);
            _ = self.mesh.addVertex(&vert);
            // log.debug("vert {}", .{tvert})
        }
        for (data.index_buf[0..data.index_len]) |id| {
            // lyon will start their index at 0 so we add our offset.
            self.mesh.addIndex(vert_offset_id + id);
        }
    }

    // Caller must check if there is enough buffer space prior.
    pub fn pushVertexData(self: *Self, comptime num_verts: usize, comptime num_indices: usize, data: *VertexData(num_verts, num_indices)) void {
        self.mesh.addVertexData(num_verts, num_indices, data);
    }

    pub fn flushDraw(self: *Self) void {
        // log.debug("flushDraw", .{});
        if (self.mesh.cur_index_buf_size > 0) {
            // log.debug("{} index size", .{self.mesh.cur_index_data_size});
            self.drawMesh(&self.mesh);
            self.mesh.cur_vert_buf_size = 0;
            self.mesh.cur_index_buf_size = 0;
        }
    }

    fn drawMesh(self: *const Self, mesh: *Mesh) void {
        _ = mesh;
        gl.useProgram(self.tex_shader.prog_id);

        gl.activeTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.cur_tex_image.tex_id);

        // set u_mvp, since transpose is false, it expects to receive in column major order.
        gl.uniformMatrix4fv(0, 1, gl.GL_FALSE, &self.mvp);

        // text_program.get_uniform_loc("u_texture");
        // set u_tex
        gl.uniform1i(1, gl.GL_TEXTURE0 + 0);

        // Recall how to pull data from the buffer for shader.
        gl.bindVertexArray(self.tex_shader.vao_id);

        // Update vertex buffer.
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vert_buf_id);
        gl.bufferData(gl.GL_ARRAY_BUFFER, @intCast(c_long, self.mesh.cur_vert_buf_size * 10 * 4),
            self.mesh.vert_buf.ptr, gl.GL_DYNAMIC_DRAW);

        // Update index buffer.
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buf_id);
        gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.mesh.cur_index_buf_size * 2),
            self.mesh.index_buf.ptr, gl.GL_DYNAMIC_DRAW);

        gl.drawElements(gl.GL_TRIANGLES, self.mesh.cur_index_buf_size, self.mesh.index_buffer_type, 0);

        // Unbind vao.
        gl.bindVertexArray(0);
    }
};
