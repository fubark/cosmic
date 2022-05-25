const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const gl = @import("gl");
const lyon = @import("lyon");
const Vec2 = stdx.math.Vec2;

const graphics = @import("../../graphics.zig");
const ImageId = graphics.ImageId;
const ImageDesc = graphics.gl.ImageDesc;
const GLTextureId = graphics.gl.GLTextureId;
const Color = graphics.Color;
const Transform = graphics.transform.Transform;
const _mesh = @import("mesh.zig");
const VertexData = _mesh.VertexData;
const TexShaderVertex = _mesh.TexShaderVertex;
const Mesh = _mesh.Mesh;
const log = stdx.log.scoped(.batcher);
const Shader = @import("shader.zig").Shader;
const shaders = @import("shaders.zig");

const BuiltinShaders = struct {
    tex: shaders.TexShader,
    gradient: shaders.GradientShader,
};

const ShaderType = enum(u2) {
    Tex = 0,
    Gradient = 1,
    Custom = 2,
};

const PreFlushTask = struct {
    cb: fn (ctx: ?*anyopaque) void,
    ctx: ?*anyopaque,
};

/// The batcher should be the primary way for consumer to push draw data/calls. It is responsible for:
/// 1. Pushing various vertex/index data formats into a mesh buffer. 
/// 2. Automatically flushing to gpu when necessary. eg. Change to shader, texture, mvp, or reaching a buffer limit.
pub const Batcher = struct {
    const Self = @This();

    vert_buf_id: gl.GLuint,
    index_buf_id: gl.GLuint,

    pre_flush_tasks: std.ArrayList(PreFlushTask),

    mesh: Mesh,

    /// Model view projection is kept until flush time to reduce redundant uniform uploads.
    mvp: Transform,

    /// It's useful to store the current texture associated with the current buffer data, 
    /// so a resize op can know whether to trigger a force flush.
    cur_tex_image: ImageDesc,

    /// Keep track of the current shader used.
    cur_shader_type: ShaderType,

    builtin_shaders: BuiltinShaders,

    /// Vars for gradient shader.
    start_pos: Vec2,
    start_color: Color,
    end_pos: Vec2,
    end_color: Color,

    /// Batcher owns vert_buf_id afterwards.
    pub fn init(alloc: std.mem.Allocator, vert_buf_id: gl.GLuint, builtin_shaders: BuiltinShaders) Self {
        var new = Self{
            .mesh = Mesh.init(alloc),
            .vert_buf_id = vert_buf_id,
            .index_buf_id = undefined,
            .pre_flush_tasks = std.ArrayList(PreFlushTask).init(alloc),
            .mvp = undefined,
            .cur_tex_image = .{
                .image_id = 0,
                .tex_id = 0,
            },
            .builtin_shaders = builtin_shaders,
            .cur_shader_type = undefined,
            .start_pos = undefined,
            .start_color = undefined,
            .end_pos = undefined,
            .end_color = undefined,
        };
        // Generate buffers.
        var buf_ids: [1]gl.GLuint = undefined;
        gl.genBuffers(1, &buf_ids);
        new.index_buf_id = buf_ids[0];
        return new;
    }

    pub fn deinit(self: Self) void {
        self.pre_flush_tasks.deinit();
        self.mesh.deinit();

        const bufs = [_]gl.GLuint{ self.vert_buf_id, self.index_buf_id };
        gl.deleteBuffers(2, &bufs);
    }

    /// Queue a task to run before the next flush.
    pub fn addNextPreFlushTask(self: *Self, ctx: ?*anyopaque, cb: fn (?*anyopaque) void) void {
        self.pre_flush_tasks.append(.{
            .ctx = ctx,
            .cb = cb,
        }) catch @panic("error");
    }

    /// Begins the tex shader. Will flush previous batched command.
    pub fn beginTex(self: *Self, image: ImageDesc) void {
        if (self.cur_shader_type != .Tex) {
            self.flushDraw();
            self.cur_shader_type = .Tex;
            return;
        }
        if (self.cur_tex_image.tex_id != image.tex_id) {
            self.flushDraw();
            self.cur_tex_image = image;
        }
    }

    /// Begins the gradient shader. Will flush previous batched command.
    pub fn beginGradient(self: *Self, start_pos: Vec2, start_color: Color, end_pos: Vec2, end_color: Color) void {
        // Always flush the previous.
        self.flushDraw();
        self.start_pos = start_pos;
        self.start_color = start_color;
        self.end_pos = end_pos;
        self.end_color = end_color;
        self.cur_shader_type = .Gradient;
    }

    // TODO: we can use sample2d arrays and pass active tex ids in vertex data to further reduce number of flushes.
    pub fn beginTexture(self: *Self, image: ImageDesc) void {
        if (self.cur_tex_image.tex_id != image.tex_id) {
            self.flushDraw();
            self.cur_tex_image = image;
        }
    }

    pub fn resetState(self: *Self, mvp: Transform, tex: ImageDesc) void {
        self.mvp = mvp;
        self.cur_tex_image = tex;
        self.cur_shader_type = .Tex;
    }

    pub fn beginMvp(self: *Self, mvp: Transform) void {
        // Always flush the previous.
        self.flushDraw();
        self.mvp = mvp;
    }

    pub fn ensureUnusedBuffer(self: *Self, vert_inc: usize, index_inc: usize) bool {
        return self.mesh.ensureUnusedBuffer(vert_inc, index_inc);
    }

    /// Push a batch of vertices and indexes where index 0 refers to the first vertex.
    pub fn pushVertIdxBatch(self: *Self, verts: []const Vec2, idxes: []const u16, color: Color) void {
        var gpu_vert: TexShaderVertex = undefined;
        gpu_vert.setColor(color);
        const vert_offset_id = self.mesh.getNextIndexId();
        for (verts) |v| {
            gpu_vert.setXY(v.x, v.y);
            gpu_vert.setUV(0, 0);
            _ = self.mesh.addVertex(&gpu_vert);
        }
        for (idxes) |i| {
            self.mesh.addIndex(vert_offset_id + i);
        }
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
        }
        for (data.index_buf[0..data.index_len]) |id| {
            self.mesh.addIndex(vert_offset_id + id);
        }
    }

    // Caller must check if there is enough buffer space prior.
    pub fn pushVertexData(self: *Self, comptime num_verts: usize, comptime num_indices: usize, data: *VertexData(num_verts, num_indices)) void {
        self.mesh.addVertexData(num_verts, num_indices, data);
    }

    pub fn flushDraw(self: *Self) void {
        if (self.mesh.cur_index_buf_size > 0) {
            // log.debug("{} index size", .{self.mesh.cur_index_data_size});

            // Run pre flush callbacks.
            if (self.pre_flush_tasks.items.len > 0) {
                for (self.pre_flush_tasks.items) |it| {
                    it.cb(it.ctx);
                }
                self.pre_flush_tasks.clearRetainingCapacity();
            }
            self.drawMesh();
            self.mesh.cur_vert_buf_size = 0;
            self.mesh.cur_index_buf_size = 0;
        }
    }

    fn drawMesh(self: *const Self) void {
        switch (self.cur_shader_type) {
            .Tex => {
                self.builtin_shaders.tex.bind(self.mvp.mat, self.cur_tex_image.tex_id);
                // Recall how to pull data from the buffer for shader.
                gl.bindVertexArray(self.builtin_shaders.tex.shader.vao_id);
            },
            .Gradient => {
                self.builtin_shaders.gradient.bind(self.mvp.mat, self.start_pos, self.start_color, self.end_pos, self.end_color);
                // Recall how to pull data from the buffer for shader.
                gl.bindVertexArray(self.builtin_shaders.gradient.shader.vao_id);
            },
            .Custom => @panic("unsupported"),
        }

        // Update vertex buffer.
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vert_buf_id);
        gl.bufferData(gl.GL_ARRAY_BUFFER, @intCast(c_long, self.mesh.cur_vert_buf_size * 10 * 4), self.mesh.vert_buf.ptr, gl.GL_DYNAMIC_DRAW);

        // Update index buffer.
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buf_id);
        gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.mesh.cur_index_buf_size * 2), self.mesh.index_buf.ptr, gl.GL_DYNAMIC_DRAW);

        gl.drawElements(gl.GL_TRIANGLES, self.mesh.cur_index_buf_size, self.mesh.index_buffer_type, 0);

        // Unbind vao.
        gl.bindVertexArray(0);
    }
};
