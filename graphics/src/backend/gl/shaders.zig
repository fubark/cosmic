const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const Vec3 = stdx.math.Vec3;
const Mat4 = stdx.math.Mat4;
const Mat3 = stdx.math.Mat3;
const gl = @import("gl");
const GLtextureId = gl.GLuint;

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const TexShaderVertex = gpu.TexShaderVertex;
const Shader = graphics.gl.Shader;
const Color = graphics.Color;

const tex_vert = @embedFile("shaders/tex_vert.glsl");
const tex_frag = @embedFile("shaders/tex_frag.glsl");

const tex_vert_webgl2 = @embedFile("shaders/tex_vert_webgl2.glsl");
const tex_frag_webgl2 = @embedFile("shaders/tex_frag_webgl2.glsl");

const tex_pbr_vert = @embedFile("shaders/tex_pbr_vert.glsl");
const tex_pbr_frag = @embedFile("shaders/tex_pbr_frag.glsl");

const tex_pbr_vert_webgl2 = @embedFile("shaders/tex_pbr_vert_webgl2.glsl");
const tex_pbr_frag_webgl2 = @embedFile("shaders/tex_pbr_frag_webgl2.glsl");

const pbr_src = @embedFile("shaders/pbr.glsl");

const gradient_vert = @embedFile("shaders/gradient_vert.glsl");
const gradient_frag = @embedFile("shaders/gradient_frag.glsl");

const gradient_vert_webgl2 = @embedFile("shaders/gradient_vert_webgl2.glsl");
const gradient_frag_webgl2 = @embedFile("shaders/gradient_frag_webgl2.glsl");

const plane_vert = @embedFile("shaders/plane_vert.glsl");
const plane_frag = @embedFile("shaders/plane_frag.glsl");

const plane_vert_webgl2 = @embedFile("shaders/plane_vert_webgl2.glsl");
const plane_frag_webgl2 = @embedFile("shaders/plane_frag_webgl2.glsl");

pub const TexPbrShader = struct {
    shader: Shader,
    u_const_vp: gl.GLint,
    u_const_model: gl.GLint,
    u_const_normal: gl.GLint,
    u_light_cam_pos: gl.GLint,
    u_light_vec: gl.GLint,
    u_light_color: gl.GLint,
    u_light_vp: gl.GLint,
    u_light_enable_shadows: gl.GLint,
    u_material_emissivity: gl.GLint,
    u_material_roughness: gl.GLint,
    u_material_metallic: gl.GLint,
    u_material_albedo: gl.GLint,
    u_tex: gl.GLint,

    pub fn init(alloc: std.mem.Allocator, vert_buf_id: gl.GLuint) !TexPbrShader {
        var shader: Shader = undefined;
        if (IsWasm) {
            const needle = "#include \"pbr.glsl\"";
            const final_frag_size = std.mem.replacementSize(u8, tex_pbr_frag_webgl2, needle, pbr_src);
            const final_frag = try alloc.alloc(u8, final_frag_size);
            defer alloc.free(final_frag);
            _ = std.mem.replace(u8, tex_pbr_frag_webgl2, needle, pbr_src, final_frag);
            shader = try Shader.init(tex_pbr_vert_webgl2, final_frag);
        } else {
            const needle = "#include \"pbr.glsl\"";
            const final_frag_size = std.mem.replacementSize(u8, tex_pbr_frag, needle, pbr_src);
            const final_frag = try alloc.alloc(u8, final_frag_size);
            defer alloc.free(final_frag);
            _ = std.mem.replace(u8, tex_pbr_frag, needle, pbr_src, final_frag);
            shader = try Shader.init(tex_pbr_vert, final_frag);
        }

        gl.bindVertexArray(shader.vao_id);
        defer gl.bindVertexArray(0);

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        bindAttributes(@sizeOf(TexShaderVertex), &.{
            // a_pos
            ShaderAttribute.init(0, @offsetOf(TexShaderVertex, "pos"), gl.GL_FLOAT, 4),
            // a_normal
            ShaderAttribute.init(1, @offsetOf(TexShaderVertex, "normal"), gl.GL_FLOAT, 3),
            // a_uv
            ShaderAttribute.init(2, @offsetOf(TexShaderVertex, "uv"), gl.GL_FLOAT, 2),
        });

        return TexPbrShader{
            .shader = shader,
            .u_const_vp = try shader.getUniformLocation("u_const.vp"),
            .u_const_model = try shader.getUniformLocation("u_const.model"),
            .u_const_normal = try shader.getUniformLocation("u_const.normal"),
            .u_light_cam_pos = try shader.getUniformLocation("u_light.cam_pos"),
            .u_light_vec = try shader.getUniformLocation("u_light.light_vec"),
            .u_light_color = try shader.getUniformLocation("u_light.light_color"),
            .u_light_vp = try shader.getUniformLocation("u_light.light_vp"),
            .u_light_enable_shadows = try shader.getUniformLocation("u_light.enable_shadows"),
            .u_material_emissivity = try shader.getUniformLocation("u_material.emissivity"),
            .u_material_roughness = try shader.getUniformLocation("u_material.roughness"),
            .u_material_metallic = try shader.getUniformLocation("u_material.metallic"),
            .u_material_albedo = try shader.getUniformLocation("u_material.albedo_color"),
            .u_tex = try shader.getUniformLocation("u_tex"),
        };
    }

    pub fn deinit(self: TexPbrShader) void {
        self.shader.deinit();
    }

    pub fn bind(self: TexPbrShader, vp: Mat4, model: Mat4, normal: Mat3, tex_id: GLtextureId, mat: graphics.Material, light: gpu.ShaderCamera) void {
        gl.useProgram(self.shader.prog_id);

        gl.uniformMatrix4fv(self.u_const_vp, 1, gl.GL_FALSE, &vp);
        gl.uniformMatrix4fv(self.u_const_model, 1, gl.GL_FALSE, &model);
        gl.uniformMatrix3fv(self.u_const_normal, 1, gl.GL_FALSE, &normal);

        gl.uniform3fv(self.u_light_cam_pos, 1, &light.cam_pos.x);
        gl.uniform3fv(self.u_light_vec, 1, &light.light_vec.x);
        gl.uniform3fv(self.u_light_color, 1, &light.light_color.x);
        gl.uniformMatrix4fv(self.u_light_vp, 1, gl.GL_FALSE, &light.light_vp);
        gl.uniform1i(self.u_light_enable_shadows, if (light.enable_shadows) 1 else 0);

        gl.uniform1fv(self.u_material_emissivity, 1, &mat.emissivity);
        gl.uniform1fv(self.u_material_roughness, 1, &mat.roughness);
        gl.uniform1fv(self.u_material_metallic, 1, &mat.metallic);
        gl.uniform4fv(self.u_material_albedo, 1, &mat.albedo_color);

        gl.activeTexture(gl.GL_TEXTURE0);
        gl.bindTexture(gl.GL_TEXTURE_2D, tex_id);
        // set tex to active texture.
        gl.uniform1i(self.u_tex, 0);
    }
};

