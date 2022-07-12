const std = @import("std");
const sdl = @import("sdl");
const builtin = @import("builtin");
const stdx = @import("stdx");
const ptrCastTo = stdx.mem.ptrCastTo;

const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", ""); // Includes glGenVertexArrays
    @cInclude("GL/gl.h");
});

const IsWasm = builtin.target.isWasm();

/// WebGL2 bindings.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext
/// https://developer.mozilla.org/en-US/docs/Web/API/WebGL2RenderingContext
extern "graphics" fn jsGlCreateTexture() u32;
extern "graphics" fn jsGlEnable(cap: u32) void;
extern "graphics" fn jsGlDisable(cap: u32) void;
extern "graphics" fn jsGlFrontFace(mode: u32) void;
extern "graphics" fn jsGlBindTexture(target: u32, texture: u32) void;
extern "graphics" fn jsGlClearColor(r: f32, g: f32, b: f32, a: f32) void;
extern "graphics" fn jsGlGetParameterInt(tag: u32) i32;
extern "graphics" fn jsGlGetFrameBufferBinding() u32;
extern "graphics" fn jsGlCreateFramebuffer() u32;
extern "graphics" fn jsGlBindFramebuffer(target: u32, framebuffer: u32) void;
extern "graphics" fn jsGlBindRenderbuffer(target: u32, renderbuffer: u32) void;
extern "graphics" fn jsGlRenderbufferStorageMultisample(target: u32, samples: i32, internalformat: u32, width: i32, height: i32) void;
extern "graphics" fn jsGlBindVertexArray(array: u32) void;
extern "graphics" fn jsGlBindBuffer(target: u32, buffer: u32) void;
extern "graphics" fn jsGlEnableVertexAttribArray(index: u32) void;
extern "graphics" fn jsGlCreateShader(@"type": u32) u32;
extern "graphics" fn jsGlShaderSource(shader: u32, src_ptr: *const u8, src_len: usize) void;
extern "graphics" fn jsGlCompileShader(shader: u32) void;
extern "graphics" fn jsGlGetShaderParameterInt(shader: u32, pname: u32) i32;
extern "graphics" fn jsGlGetShaderInfoLog(shader: u32, buf_size: u32, log_ptr: *u8) u32;
extern "graphics" fn jsGlDeleteShader(shader: u32) void;
extern "graphics" fn jsGlCreateProgram() u32;
extern "graphics" fn jsGlAttachShader(program: u32, shader: u32) void;
extern "graphics" fn jsGlDetachShader(program: u32, shader: u32) void;
extern "graphics" fn jsGlLinkProgram(program: u32) void;
extern "graphics" fn jsGlGetProgramParameterInt(program: u32, pname: u32) i32;
extern "graphics" fn jsGlGetProgramInfoLog(program: u32, buf_size: u32, log_ptr: *u8) u32;
extern "graphics" fn jsGlDeleteProgram(program: u32) void;
extern "graphics" fn jsGlCreateVertexArray() u32;
extern "graphics" fn jsGlTexParameteri(target: u32, pname: u32, param: i32) void;
extern "graphics" fn jsGlTexImage2D(target: u32, level: i32, internal_format: i32, width: i32, height: i32, border: i32, format: u32, @"type": u32, pixels: ?*const u8) void;
extern "graphics" fn jsGlTexSubImage2D(target: u32, level: i32, xoffset: i32, yoffset: i32, width: i32, height: i32, format: u32, @"type": u32, pixels: ?*const u8) void;
extern "graphics" fn jsGlCreateBuffer() u32;
extern "graphics" fn jsGlVertexAttribPointer(index: u32, size: i32, @"type": u32, normalized: u8, stride: i32, pointer: ?*const anyopaque) void;
extern "graphics" fn jsGlActiveTexture(texture: u32) void;
extern "graphics" fn jsGlDeleteTexture(texture: u32) void;
extern "graphics" fn jsGlUseProgram(program: u32) void;
extern "graphics" fn jsGlUniformMatrix4fv(location: i32, transpose: u8, value_ptr: *const f32) void;
extern "graphics" fn jsGlUniform1i(location: i32, val: i32) void;
extern "graphics" fn jsGlUniform2fv(location: i32, value_ptr: *const f32) void;
extern "graphics" fn jsGlUniform4fv(location: i32, value_ptr: *const f32) void;
extern "graphics" fn jsGlBufferData(target: u32, data_ptr: ?*const u8, data_size: u32, usage: u32) void;
extern "graphics" fn jsGlDrawElements(mode: u32, num_indices: u32, index_type: u32, index_offset: u32) void;
extern "graphics" fn jsGlCreateRenderbuffer() u32;
extern "graphics" fn jsGlFramebufferRenderbuffer(target: u32, attachment: u32, renderbuffertarget: u32, renderbuffer: u32) void;
extern "graphics" fn jsGlFramebufferTexture2D(target: u32, attachment: u32, textarget: u32, texture: u32, level: i32) void;
extern "graphics" fn jsGlViewport(x: i32, y: i32, width: i32, height: i32) void;
extern "graphics" fn jsGlClear(mask: u32) void;
extern "graphics" fn jsGlBlendFunc(sfactor: u32, dfactor: u32) void;
extern "graphics" fn jsGlBlitFramebuffer(srcX0: i32, srcY0: i32, srcX1: i32, srcY1: i32, dstX0: i32, dstY0: i32, dstX1: i32, dstY1: i32, mask: u32, filter: u32) void;
extern "graphics" fn jsGlBlendEquation(mode: u32) void;
extern "graphics" fn jsGlScissor(x: i32, y: i32, width: i32, height: i32) void;
extern "graphics" fn jsGlGetUniformLocation(program: u32, name_ptr: *const u8, name_len: u32) u32;
extern "graphics" fn jsGlCheckFramebufferStatus(target: u32) u32;
extern "graphics" fn jsGlDeleteVertexArray(vao: u32) void;
extern "graphics" fn jsGlDeleteBuffer(buffer: u32) void;

