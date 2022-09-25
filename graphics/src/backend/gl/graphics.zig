const std = @import("std");
const stdx = @import("stdx");
const Vec4 = stdx.math.Vec4;
const Vec3 = stdx.math.Vec3;
const Transform = stdx.math.Transform;
const gl = @import("gl");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const Color = graphics.Color;
pub const SwapChain = @import("swapchain.zig").SwapChain;
pub const Shader = @import("shader.zig").Shader;
pub const Renderer = @import("renderer.zig").Renderer;
pub const SlaveRenderer = @import("renderer.zig").SlaveRenderer;
const TexShaderVertex = gpu.TexShaderVertex;
const log = stdx.log.scoped(.gl_graphics);

pub const Graphics = struct {
    renderer: *Renderer,
    mesh: *gpu.Mesh,
    gpu_ctx: *gpu.Graphics,

    pub fn init(self: *Graphics, _: std.mem.Allocator, renderer: *Renderer) !void {
        self.* = .{
            .gpu_ctx = undefined,
            .renderer = renderer,
            .mesh = undefined,
        };
        self.mesh = &self.renderer.mesh;
    }

    pub fn deinit(_: Graphics, _: std.mem.Allocator) void {
    }

    /// Points of front face is in ccw order.
    pub fn fillTriangle3D(self: *Graphics, x1: f32, y1: f32, z1: f32, x2: f32, y2: f32, z2: f32, x3: f32, y3: f32, z3: f32) void {
        self.gpu_ctx.batcher.endCmd();
        self.renderer.ensureUnusedBuffer(3, 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.gpu_ctx.ps.fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.mesh.getNextIndexId();
        vert.setXYZ(x1, y1, z1);
        self.mesh.pushVertex(vert);
        vert.setXYZ(x2, y2, z2);
        self.mesh.pushVertex(vert);
        vert.setXYZ(x3, y3, z3);
        self.mesh.pushVertex(vert);
        self.mesh.pushTriangle(start_idx, start_idx + 1, start_idx + 2);

        const vp = self.gpu_ctx.ps.view_xform.getAppliedTransform(self.gpu_ctx.ps.proj_xform);
        self.renderer.pushTex3D(vp.mat, self.gpu_ctx.white_tex.tex_id);
    }

    pub fn fillScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.fillMesh3D(xform, prim);
            }
        }
    }

    pub fn fillMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        self.gpu_ctx.batcher.endCmd();
        const vp = self.gpu_ctx.ps.view_xform.getAppliedTransform(self.gpu_ctx.ps.proj_xform);
        const mvp = xform.getAppliedTransform(vp);

        self.renderer.ensureUnusedBuffer(mesh.verts.len, mesh.indexes.len);
        const vert_start = self.mesh.getNextIndexId();
        for (mesh.verts) |vert| {
            var new_vert = vert;
            new_vert.setColor(self.gpu_ctx.ps.fill_color);
            self.mesh.pushVertex(new_vert);
        }
        self.mesh.pushDeltaIndexes(vert_start, mesh.indexes);
        self.renderer.pushTex3D(mvp.mat, self.gpu_ctx.white_tex.tex_id);
    }

    pub fn drawScenePbrCustom3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene, mat: graphics.Material) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.drawMeshPbrCustom3D(xform, prim, mat);
            }
        }
    }

    pub fn drawMeshPbrCustom3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D, mat: graphics.Material) void {
        self.gpu_ctx.batcher.endCmd();
        const vp = self.gpu_ctx.ps.view_xform.getAppliedTransform(self.gpu_ctx.ps.proj_xform);
        // Compute normal matrix for lighting.
        const normal = xform.toRotationMat();
        self.renderer.ensurePushMeshData(mesh.verts, mesh.indexes);
        const tex_id = if (mesh.image_id) |image_id| b: {
            const img = self.renderer.image_store.images.getNoCheck(image_id);
            break :b img.tex_id;
        } else self.gpu_ctx.white_tex.tex_id;

        const light = gpu.ShaderCamera{
            .cam_pos = self.gpu_ctx.cur_cam_world_pos,
            .light_vec = self.gpu_ctx.light_vec,
            .light_color = self.gpu_ctx.light_color,
            .light_vp = undefined,
            .enable_shadows = false,
        };
        self.renderer.pushTexPbr3D(vp.mat, xform.mat, normal, mat, light, tex_id);
    }

    pub fn strokeScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.strokeMesh3D(xform, prim);
            }
        }
    }

    pub fn strokeMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        self.gpu_ctx.batcher.endCmd();
        const vp = self.gpu_ctx.ps.view_xform.getAppliedTransform(self.gpu_ctx.ps.proj_xform);
        const mvp = xform.getAppliedTransform(vp);

        self.renderer.ensureUnusedBuffer(mesh.verts.len, mesh.indexes.len);
        const vert_start = self.mesh.getNextIndexId();
        for (mesh.verts) |vert| {
            var new_vert = vert;
            new_vert.setColor(self.gpu_ctx.ps.stroke_color);
            self.mesh.pushVertex(new_vert);
        }
        self.mesh.pushDeltaIndexes(vert_start, mesh.indexes);
        self.renderer.pushTexWireframe3D(mvp.mat, self.gpu_ctx.white_tex.tex_id);
    }

    /// Vertices are duped so that each side reflects light without interpolating the normals.
    pub fn drawCuboidPbr3D(self: *Graphics, xform: Transform, material: graphics.Material) void {
        const vp = self.gpu_ctx.ps.view_xform.getAppliedTransform(self.gpu_ctx.ps.proj_xform);

        // Compute normal matrix for lighting.
        const normal = xform.toRotationMat();

        self.renderer.ensureUnusedBuffer(6*4, 6*6);
        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);
        vert.setUV(0, 0);
        const far_top_left = Vec4.init(-0.5, 0.5, -0.5, 1.0);
        const far_top_right = Vec4.init(0.5, 0.5, -0.5, 1.0);
        const far_bot_right = Vec4.init(0.5, -0.5, -0.5, 1.0);
        const far_bot_left = Vec4.init(-0.5, -0.5, -0.5, 1.0);
        const near_top_left = Vec4.init(-0.5, 0.5, 0.5, 1.0);
        const near_top_right = Vec4.init(0.5, 0.5, 0.5, 1.0);
        const near_bot_right = Vec4.init(0.5, -0.5, 0.5, 1.0);
        const near_bot_left = Vec4.init(-0.5, -0.5, 0.5, 1.0);

        // Far face.
        vert.setNormal(Vec3.init(0, 0, -1));
        self.mesh.pushQuad(far_top_right, far_top_left, far_bot_left, far_bot_right, vert);

        // Left face.
        vert.setNormal(Vec3.init(-1, 0, 0));
        self.mesh.pushQuad(far_top_left, near_top_left, near_bot_left, far_bot_left, vert);

        // Right face.
        vert.setNormal(Vec3.init(1, 0, 0));
        self.mesh.pushQuad(near_top_right, far_top_right, far_bot_right, near_bot_right, vert);

        // Near face.
        vert.setNormal(Vec3.init(0, 0, 1));
        self.mesh.pushQuad(near_top_left, near_top_right, near_bot_right, near_bot_left, vert);

        // Bottom face.
        vert.setNormal(Vec3.init(0, -1, 0));
        self.mesh.pushQuad(far_bot_right, far_bot_left, near_bot_left, near_bot_right, vert);

        // Top face.
        vert.setNormal(Vec3.init(0, 1, 0));
        self.mesh.pushQuad(far_top_left, far_top_right, near_top_right, near_top_left, vert);

        const light = gpu.ShaderCamera{
            .cam_pos = self.gpu_ctx.cur_cam_world_pos,
            .light_vec = self.gpu_ctx.light_vec,
            .light_color = self.gpu_ctx.light_color,
            .light_vp = undefined,
            .enable_shadows = false,
        };

        self.renderer.pushTexPbr3D(vp.mat, xform.mat, normal, material, light, self.gpu_ctx.white_tex.tex_id);
    }
};

