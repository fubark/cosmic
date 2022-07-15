const std = @import("std");
const Backend = @import("build_options").GraphicsBackend;
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const fatal = stdx.fatal;
const unsupported = stdx.unsupported;
const ds = stdx.ds;
const gl = @import("gl");
const vk = @import("vk");
const lyon = @import("lyon");
const Vec2 = stdx.math.Vec2;
const Vec3 = stdx.math.Vec3;
const Vec4 = stdx.math.Vec4;
const Transform = stdx.math.Transform;

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const TexShaderVertex = gpu.TexShaderVertex;
const gvk = graphics.vk;
const ImageId = graphics.ImageId;
const ImageTex = graphics.gpu.ImageTex;
const GLTextureId = gl.GLuint;
const Color = graphics.Color;
const mesh = @import("mesh.zig");
const VertexData = mesh.VertexData;
const Mesh = mesh.Mesh;
const log = stdx.log.scoped(.batcher);

const NullId = std.math.maxInt(u32);

/// Initial buffer sizes
pub const MatBufferInitialSize = 5000;
pub const MatBufferInitialSizeBytes = MatBufferInitialSize * @sizeOf(stdx.math.Mat4);
pub const MaterialBufferInitialSize = 100;
pub const MaterialBufferInitialSizeBytes = MaterialBufferInitialSize * @sizeOf(graphics.Material);

const ShaderType = enum(u4) {
    Tex = 0,
    Tex3D = 1,
    Gradient = 2,
    Plane = 3,
    Wireframe = 4,
    Custom = 5,
    Anim3D = 6,
    Normal = 7,
    TexPbr3D = 8,
    AnimPbr3D = 9,
};

const PreFlushTask = struct {
    cb: fn (ctx: ?*anyopaque) void,
    ctx: ?*anyopaque,
};

const VkFrame = struct {
    host_cam_buf: *graphics.gpu.ShaderCamera,
};

