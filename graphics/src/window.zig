const std = @import("std");
const stdx = @import("stdx");

const gl = @import("backend/gl/window.zig");
const canvas = @import("backend/canvas/window.zig");
const log = stdx.log.scoped(.window);
const graphics = @import("graphics.zig");
const Graphics = graphics.Graphics;
const Backend = graphics.Backend;

// TODO: Move Window to the platform package.
pub const Window = struct {
    const Self = @This();

    inner: switch (Backend) {
        .OpenGL => gl.Window,
        .WasmCanvas => canvas.Window,
        .Test => TestWindow,
    },

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        const inner = switch (Backend) {
            .OpenGL => try gl.Window.init(alloc, config),
            .WasmCanvas => try canvas.Window.init(alloc, config),
            .Test => TestWindow{ .width = config.width, .height = config.height },
        };
        return Self{
            .inner = inner,
        };
    }

    pub fn initWithSharedContext(alloc: std.mem.Allocator, config: Config, win: Window) !Self {
        const inner = switch (Backend) {
            .OpenGL => try gl.Window.initWithSharedContext(alloc, config, win.inner),
            else => @panic("unsupported"),
        };
        return Self{
            .inner = inner,
        };
    }

    pub fn deinit(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.deinit(self.inner),
            .WasmCanvas => canvas.Window.deinit(&self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    /// Should be called before beginFrame if multiple windows are being rendered together.
    /// If there is only one window, it only needs to be called once.
    pub fn makeCurrent(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.makeCurrent(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    /// Setup for the frame before any user draw calls.
    /// In OpenGL, glClear can block if there there are too many commands in the queue.
    pub fn beginFrame(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.beginFrame(self.inner),
            .WasmCanvas => canvas.Window.beginFrame(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    // Post frame ops.
    pub fn endFrame(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.endFrame(self.inner),
            .WasmCanvas => canvas.Window.endFrame(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getGraphics(self: Self) *graphics.Graphics {
        switch (Backend) {
            .OpenGL => return gl.Window.getGraphics(self.inner),
            .WasmCanvas => return canvas.Window.getGraphics(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        switch (Backend) {
            .OpenGL => gl.Window.resize(&self.inner, width, height),
            else => stdx.panic("unsupported"),
        }
    }

    /// Internal function to update the buffer on a user resize or window manager resize.
    /// An explicit call to resize() should not need to call this.
    pub fn handleResize(self: *Self, width: u32, height: u32) void {
        switch (Backend) {
            .OpenGL => return gl.Window.handleResize(&self.inner, width, height),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getWidth(self: Self) u32 {
        return self.inner.width;
    }

    pub fn getHeight(self: Self) u32 {
        return self.inner.height;
    }

    pub fn minimize(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.minimize(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn maximize(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.maximize(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn restore(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.restore(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setMode(self: Self, mode: Mode) void {
        switch (Backend) {
            .OpenGL => gl.Window.setMode(self.inner, mode),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setPosition(self: Self, x: i32, y: i32) void {
        switch (Backend) {
            .OpenGL => gl.Window.setPosition(self.inner, x, y),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn center(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.center(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn focus(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.focus(self.inner),
            else => stdx.panic("unsupported"),
        }
    }

    /// In the OpenGL SDL backend, swapBuffers will also block the thread to achieve the target refresh rate if vsync is on.
    pub fn swapBuffers(self: Self) void {
        switch (Backend) {
            .OpenGL => gl.Window.swapBuffers(self.inner),
            .WasmCanvas => {},
            .Test => {},
        }
    }

    pub fn setTitle(self: Self, title: []const u8) void {
        switch (Backend) {
            .OpenGL => gl.Window.setTitle(self.inner, title),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getTitle(self: Self, alloc: std.mem.Allocator) []const u8 {
        switch (Backend) {
            .OpenGL => return gl.Window.getTitle(self.inner, alloc),
            else => stdx.panic("unsupported"),
        }
    }
};

pub const Mode = enum {
    Windowed,
    PseudoFullscreen,
    Fullscreen,
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
    mode: Mode = .Windowed,
};

const TestWindow = struct {
    width: u32,
    height: u32,
};