const sdl = @import("sdl");
const builtin = @import("builtin");
const stdx = @import("stdx");
const ptrCastTo = stdx.mem.ptrCastTo;

const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", ""); // Includes glGenVertexArrays
    @cInclude("GL/gl.h");
});

pub usingnamespace c;

pub fn getMaxTotalTextures() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS, &res);
    return @intCast(usize, res);
}

pub fn getMaxFragmentTextures() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_MAX_TEXTURE_IMAGE_UNITS, &res);
    return @intCast(usize, res);
}

pub fn getMaxSamples() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_MAX_SAMPLES, &res);
    return @intCast(usize, res);
}

pub fn getNumSampleBuffers() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_SAMPLE_BUFFERS, &res);
    return @intCast(usize, res);
}

pub fn getNumSamples() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_SAMPLES, &res);
    return @intCast(usize, res);
}

pub fn getDrawFrameBufferBinding() usize {
    var res: c_int = 0;
    c.glGetIntegerv(c.GL_FRAMEBUFFER_BINDING, &res);
    return @intCast(usize, res);
}

pub fn drawElements(mode: c.GLenum, num_indices: usize, index_type: c.GLenum, index_offset: usize) void {
    c.glDrawElements(mode, @intCast(c_int, num_indices), index_type, @intToPtr(?*const c.GLvoid, index_offset));
}

pub fn useProgram(program: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winUseProgram(program);
    } else {
        c.glUseProgram(program);
    }
}

pub fn createShader(@"type": c.GLenum) c.GLuint {
    if (builtin.os.tag == .windows) {
        return winCreateShader(@"type");
    } else {
        return c.glCreateShader(@"type");
    }
}

pub fn getShaderInfoLog(shader: c.GLuint, bufSize: c.GLsizei, length: [*c]c.GLsizei, infoLog: [*c]c.GLchar) void {
    if (builtin.os.tag == .windows) {
        winGetShaderInfoLog(shader, bufSize, length, infoLog);
    } else {
        c.glGetShaderInfoLog(shader, bufSize, length, infoLog);
    }
}

pub fn createProgram() c.GLuint {
    if (builtin.os.tag == .windows) {
        return winCreateProgram();
    } else {
        return c.glCreateProgram();
    }
}

pub fn attachShader(program: c.GLuint, shader: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winAttachShader(program, shader);
    } else {
        c.glAttachShader(program, shader);
    }
}

pub fn linkProgram(program: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winLinkProgram(program);
    } else {
        c.glLinkProgram(program);
    }
}

pub fn getProgramiv(program: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void {
    if (builtin.os.tag == .windows) {
        winGetProgramiv(program, pname, params);
    } else {
        c.glGetProgramiv(program, pname, params);
    }
}

pub fn getProgramInfoLog(program: c.GLuint, bufSize: c.GLsizei, length: [*c]c.GLsizei, infoLog: [*c]c.GLchar) void {
    if (builtin.os.tag == .windows) {
        winGetProgramInfoLog(program, bufSize, length, infoLog);
    } else {
        c.glGetProgramInfoLog(program, bufSize, length, infoLog);
    }
}

pub fn deleteProgram(program: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winDeleteProgram(program);
    } else {
        c.glDeleteProgram(program);
    }
}

pub fn deleteShader(shader: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winDeleteShader(shader);
    } else {
        c.glDeleteShader(shader);
    }
}

pub fn genVertexArrays(n: c.GLsizei, arrays: [*c]c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winGenVertexArrays(n, arrays);
    } else {
        c.glGenVertexArrays(n, arrays);
    }
}

pub fn shaderSource(shader: c.GLuint, count: c.GLsizei, string: [*c]const [*c]const c.GLchar, length: [*c]const c.GLint) void {
    if (builtin.os.tag == .windows) {
        winShaderSource(shader, count, string, length);
    } else {
        c.glShaderSource(shader, count, string, length);
    }
}

pub fn compileShader(shader: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winCompileShader(shader);
    } else {
        c.glCompileShader(shader);
    }
}