pub const PlaneShader = struct {
    shader: Shader,
    u_const: gl.GLint,

    pub fn init(vert_buf_id: gl.GLuint) !PlaneShader {
        var shader: Shader = undefined;
        if (IsWasm) {
            shader = try Shader.init(plane_vert_webgl2, plane_frag_webgl2);
        } else {
            shader = try Shader.init(plane_vert, plane_frag);
        }

        gl.bindVertexArray(shader.vao_id);
        defer gl.bindVertexArray(0);

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        bindAttributes(@sizeOf(TexShaderVertex), &.{
            // a_pos
            ShaderAttribute.init(0, @offsetOf(TexShaderVertex, "pos"), gl.GL_FLOAT, 4),
        });

        return PlaneShader{
            .shader = shader,
            .u_const = try shader.getUniformLocation("u_const.mvp"),
        };
    }

    pub fn deinit(self: PlaneShader) void {
        self.shader.deinit();
    }

    pub fn bind(self: PlaneShader, mvp: Mat4) void {
        gl.useProgram(self.shader.prog_id);

        // set u_mvp, since transpose is false, it expects to receive in column major order.
        gl.uniformMatrix4fv(self.u_const, 1, gl.GL_FALSE, &mvp);
    }
};

pub const TexShader = struct {
    shader: Shader,
    u_mvp: gl.GLint,
    u_tex: gl.GLint,

    pub fn init(vert_buf_id: gl.GLuint) !TexShader {
        var shader: Shader = undefined;
        if (IsWasm) {
            shader = Shader.init(tex_vert_webgl2, tex_frag_webgl2) catch unreachable;
        } else {
            shader = Shader.init(tex_vert, tex_frag) catch unreachable;
        }

        gl.bindVertexArray(shader.vao_id);
        defer gl.bindVertexArray(0);

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        bindAttributes(@sizeOf(TexShaderVertex), &.{
            // a_pos
            ShaderAttribute.init(0, @offsetOf(TexShaderVertex, "pos"), gl.GL_FLOAT, 4),
            // a_uv
            ShaderAttribute.init(1, @offsetOf(TexShaderVertex, "uv"), gl.GL_FLOAT, 2),
            // a_color
            ShaderAttribute.init(2, @offsetOf(TexShaderVertex, "color"), gl.GL_FLOAT, 4),
        });

        return TexShader{
            .shader = shader,
            .u_mvp = try shader.getUniformLocation("u_mvp"),
            .u_tex = try shader.getUniformLocation("u_tex"),
        };
    }

    pub fn deinit(self: TexShader) void {
        self.shader.deinit();
    }

    pub fn bind(self: TexShader, mvp: Mat4, tex_id: gl.GLuint) void {
        gl.useProgram(self.shader.prog_id);

        // set u_mvp, since transpose is false, it expects to receive in column major order.
        gl.uniformMatrix4fv(self.u_mvp, 1, gl.GL_FALSE, &mvp);

        gl.activeTexture(gl.GL_TEXTURE0);
        gl.bindTexture(gl.GL_TEXTURE_2D, tex_id);

        // set tex to active texture.
        gl.uniform1i(self.u_tex, 0);
    }
};

