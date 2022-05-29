pub const SwapChain = @import("swapchain.zig").SwapChain;
pub const Shader = @import("shader.zig").Shader;
const shaders = @import("shaders.zig");
pub const TexShader = shaders.TexShader;
pub const GradientShader = shaders.GradientShader;

pub const Pipelines = struct {
    tex: TexShader,
    gradient: GradientShader,

    pub fn deinit(self: Pipelines) void {
        self.tex.deinit();
        self.gradient.deinit();
    }
};