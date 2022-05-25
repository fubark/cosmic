const std = @import("std");
const stdx = @import("stdx");
const gl = @import("gl");

const log = stdx.log.scoped(.shader);

pub const Shader = struct {
    const Self = @This();

    vert_id: gl.GLuint,
    frag_id: gl.GLuint,
    prog_id: gl.GLuint,
    // Vertex array object used to record vbo layout.
    vao_id: gl.GLuint,

    pub fn init(vert_src: []const u8, frag_src: []const u8) !Self {
        const vert_id = gl.createShader(gl.GL_VERTEX_SHADER);
        var src_len = @intCast(c_int, vert_src.len);
        var srcs = [_][]const u8{vert_src};
        gl.shaderSource(vert_id, 1, @ptrCast(*[*c]const u8, &srcs), &src_len);
        gl.compileShader(vert_id);

        var res: i32 = 0;
        gl.getShaderiv(vert_id, gl.GL_COMPILE_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to load vertex shader: {s}", .{vert_src});
            var res_len: i32 = 0;
            var buf = std.mem.zeroes([100]u8);
            gl.getShaderInfoLog(vert_id, buf.len, &res_len, &buf);
            log.warn("shader log: {s}", .{buf});
            gl.deleteShader(vert_id);
            return error.Failed;
        }

        const frag_id = gl.createShader(gl.GL_FRAGMENT_SHADER);
        src_len = @intCast(c_int, frag_src.len);
        srcs = [_][]const u8{frag_src};
        gl.shaderSource(frag_id, 1, @ptrCast(*[*c]const u8, &srcs), &src_len);
        gl.compileShader(frag_id);
        gl.getShaderiv(frag_id, gl.GL_COMPILE_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to load fragment shader: {s}", .{frag_src});
            var res_len: i32 = 0;
            var buf = std.mem.zeroes([100]u8);
            gl.getShaderInfoLog(frag_id, buf.len, &res_len, &buf);
            log.warn("shader log: {s}", .{buf});
            gl.deleteShader(frag_id);
            return error.Failed;
        }

        const prog_id = gl.createProgram();
        gl.attachShader(prog_id, vert_id);
        gl.attachShader(prog_id, frag_id);
        gl.linkProgram(prog_id);
        gl.getProgramiv(prog_id, gl.GL_LINK_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to link shader program: {}", .{prog_id});
            var res_len: i32 = undefined;
            var buf: [100]u8 = undefined;
            gl.getProgramInfoLog(prog_id, buf.len, &res_len, &buf);
            log.warn("program log: {s}", .{buf});
            gl.deleteProgram(prog_id);
            return error.Failed;
        }

        // Cleanup.
        gl.detachShader(prog_id, vert_id);
        gl.deleteShader(vert_id);
        gl.detachShader(prog_id, frag_id);
        gl.deleteShader(frag_id);

        var ids: [1]gl.GLuint = undefined;
        gl.genVertexArrays(1, &ids);

        return Shader{
            .vao_id = ids[0],
            .vert_id = vert_id,
            .frag_id = frag_id,
            .prog_id = prog_id,
        };
    }

    pub fn deinit(self: Self) void {
        gl.deleteVertexArrays(1, &self.vao_id);
        gl.deleteProgram(self.prog_id);
        gl.deleteShader(self.frag_id);
        gl.deleteShader(self.vert_id);
    }

    pub fn getUniformLocation(self: Self, name: [:0]const u8) gl.GLint {
        return gl.getUniformLocation(self.prog_id, name);
    }
};
