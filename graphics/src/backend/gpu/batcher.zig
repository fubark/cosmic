const std = @import("std");
const Backend = @import("build_options").GraphicsBackend;
const stdx = @import("stdx");
const ds = stdx.ds;
const gl = @import("gl");
const vk = @import("vk");
const lyon = @import("lyon");
const Vec2 = stdx.math.Vec2;

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const cs_vk = graphics.vk;
const ImageId = graphics.ImageId;
const ImageTex = graphics.gpu.ImageTex;
const GLTextureId = gl.GLuint;
const Color = graphics.Color;
const Transform = graphics.transform.Transform;
const mesh = @import("mesh.zig");
const VertexData = mesh.VertexData;
const TexShaderVertex = mesh.TexShaderVertex;
const Mesh = mesh.Mesh;
const log = stdx.log.scoped(.batcher);

const NullId = std.math.maxInt(u32);

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
/// 2. Automatically ending the current batch command when necessary. eg. Change to shader, texture, mvp, or reaching a buffer limit.
pub const Batcher = struct {
    pre_flush_tasks: std.ArrayList(PreFlushTask),

    mesh: Mesh,
    cmds: std.ArrayList(DrawCmd),
    cmd_vert_start_idx: u32,
    cmd_index_start_idx: u32,

    /// Model view projection is kept until flush time to reduce redundant uniform uploads.
    mvp: Transform,

    /// It's useful to store the current texture associated with the current buffer data, 
    /// so a resize op can know whether to trigger a force flush.
    cur_image_tex: ImageTex,

    /// Keep track of the current shader used.
    cur_shader_type: ShaderType,

    inner: switch (Backend) {
        .OpenGL => struct {
            vert_buf_id: gl.GLuint,
            index_buf_id: gl.GLuint,
            pipelines: graphics.gl.Pipelines,
            cur_gl_tex_id: GLTextureId,
        },
        .Vulkan => struct {
            ctx: cs_vk.VkContext,
            cur_cmd_buf: vk.VkCommandBuffer,
            tex_pipeline: cs_vk.pipeline.Pipeline,
            vert_buf: vk.VkBuffer,
            vert_buf_mem: vk.VkDeviceMemory,
            index_buf: vk.VkBuffer,
            index_buf_mem: vk.VkDeviceMemory,
            cur_tex_desc_set: vk.VkDescriptorSet,
        },
        else => @compileError("unsupported"),
    },
    image_store: *graphics.gpu.ImageStore,

    /// Vars for gradient shader.
    start_pos: Vec2,
    start_color: Color,
    end_pos: Vec2,
    end_color: Color,

    const Self = @This();

    /// Batcher owns vert_buf_id afterwards.
    pub fn initGL(alloc: std.mem.Allocator, vert_buf_id: gl.GLuint, pipelines: graphics.gl.Pipelines, image_store: *graphics.gpu.ImageStore) Self {
        var new = Self{
            .mesh = Mesh.init(alloc),
            .cmds = std.ArrayList(DrawCmd).init(alloc),
            .cmd_vert_start_idx = 0,
            .cmd_index_start_idx = 0,
            .inner = .{
                .pipelines = pipelines,
                .vert_buf_id = vert_buf_id,
                .index_buf_id = undefined,
                .cur_gl_tex_id = undefined,
            },
            .pre_flush_tasks = std.ArrayList(PreFlushTask).init(alloc),
            .mvp = undefined,
            .cur_image_tex = .{
                .image_id = NullId,
                .tex_id = NullId,
            },
            .cur_shader_type = undefined,
            .start_pos = undefined,
            .start_color = undefined,
            .end_pos = undefined,
            .end_color = undefined,
            .image_store = image_store,
        };
        // Generate buffers.
        var buf_ids: [1]gl.GLuint = undefined;
        gl.genBuffers(1, &buf_ids);
        new.inner.index_buf_id = buf_ids[0];
        return new;
    }

    pub fn initVK(alloc: std.mem.Allocator,
        vert_buf: vk.VkBuffer, vert_buf_mem: vk.VkDeviceMemory, index_buf: vk.VkBuffer, index_buf_mem: vk.VkDeviceMemory,
        vk_ctx: cs_vk.VkContext, tex_pipeline: cs_vk.pipeline.Pipeline, image_store: *graphics.gpu.ImageStore
    ) Self {
        var new = Self{
            .mesh = Mesh.init(alloc),
            .cmds = std.ArrayList(DrawCmd).init(alloc),
            .cmd_vert_start_idx = 0,
            .cmd_index_start_idx = 0,
            .pre_flush_tasks = std.ArrayList(PreFlushTask).init(alloc),
            .mvp = undefined,
            .cur_image_tex = .{
                .image_id = NullId,
                .tex_id = NullId,
            },
            .cur_shader_type = undefined,
            .start_pos = undefined,
            .start_color = undefined,
            .end_pos = undefined,
            .end_color = undefined,
            .inner = .{
                .ctx = vk_ctx,
                .cur_cmd_buf = undefined,
                .tex_pipeline = tex_pipeline,
                .vert_buf = vert_buf,
                .vert_buf_mem = vert_buf_mem,
                .index_buf = index_buf,
                .index_buf_mem = index_buf_mem,
                .cur_tex_desc_set = undefined,
            },
            .image_store = image_store,
        };
        return new;
    }

    pub fn deinit(self: Self) void {
        self.pre_flush_tasks.deinit();
        self.mesh.deinit();
        self.cmds.deinit();

        switch (Backend) {
            .OpenGL => {
                const bufs = [_]gl.GLuint{ self.inner.vert_buf_id, self.inner.index_buf_id };
                gl.deleteBuffers(2, &bufs);
            },
            .Vulkan => {
                const device = self.inner.ctx.device;
                vk.destroyBuffer(device, self.inner.vert_buf, null);
                vk.freeMemory(device, self.inner.vert_buf_mem, null);
                vk.destroyBuffer(device, self.inner.index_buf, null);
                vk.freeMemory(device, self.inner.index_buf_mem, null);
            },
            else => {},
        }
    }

    /// Queue a task to run before the next flush.
    pub fn addNextPreFlushTask(self: *Self, ctx: ?*anyopaque, cb: fn (?*anyopaque) void) void {
        self.pre_flush_tasks.append(.{
            .ctx = ctx,
            .cb = cb,
        }) catch @panic("error");
    }

    /// Begins the tex shader. Will flush previous batched command.
    pub fn beginTex(self: *Self, image: ImageTex) void {
        if (self.cur_shader_type != .Tex) {
            self.endCmd();
            self.cur_shader_type = .Tex;
            return;
        }
        self.setTexture(image);
    }

    /// Begins the gradient shader. Will flush previous batched command.
    pub fn beginGradient(self: *Self, start_pos: Vec2, start_color: Color, end_pos: Vec2, end_color: Color) void {
        // Always flush the previous.
        self.endCmd();
        self.start_pos = start_pos;
        self.start_color = start_color;
        self.end_pos = end_pos;
        self.end_color = end_color;
        self.cur_shader_type = .Gradient;
    }

    // TODO: we can use sample2d arrays and pass active tex ids in vertex data to further reduce number of flushes.
    pub fn beginTexture(self: *Self, image: ImageTex) void {
        self.setTexture(image);
    }

    inline fn setTexture(self: *Self, image: ImageTex) void {
        if (self.cur_image_tex.tex_id != image.tex_id) {
            self.endCmd();
            self.cur_image_tex = image;
            switch (Backend) {
                .OpenGL => {
                    self.inner.cur_gl_tex_id = self.image_store.getTexture(image.tex_id).inner.tex_id;
                },
                .Vulkan => {
                    self.inner.cur_tex_desc_set = self.image_store.getTexture(image.tex_id).inner.desc_set;
                },
                else => {},
            }
        }
    }

    pub fn resetState(self: *Self, tex: ImageTex) void {
        self.cur_image_tex = tex;
        self.cur_shader_type = .Tex;
        self.cmd_vert_start_idx = 0;
        self.cmd_index_start_idx = 0;
        self.inner.cur_gl_tex_id = self.image_store.getTexture(tex.tex_id).inner.tex_id;
        self.mesh.reset();
    }

    pub fn resetStateVK(self: *Self, image_tex: ImageTex, image_idx: u32, frame_idx: u32, clear_color: Color) void {
        _ = frame_idx;
        self.inner.cur_cmd_buf = self.inner.ctx.cmd_bufs[image_idx];
        self.inner.cur_tex_desc_set = self.image_store.getTexture(image_tex.tex_id).inner.desc_set;

        self.cur_image_tex = image_tex;
        self.cur_shader_type = .Tex;
        self.cmd_vert_start_idx = 0;
        self.cmd_index_start_idx = 0;
        self.mesh.reset();

        const cmd_buf = self.inner.cur_cmd_buf;
        cs_vk.command.beginCommandBuffer(cmd_buf);
        cs_vk.command.beginRenderPass(cmd_buf, self.inner.ctx.pass, self.inner.ctx.framebuffers[image_idx], self.inner.ctx.framebuffer_size, clear_color);

        var offset: vk.VkDeviceSize = 0;
        vk.cmdBindVertexBuffers(cmd_buf, 0, 1, &self.inner.vert_buf, &offset);
        vk.cmdBindIndexBuffer(cmd_buf, self.inner.index_buf, 0, vk.VK_INDEX_TYPE_UINT16);
    }

    pub fn endFrameVK(self: *Self) void {
        const cmd_buf = self.inner.cur_cmd_buf;
        cs_vk.command.endRenderPass(cmd_buf);
        cs_vk.command.endCommandBuffer(cmd_buf);

        // Send all the mesh data at once.

        // Copy vertex buffer.
        var vert_dst: [*]TexShaderVertex = undefined;
        var res = vk.mapMemory(self.inner.ctx.device, self.inner.vert_buf_mem, 0, self.mesh.cur_vert_buf_size * 40, 0, @ptrCast([*c]?*anyopaque, &vert_dst));
        vk.assertSuccess(res);
        std.mem.copy(TexShaderVertex, vert_dst[0..self.mesh.cur_vert_buf_size], self.mesh.vert_buf[0..self.mesh.cur_vert_buf_size]);
        vk.unmapMemory(self.inner.ctx.device, self.inner.vert_buf_mem);

        // Copy index buffer.
        var index_dst: [*]u16 = undefined;
        res = vk.mapMemory(self.inner.ctx.device, self.inner.index_buf_mem, 0, self.mesh.cur_index_buf_size * 2, 0, @ptrCast([*c]?*anyopaque, &index_dst));
        vk.assertSuccess(res);
        std.mem.copy(u16, index_dst[0..self.mesh.cur_index_buf_size], self.mesh.index_buf[0..self.mesh.cur_index_buf_size]);
        vk.unmapMemory(self.inner.ctx.device, self.inner.index_buf_mem);
    }

    pub fn beginMvp(self: *Self, mvp: Transform) void {
        // Always flush the previous.
        self.endCmd();
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

    pub fn endCmd(self: *Self) void {
        if (self.mesh.cur_index_buf_size > self.cmd_index_start_idx) {
            // Run pre flush callbacks.
            if (self.pre_flush_tasks.items.len > 0) {
                for (self.pre_flush_tasks.items) |it| {
                    it.cb(it.ctx);
                }
                self.pre_flush_tasks.clearRetainingCapacity();
            }

            self.pushDrawCall();
            switch (Backend) {
                .OpenGL => {
                    self.mesh.reset();
                },
                .Vulkan => {
                    self.cmd_vert_start_idx = self.mesh.cur_vert_buf_size;
                    self.cmd_index_start_idx = self.mesh.cur_index_buf_size;
                },
                else => {},
            }
        }
    }

    /// OpenGL immediately flushes with drawElements.
    /// Vulkan records the draw command, flushed by endFrameVK.
    fn pushDrawCall(self: *Self) void {
        switch (Backend) {
            .OpenGL => {
                switch (self.cur_shader_type) {
                    .Tex => {
                        self.inner.pipelines.tex.bind(self.mvp.mat, self.inner.cur_gl_tex_id);
                        // Recall how to pull data from the buffer for shader.
                        gl.bindVertexArray(self.inner.pipelines.tex.shader.vao_id);
                    },
                    .Gradient => {
                        self.inner.pipelines.gradient.bind(self.mvp.mat, self.start_pos, self.start_color, self.end_pos, self.end_color);
                        // Recall how to pull data from the buffer for shader.
                        gl.bindVertexArray(self.inner.pipelines.gradient.shader.vao_id);
                    },
                    .Custom => stdx.unsupported(),
                }

                const num_verts = self.mesh.cur_vert_buf_size;
                const num_indexes = self.mesh.cur_index_buf_size;

                // Update vertex buffer.
                gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.inner.vert_buf_id);
                gl.bufferData(gl.GL_ARRAY_BUFFER, @intCast(c_long, num_verts * 10 * 4), self.mesh.vert_buf.ptr, gl.GL_DYNAMIC_DRAW);

                // Update index buffer.
                gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.inner.index_buf_id);
                gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, num_indexes * 2), self.mesh.index_buf.ptr, gl.GL_DYNAMIC_DRAW);

                gl.drawElements(gl.GL_TRIANGLES, num_indexes, self.mesh.index_buffer_type, 0);

                // Unbind vao.
                gl.bindVertexArray(0);
            },
            .Vulkan => {
                const cmd_buf = self.inner.cur_cmd_buf;
                switch (self.cur_shader_type) {
                    .Tex => {
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.inner.tex_pipeline.pipeline);

                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.inner.tex_pipeline.layout, 0, 1, &self.inner.cur_tex_desc_set, 0, null);

                        // It's expensive to update a uniform buffer all the time so use push constants.
                        vk.cmdPushConstants(cmd_buf, self.inner.tex_pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 16 * 4, &self.mvp.mat);
                    },
                    else => stdx.unsupported(),
                }
                const num_indexes = self.mesh.cur_index_buf_size - self.cmd_index_start_idx;
                vk.cmdDrawIndexed(cmd_buf, num_indexes, 1, self.cmd_index_start_idx, 0, 0);
            },
            else => stdx.unsupported(),
        }
    }
};

/// Currently not used. 
const DrawCmd = struct {
    vert_offset: u32,
    idx_offset: u32,
};