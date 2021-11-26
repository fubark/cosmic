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