const IsWindows = builtin.os.tag == .windows;

pub usingnamespace c;

pub inline fn clear(mask: c.GLbitfield) void {
    if (IsWasm) {
        jsGlClear(mask);
    } else {
        c.glClear(mask);
    }
}

pub inline fn frontFace(mode: c.GLenum) void {
    if (IsWasm) {
        jsGlFrontFace(mode);
    } else {
        c.glFrontFace(mode);
    }
}

pub inline fn getUniformLocation(program: c.GLuint, name: [:0]const u8) c.GLint {
    if (IsWasm) {
        const len = std.mem.indexOfSentinel(u8, 0, name);
        return @intCast(i32, jsGlGetUniformLocation(program, &name[0], len));
    } else if (IsWindows) {
        return winGetUniformLocation(program, name);
    } else {
        return c.glGetUniformLocation(program, name);
    }
}

pub inline fn genTextures(n: c.GLsizei, textures: [*c]c.GLuint) void {
    if (IsWasm) {
        if (n == 1) {
            textures[0] = jsGlCreateTexture();
        } else {
            stdx.unsupported();
        }
    } else {
        c.glGenTextures(n, textures);
    }
}

pub inline fn deleteTextures(n: c.GLsizei, textures: [*c]const c.GLuint) void {
    if (IsWasm) {
        if (n == 1) {
            jsGlDeleteTexture(textures[0]);
        } else {
            stdx.unsupported();
        }
    } else {
        c.glDeleteTextures(n, textures);
    }
}

pub inline fn texParameteri(target: c.GLenum, pname: c.GLenum, param: c.GLint) void {
    if (IsWasm) {
        // webgl2 supported targets:
        // GL_TEXTURE_2D
        // GL_TEXTURE_CUBE_MAP
        // GL_TEXTURE_3D
        // GL_TEXTURE_2D_ARRAY
        jsGlTexParameteri(target, pname, param);
    } else {
        c.glTexParameteri(target, pname, param);
    }
}

pub inline fn enable(cap: c.GLenum) void {
    if (IsWasm) {
        // webgl2 supports:
        // GL_BLEND
        // GL_DEPTH_TEST
        // GL_DITHER
        // GL_POLYGON_OFFSET_FILL
        // GL_SAMPLE_ALPHA_TO_COVERAGE
        // GL_SAMPLE_COVERAGE
        // GL_SCISSOR_TEST
        // GL_STENCIL_TEST
        jsGlEnable(cap);
    } else {
        c.glEnable(cap);
    }
}

