const std = @import("std");
const stdx = @import("stdx");

const wasm = @import("backend/wasm/window.zig");
const gl = @import("backend/gl/window.zig");
const log = stdx.log.scoped(.window);
const Backend = @import("graphics.zig").Backend;

pub const Window = struct {
    const Self = @This();

    inner: switch (Backend) {
        .OpenGL => gl.Window,
        .WasmCanvas => wasm.Window,
        .Test => TestWindow,
    },

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        const inner = switch (Backend) {
            .OpenGL => try gl.Window.init(alloc, config),
            .WasmCanvas => try wasm.Window.init(config),
            .Test => TestWindow{ .width = config.width, .height = config.height },
        };
        return Self{
            .inner = inner,
        };
    }

    pub fn deinit(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.deinit(self.inner),
            .WasmCanvas => wasm.Window.deinit(&self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getWidth(self: Self) u32 {
        return self.inner.width;
    }

    pub fn getHeight(self: Self) u32 {
        return self.inner.height;
    }

    /// In the OpenGL SDL backend, swapBuffers will also block the thread to achieve the target refresh rate if vsync is on.
    pub fn swapBuffers(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.swapBuffers(self.inner),
            .WasmCanvas => {},
            .Test => {},
        }
    }
};

pub fn quit() void {
    switch (Backend) {
        .OpenGL => gl.quit(),
        .WasmCanvas => {},
        else => stdx.panic("unsupported"),
    }
}

pub const Config = struct {
    title: []const u8 = "My Window",
    width: u32 = 1024,
    height: u32 = 768,
    resizable: bool = false,
    high_dpi: bool = false,
    fullscreen: bool = false,
};

const TestWindow = struct {
    width: u32,
    height: u32,
};