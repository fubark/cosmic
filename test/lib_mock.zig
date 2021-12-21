const gl = @import("gl");
const GLint = gl.GLint;
const GLsizei = gl.GLsizei;
const GLclampf = gl.GLclampf;
const GLenum = gl.GLenum;

// Mocked out external deps.

export fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;
}

export fn glClearColor(red: GLclampf, green: GLclampf, blue: GLclampf, alpha: GLclampf) void {
    _ = red;
    _ = green;
    _ = blue;
    _ = alpha;
}

export fn glDisable(cap: GLenum) void {
    _ = cap;
}

export fn glEnable(cap: GLenum) void {
    _ = cap;
}

export fn glGetIntegerv(pname: GLenum, params: [*c]GLint) void {
    _ = pname;
    _ = params;
}

export fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) void {
    _ = sfactor;
    _ = dfactor;
}

export fn lyon_init() void {}

export fn lyon_deinit() void {}
