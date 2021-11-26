const std = @import("std");
const stdx = @import("stdx");

const wasm = @import("backend/wasm/window.zig");
const gl = @import("backend/gl/window.zig");
const log = stdx.log.scoped(.window);
const Backend = @import("graphics.zig").Backend;

pub const Window = struct {
    const Self = @This();

    inner: switch (Backend) {
        .WasmCanvas => wasm.Window,
        .OpenGL => gl.Window,
        .Test => void,
    },

    pub fn init(alloc: *std.mem.Allocator, config: Config) !Self {
        const inner = try switch (Backend) {
            .OpenGL => gl.Window.init(alloc, config),
            .WasmCanvas => wasm.Window.init(config),
            .Test => {},
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

    pub fn swapBuffers(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.swapBuffers(self.inner),
            .WasmCanvas => {},
            else => stdx.panic("unsupported"),
        }
    }
};

pub fn quit() void {
    switch (Backend) {
        .WasmCanvas => {},
        .OpenGL => gl.quit(),
        else => stdx.panic("unsupported"),
    }
}

pub const Config = struct {
    title: []const u8 = "My Window",
    width: c_int = 1024,
    height: c_int = 768,
    resizable: bool = false,
    high_dpi: bool = false,
    fullscreen: bool = false,
};