pub fn getShaderiv(shader: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void {
    if (builtin.os.tag == .windows) {
        winGetShaderiv(shader, pname, params);
    } else {
        c.glGetShaderiv(shader, pname, params);
    }
}

pub fn blendFunc(sfactor: c.GLenum, dfactor: c.GLenum) void {
    sdl.glBlendFunc(sfactor, dfactor);
}

pub fn blendEquation(mode: c.GLenum) void {
    if (builtin.os.tag == .windows) {
        winBlendEquation(mode);
    } else {
        sdl.glBlendEquation(mode);
    }
}

pub fn bindVertexArray(array: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winBindVertexArray(array);
    } else {
        sdl.glBindVertexArray(array);
    }
}

pub fn bindBuffer(target: c.GLenum, buffer: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winBindBuffer(target, buffer);
    } else {
        sdl.glBindBuffer(target, buffer);
    }
}

pub fn bufferData(target: c.GLenum, size: c.GLsizeiptr, data: ?*const c_void, usage: c.GLenum) void {
    if (builtin.os.tag == .windows) {
        winBufferData(target, size, data, usage);
    } else {
        sdl.glBufferData(target, size, data, usage);
    }
}

pub fn enableVertexAttribArray(index: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winEnableVertexAttribArray(index);
    } else {
        sdl.glEnableVertexAttribArray(index);
    }
}

pub fn activeTexture(texture: c.GLenum) void {
    if (builtin.os.tag == .windows) {
        winActiveTexture(texture);
    } else {
        sdl.glActiveTexture(texture);
    }
}

pub fn detachShader(program: c.GLuint, shader: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winDetachShader(program, shader);
    } else {
        sdl.glDetachShader(program, shader);
    }
}

pub fn genFramebuffers(n: c.GLsizei, framebuffers: [*c]c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winGenFramebuffers(n, framebuffers);
    } else {
        sdl.glGenFramebuffers(n, framebuffers);
    }
}

pub fn bindFramebuffer(target: c.GLenum, framebuffer: c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winBindFramebuffer(target, framebuffer);
    } else {
        sdl.glBindFramebuffer(target, framebuffer);
    }
}

pub fn texImage2DMultisample(target: c.GLenum, samples: c.GLsizei, internalformat: c.GLenum, width: c.GLsizei, height: c.GLsizei, fixedsamplelocations: c.GLboolean) void {
    if (builtin.os.tag == .windows) {
        winTexImage2DMultisample(target, samples, internalformat, width, height, fixedsamplelocations);
    } else {
        sdl.glTexImage2DMultisample(target, samples, internalformat, width, height, fixedsamplelocations);
    }
}

pub fn framebufferTexture2D(target: c.GLenum, attachment: c.GLenum, textarget: c.GLenum, texture: c.GLuint, level: c.GLint) void {
    if (builtin.os.tag == .windows) {
        winFramebufferTexture2D(target, attachment, textarget, texture, level);
    } else {
        sdl.glFramebufferTexture2D(target, attachment, textarget, texture, level);
    }
}

pub fn genBuffers(n: c.GLsizei, buffers: [*c]c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winGenBuffers(n, buffers);
    } else {
        sdl.glGenBuffers(n, buffers);
    }
}

pub fn vertexAttribPointer(index: c.GLuint, size: c.GLint, @"type": c.GLenum, normalized: c.GLboolean, stride: c.GLsizei, pointer: ?*const c_void) void {
    if (builtin.os.tag == .windows) {
        winVertexAttribPointer(index, size, @"type", normalized, stride, pointer);
    } else {
        sdl.glVertexAttribPointer(index, size, @"type", normalized, stride, pointer);
    }
}

pub fn deleteVertexArrays(n: c.GLsizei, arrays: [*c]const c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winDeleteVertexArrays(n, arrays);
    } else {
        sdl.glDeleteVertexArrays(n, arrays);
    }
}

pub fn deleteBuffers(n: c.GLsizei, buffers: [*c]const c.GLuint) void {
    if (builtin.os.tag == .windows) {
        winDeleteBuffers(n, buffers);
    } else {
        sdl.glDeleteBuffers(n, buffers);
    }
}

pub fn blitFramebuffer(srcX0: c.GLint, srcY0: c.GLint, srcX1: c.GLint, srcY1: c.GLint, dstX0: c.GLint, dstY0: c.GLint, dstX1: c.GLint, dstY1: c.GLint, mask: c.GLbitfield, filter: c.GLenum) void {
    if (builtin.os.tag == .windows) {
        winBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
    } else {
        sdl.glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
    }
}

