const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const Mat4 = stdx.math.Mat4;
const gl = @import("gl");

const gl_graphics = @import("graphics.zig");
const Shader = @import("shader.zig").Shader;
const graphics = @import("../../graphics.zig");
const Color = graphics.Color;

const tex_vert = @embedFile("../../shaders/tex_vert.glsl");
const tex_frag = @embedFile("../../shaders/tex_frag.glsl");

const tex_vert_webgl2 = @embedFile("../../shaders/tex_vert_webgl2.glsl");
const tex_frag_webgl2 = @embedFile("../../shaders/tex_frag_webgl2.glsl");

const gradient_vert = @embedFile("../../shaders/gradient_vert.glsl");
const gradient_frag = @embedFile("../../shaders/gradient_frag.glsl");

pub const TexShader = struct {
    shader: Shader,
    u_mvp: gl.GLint,
    u_tex: gl.GLint,

    const Self = @This();

    pub fn init(vert_buf_id: gl.GLuint) Self {
        var shader: Shader = undefined;
        if (IsWasm) {
            shader = Shader.init(tex_vert_webgl2, tex_frag_webgl2) catch unreachable;
        } else {
            shader = Shader.init(tex_vert, tex_frag) catch unreachable;
        }

        gl.bindVertexArray(shader.vao_id);
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        // a_pos
        gl.enableVertexAttribArray(0);
        vertexAttribPointer(0, 4, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(0));
        // a_uv
        gl.enableVertexAttribArray(1);
        vertexAttribPointer(1, 2, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(4 * 4));
        // a_color
        gl.enableVertexAttribArray(2);
        vertexAttribPointer(2, 4, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(6 * 4));
        gl.bindVertexArray(0);

        return .{
            .shader = shader,
            .u_mvp = shader.getUniformLocation("u_mvp"),
            .u_tex = shader.getUniformLocation("u_tex"),
        };
    }

    pub fn deinit(self: Self) void {
        self.shader.deinit();
    }

    pub fn bind(self: Self, mvp: Mat4, tex_id: gl.GLuint) void {
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

    const Self = @This();

    pub fn init(vert_buf_id: gl.GLuint) Self {
        var shader: Shader = undefined;
        shader = Shader.init(gradient_vert, gradient_frag) catch unreachable;

        gl.bindVertexArray(shader.vao_id);
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, vert_buf_id);
        // a_pos
        gl.enableVertexAttribArray(0);
        vertexAttribPointer(0, 4, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(0));
        gl.bindVertexArray(0);

        return .{
            .shader = shader,
            .u_mvp = shader.getUniformLocation("u_mvp"),
            .u_start_pos = shader.getUniformLocation("u_start_pos"),
            .u_start_color = shader.getUniformLocation("u_start_color"),
            .u_end_pos = shader.getUniformLocation("u_end_pos"),
            .u_end_color = shader.getUniformLocation("u_end_color"),
        };
    }

    pub fn deinit(self: Self) void {
        self.shader.deinit();
    }

    pub fn bind(self: Self, mvp: Mat4, start_pos: Vec2, start_color: Color, end_pos: Vec2, end_color: Color) void {
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