pub inline fn disable(cap: c.GLenum) void {
    if (IsWasm) {
        jsGlDisable(cap);
    } else {
        c.glDisable(cap);
    }
}

pub inline fn bindTexture(target: c.GLenum, texture: c.GLuint) void {
    if (IsWasm) {
        // webgl2 supports:
        // GL_TEXTURE_2D
        // GL_TEXTURE_CUBE_MAP
        // GL_TEXTURE_3D
        // GL_TEXTURE_2D_ARRAY
        jsGlBindTexture(target, texture);
    } else {
        c.glBindTexture(target, texture);
    }
}

pub inline fn clearColor(red: c.GLclampf, green: c.GLclampf, blue: c.GLclampf, alpha: c.GLclampf) void {
    if (IsWasm) {
        jsGlClearColor(red, green, blue, alpha);
    } else {
        c.glClearColor(red, green, blue, alpha);
    }
}

pub inline fn getIntegerv(pname: c.GLenum, params: [*c]c.GLint) void {
    if (IsWasm) {
        switch (pname) {
            c.GL_MAJOR_VERSION => {
                params[0] = 3;
            },
            c.GL_MINOR_VERSION => {
                params[0] = 0;
            },
            c.GL_FRAMEBUFFER_BINDING => {
                params[0] = @intCast(i32, jsGlGetFrameBufferBinding());
            },
            else => {
                params[0] = jsGlGetParameterInt(pname);
            },
        }
    } else {
        c.glGetIntegerv(pname, params);
    }
}

pub inline fn renderbufferStorageMultisample(target: c.GLenum, samples: c.GLsizei, internalformat: c.GLenum, width: c.GLsizei, height: c.GLsizei) void {
    if (IsWasm) {
        // webgl2 supported targets:
        // GL_RENDERBUFFER
        jsGlRenderbufferStorageMultisample(target, samples, internalformat, width, height);
    } else {
        c.glRenderbufferStorageMultisample(target, samples, internalformat, width, height);
    }
}

pub fn getMaxTotalTextures() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS, &res);
    return @intCast(usize, res);
}

pub fn getMaxFragmentTextures() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_MAX_TEXTURE_IMAGE_UNITS, &res);
    return @intCast(usize, res);
}

pub fn getMaxSamples() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_MAX_SAMPLES, &res);
    return @intCast(usize, res);
}

pub fn getNumSampleBuffers() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_SAMPLE_BUFFERS, &res);
    return @intCast(usize, res);
}

pub fn getNumSamples() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_SAMPLES, &res);
    return @intCast(usize, res);
}

pub fn getDrawFrameBufferBinding() usize {
    var res: c_int = 0;
    getIntegerv(c.GL_FRAMEBUFFER_BINDING, &res);
    return @intCast(usize, res);
}

pub fn checkFramebufferStatus(target: c.GLenum) c.GLenum {
    if (IsWasm) {
        return jsGlCheckFramebufferStatus(target);
    } else if (IsWindows) {
        return winCheckFramebufferStatus(target);
    } else {
        return c.glCheckFramebufferStatus(target);
    }
} 

pub inline fn drawArrays(mode: c.GLenum, first: c.GLint, count: usize) void {
    c.glDrawArrays(mode, first, @intCast(c_int, count));
}

pub inline fn drawElements(mode: c.GLenum, num_indices: usize, index_type: c.GLenum, index_offset: usize) void {
    if (IsWasm) {
        jsGlDrawElements(mode, num_indices, index_type, index_offset);
    } else {
        c.glDrawElements(mode, @intCast(c_int, num_indices), index_type, @intToPtr(?*const c.GLvoid, index_offset));
    }
}

pub inline fn useProgram(program: c.GLuint) void {
    if (IsWasm) {
        jsGlUseProgram(program);
    } else if (IsWindows) {
        winUseProgram(program);
    } else {
        c.glUseProgram(program);
    }
}

pub inline fn createShader(@"type": c.GLenum) c.GLuint {
    if (IsWasm) {
        // webgl2 supported types:
        // GL_VERTEX_SHADER
        // GL_FRAGMENT_SHADER
        return jsGlCreateShader(@"type");
    } else if (IsWindows) {
        return winCreateShader(@"type");
    } else {
        return c.glCreateShader(@"type");
    }
}