pub fn uniformMatrix4fv(location: c.GLint, count: c.GLsizei, transpose: c.GLboolean, value: [*c]const c.GLfloat) void {
    if (builtin.os.tag == .windows) {
        winUniformMatrix4fv(location, count, transpose, value);
    } else {
        sdl.glUniformMatrix4fv(location, count, transpose, value);
    }
}

pub fn uniform1i(location: c.GLint, v0: c.GLint) void {
    if (builtin.os.tag == .windows) {
        winUniform1i(location, v0);
    } else {
        sdl.glUniform1i(location, v0);
    }
}

var winUseProgram: fn (program: c.GLuint) void = undefined;
var winCreateShader: fn (@"type": c.GLenum) c.GLuint = undefined;
var winGetShaderInfoLog: fn (shader: c.GLuint, bufSize: c.GLsizei, length: [*c]c.GLsizei, infoLog: [*c]c.GLchar) void = undefined;
var winDeleteShader: fn (shader: c.GLuint) void = undefined;
var winCreateProgram: fn () c.GLuint = undefined;
var winAttachShader: fn (program: c.GLuint, shader: c.GLuint) void = undefined;
var winLinkProgram: fn (program: c.GLuint) void = undefined;
var winGetProgramiv: fn (program: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void = undefined;
var winGetProgramInfoLog: fn (program: c.GLuint, bufSize: c.GLsizei, length: [*c]c.GLsizei, infoLog: [*c]c.GLchar) void = undefined;
var winDeleteProgram: fn (program: c.GLuint) void = undefined;
var winGenVertexArrays: fn (n: c.GLsizei, arrays: [*c]c.GLuint) void = undefined;
var winShaderSource: fn (shader: c.GLuint, count: c.GLsizei, string: [*c]const [*c]const c.GLchar, length: [*c]const c.GLint) void = undefined;
var winCompileShader: fn (shader: c.GLuint) void = undefined;
var winGetShaderiv: fn (shader: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void = undefined;
var winBindBuffer: fn (target: c.GLenum, buffer: c.GLuint) void = undefined;
var winBufferData: fn (target: c.GLenum, size: c.GLsizeiptr, data: ?*const c_void, usage: c.GLenum) void = undefined;
var winUniformMatrix4fv: fn (location: c.GLint, count: c.GLsizei, transpose: c.GLboolean, value: [*c]const c.GLfloat) void = undefined;
var winUniform1i: fn (location: c.GLint, v0: c.GLint) void = undefined;
var winGenBuffers: fn (n: c.GLsizei, buffers: [*c]c.GLuint) void = undefined;
var winDeleteBuffers: fn (n: c.GLsizei, buffers: [*c]const c.GLuint) void = undefined;
var winBlendEquation: fn (mode: c.GLenum) void = undefined;
var winBlitFramebuffer: fn (srcX0: c.GLint, srcY0: c.GLint, srcX1: c.GLint, srcY1: c.GLint, dstX0: c.GLint, dstY0: c.GLint, dstX1: c.GLint, dstY1: c.GLint, mask: c.GLbitfield, filter: c.GLenum) void = undefined;
var winDeleteVertexArrays: fn (n: c.GLsizei, arrays: [*c]const c.GLuint) void = undefined;
var winVertexAttribPointer: fn (index: c.GLuint, size: c.GLint, @"type": c.GLenum, normalized: c.GLboolean, stride: c.GLsizei, pointer: ?*const c_void) void = undefined;
var winBindVertexArray: fn (array: c.GLuint) void = undefined;
var winDetachShader: fn (program: c.GLuint, shader: c.GLuint) void = undefined;
var winFramebufferTexture2D: fn (target: c.GLenum, attachment: c.GLenum, textarget: c.GLenum, texture: c.GLuint, level: c.GLint) void = undefined;
var winTexImage2DMultisample: fn (target: c.GLenum, samples: c.GLsizei, internalformat: c.GLenum, width: c.GLsizei, height: c.GLsizei, fixedsamplelocations: c.GLboolean) void = undefined;
var winGenFramebuffers: fn (n: c.GLsizei, framebuffers: [*c]c.GLuint) void = undefined;
var winEnableVertexAttribArray: fn (index: c.GLuint) void = undefined;
var winActiveTexture: fn (texture: c.GLenum) void = undefined;
var winBindFramebuffer: fn (target: c.GLenum, framebuffer: c.GLuint) void = undefined;

// opengl32.dll on Windows only supports 1.1 functions but it knows how to retrieve newer functions
// from vendor implementations of OpenGL. This should be called once to load the function pointers we need.
// If this becomes hard to maintain we might autogen this like: https://github.com/skaslev/gl3w
pub fn initWinGL_Functions() void {
    ptrCastTo(&winUseProgram, sdl.SDL_GL_GetProcAddress("glUseProgram").?);
    ptrCastTo(&winCreateShader, sdl.SDL_GL_GetProcAddress("glCreateShader").?);
    ptrCastTo(&winGetShaderInfoLog, sdl.SDL_GL_GetProcAddress("glGetShaderInfoLog").?);
    ptrCastTo(&winDeleteShader, sdl.SDL_GL_GetProcAddress("glDeleteShader").?);
    ptrCastTo(&winCreateProgram, sdl.SDL_GL_GetProcAddress("glCreateProgram").?);
    ptrCastTo(&winAttachShader, sdl.SDL_GL_GetProcAddress("glAttachShader").?);
    ptrCastTo(&winLinkProgram, sdl.SDL_GL_GetProcAddress("glLinkProgram").?);
    ptrCastTo(&winGetProgramiv, sdl.SDL_GL_GetProcAddress("glGetProgramiv").?);
    ptrCastTo(&winGetProgramInfoLog, sdl.SDL_GL_GetProcAddress("glGetProgramInfoLog").?);
    ptrCastTo(&winDeleteProgram, sdl.SDL_GL_GetProcAddress("glDeleteProgram").?);
    ptrCastTo(&winGenVertexArrays, sdl.SDL_GL_GetProcAddress("glGenVertexArrays").?);
    ptrCastTo(&winShaderSource, sdl.SDL_GL_GetProcAddress("glShaderSource").?);
    ptrCastTo(&winCompileShader, sdl.SDL_GL_GetProcAddress("glCompileShader").?);
    ptrCastTo(&winGetShaderiv, sdl.SDL_GL_GetProcAddress("glGetShaderiv").?);
    ptrCastTo(&winBindVertexArray, sdl.SDL_GL_GetProcAddress("glBindVertexArray").?);
    ptrCastTo(&winBindBuffer, sdl.SDL_GL_GetProcAddress("glBindBuffer").?);
    ptrCastTo(&winEnableVertexAttribArray, sdl.SDL_GL_GetProcAddress("glEnableVertexAttribArray").?);
    ptrCastTo(&winActiveTexture, sdl.SDL_GL_GetProcAddress("glActiveTexture").?);
    ptrCastTo(&winDetachShader, sdl.SDL_GL_GetProcAddress("glDetachShader").?);
    ptrCastTo(&winGenFramebuffers, sdl.SDL_GL_GetProcAddress("glGenFramebuffers").?);
    ptrCastTo(&winBindFramebuffer, sdl.SDL_GL_GetProcAddress("glBindFramebuffer").?);
    ptrCastTo(&winTexImage2DMultisample, sdl.SDL_GL_GetProcAddress("glTexImage2DMultisample").?);
    ptrCastTo(&winFramebufferTexture2D, sdl.SDL_GL_GetProcAddress("glFramebufferTexture2D").?);
    ptrCastTo(&winVertexAttribPointer, sdl.SDL_GL_GetProcAddress("glVertexAttribPointer").?);
    ptrCastTo(&winDeleteVertexArrays, sdl.SDL_GL_GetProcAddress("glDeleteVertexArrays").?);
    ptrCastTo(&winGenBuffers, sdl.SDL_GL_GetProcAddress("glGenBuffers").?);
    ptrCastTo(&winDeleteBuffers, sdl.SDL_GL_GetProcAddress("glDeleteBuffers").?);
    ptrCastTo(&winBlitFramebuffer, sdl.SDL_GL_GetProcAddress("glBlitFramebuffer").?);
    ptrCastTo(&winBlendEquation, sdl.SDL_GL_GetProcAddress("glBlendEquation").?);
    ptrCastTo(&winUniformMatrix4fv ,sdl.SDL_GL_GetProcAddress("glUniformMatrix4fv").?);
    ptrCastTo(&winUniform1i, sdl.SDL_GL_GetProcAddress("glUniform1i").?);
    ptrCastTo(&winBufferData, sdl.SDL_GL_GetProcAddress("glBufferData").?);
}