pub const GradientShader = struct {
    shader: Shader,
    u_mvp: gl.GLint,
    u_start_pos: gl.GLint,
    u_start_color: gl.GLint,
    u_end_pos: gl.GLint,
    u_end_color: gl.GLint,

    pub fn init(vert_buf_id: gl.GLuint) !GradientShader {
        var shader: Shader = undefined;
        if (IsWasm) {
            shader = Shader.init(gradient_vert_webgl2, gradient_frag_webgl2) catch unreachable;
        } else {
            shader = Shader.init(gradient_vert, gradient_frag) catch unreachable;
        }

        gl.bindVertexArray(shader.vao_id);
        defer gl.bindVertexArray(0);

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        bindAttributes(@sizeOf(TexShaderVertex), &.{
            // a_pos
            ShaderAttribute.init(0, @offsetOf(TexShaderVertex, "pos"), gl.GL_FLOAT, 4),
        });

        return GradientShader{
            .shader = shader,
            .u_mvp = try shader.getUniformLocation("u_mvp"),
            .u_start_pos = try shader.getUniformLocation("u_start_pos"),
            .u_start_color = try shader.getUniformLocation("u_start_color"),
            .u_end_pos = try shader.getUniformLocation("u_end_pos"),
            .u_end_color = try shader.getUniformLocation("u_end_color"),
        };
    }

    pub fn deinit(self: GradientShader) void {
        self.shader.deinit();
    }

    pub fn bind(self: GradientShader, mvp: Mat4, start_pos: Vec2, start_color: Color, end_pos: Vec2, end_color: Color) void {
        gl.useProgram(self.shader.prog_id);

        // set u_mvp, since transpose is false, it expects to receive in column major order.
        gl.uniformMatrix4fv(self.u_mvp, 1, gl.GL_FALSE, &mvp);

        gl.uniform2fv(self.u_start_pos, 1, @ptrCast([*]const f32, &start_pos));
        gl.uniform2fv(self.u_end_pos, 1, @ptrCast([*]const f32, &end_pos));

        const start_color_arr = start_color.toFloatArray();
        gl.uniform4fv(self.u_start_color, 1, &start_color_arr);

        const end_color_arr = end_color.toFloatArray();
        gl.uniform4fv(self.u_end_color, 1, &end_color_arr);
    }
};

fn u32ToVoidPtr(val: u32) ?*const gl.GLvoid {
    return @intToPtr(?*const gl.GLvoid, val);
}

// Define how to get attribute data out of vertex buffer. Eg. an attribute a_pos could be a vec4 meaning 4 components.
// size - num of components for the attribute.
// type - component data type.
// normalized - normally false, only relevant for non GL_FLOAT types anyway.
// stride - number of bytes for each vertex. 0 indicates that the stride is size * sizeof(type)
// offset - offset in bytes of the first component of first vertex.
fn vertexAttribPointer(attr_idx: gl.GLuint, size: gl.GLint, data_type: gl.GLenum, stride: gl.GLsizei, offset: ?*const gl.GLvoid) void {
    gl.vertexAttribPointer(attr_idx, size, data_type, gl.GL_FALSE, stride, offset);
}

const ShaderAttribute = struct {
    pos: u32,
    offset: u32,
    num_components: gl.GLint,
    data_type: gl.GLenum,

    fn init(pos: u32, offset: u32, data_type: gl.GLenum, num_components: gl.GLint) ShaderAttribute {
        return .{
            .pos = pos,
            .offset = offset,
            .data_type = data_type,
            .num_components = num_components,
        };
    }
};

fn bindAttributes(stride: u32, attrs: []const ShaderAttribute) void {
    for (attrs) |attr| {
        gl.enableVertexAttribArray(attr.pos);
        vertexAttribPointer(attr.pos, attr.num_components, attr.data_type, @intCast(c_int, stride), u32ToVoidPtr(attr.offset));
    }
}