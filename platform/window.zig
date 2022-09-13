const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;

const window_sdl = @import("window_sdl.zig");
const WindowSdl = window_sdl.Window;
const canvas = @import("window_canvas.zig");
const log = stdx.log.scoped(.window);

const platform = @import("platform.zig");
const WindowResizeEvent = platform.WindowResizeEvent;
const EventDispatcher = platform.EventDispatcher;

pub const Window = struct {
    impl: switch (Backend) {
        .OpenGL => WindowSdl,
        .Vulkan => WindowSdl,
        .WasmCanvas => canvas.Window,
        .Test => TestWindow,
        else => @compileError("unsupported"),
    },

    /// A hook for window resizes. 
    on_resize: ?std.meta.FnPtr(fn (ctx: ?*anyopaque, width: u32, height: u32) void),
    on_resize_ctx: ?*anyopaque,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        const impl = switch (Backend) {
            .OpenGL => try WindowSdl.init(alloc, config),
            .Vulkan => try WindowSdl.init(alloc, config),
            .WasmCanvas => try canvas.Window.init(alloc, config),
            .Test => TestWindow{ .width = config.width, .height = config.height },
            else => stdx.unsupported(),
        };
        return Self{
            .impl = impl,
            .on_resize = null,
            .on_resize_ctx = null,
        };
    }

    pub fn initWithSharedContext(alloc: std.mem.Allocator, config: Config, win: Window) !Self {
        const impl = switch (Backend) {
            .OpenGL => try WindowSdl.initWithSharedContext(alloc, config, win.impl),
            else => @panic("unsupported"),
        };
        return Self{
            .impl = impl,
            .on_resize = null,
            .on_resize_ctx = null,
        };
    }

    pub fn deinit(self: Self) void {
        switch (Backend) {
            .OpenGL, .Vulkan => WindowSdl.deinit(self.impl),
            .WasmCanvas => canvas.Window.deinit(&self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn addDefaultHandlers(self: *Self, dispatcher: *EventDispatcher) void {
        const S = struct {
            fn onWindowResize(ctx: ?*anyopaque, e: WindowResizeEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                self_.handleResize(e.width, e.height);
            }
        };
        dispatcher.addOnWindowResize(self, S.onWindowResize);
    }

    /// Should be called before beginFrame if multiple windows are being rendered together.
    /// If there is only one window, it only needs to be called once.
    pub fn makeCurrent(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.makeCurrent(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        switch (Backend) {
            .OpenGL => WindowSdl.resize(&self.impl, width, height),
            else => stdx.unsupported(),
        }
    }

    pub fn setUserResizeHook(self: *Self, ctx: ?*anyopaque, cb: fn (?*anyopaque, u32, u32) void) void {
        self.on_resize = cb;
        self.on_resize_ctx = ctx;
    }

    /// Internal function to update the buffer on a user resize or window manager resize.
    /// An explicit call to resize() should not need to call this.
    pub fn handleResize(self: *Self, width: u32, height: u32) void {
        switch (Backend) {
            .OpenGL => return WindowSdl.handleResize(&self.impl, width, height),
            else => stdx.unsupported(),
        }
        if (self.on_resize) |cb| {
            cb(self.on_resize_ctx, width, height);
        }
    }

    pub fn getWidth(self: Self) u32 {
        return self.impl.width;
    }

    pub fn getHeight(self: Self) u32 {
        return self.impl.height;
    }

    pub fn getAspectRatio(self: Self) f32 {
        return @intToFloat(f32, self.impl.width) / @intToFloat(f32, self.impl.height);
    }

    pub fn minimize(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.minimize(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn maximize(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.maximize(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn restore(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.restore(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn setMode(self: Self, mode: Mode) void {
        switch (Backend) {
            .OpenGL => WindowSdl.setMode(self.impl, mode),
            else => stdx.unsupported(),
        }
    }

    pub fn setPosition(self: Self, x: i32, y: i32) void {
        switch (Backend) {
            .OpenGL => WindowSdl.setPosition(self.impl, x, y),
            else => stdx.unsupported(),
        }
    }

    pub fn center(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.center(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn focus(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.focus(self.impl),
            else => stdx.unsupported(),
        }
    }

    /// In the OpenGL SDL backend, swapBuffers will also block the thread to achieve the target refresh rate if vsync is on.
    pub fn swapBuffers(self: Self) void {
        switch (Backend) {
            .OpenGL => WindowSdl.swapBuffers(self.impl),
            .WasmCanvas => {},
            .Test => {},
            else => stdx.unsupported(),
        }
    }

    pub fn setTitle(self: Self, title: []const u8) void {
        switch (Backend) {
            .OpenGL => WindowSdl.setTitle(self.impl, title),
            else => stdx.unsupported(),
        }
    }

    pub fn getTitle(self: Self, alloc: std.mem.Allocator) []const u8 {
        switch (Backend) {
            .OpenGL => return WindowSdl.getTitle(self.impl, alloc),
            else => stdx.unsupported(),
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
        .OpenGL => window_sdl.quit(),
        .WasmCanvas => {},
        else => stdx.unsupported(),
    }
}

pub const Config = struct {
    title: []const u8 = "My Window",
    width: u32 = 1024,
    height: u32 = 768,
    resizable: bool = false,
    high_dpi: bool = false,
    mode: Mode = .Windowed,
    anti_alias: bool = false,
};

const TestWindow = struct {
    width: u32,
    height: u32,
};