pub fn initImage(image: *gpu.Image, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) void {
    image.* = .{
        .tex_id = undefined,
        .width = width,
        .height = height,
        .inner = undefined,
        .remove = false,
    };

    gl.genTextures(1, &image.tex_id);
    gl.activeTexture(gl.GL_TEXTURE0 + 0);
    gl.bindTexture(gl.GL_TEXTURE_2D, image.tex_id);

    // A GLint specifying the level of detail. Level 0 is the base image level and level n is the nth mipmap reduction level.
    const level = 0;
    // A GLint specifying the width of the border. Usually 0.
    const border = 0;
    // Data type of the texel data.
    const data_type = gl.GL_UNSIGNED_BYTE;

    // Set the filtering so we don't need mips.
    // TEXTURE_MIN_FILTER - filter for scaled down texture
    // TEXTURE_MAG_FILTER - filter for scaled up texture
    // Linear filter is better for anti-aliased font bitmaps.
    gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, if (linear_filter) gl.GL_LINEAR else gl.GL_NEAREST);
    gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, if (linear_filter) gl.GL_LINEAR else gl.GL_NEAREST);
    gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    const data_ptr = if (data != null) data.?.ptr else null;
    gl.texImage2D(gl.GL_TEXTURE_2D, level, gl.GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height), border, gl.GL_RGBA, data_type, data_ptr);

    gl.bindTexture(gl.GL_TEXTURE_2D, 0);
}