pub inline fn getShaderInfoLog(shader: c.GLuint, buf_size: c.GLsizei, length: [*c]c.GLsizei, info_log: [*c]c.GLchar) void {
    if (IsWasm) {
        length[0] = @intCast(i32, jsGlGetShaderInfoLog(shader, @intCast(u32, buf_size), info_log));
    } else if (IsWindows) {
        winGetShaderInfoLog(shader, buf_size, length, info_log);
    } else {
        c.glGetShaderInfoLog(shader, buf_size, length, info_log);
    }
}

pub inline fn createProgram() c.GLuint {
    if (IsWasm) {
        return jsGlCreateProgram();
    } else if (IsWindows) {
        return winCreateProgram();
    } else {
        return c.glCreateProgram();
    }
}

pub inline fn attachShader(program: c.GLuint, shader: c.GLuint) void {
    if (IsWasm) {
        jsGlAttachShader(program, shader);
    } else if (IsWindows) {
        winAttachShader(program, shader);
    } else {
        c.glAttachShader(program, shader);
    }
}

pub inline fn linkProgram(program: c.GLuint) void {
    if (IsWasm) {
        jsGlLinkProgram(program);
    } else if (IsWindows) {
        winLinkProgram(program);
    } else {
        c.glLinkProgram(program);
    }
}

