const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const Mat4 = stdx.math.Mat4;
const Mat3 = stdx.math.Mat3;
const Vec3 = stdx.math.Vec3;
const gl = @import("gl");
const GLtextureId = gl.GLuint;

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const TexShaderVertex = gpu.TexShaderVertex;
const TextureId = gpu.TextureId;
const Mesh = gpu.Mesh;
const shaders = @import("shaders.zig");
const log = stdx.log.scoped(.gl_renderer);

/// Initial buffer sizes
const MatBufferInitialSize = 5000;
const MatBufferInitialSizeBytes = MatBufferInitialSize * @sizeOf(Mat4);
const MaterialBufferInitialSize = 100;
const MaterialBufferInitialSizeBytes = MaterialBufferInitialSize * @sizeOf(graphics.Material);

pub const SlaveRenderer = struct {
    dummy: bool,

    pub fn init(self: *SlaveRenderer, alloc: std.mem.Allocator) !void {
        _ = self;
        _ = alloc;
    }
};

/// Provides an API to make direct draw calls using OpenGL shaders.
/// Makes no assumptions about how to group draw calls together.
/// Manages common buffers used for shaders.
/// Keeps some OpenGL state to avoid redundant calls.
pub const Renderer = struct {
    /// Buffers.
    vert_buf_id: gl.GLuint,
    index_buf_id: gl.GLuint,
    mats_buf_id: gl.GLuint,
    mats_buf: []stdx.math.Mat4,
    materials_buf_id: gl.GLuint,
    materials_buf: []graphics.Material,
    mesh: Mesh,
    image_store: *graphics.gpu.ImageStore,

    /// Pipelines.
    pipelines: Pipelines,

    /// State.
    depth_test: bool,
    binded_draw_framebuffer: gl.GLuint,

    pub fn init(self: *Renderer, alloc: std.mem.Allocator) !void {
        self.* = .{
            .vert_buf_id = undefined,
            .index_buf_id = undefined,
            .mats_buf_id = undefined,
            .materials_buf_id = undefined,
            .materials_buf = undefined,
            .mats_buf = undefined,
            .depth_test = undefined,
            .mesh = undefined,
            .pipelines = undefined,
            .image_store = undefined,
            .binded_draw_framebuffer = 0,
        };
        const max_total_textures = gl.getMaxTotalTextures();
        const max_fragment_textures = gl.getMaxFragmentTextures();
        log.debug("max frag textures: {}, max total textures: {}", .{ max_fragment_textures, max_total_textures });

        // Generate buffers.
        var buf_ids: [4]gl.GLuint = undefined;
        gl.genBuffers(4, &buf_ids);
        self.vert_buf_id = buf_ids[0];
        self.index_buf_id = buf_ids[1];
        self.mats_buf_id = buf_ids[2];
        self.materials_buf_id = buf_ids[3];

        self.mats_buf = try alloc.alloc(Mat4, MatBufferInitialSize);
        self.materials_buf = try alloc.alloc(graphics.Material, MaterialBufferInitialSize);

        self.mesh = Mesh.init(alloc, self.mats_buf, self.materials_buf);

        // Initialize pipelines.
        self.pipelines = .{
            .tex = try shaders.TexShader.init(self.vert_buf_id),
            .gradient = try shaders.GradientShader.init(self.vert_buf_id),
            .plane = try shaders.PlaneShader.init(self.vert_buf_id),
            .tex_pbr = try shaders.TexPbrShader.init(alloc, self.vert_buf_id),
        };

        // Enable blending by default.
        gl.enable(gl.GL_BLEND);

        // Cull back face.
        gl.enable(gl.GL_CULL_FACE);
        gl.frontFace(gl.GL_CCW);

        // Disable depth test by default.
        gl.disable(gl.GL_DEPTH_TEST);
        self.depth_test = false;

        gl.disable(gl.GL_POLYGON_OFFSET_FILL);
    }

    pub fn deinit(self: Renderer, alloc: std.mem.Allocator) void {
        const bufs = [_]gl.GLuint{
            self.vert_buf_id,
            self.index_buf_id,
            self.mats_buf_id,
            self.materials_buf_id,
        };
        gl.deleteBuffers(4, &bufs);

        alloc.free(self.mats_buf);
        alloc.free(self.materials_buf);
        self.mesh.deinit();

        self.pipelines.deinit();
    }

    pub fn bindDrawFramebuffer(self: *Renderer, framebuffer: gl.GLuint) void {
        gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, framebuffer);
        self.binded_draw_framebuffer = framebuffer;
    }

    pub fn pushTex3D(self: *Renderer, mvp: Mat4, tex_id: TextureId) void {
        const gl_tex_id = self.image_store.getTexture(tex_id).inner.tex_id;
        self.setDepthTest(true);
        self.pipelines.tex.bind(mvp, gl_tex_id);
        gl.bindVertexArray(self.pipelines.tex.shader.vao_id);
        self.pushCurrentElements();
    }

    pub fn pushTexWireframe3D(self: *Renderer, mvp: Mat4, tex_id: TextureId) void {
        // Only supported on Desktop atm.
        if (!IsWasm) {
            const gl_tex_id = self.image_store.getTexture(tex_id).inner.tex_id;
            gl.polygonMode(gl.GL_FRONT_AND_BACK, gl.GL_LINE);
            self.setDepthTest(true);
            self.pipelines.tex.bind(mvp, gl_tex_id);
            gl.bindVertexArray(self.pipelines.tex.shader.vao_id);
            self.pushCurrentElements();
            gl.polygonMode(gl.GL_FRONT_AND_BACK, gl.GL_FILL);
        }
    }

    pub fn pushTexPbr3D(self: *Renderer, mvp: Mat4, model: Mat4, normal: Mat3, mat: graphics.Material, light: gpu.ShaderCamera, tex_id: TextureId) void {
        const gl_tex_id = self.image_store.getTexture(tex_id).inner.tex_id;
        self.setDepthTest(true);
        self.pipelines.tex_pbr.bind(mvp, model, normal, gl_tex_id, mat, light);
        gl.bindVertexArray(self.pipelines.tex_pbr.shader.vao_id);
        self.pushCurrentElements();
    }

    pub fn ensurePushMeshData(self: *Renderer, verts: []const TexShaderVertex, indexes: []const u16) void {
        self.ensureUnusedBuffer(verts.len, indexes.len);
        const vert_start = self.mesh.pushVertexes(verts);
        self.mesh.pushDeltaIndexes(vert_start, indexes);
    }

    /// Ensures that the buffer has enough space.
    pub fn ensureUnusedBuffer(self: *Renderer, vert_inc: usize, index_inc: usize) void {
        if (!self.mesh.ensureUnusedBuffer(vert_inc, index_inc)) {
            // Currently, draw calls reset the mesh so data that proceeds the current buffer belongs to the same draw call.
            stdx.panic("buffer limit");
        }
    }

    fn pushCurrentElements(self: *Renderer) void {
        const num_verts = self.mesh.cur_vert_buf_size;
        const num_indexes = self.mesh.cur_index_buf_size;

        // Update vertex buffer.
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vert_buf_id);
        gl.bufferData(gl.GL_ARRAY_BUFFER, @intCast(c_long, num_verts * @sizeOf(TexShaderVertex)), self.mesh.vert_buf.ptr, gl.GL_DYNAMIC_DRAW);

        // Update index buffer.
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buf_id);
        gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, num_indexes * 2), self.mesh.index_buf.ptr, gl.GL_DYNAMIC_DRAW);

        gl.drawElements(gl.GL_TRIANGLES, num_indexes, self.mesh.index_buffer_type, 0);
        self.mesh.reset();
    }

    pub fn setDepthTest(self: *Renderer, depth_test: bool) void {
        if (self.depth_test == depth_test) {
            return;
        }
        if (depth_test) {
            gl.enable(gl.GL_DEPTH_TEST);
        } else {
            gl.disable(gl.GL_DEPTH_TEST);
        }
        self.depth_test = depth_test;
    }
};

pub const Pipelines = struct {
    tex: shaders.TexShader,
    gradient: shaders.GradientShader,
    plane: shaders.PlaneShader,
    tex_pbr: shaders.TexPbrShader,

    pub fn deinit(self: Pipelines) void {
        self.tex.deinit();
        self.tex_pbr.deinit();
        self.gradient.deinit();
        self.plane.deinit();
    }
};