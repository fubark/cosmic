const std = @import("std");
const stdx = @import("stdx");
const sdl = @import("sdl");
const gl = @import("gl");
const builtin = @import("builtin");

const window = @import("../../window.zig");
const Config = window.Config;
const log = stdx.log.scoped(.window_gl);

pub const Window = struct {
    const Self = @This();

    id: u32,
    sdl_window: *sdl.SDL_Window,
    gl_ctx: *anyopaque,
    width: u32,
    height: u32,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        var res: Window = undefined;
        if (sdl.SDL_InitSubSystem(sdl.SDL_INIT_VIDEO) != 0) {
            log.warn("unable to initialize SDL: {s}", .{sdl.SDL_GetError()});
            return error.FailedSdlInit;
        }

        var flags: c_int = 0;
        if (config.resizable) flags |= sdl.SDL_WINDOW_RESIZABLE;
        if (config.high_dpi) flags |= sdl.SDL_WINDOW_ALLOW_HIGHDPI;
        if (config.fullscreen) flags |= sdl.SDL_WINDOW_FULLSCREEN_DESKTOP;

        try initGL_Window(alloc, &res, config, flags);

        res.id = sdl.SDL_GetWindowID(res.sdl_window);
        res.width = @intCast(u32, config.width);
        res.height = @intCast(u32, config.height);
        return res;
    }

    pub fn deinit(self: Self) void {
        sdl.SDL_DestroyWindow(self.sdl_window);
        sdl.SDL_GL_DeleteContext(self.gl_ctx);
    }

    pub fn swapBuffers(self: Self) void {
        // Copy over opengl buffer to window. Also flushes any opengl commands that might be queued.
        // If vsync is enabled, it will also block wait to achieve the target refresh rate (eg. 60fps).
        sdl.SDL_GL_SwapWindow(self.sdl_window);
    }
};

pub fn disableVSync() !void {
    if (sdl.SDL_GL_SetSwapInterval(0) != 0) {
        log.warn("unable to turn off vsync: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

fn glSetAttr(attr: sdl.SDL_GLattr, val: c_int) !void {
    if (sdl.SDL_GL_SetAttribute(attr, val) != 0) {
        log.warn("sdl set attribute: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

fn initGL_Window(alloc: std.mem.Allocator, win: *Window, config: Config, flags: c_int) !void {
    try glSetAttr(sdl.SDL_GL_CONTEXT_FLAGS, sdl.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
    try glSetAttr(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);

    // Use GL 3.3 to stay close to GLES.
    try glSetAttr(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    try glSetAttr(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);

    try glSetAttr(sdl.SDL_GL_DOUBLEBUFFER, 1);
    try glSetAttr(sdl.SDL_GL_DEPTH_SIZE, 24);
    try glSetAttr(sdl.SDL_GL_STENCIL_SIZE, 8);

    var window_flags = flags | sdl.SDL_WINDOW_OPENGL;
    win.sdl_window = sdl.createWindow(alloc, config.title, sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, config.width), @intCast(c_int, config.height), @bitCast(u32, window_flags)) orelse {
        log.err("Unable to create window: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    };

    if (sdl.SDL_GL_CreateContext(win.sdl_window)) |ctx| {
        win.gl_ctx = ctx;
        log.debug("OpenGL: {s}", .{gl.glGetString(gl.GL_VERSION)});
    } else {
        log.err("Create GLContext: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }

    if (builtin.os.tag == .windows) {
        gl.initWinGL_Functions();
    }

    // Not necessary but better to be explicit.
    if (sdl.SDL_GL_MakeCurrent(win.sdl_window, win.gl_ctx) != 0) {
        log.err("Unable to attach gl context to window: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

// Should be called for cleanup before app exists.
pub fn quit() void {
    sdl.SDL_Quit();
}
