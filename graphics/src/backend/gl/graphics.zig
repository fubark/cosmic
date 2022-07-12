const gl = @import("gl");
const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
pub const SwapChain = @import("swapchain.zig").SwapChain;
pub const Shader = @import("shader.zig").Shader;
pub const shaders = @import("shaders.zig");

pub const Pipelines = struct {
    tex: shaders.TexShader,
    gradient: shaders.GradientShader,
    plane: shaders.PlaneShader,

    pub fn deinit(self: Pipelines) void {
        self.tex.deinit();
        self.gradient.deinit();
        self.plane.deinit();
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