/// The batcher should be the primary way for consumer to push draw data/calls. It is responsible for:
/// 1. Pushing various vertex/index data formats into a mesh buffer. 
/// 2. Automatically ending the current batch command when necessary. eg. Change to shader, texture, mvp, or reaching a buffer limit.
pub const Batcher = struct {
    pre_flush_tasks: std.ArrayList(PreFlushTask),

    mesh: *Mesh,
    cmds: std.ArrayList(DrawCmd),
    cmd_vert_start_idx: u32,
    cmd_index_start_idx: u32,

    /// Model view projection is kept until flush time to reduce redundant uniform uploads.
    mvp: Transform,

    /// Normal matrix for lighting.
    normal: stdx.math.Mat3,
    material_idx: u32,
    model_idx: u32,

    /// It's useful to store the current texture associated with the current buffer data, 
    /// so a resize op can know whether to trigger a force flush.
    cur_image_tex: ImageTex,

    /// Keep track of the current shader used.
    cur_shader_type: ShaderType,

    inner: switch (Backend) {
        .OpenGL => struct {
            renderer: *graphics.gl.Renderer,
            cur_gl_tex_id: GLTextureId,
        },
        .Vulkan => struct {
            mesh: Mesh,
            ctx: gvk.VkContext,
            renderer: *gvk.Renderer,
            cur_frame: gvk.Frame,
            pipelines: gvk.Pipelines,
            vert_buf: gvk.Buffer,
            index_buf: gvk.Buffer,
            mats_buf: gvk.Buffer,
            materials_buf: gvk.Buffer,
            cur_tex_desc_set: vk.VkDescriptorSet,
            materials_desc_set: vk.VkDescriptorSet,
            mats_desc_set: vk.VkDescriptorSet,
            batcher_frames: []VkFrame,
            cur_batcher_frame: VkFrame,
            host_vert_buf: []TexShaderVertex,
            host_index_buf: []u16,
            host_mats_buf: []stdx.math.Mat4,
            host_materials_buf: []graphics.Material,
            do_shadow_pass: bool,
            // Directional light shadow cast view * proj.
            light_cast_vp: Transform,
        },
        else => @compileError("unsupported"),
    },
    image_store: *graphics.gpu.ImageStore,

    /// Vars for gradient shader.
    start_pos: Vec2,
    start_color: Color,
    end_pos: Vec2,
    end_color: Color,

    /// Batcher owns vert_buf_id afterwards.
    pub fn initGL(
        alloc: std.mem.Allocator,
        renderer: *graphics.gl.Renderer,
        image_store: *graphics.gpu.ImageStore
    ) Batcher {
        var new = Batcher{
            .mesh = &renderer.mesh,
            .cmds = std.ArrayList(DrawCmd).init(alloc),
            .cmd_vert_start_idx = 0,
            .cmd_index_start_idx = 0,
            .inner = .{
                .renderer = renderer,
                .cur_gl_tex_id = undefined,
            },
            .pre_flush_tasks = std.ArrayList(PreFlushTask).init(alloc),
            .mvp = undefined,
            .normal = undefined,
            .material_idx = undefined,
            .cur_image_tex = .{
                .image_id = NullId,
                .tex_id = NullId,
            },
            .cur_shader_type = undefined,
            .model_idx = undefined,
            .start_pos = undefined,
            .start_color = undefined,
            .end_pos = undefined,
            .end_color = undefined,
            .image_store = image_store,
        };
        return new;
    }

    pub fn initVK(new: *Batcher, alloc: std.mem.Allocator,
        vert_buf: gvk.Buffer,
        index_buf: gvk.Buffer,
        mats_buf: gvk.Buffer,
        mats_desc_set: vk.VkDescriptorSet,
        materials_buf: gvk.Buffer,
        materials_desc_set: vk.VkDescriptorSet,
        vk_ctx: gvk.VkContext,
        renderer: *gvk.Renderer,
        pipelines: gvk.Pipelines,
        image_store: *graphics.gpu.ImageStore
    ) void {
        new.* = .{
            .mesh = undefined,
            .cmds = std.ArrayList(DrawCmd).init(alloc),
            .cmd_vert_start_idx = 0,
            .cmd_index_start_idx = 0,
            .pre_flush_tasks = std.ArrayList(PreFlushTask).init(alloc),
            .mvp = undefined,
            .normal = undefined,
            .material_idx = undefined,
            .model_idx = undefined,
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
                .mesh = undefined,
                .ctx = vk_ctx,
                .renderer = renderer,
                .cur_frame = undefined,
                .cur_batcher_frame = undefined,
                .pipelines = pipelines,
                .vert_buf = vert_buf,
                .index_buf = index_buf,
                .mats_buf = mats_buf,
                .mats_desc_set = mats_desc_set,
                .materials_buf = materials_buf,
                .materials_desc_set = materials_desc_set,
                .batcher_frames = alloc.alloc(VkFrame, gpu.MaxActiveFrames) catch fatal(),
                .cur_tex_desc_set = undefined,
                .host_vert_buf = undefined,
                .host_index_buf = undefined,
                .host_mats_buf = undefined,
                .host_materials_buf = undefined,
                .do_shadow_pass = false,
                .light_cast_vp = undefined,
            },
            .image_store = image_store,
        };

        var host_vert_buf: [*]TexShaderVertex = undefined;
        var res = vk.mapMemory(new.inner.ctx.device, new.inner.vert_buf.mem, 0, new.inner.vert_buf.size, 0, @ptrCast([*c]?*anyopaque, &host_vert_buf));
        vk.assertSuccess(res);
        new.inner.host_vert_buf = host_vert_buf[0..new.inner.vert_buf.size/@sizeOf(TexShaderVertex)];

        var host_index_buf: [*]u16 = undefined;
        res = vk.mapMemory(new.inner.ctx.device, new.inner.index_buf.mem, 0, new.inner.index_buf.size, 0, @ptrCast([*c]?*anyopaque, &host_index_buf));
        vk.assertSuccess(res);
        new.inner.host_index_buf = host_index_buf[0..new.inner.index_buf.size/@sizeOf(u16)];

        var host_mats_buf: [*]stdx.math.Mat4 = undefined;
        res = vk.mapMemory(new.inner.ctx.device, new.inner.mats_buf.mem, 0, new.inner.mats_buf.size, 0, @ptrCast([*c]?*anyopaque, &host_mats_buf));
        vk.assertSuccess(res);
        new.inner.host_mats_buf = host_mats_buf[0..new.inner.mats_buf.size/@sizeOf(stdx.math.Mat4)];

        var host_materials_buf: [*]graphics.Material = undefined;
        res = vk.mapMemory(new.inner.ctx.device, new.inner.materials_buf.mem, 0, new.inner.materials_buf.size, 0, @ptrCast([*c]?*anyopaque, &host_materials_buf));
        vk.assertSuccess(res);
        new.inner.host_materials_buf = host_materials_buf[0..new.inner.materials_buf.size/@sizeOf(graphics.Material)];

        for (new.inner.batcher_frames) |*frame, i| {
            const renderer_frame = renderer.frames[i];
            var host_cam_buf: *graphics.gpu.ShaderCamera = undefined;
            res = vk.mapMemory(new.inner.ctx.device, renderer_frame.u_cam_buf.mem, 0, renderer_frame.u_cam_buf.size, 0, @ptrCast([*c]?*anyopaque, &host_cam_buf));
            vk.assertSuccess(res);
            frame.host_cam_buf = host_cam_buf;
        }

        new.inner.mesh = Mesh.init(alloc, new.inner.host_mats_buf, new.inner.host_materials_buf);
        new.mesh = &new.inner.mesh;
    }

    pub fn deinit(self: Batcher, alloc: std.mem.Allocator) void {
        self.pre_flush_tasks.deinit();
        self.cmds.deinit();

        switch (Backend) {
            .Vulkan => {
                self.mesh.deinit();
                const device = self.inner.ctx.device;
                self.inner.vert_buf.deinit(device);
                self.inner.index_buf.deinit(device);
                self.inner.mats_buf.deinit(device);
                self.inner.materials_buf.deinit(device);

                alloc.free(self.inner.batcher_frames);
            },
            else => {},
        }
    }

    /// Queue a task to run before the next flush.
    pub fn addNextPreFlushTask(self: *Batcher, ctx: ?*anyopaque, cb: fn (?*anyopaque) void) void {
        self.pre_flush_tasks.append(.{
            .ctx = ctx,
            .cb = cb,
        }) catch @panic("error");
    }

    /// Begins the tex shader. Will flush previous batched command.
    pub fn beginTex(self: *Batcher, image: ImageTex) void {
        if (self.cur_shader_type != .Tex) {
            self.endCmd();
            self.cur_shader_type = .Tex;
            self.setTexture(image);
            return;
        }
        self.setTexture(image);
    }

    pub fn beginNormal(self: *Batcher) void {
        if (self.cur_shader_type != .Normal) {
            self.endCmd();
            self.cur_shader_type = .Normal;
            return;
        }
    }

    pub fn beginTex3D(self: *Batcher, image: ImageTex) void {
        if (self.cur_shader_type != .Tex3D) {
            self.endCmd();
            self.cur_shader_type = .Tex3D;
            self.setTexture(image);
            return;
        }
        self.setTexture(image);
    }

    pub fn beginTexPbr3D(self: *Batcher, image: ImageTex, cam_loc: stdx.math.Vec3) void {
        if (self.cur_shader_type != .TexPbr3D) {
            self.endCmd();
            self.cur_shader_type = .TexPbr3D;
            self.setTexture(image);
            if (Backend == .Vulkan) {
                self.inner.cur_batcher_frame.host_cam_buf.cam_pos = cam_loc;
            }
            return;
        }
        self.setTexture(image);
        if (Backend == .Vulkan) {
            self.inner.cur_batcher_frame.host_cam_buf.cam_pos = cam_loc;
        }
    }

    pub fn beginAnimPbr3D(self: *Batcher, image: ImageTex, cam_loc: stdx.math.Vec3) void {
        if (self.cur_shader_type != .AnimPbr3D) {
            self.endCmd();
            self.cur_shader_type = .AnimPbr3D;
            self.setTexture(image);
            if (Backend == .Vulkan) {
                self.inner.cur_batcher_frame.host_cam_buf.cam_pos = cam_loc;
            }
            return;
        }
        self.setTexture(image);
        if (Backend == .Vulkan) {
            self.inner.cur_batcher_frame.host_cam_buf.cam_pos = cam_loc;
        }
    }

    pub fn beginAnim3D(self: *Batcher, image: ImageTex) void {
        if (self.cur_shader_type != .Anim3D) {
            self.endCmd();
            self.cur_shader_type = .Anim3D;
            self.setTexture(image);
            return;
        }
        self.setTexture(image);
    }

    pub fn beginWireframe(self: *Batcher) void {
        if (self.cur_shader_type != .Wireframe) {
            self.endCmd();
            self.cur_shader_type = .Wireframe;
        }
    }

    /// Begins the gradient shader. Will flush previous batched command.
    pub fn beginGradient(self: *Batcher, start_pos: Vec2, start_color: Color, end_pos: Vec2, end_color: Color) void {
        // Always flush the previous.
        self.endCmd();
        self.start_pos = start_pos;
        self.start_color = start_color;
        self.end_pos = end_pos;
        self.end_color = end_color;
        self.cur_shader_type = .Gradient;
    }

    // TODO: we can use sample2d arrays and pass active tex ids in vertex data to further reduce number of flushes.
    pub fn beginTexture(self: *Batcher, image: ImageTex) void {
        self.setTexture(image);
    }

    inline fn setTexture(self: *Batcher, image: ImageTex) void {
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

    pub fn resetState(self: *Batcher, tex: ImageTex) void {
        self.cur_image_tex = tex;
        self.cur_shader_type = .Tex;
        self.cmd_vert_start_idx = 0;
        self.cmd_index_start_idx = 0;
        self.inner.cur_gl_tex_id = self.image_store.getTexture(tex.tex_id).inner.tex_id;
        self.mesh.reset();
    }

    pub fn resetStateVK(self: *Batcher, image_tex: ImageTex, frame_idx: u8, framebuffer: vk.VkFramebuffer, clear_color: Color) void {
        self.inner.cur_frame = self.inner.renderer.frames[frame_idx];
        self.inner.cur_batcher_frame = self.inner.batcher_frames[frame_idx];
        self.inner.cur_tex_desc_set = self.image_store.getTexture(image_tex.tex_id).inner.desc_set;
        self.inner.do_shadow_pass = false;

        self.cur_image_tex = image_tex;
        self.cur_shader_type = .Tex;
        self.cmd_vert_start_idx = 0;
        self.cmd_index_start_idx = 0;
        self.mesh.reset();

        // Push the identity matrix onto index 0 for draw calls that don't need a model matrix.
        self.mesh.pushMatrix(Transform.initIdentity().mat);

        const cmd_buf = self.inner.cur_frame.main_cmd_buf;
        gvk.command.beginCommandBuffer(cmd_buf);

        // Main renderpass depends on shadow pass. (Seems we don't need this atm.)
        // const barrier = vk.VkImageMemoryBarrier{
        //     .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        //     .oldLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        //     .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        //     .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        //     .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        //     .image = self.inner.cur_frame.shadow_image.image,
        //     .subresourceRange = .{
        //         .aspectMask = vk.VK_IMAGE_ASPECT_DEPTH_BIT,
        //         .baseMipLevel = 0,
        //         .levelCount = 1,
        //         .baseArrayLayer = 0,
        //         .layerCount = 1,
        //     },
        //     .srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        //     .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
        //     .pNext = null,
        // };
        // vk.cmdPipelineBarrier(self.inner.cur_frame.main_cmd_buf,
        //     vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        //     vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        //     0, 0, null, 0, null, 1, &barrier);
        gvk.command.beginRenderPass(cmd_buf, self.inner.renderer.main_pass, framebuffer, self.inner.renderer.fb_size.width, self.inner.renderer.fb_size.height, clear_color);

        var offset: vk.VkDeviceSize = 0;
        vk.cmdBindVertexBuffers(cmd_buf, 0, 1, &self.inner.vert_buf.buf, &offset);
        vk.cmdBindIndexBuffer(cmd_buf, self.inner.index_buf.buf, 0, vk.VK_INDEX_TYPE_UINT16);
    }

    /// Must be called before draw calls are recorded for the shadow pass.
    pub fn prepareShadowPass(self: *Batcher, light_vp: Transform) void {
        if (Backend == .Vulkan) {
            if (!self.inner.do_shadow_pass) {
                self.inner.do_shadow_pass = true;
                self.inner.light_cast_vp = light_vp;
                self.inner.cur_batcher_frame.host_cam_buf.light_vp = light_vp.mat;

                const shadow_cmd = self.inner.cur_frame.shadow_cmd_buf;
                gvk.command.beginCommandBuffer(shadow_cmd);
                gvk.command.beginRenderPass(shadow_cmd, self.inner.renderer.shadow_pass, self.inner.cur_frame.shadow_framebuffer, gvk.Renderer.ShadowMapSize, gvk.Renderer.ShadowMapSize, null);

                var offset: vk.VkDeviceSize = 0;
                vk.cmdBindVertexBuffers(shadow_cmd, 0, 1, &self.inner.vert_buf.buf, &offset);
                vk.cmdBindIndexBuffer(shadow_cmd, self.inner.index_buf.buf, 0, vk.VK_INDEX_TYPE_UINT16);

                const vk_rect = vk.VkRect2D{
                    .offset = .{
                        .x = 0,
                        .y = 0,
                    },
                    .extent = .{
                        .width = gvk.Renderer.ShadowMapSize,
                        .height = gvk.Renderer.ShadowMapSize,
                    },
                };
                vk.cmdSetScissor(shadow_cmd, 0, 1, &vk_rect);
            }
        }
    }

    pub fn endFrameVK(self: *Batcher) graphics.FrameResultVK {
        const cmd_buf = self.inner.cur_frame.main_cmd_buf;
        gvk.command.endRenderPass(cmd_buf);
        gvk.command.endCommandBuffer(cmd_buf);

        var res = graphics.FrameResultVK{
            .submit_shadow_cmd = false,
        };
        if (self.inner.do_shadow_pass) {
            const shadow_cmd = self.inner.cur_frame.shadow_cmd_buf;
            gvk.command.endRenderPass(shadow_cmd);
            gvk.command.endCommandBuffer(shadow_cmd);
            res.submit_shadow_cmd = true;
            self.inner.cur_batcher_frame.host_cam_buf.enable_shadows = true;
        } else {
            self.inner.cur_batcher_frame.host_cam_buf.enable_shadows = false;
        }

        // Send all the mesh data at once.

        // TODO: This should work with zero copy if mesh is aware of the buffer pointer.
        // TODO: Buffer should be reallocated if it's not big enough.
        // TODO: The buffers should be large enough to hold 2 frames worth of data and writing data should use an offset from the previous frame.
        // Copy vertex buffer.
        std.mem.copy(TexShaderVertex, self.inner.host_vert_buf[0..self.mesh.cur_vert_buf_size], self.mesh.vert_buf[0..self.mesh.cur_vert_buf_size]);

        // Copy index buffer.
        std.mem.copy(u16, self.inner.host_index_buf[0..self.mesh.cur_index_buf_size], self.mesh.index_buf[0..self.mesh.cur_index_buf_size]);

        return res;
    }

    pub fn beginMvp(self: *Batcher, mvp: Transform) void {
        // Always flush the previous.
        self.endCmd();
        self.mvp = mvp;
    }

    /// Ensures that the buffer has enough space.
    pub fn ensureUnusedBuffer(self: *Batcher, vert_inc: usize, index_inc: usize) void {
        if (!self.mesh.ensureUnusedBuffer(vert_inc, index_inc)) {
            self.endCmdForce();
        }
    }

    /// Push a batch of vertices and indexes where index 0 refers to the first vertex.
    pub fn pushVertIdxBatch(self: *Batcher, verts: []const Vec2, idxes: []const u16, color: Color) void {
        var gpu_vert: TexShaderVertex = undefined;
        gpu_vert.setColor(color);
        const vert_offset_id = self.mesh.getNextIndexId();
        for (verts) |v| {
            gpu_vert.setXY(v.x, v.y);
            gpu_vert.setUV(0, 0);
            _ = self.mesh.pushVertex(gpu_vert);
        }
        for (idxes) |i| {
            self.mesh.pushIndex(vert_offset_id + i);
        }
    }

    // Caller must check if there is enough buffer space prior.
    pub fn pushLyonVertexData(self: *Batcher, data: *lyon.VertexData, color: Color) void {
        var vert: TexShaderVertex = undefined;
        vert.setColor(color);
        const vert_offset_id = self.mesh.getNextIndexId();
        for (data.vertex_buf[0..data.vertex_len]) |pos| {
            vert.setXY(pos.x, pos.y);
            vert.setUV(0, 0);
            _ = self.mesh.pushVertex(vert);
        }
        for (data.index_buf[0..data.index_len]) |id| {
            self.mesh.pushIndex(vert_offset_id + id);
        }
    }

    // Caller must check if there is enough buffer space prior.
    pub fn pushVertexData(self: *Batcher, comptime num_verts: usize, comptime num_indices: usize, data: *VertexData(num_verts, num_indices)) void {
        self.mesh.pushVertexData(num_verts, num_indices, data);
    }

    pub fn ensurePushMeshData(self: *Batcher, verts: []const TexShaderVertex, indexes: []const u16) void {
        self.ensureUnusedBuffer(verts.len, indexes.len);
        const vert_start = self.mesh.pushVertexes(verts);
        self.mesh.pushDeltaIndexes(vert_start, indexes);
    }

    pub fn endCmdForce(self: *Batcher) void {
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

    pub fn endCmd(self: *Batcher) void {
        if (self.mesh.cur_index_buf_size > self.cmd_index_start_idx) {
            self.endCmdForce();
        }
    }

    /// OpenGL immediately flushes with drawElements.
    /// Vulkan records the draw command, flushed by endFrameVK.
    fn pushDrawCall(self: *Batcher) void {
        switch (Backend) {
            .OpenGL => {
                switch (self.cur_shader_type) {
                    .Plane => {
                        self.inner.renderer.setDepthTest(true);
                        self.inner.renderer.pipelines.plane.bind(self.mvp.mat);
                        gl.bindVertexArray(self.inner.renderer.pipelines.plane.shader.vao_id);
                    },
                    .Wireframe => {
                        if (!IsWasm) {
                            gl.polygonMode(gl.GL_FRONT_AND_BACK, gl.GL_LINE);
                            self.inner.renderer.setDepthTest(true);
                            self.inner.renderer.pipelines.tex.bind(self.mvp.mat, self.inner.cur_gl_tex_id);
                            gl.bindVertexArray(self.inner.renderer.pipelines.tex.shader.vao_id);
                            gl.polygonMode(gl.GL_FRONT_AND_BACK, gl.GL_FILL);
                        } else {
                            // Only supported on Desktop atm.
                            return;
                        }
                    },
                    .Anim3D => stdx.panic("anim 3d"),
                    .AnimPbr3D => stdx.panic("anim pbr 3d"),
                    .Normal => stdx.panic("normal"),
                    .Tex => {
                        self.inner.renderer.setDepthTest(false);
                        self.inner.renderer.pipelines.tex.bind(self.mvp.mat, self.inner.cur_gl_tex_id);
                        // Recall how to pull data from the buffer for shader.
                        gl.bindVertexArray(self.inner.renderer.pipelines.tex.shader.vao_id);
                    },
                    .Gradient => {
                        self.inner.renderer.setDepthTest(false);
                        self.inner.renderer.pipelines.gradient.bind(self.mvp.mat, self.start_pos, self.start_color, self.end_pos, self.end_color);
                        // Recall how to pull data from the buffer for shader.
                        gl.bindVertexArray(self.inner.renderer.pipelines.gradient.shader.vao_id);
                    },
                    .Tex3D,
                    .TexPbr3D,
                    .Custom => unsupported(),
                }

                const num_verts = self.mesh.cur_vert_buf_size;
                const num_indexes = self.mesh.cur_index_buf_size;

                // Update vertex buffer.
                gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.inner.renderer.vert_buf_id);
                gl.bufferData(gl.GL_ARRAY_BUFFER, @intCast(c_long, num_verts * @sizeOf(TexShaderVertex)), self.mesh.vert_buf.ptr, gl.GL_DYNAMIC_DRAW);

                // Update index buffer.
                gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.inner.renderer.index_buf_id);
                gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, num_indexes * 2), self.mesh.index_buf.ptr, gl.GL_DYNAMIC_DRAW);

                gl.drawElements(gl.GL_TRIANGLES, num_indexes, self.mesh.index_buffer_type, 0);

                // Unbind vao.
                gl.bindVertexArray(0);
            },
            .Vulkan => {
                const cmd_buf = self.inner.cur_frame.main_cmd_buf;
                const num_indexes = self.mesh.cur_index_buf_size - self.cmd_index_start_idx;
                switch (self.cur_shader_type) {
                    .Tex3D => {
                        const pipeline = self.inner.pipelines.tex_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);

                        // It's expensive to update a uniform buffer all the time so use push constants.
                        var push_const = gvk.ModelVertexConstant{
                            .vp = self.mvp.mat,
                            .model_idx = self.model_idx,
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.ModelVertexConstant), &push_const);
                    },
                    .TexPbr3D => {
                        if (self.inner.do_shadow_pass) {
                            const shadow_p = self.inner.pipelines.shadow_pipeline;
                            const shadow_cmd = self.inner.cur_frame.shadow_cmd_buf;
                            vk.cmdBindPipeline(shadow_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, shadow_p.pipeline);
                            const desc_sets = [_]vk.VkDescriptorSet{
                                self.inner.cur_tex_desc_set,
                                self.inner.mats_desc_set,
                            };
                            vk.cmdBindDescriptorSets(shadow_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, shadow_p.layout, 0, desc_sets.len, &desc_sets, 0, null);
                            var push_const = gvk.ShadowVertexConstant{
                                .vp = self.inner.light_cast_vp.mat,
                                .model_idx = self.model_idx,
                            };
                            vk.cmdPushConstants(shadow_cmd, shadow_p.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.ShadowVertexConstant), &push_const);
                            vk.cmdDrawIndexed(shadow_cmd, num_indexes, 1, self.cmd_index_start_idx, 0, 0);
                        }
                        const pipeline = self.inner.pipelines.tex_pbr_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                            self.inner.cur_frame.cam_desc_set,
                            self.inner.materials_desc_set,
                            self.inner.cur_frame.shadowmap_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);
                        var push_const = gvk.TexLightingVertexConstant{
                            .mvp = self.mvp.mat,
                            .normal_0 = self.normal[0..3].*,
                            .normal_1 = self.normal[3..6].*,
                            .normal_2 = self.normal[6..9].*,
                            .model_idx = self.model_idx,
                            .material_idx = self.material_idx,
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.TexLightingVertexConstant), &push_const);
                    },
                    .AnimPbr3D => {
                        if (self.inner.do_shadow_pass) {
                            const shadow_p = self.inner.pipelines.anim_shadow_pipeline;
                            const shadow_cmd = self.inner.cur_frame.shadow_cmd_buf;
                            vk.cmdBindPipeline(shadow_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, shadow_p.pipeline);
                            const desc_sets = [_]vk.VkDescriptorSet{
                                self.inner.cur_tex_desc_set,
                                self.inner.mats_desc_set,
                            };
                            vk.cmdBindDescriptorSets(shadow_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, shadow_p.layout, 0, desc_sets.len, &desc_sets, 0, null);
                            var push_const = gvk.ShadowVertexConstant{
                                .vp = self.inner.light_cast_vp.mat,
                                .model_idx = self.model_idx,
                            };
                            vk.cmdPushConstants(shadow_cmd, shadow_p.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.ShadowVertexConstant), &push_const);
                            vk.cmdDrawIndexed(shadow_cmd, num_indexes, 1, self.cmd_index_start_idx, 0, 0);
                        }
                        const pipeline = self.inner.pipelines.anim_pbr_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                            self.inner.cur_frame.cam_desc_set,
                            self.inner.materials_desc_set,
                            self.inner.cur_frame.shadowmap_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);
                        var push_const = gvk.TexLightingVertexConstant{
                            .mvp = self.mvp.mat,
                            .normal_0 = self.normal[0..3].*,
                            .normal_1 = self.normal[3..6].*,
                            .normal_2 = self.normal[6..9].*,
                            .model_idx = self.model_idx,
                            .material_idx = self.material_idx,
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.TexLightingVertexConstant), &push_const);
                    },
                    .Anim3D => {
                        const pipeline = self.inner.pipelines.anim_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);
                        var push_const = gvk.ModelVertexConstant{
                            .vp = self.mvp.mat,
                            .model_idx = self.model_idx,
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.ModelVertexConstant), &push_const);
                    },
                    .Wireframe => {
                        const pipeline = self.inner.pipelines.wireframe_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        // Must bind even though it does not use the texture since the pipeline was created with the descriptor layout.
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 16 * 4, &self.mvp.mat);
                    },
                    .Normal => {
                        const pipeline = self.inner.pipelines.norm_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 16 * 4, &self.mvp.mat);
                    },
                    .Tex => {
                        const pipeline = self.inner.pipelines.tex_pipeline_2d;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        const desc_sets = [_]vk.VkDescriptorSet{
                            self.inner.cur_tex_desc_set,
                            self.inner.mats_desc_set,
                        };
                        vk.cmdBindDescriptorSets(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, desc_sets.len, &desc_sets, 0, null);
                        var push_const = gvk.ModelVertexConstant{
                            .vp = self.mvp.mat,
                            .model_idx = 0,
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(gvk.ModelVertexConstant), &push_const);
                    },
                    .Gradient => {
                        const pipeline = self.inner.pipelines.gradient_pipeline_2d;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 16 * 4, &self.mvp.mat);
                        const data = GradientFragmentData{
                            .start_pos = self.start_pos,
                            .start_color = self.start_color.toFloatArray(),
                            .end_pos = self.end_pos,
                            .end_color = self.end_color.toFloatArray(),
                        };
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_FRAGMENT_BIT, 16 * 4, 4 * 12, &data);
                    },
                    .Plane => {
                        const pipeline = self.inner.pipelines.plane_pipeline;
                        vk.cmdBindPipeline(cmd_buf, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
                        vk.cmdPushConstants(cmd_buf, pipeline.layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 16 * 4, &self.mvp.mat);
                    },
                    else => stdx.unsupported(),
                }
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

/// Properties are ordered to have the same alignment in glsl.
const GradientFragmentData = struct {
    start_color: [4]f32,
    end_color: [4]f32,
    start_pos: Vec2,
    end_pos: Vec2,
};