pub inline fn getProgramiv(program: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void {
    if (IsWasm) {
        params[0] = jsGlGetProgramParameterInt(program, pname);
    } else if (IsWindows) {
        winGetProgramiv(program, pname, params);
    } else {
        c.glGetProgramiv(program, pname, params);
    }
}

pub inline fn getProgramInfoLog(program: c.GLuint, buf_size: c.GLsizei, length: [*c]c.GLsizei, info_log: [*c]c.GLchar) void {
    if (IsWasm) {
        length[0] = @intCast(i32, jsGlGetProgramInfoLog(program, @intCast(u32, buf_size), info_log));
    } else if (IsWindows) {
        winGetProgramInfoLog(program, buf_size, length, info_log);
    } else {
        c.glGetProgramInfoLog(program, buf_size, length, info_log);
    }
}

pub inline fn deleteProgram(program: c.GLuint) void {
    if (IsWasm) {
        jsGlDeleteProgram(program);
    } else if (IsWindows) {
        winDeleteProgram(program);
    } else {
        c.glDeleteProgram(program);
    }
}

pub inline fn deleteShader(shader: c.GLuint) void {
    if (IsWasm) {
        jsGlDeleteShader(shader);
    } else if (IsWindows) {
        winDeleteShader(shader);
    } else {
        c.glDeleteShader(shader);
    }
}

pub inline fn genVertexArrays(n: c.GLsizei, arrays: [*c]c.GLuint) void {
    if (IsWasm) {
        if (n == 1) {
            arrays[0] = jsGlCreateVertexArray();
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winGenVertexArrays(n, arrays);
    } else {
        c.glGenVertexArrays(n, arrays);
    }
}

pub inline fn shaderSource(shader: c.GLuint, count: c.GLsizei, string: [*c]const [*c]const c.GLchar, length: [*c]const c.GLint) void {
    if (IsWasm) {
        if (count == 1) {
            jsGlShaderSource(shader, @ptrCast(*const u8, string[0]), @intCast(usize, length[0]));
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winShaderSource(shader, count, string, length);
    } else {
        c.glShaderSource(shader, count, string, length);
    }
}

pub inline fn compileShader(shader: c.GLuint) void {
    if (IsWasm) {
        jsGlCompileShader(shader);
    } else if (IsWindows) {
        winCompileShader(shader);
    } else {
        c.glCompileShader(shader);
    }
}

pub inline fn getShaderiv(shader: c.GLuint, pname: c.GLenum, params: [*c]c.GLint) void {
    if (IsWasm) {
        params[0] = jsGlGetShaderParameterInt(shader, pname);
    } else if (IsWindows) {
        winGetShaderiv(shader, pname, params);
    } else {
        c.glGetShaderiv(shader, pname, params);
    }
}

pub inline fn scissor(x: c.GLint, y: c.GLint, width: c.GLsizei, height: c.GLsizei) void {
    if (IsWasm) {
        jsGlScissor(x, y, width, height);
    } else {
        c.glScissor(x, y, width, height);
    }
}

pub inline fn blendFunc(sfactor: c.GLenum, dfactor: c.GLenum) void {
    if (IsWasm) {
        jsGlBlendFunc(sfactor, dfactor);
    } else {
        c.glBlendFunc(sfactor, dfactor);
    }
}

pub inline fn blendEquation(mode: c.GLenum) void {
    if (IsWasm) {
        jsGlBlendEquation(mode);
    } else if (IsWindows) {
        winBlendEquation(mode);
    } else {
        c.glBlendEquation(mode);
    }
}

pub inline fn bindVertexArray(array: c.GLuint) void {
    if (IsWasm) {
        jsGlBindVertexArray(array);
    } else if (IsWindows) {
        winBindVertexArray(array);
    } else {
        sdl.glBindVertexArray(array);
    }
}

pub inline fn bindBuffer(target: c.GLenum, buffer: c.GLuint) void {
    if (IsWasm) {
        // webgl2 supported targets:
        // GL_ARRAY_BUFFER
        // GL_ELEMENT_ARRAY_BUFFER
        // GL_COPY_READ_BUFFER
        // GL_COPY_WRITE_BUFFER
        // GL_TRANSFORM_FEEDBACK_BUFFER
        // GL_UNIFORM_BUFFER
        // GL_PIXEL_PACK_BUFFER
        // GL_PIXEL_UNPACK_BUFFER
        jsGlBindBuffer(target, buffer);
    } else if (IsWindows) {
        winBindBuffer(target, buffer);
    } else {
        sdl.glBindBuffer(target, buffer);
    }
}

pub inline fn bufferData(target: c.GLenum, size: c.GLsizeiptr, data: ?*const anyopaque, usage: c.GLenum) void {
    if (IsWasm) {
        jsGlBufferData(target, @ptrCast(?*const u8, data), @intCast(u32, size), usage);
    } else if (IsWindows) {
        winBufferData(target, size, data, usage);
    } else {
        sdl.glBufferData(target, size, data, usage);
    }
}

pub inline fn polygonMode(face: c.GLenum, mode: c.GLenum) void {
    if (IsWasm) {
        @compileError("unsupported");
    } else {
        sdl.glPolygonMode(face, mode);
    }
}

pub inline fn enableVertexAttribArray(index: c.GLuint) void {
    if (IsWasm) {
        jsGlEnableVertexAttribArray(index);
    } else if (IsWindows) {
        winEnableVertexAttribArray(index);
    } else {
        sdl.glEnableVertexAttribArray(index);
    }
}

pub inline fn activeTexture(texture: c.GLenum) void {
    if (IsWasm) {
        jsGlActiveTexture(texture);
    } else if (IsWindows) {
        winActiveTexture(texture);
    } else {
        sdl.glActiveTexture(texture);
    }
}

pub inline fn detachShader(program: c.GLuint, shader: c.GLuint) void {
    if (IsWasm) {
        jsGlDetachShader(program, shader);
    } else if (IsWindows) {
        winDetachShader(program, shader);
    } else {
        sdl.glDetachShader(program, shader);
    }
}

pub inline fn genRenderbuffers(n: c.GLsizei, renderbuffers: [*c]c.GLuint) void {
    if (IsWasm) {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            renderbuffers[i] = jsGlCreateRenderbuffer();
        }
    } else {
        sdl.glGenRenderbuffers(n, renderbuffers);
    }
}

pub inline fn viewport(x: c.GLint, y: c.GLint, width: c.GLsizei, height: c.GLsizei) void {
    if (IsWasm) {
        jsGlViewport(x, y, width, height);
    } else {
        c.glViewport(x, y, width, height);
    }
}

pub inline fn genFramebuffers(n: c.GLsizei, framebuffers: [*c]c.GLuint) void {
    if (IsWasm) {
        if (n == 1) {
            framebuffers[0] = jsGlCreateFramebuffer();
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winGenFramebuffers(n, framebuffers);
    } else {
        sdl.glGenFramebuffers(n, framebuffers);
    }
}

pub inline fn bindFramebuffer(target: c.GLenum, framebuffer: c.GLuint) void {
    if (IsWasm) {
        // webgl2 supports targets:
        // GL_FRAMEBUFFER
        // GL_DRAW_FRAMEBUFFER
        // GL_READ_FRAMEBUFFER
        jsGlBindFramebuffer(target, framebuffer);
    } else if (IsWindows) {
        winBindFramebuffer(target, framebuffer);
    } else {
        sdl.glBindFramebuffer(target, framebuffer);
    }
}

pub inline fn bindRenderbuffer(target: c.GLenum, renderbuffer: c.GLuint) void {
    if (IsWasm) {
        // webgl2 supports targets:
        // GL_RENDERBUFFER
        jsGlBindRenderbuffer(target, renderbuffer);
    } else {
        c.glBindRenderbuffer(target, renderbuffer);
    }
}

pub inline fn texSubImage2D(target: c.GLenum, level: c.GLint, xoffset: c.GLint, yoffset: c.GLint, width: c.GLsizei, height: c.GLsizei, format: c.GLenum, @"type": c.GLenum, pixels: ?*const c.GLvoid) void {
    if (IsWasm) {
        jsGlTexSubImage2D(target, level, xoffset, yoffset, width, height, format, @"type", @ptrCast(?*const u8, pixels));
    } else {
        c.glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, @"type", pixels);
    }
}

pub inline fn texImage2D(target: c.GLenum, level: c.GLint, internal_format: c.GLint, width: c.GLsizei, height: c.GLsizei, border: c.GLint, format: c.GLenum, @"type": c.GLenum, pixels: ?*const c.GLvoid) void {
    if (IsWasm) {
        jsGlTexImage2D(target, level, internal_format, width, height, border, format, @"type", @ptrCast(?*const u8, pixels));
    } else {
        c.glTexImage2D(target, level, internal_format, width, height, border, format, @"type", pixels);
    }
}

pub fn texImage2DMultisample(target: c.GLenum, samples: c.GLsizei, internalformat: c.GLenum, width: c.GLsizei, height: c.GLsizei, fixedsamplelocations: c.GLboolean) void {
    if (builtin.os.tag == .windows) {
        winTexImage2DMultisample(target, samples, internalformat, width, height, fixedsamplelocations);
    } else {
        sdl.glTexImage2DMultisample(target, samples, internalformat, width, height, fixedsamplelocations);
    }
}

pub inline fn framebufferRenderbuffer(target: c.GLenum, attachment: c.GLenum, renderbuffertarget: c.GLenum, renderbuffer: c.GLuint) void {
    if (IsWasm) {
        jsGlFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer);
    } else {
        c.glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer);
    }
}

