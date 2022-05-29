const std = @import("std");
const Backend = @import("build_options").GraphicsBackend;
const stdx = @import("stdx");
const platform = @import("platform");

const graphics = @import("graphics.zig");
const gl = graphics.gl;
const vk = graphics.vk;

pub const SwapChain = struct {
    impl: switch (Backend) {
        .OpenGL => gl.SwapChain,
        .Vulkan => vk.SwapChain,
        else => @compileError("unsupported"),
    },

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator, w: *platform.Window, g: *graphics.Graphics) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.init(&self.impl, w, g),
            .Vulkan => vk.SwapChain.init(&self.impl, alloc, w, g),
            else => stdx.panic("unsupported"),
        }
    }

    /// Setup for the frame before any user draw calls.
    pub inline fn beginFrame(self: Self, cam: graphics.Camera) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.beginFrame(self.impl, cam),
            .Vulkan => vk.SwapChain.beginFrame(self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    /// Post frame ops.
    pub inline fn endFrame(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.endFrame(self.impl),
            .Vulkan => vk.SwapChain.endFrame(self.impl),
            else => stdx.panic("unsupported"),
        }
    }
};