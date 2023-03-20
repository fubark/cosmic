const std = @import("std");
const Backend = @import("graphics_options").GraphicsBackend;
const stdx = @import("stdx");
const platform = @import("platform");

const graphics = @import("graphics.zig");
const gl = graphics.gl;
const vk = graphics.vk;

pub const SwapChain = struct {
    impl: switch (Backend) {
        .OpenGL => gl.SwapChain,
        .Vulkan => vk.SwapChain,
        else => void,
    },

    const Self = @This();

    pub fn init(self: *Self, _: std.mem.Allocator, win: *platform.Window) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.init(&self.impl, win),
            else => stdx.unsupported(),
        }
    }

    pub fn initVK(self: *Self, alloc: std.mem.Allocator, win: *platform.Window) void {
        vk.SwapChain.init(&self.impl, alloc, win);
    }

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        switch (Backend) {
            .OpenGL => {},
            .Vulkan => vk.SwapChain.deinit(self.impl, alloc),
            else => stdx.unsupported(),
        }
    }

    /// Acquire the next available framebuffer.
    pub inline fn beginFrame(self: *Self) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.beginFrame(self.impl),
            .Vulkan => vk.SwapChain.beginFrame(&self.impl),
            else => stdx.unsupported(),
        }
    }

    /// Copy buffer to window buffer.
    pub inline fn endFrame(self: *Self) void {
        switch (Backend) {
            .OpenGL => gl.SwapChain.endFrame(self.impl),
            .Vulkan => vk.SwapChain.endFrame(&self.impl),
            else => stdx.unsupported(),
        }
    }
};