pub inline fn framebufferTexture2D(target: c.GLenum, attachment: c.GLenum, textarget: c.GLenum, texture: c.GLuint, level: c.GLint) void {
    if (IsWasm) {
        jsGlFramebufferTexture2D(target, attachment, textarget, texture, level);
    } else if (IsWindows) {
        winFramebufferTexture2D(target, attachment, textarget, texture, level);
    } else {
        c.glFramebufferTexture2D(target, attachment, textarget, texture, level);
    }
}

pub inline fn genBuffers(n: c.GLsizei, buffers: [*c]c.GLuint) void {
    if (IsWasm) {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            buffers[i] = jsGlCreateBuffer();
        }
    } else if (IsWindows) {
        winGenBuffers(n, buffers);
    } else {
        sdl.glGenBuffers(n, buffers);
    }
}

pub inline fn vertexAttribPointer(index: c.GLuint, size: c.GLint, @"type": c.GLenum, normalized: c.GLboolean, stride: c.GLsizei, pointer: ?*const anyopaque) void {
    if (IsWasm) {
        jsGlVertexAttribPointer(index, size, @"type", normalized, stride, pointer);
    } else if (IsWindows) {
        winVertexAttribPointer(index, size, @"type", normalized, stride, pointer);
    } else {
        sdl.glVertexAttribPointer(index, size, @"type", normalized, stride, pointer);
    }
}

pub inline fn deleteVertexArrays(n: c.GLsizei, arrays: [*c]const c.GLuint) void {
    if (IsWasm) {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            jsGlDeleteVertexArray(arrays[i]);
        }
    } else if (IsWindows) {
        winDeleteVertexArrays(n, arrays);
    } else {
        c.glDeleteVertexArrays(n, arrays);
    }
}

