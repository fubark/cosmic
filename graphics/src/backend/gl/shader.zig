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
        const vert_id = gl.glCreateShader(gl.GL_VERTEX_SHADER);
        var src_len = @intCast(c_int, vert_src.len);
        var srcs = [_][]const u8{ vert_src };
        gl.glShaderSource(vert_id, 1, @ptrCast(*[*c]const u8, &srcs), &src_len);
        gl.glCompileShader(vert_id);

        var res: i32 = 0;
        gl.glGetShaderiv(vert_id, gl.GL_COMPILE_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to load vertex shader: {s}", .{vert_src});
            var res_len: i32 = 0;
            var buf = std.mem.zeroes([100]u8);
            gl.glGetShaderInfoLog(vert_id, buf.len, &res_len, &buf);
            log.warn("shader log: {s}", .{buf});
            gl.glDeleteShader(vert_id);
            return error.Failed;
        }

        const frag_id = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
        src_len = @intCast(c_int, frag_src.len);
        srcs = [_][]const u8{ frag_src };
        gl.glShaderSource(frag_id, 1, @ptrCast(*[*c]const u8, &srcs), &src_len);
        gl.glCompileShader(frag_id);
        gl.glGetShaderiv(frag_id, gl.GL_COMPILE_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to load fragment shader: {s}", .{frag_src});
            var res_len: i32 = 0;
            var buf = std.mem.zeroes([100]u8);
            gl.glGetShaderInfoLog(frag_id, buf.len, &res_len, &buf);
            log.warn("shader log: {s}", .{buf});
            gl.glDeleteShader(frag_id);
            return error.Failed;
        }

        const prog_id = gl.glCreateProgram();
        gl.glAttachShader(prog_id, vert_id);
        gl.glAttachShader(prog_id, frag_id);
        gl.glLinkProgram(prog_id);
        gl.glGetProgramiv(prog_id, gl.GL_LINK_STATUS, &res);
        if (res == gl.GL_FALSE) {
            log.warn("failed to link shader program: {}", .{prog_id});
            var res_len: i32 = undefined;
            var buf: [100]u8 = undefined;
            gl.glGetProgramInfoLog(prog_id, buf.len, &res_len, &buf);
            log.warn("program log: {s}", .{buf});
            gl.glDeleteProgram(prog_id);
            return error.Failed;
        }

        // Cleanup.
        gl.glDetachShader(prog_id, vert_id);
        gl.glDeleteShader(vert_id);
        gl.glDetachShader(prog_id, frag_id);
        gl.glDeleteShader(frag_id);

        var ids: [1]gl.GLuint = undefined;
        gl.glGenVertexArrays(1, &ids);

        return Shader{
            .vao_id = ids[0],
            .vert_id = vert_id,
            .frag_id = frag_id,
            .prog_id = prog_id,
        };
    }

    pub fn deinit(self: *Self) void {
        gl.glDeleteVertexArrays(1, &self.vao_id);
        gl.glDeleteProgram(self.prog_id);
        gl.glDeleteShader(self.frag_id);
        gl.glDeleteShader(self.vert_id);
    }
};