pub inline fn deleteBuffers(n: c.GLsizei, buffers: [*c]const c.GLuint) void {
    if (IsWasm) {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            jsGlDeleteBuffer(buffers[i]);
        }
    } else if (IsWindows) {
        winDeleteBuffers(n, buffers);
    } else {
        c.glDeleteBuffers(n, buffers);
    }
}

pub inline fn blitFramebuffer(srcX0: c.GLint, srcY0: c.GLint, srcX1: c.GLint, srcY1: c.GLint, dstX0: c.GLint, dstY0: c.GLint, dstX1: c.GLint, dstY1: c.GLint, mask: c.GLbitfield, filter: c.GLenum) void {
    if (IsWasm) {
        jsGlBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
    } else if (IsWindows) {
        winBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
    } else {
        c.glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
    }
}

pub inline fn uniformMatrix4fv(location: c.GLint, count: c.GLsizei, transpose: c.GLboolean, value: [*c]const c.GLfloat) void {
    if (IsWasm) {
        if (count == 1) {
            jsGlUniformMatrix4fv(location, transpose, value);
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winUniformMatrix4fv(location, count, transpose, value);
    } else {
        sdl.glUniformMatrix4fv(location, count, transpose, value);
    }
}

pub inline fn uniform2fv(location: c.GLint, count: c.GLsizei, value: [*c]const c.GLfloat) void {
    if (IsWasm) {
        if (count == 1) {
            jsGlUniform2fv(location, value);
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winUniform2fv(location, count, value);
    } else {
        c.glUniform2fv(location, count, value);
    }
}

pub inline fn uniform4fv(location: c.GLint, count: c.GLsizei, value: [*c]const c.GLfloat) void {
    if (IsWasm) {
        if (count == 1) {
            jsGlUniform4fv(location, value);
        } else {
            stdx.unsupported();
        }
    } else if (IsWindows) {
        winUniform4fv(location, count, value);
    } else {
        c.glUniform4fv(location, count, value);
    }
}

pub inline fn uniform1i(location: c.GLint, v0: c.GLint) void {
    if (IsWasm) {
        jsGlUniform1i(location, v0);
    } else if (IsWindows) {
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
var winBufferData: fn (target: c.GLenum, size: c.GLsizeiptr, data: ?*const anyopaque, usage: c.GLenum) void = undefined;
var winUniformMatrix4fv: fn (location: c.GLint, count: c.GLsizei, transpose: c.GLboolean, value: [*c]const c.GLfloat) void = undefined;
var winUniform2fv: fn (location: c.GLint, count: c.GLsizei, value: [*c]const c.GLfloat) void = undefined;
var winUniform4fv: fn (location: c.GLint, count: c.GLsizei, value: [*c]const c.GLfloat) void = undefined;
var winGetUniformLocation: fn (program: c.GLuint, name: [*c]const c.GLchar) c.GLint = undefined;
var winUniform1i: fn (location: c.GLint, v0: c.GLint) void = undefined;
var winGenBuffers: fn (n: c.GLsizei, buffers: [*c]c.GLuint) void = undefined;
var winDeleteBuffers: fn (n: c.GLsizei, buffers: [*c]const c.GLuint) void = undefined;
var winBlendEquation: fn (mode: c.GLenum) void = undefined;
var winBlitFramebuffer: fn (srcX0: c.GLint, srcY0: c.GLint, srcX1: c.GLint, srcY1: c.GLint, dstX0: c.GLint, dstY0: c.GLint, dstX1: c.GLint, dstY1: c.GLint, mask: c.GLbitfield, filter: c.GLenum) void = undefined;
var winDeleteVertexArrays: fn (n: c.GLsizei, arrays: [*c]const c.GLuint) void = undefined;
var winVertexAttribPointer: fn (index: c.GLuint, size: c.GLint, @"type": c.GLenum, normalized: c.GLboolean, stride: c.GLsizei, pointer: ?*const anyopaque) void = undefined;
var winBindVertexArray: fn (array: c.GLuint) void = undefined;
var winDetachShader: fn (program: c.GLuint, shader: c.GLuint) void = undefined;
var winFramebufferTexture2D: fn (target: c.GLenum, attachment: c.GLenum, textarget: c.GLenum, texture: c.GLuint, level: c.GLint) void = undefined;
var winTexImage2DMultisample: fn (target: c.GLenum, samples: c.GLsizei, internalformat: c.GLenum, width: c.GLsizei, height: c.GLsizei, fixedsamplelocations: c.GLboolean) void = undefined;
var winGenFramebuffers: fn (n: c.GLsizei, framebuffers: [*c]c.GLuint) void = undefined;
var winEnableVertexAttribArray: fn (index: c.GLuint) void = undefined;
var winActiveTexture: fn (texture: c.GLenum) void = undefined;
var winBindFramebuffer: fn (target: c.GLenum, framebuffer: c.GLuint) void = undefined;
var winCheckFramebufferStatus: fn (target: c.GLenum) c.GLenum = undefined;

var initedWinGL = false;

// opengl32.dll on Windows only supports 1.1 functions but it knows how to retrieve newer functions
// from vendor implementations of OpenGL. This should be called once to load the function pointers we need.
// If this becomes hard to maintain we might autogen this like: https://github.com/skaslev/gl3w
pub fn initWinGL_Functions() void {
    if (initedWinGL) { 
        return;
    }
    loadGlFunc(&winUseProgram, "glUseProgram");
    loadGlFunc(&winCreateShader, "glCreateShader");
    loadGlFunc(&winGetShaderInfoLog, "glGetShaderInfoLog");
    loadGlFunc(&winDeleteShader, "glDeleteShader");
    loadGlFunc(&winCreateProgram, "glCreateProgram");
    loadGlFunc(&winAttachShader, "glAttachShader");
    loadGlFunc(&winLinkProgram, "glLinkProgram");
    loadGlFunc(&winGetProgramiv, "glGetProgramiv");
    loadGlFunc(&winGetProgramInfoLog, "glGetProgramInfoLog");
    loadGlFunc(&winDeleteProgram, "glDeleteProgram");
    loadGlFunc(&winGenVertexArrays, "glGenVertexArrays");
    loadGlFunc(&winShaderSource, "glShaderSource");
    loadGlFunc(&winCompileShader, "glCompileShader");
    loadGlFunc(&winGetShaderiv, "glGetShaderiv");
    loadGlFunc(&winBindVertexArray, "glBindVertexArray");
    loadGlFunc(&winBindBuffer, "glBindBuffer");
    loadGlFunc(&winEnableVertexAttribArray, "glEnableVertexAttribArray");
    loadGlFunc(&winActiveTexture, "glActiveTexture");
    loadGlFunc(&winDetachShader, "glDetachShader");
    loadGlFunc(&winGenFramebuffers, "glGenFramebuffers");
    loadGlFunc(&winBindFramebuffer, "glBindFramebuffer");
    loadGlFunc(&winTexImage2DMultisample, "glTexImage2DMultisample");
    loadGlFunc(&winFramebufferTexture2D, "glFramebufferTexture2D");
    loadGlFunc(&winVertexAttribPointer, "glVertexAttribPointer");
    loadGlFunc(&winDeleteVertexArrays, "glDeleteVertexArrays");
    loadGlFunc(&winGenBuffers, "glGenBuffers");
    loadGlFunc(&winDeleteBuffers, "glDeleteBuffers");
    loadGlFunc(&winBlitFramebuffer, "glBlitFramebuffer");
    loadGlFunc(&winBlendEquation, "glBlendEquation");
    loadGlFunc(&winUniformMatrix4fv, "glUniformMatrix4fv");
    loadGlFunc(&winUniform2fv, "glUniform2fv");
    loadGlFunc(&winUniform4fv, "glUniform4fv");
    loadGlFunc(&winGetUniformLocation, "glGetUniformLocation");
    loadGlFunc(&winUniform1i, "glUniform1i");
    loadGlFunc(&winBufferData, "glBufferData");
    loadGlFunc(&winCheckFramebufferStatus, "glCheckFramebufferStatus");
}

fn loadGlFunc(ptr_to_local: anytype, name: [:0]const u8) void {
    if (sdl.SDL_GL_GetProcAddress(name)) |ptr| {
        ptrCastTo(ptr_to_local, ptr);
    } else {
        std.debug.panic("Failed to load: {s}", .{name});
    }
}
