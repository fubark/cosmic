const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const math = stdx.math;
const Mat4 = math.Mat4;
const sdl = @import("sdl");
const gl = @import("gl");
const builtin = @import("builtin");
const graphics = @import("../../graphics.zig");
const Transform = graphics.transform.Transform;

const window = @import("../../window.zig");
const Config = window.Config;
const Mode = window.Mode;
const log = stdx.log.scoped(.window_gl);

var inited_sdl = false;

pub fn ensureSdlInit() !void {
    if (!inited_sdl) {
        if (sdl.SDL_InitSubSystem(sdl.SDL_INIT_VIDEO) != 0) {
            log.err("SDL_InitSubSystem: {s}", .{sdl.SDL_GetError()});
            return error.FailedSdlInit;
        }
        inited_sdl = true;
    }
}

pub const Window = struct {
    const Self = @This();

    id: u32,
    sdl_window: *sdl.SDL_Window,

    // Since other windows can use the same context, we defer deinit until the last window.
    alloc: std.mem.Allocator,
    gl_ctx_ref_count: *u32,
    gl_ctx: *anyopaque,
    graphics: *graphics.Graphics,

    width: u32,
    height: u32,

    // When creating a window with high dpi, the buffer size can differ from
    // the logical window size. (Usually a multiple, eg. 2x)
    buf_width: u32,
    buf_height: u32,

    // Depth pixel ratio. Buffer size / logical window size.
    dpr: u8,

    // Initialize to the default gl framebuffer.
    // If we are doing MSAA, then we'll need to set this to the multisample framebuffer.
    fbo_id: gl.GLuint = 0,

    msaa: ?MsaaFrameBuffer = null,

    proj_transform: Transform,
    initial_mvp: Mat4,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        try ensureSdlInit();

        var res: Window = undefined;
        const flags = getSdlWindowFlags(config);
        try initGL_Window(alloc, &res, config, flags);
        try initGL_Context(&res);
        res.alloc = alloc;
        res.gl_ctx_ref_count = alloc.create(u32) catch unreachable;
        res.gl_ctx_ref_count.* = 1;

        // Initialize graphics.
        res.graphics = alloc.create(graphics.Graphics) catch unreachable;
        res.graphics.init(alloc);
        res.graphics.g.cur_dpr = res.dpr;

        // Setup transforms.
        res.proj_transform = initDisplayProjection(@intToFloat(f32, res.width), @intToFloat(f32, res.height));
        res.initial_mvp = math.Mul4x4_4x4(res.proj_transform.mat, Transform.initIdentity().mat);

        if (createMsaaFrameBuffer(res.buf_width, res.buf_height, res.dpr)) |msaa| {
            res.fbo_id = msaa.fbo;
            res.msaa = msaa;
        }

        return res;
    }

    /// Currently, we share a GL context by simply reusing the same handle.
    /// There is a different concept of sharing a context supported by GL in which textures and internal data are shared
    /// and a new GL context is created to operate on that. SDL can do this with SDL_GL_SHARE_WITH_CURRENT_CONTEXT = 1.
    /// However, it could involve reorganizing how Graphics does rendering because not everything is shared.
    /// There doesn't seem to be a good reason to use GL's shared context so prefer the simpler method and don't create a new context here.
    pub fn initWithSharedContext(alloc: std.mem.Allocator, config: Config, existing_win: Self) !Self {
        try ensureSdlInit();

        var res: Window = undefined;
        const flags = getSdlWindowFlags(config);
        try initGL_Window(alloc, &res, config, flags);
        // Reuse existing window's GL context.
        res.gl_ctx = existing_win.gl_ctx;
        res.alloc = existing_win.alloc;
        res.gl_ctx_ref_count = existing_win.gl_ctx_ref_count;
        res.gl_ctx_ref_count.* += 1;

        res.graphics = existing_win.graphics;

        // Setup transforms.
        res.proj_transform = initDisplayProjection(@intToFloat(f32, res.width), @intToFloat(f32, res.height));
        res.initial_mvp = math.Mul4x4_4x4(res.proj_transform.mat, Transform.initIdentity().mat);

        if (createMsaaFrameBuffer(res.buf_width, res.buf_height, res.dpr)) |msaa| {
            res.fbo_id = msaa.fbo;
            res.msaa = msaa;
        }

        return res;
    }

    pub fn deinit(self: Self) void {
        sdl.SDL_DestroyWindow(self.sdl_window);
        if (self.gl_ctx_ref_count.* == 1) {
            self.graphics.deinit();
            self.alloc.destroy(self.graphics);

            sdl.SDL_GL_DeleteContext(self.gl_ctx);
            self.alloc.destroy(self.gl_ctx_ref_count);
        } else {
            self.gl_ctx_ref_count.* -= 1;
        }
    }

    pub fn handleResize(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;

        var buf_width: c_int = undefined;
        var buf_height: c_int = undefined;
        sdl.SDL_GL_GetDrawableSize(self.sdl_window, &buf_width, &buf_height);
        self.buf_width = @intCast(u32, buf_width);
        self.buf_height = @intCast(u32, buf_height);

        // Resize the transforms.
        self.proj_transform = initDisplayProjection(@intToFloat(f32, width), @intToFloat(f32, height));
        self.initial_mvp = math.Mul4x4_4x4(self.proj_transform.mat, Transform.initIdentity().mat);

        // The default frame buffer already resizes to the window.
        // The msaa texture was created separately, so it needs to update.
        if (self.msaa) |msaa| {
            resizeMsaaFrameBuffer(msaa, self.buf_width, self.buf_height);
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        sdl.SDL_SetWindowSize(self.sdl_window, @intCast(c_int, width), @intCast(c_int, height));

        var cur_width: c_int = undefined;
        var cur_height: c_int = undefined;
        sdl.SDL_GetWindowSize(self.sdl_window, &cur_width, &cur_height);
        self.width = @intCast(u32, cur_width);
        self.height = @intCast(u32, cur_height);

        var buf_width: c_int = undefined;
        var buf_height: c_int = undefined;
        sdl.SDL_GL_GetDrawableSize(self.sdl_window, &buf_width, &buf_height);
        self.buf_width = @intCast(u32, buf_width);
        self.buf_height = @intCast(u32, buf_height);

        self.proj_transform = initDisplayProjection(@intToFloat(f32, self.width), @intToFloat(f32, self.height));
        self.initial_mvp = math.Mul4x4_4x4(self.proj_transform.mat, Transform.initIdentity().mat);

        if (self.msaa) |msaa| {
            resizeMsaaFrameBuffer(msaa, self.buf_width, self.buf_height);
        }
    }

    pub fn minimize(self: Self) void {
        sdl.SDL_MinimizeWindow(self.sdl_window);
    }

    pub fn maximize(self: Self) void {
        sdl.SDL_MaximizeWindow(self.sdl_window);
    }

    pub fn restore(self: Self) void {
        sdl.SDL_RestoreWindow(self.sdl_window);
    }

    pub fn setMode(self: Self, mode: Mode) void {
        switch (mode) {
            .Windowed => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, 0),
            .PseudoFullscreen => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, sdl.SDL_WINDOW_FULLSCREEN_DESKTOP),
            .Fullscreen => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, sdl.SDL_WINDOW_FULLSCREEN),
        }
    }

    pub fn setPosition(self: Self, x: i32, y: i32) void {
        sdl.SDL_SetWindowPosition(self.sdl_window, x, y);
    }

    pub fn center(self: Self) void {
        sdl.SDL_SetWindowPosition(self.sdl_window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);
    }

    pub fn focus(self: Self) void {
        sdl.SDL_RaiseWindow(self.sdl_window);
    }

    pub fn getGraphics(self: Self) *graphics.Graphics {
        return self.graphics;
    }

    pub fn makeCurrent(self: Self) void {
        _ = sdl.SDL_GL_MakeCurrent(self.sdl_window, self.gl_ctx);
    }

    pub fn beginFrame(self: Self) void {
        self.graphics.g.beginFrame(self.buf_width, self.buf_height, self.fbo_id, self.proj_transform, self.initial_mvp);
    }

    pub fn endFrame(self: Self) void {
        self.graphics.g.endFrame(self.buf_width, self.buf_height, self.fbo_id);
    }

    pub fn swapBuffers(self: Self) void {
        // Copy over opengl buffer to window. Also flushes any opengl commands that might be queued.
        // If vsync is enabled, it will also block wait to achieve the target refresh rate (eg. 60fps).
        sdl.SDL_GL_SwapWindow(self.sdl_window);
    }

    pub fn setTitle(self: Self, title: []const u8) void {
        const cstr = std.cstr.addNullByte(self.alloc, title) catch unreachable;
        defer self.alloc.free(cstr);
        sdl.SDL_SetWindowTitle(self.sdl_window, cstr);
    }

    pub fn getTitle(self: Self, alloc: std.mem.Allocator) []const u8 {
        const cstr = sdl.SDL_GetWindowTitle(self.sdl_window);
        return alloc.dupe(u8, std.mem.span(cstr)) catch unreachable;
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

    win.id = sdl.SDL_GetWindowID(win.sdl_window);
    win.width = @intCast(u32, config.width);
    win.height = @intCast(u32, config.height);

    var buf_width: c_int = undefined;
    var buf_height: c_int = undefined;
    sdl.SDL_GL_GetDrawableSize(win.sdl_window, &buf_width, &buf_height);
    win.buf_width = @intCast(u32, buf_width);
    win.buf_height = @intCast(u32, buf_height);

    win.dpr = @intCast(u8, win.buf_width / win.width);
}

fn initGL_Context(win: *Window) !void {
    if (sdl.SDL_GL_CreateContext(win.sdl_window)) |ctx| {
        win.gl_ctx = ctx;

        // GL version on some platforms is only available after the context is created and made current.
        // This also means it's better to start initing opengl functions (GetProcAddress) on windows after an opengl context is created.
        var major: i32 = undefined;
        var minor: i32 = undefined;
        gl.glGetIntegerv(gl.GL_MAJOR_VERSION, &major);
        gl.glGetIntegerv(gl.GL_MINOR_VERSION, &minor);
        _ = minor;
        if (major < 3) {
            log.err("OpenGL Version Unsupported: {s}", .{gl.glGetString(gl.GL_VERSION)});
            return error.OpenGLUnsupported;
        }
        if (builtin.os.tag == .windows) {
            gl.initWinGL_Functions();
        }
        log.debug("OpenGL: {s}", .{gl.glGetString(gl.GL_VERSION)});
    } else {
        log.err("Create GLContext: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
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

fn getSdlWindowFlags(config: Config) c_int {
    var flags: c_int = 0;
    if (config.resizable) flags |= sdl.SDL_WINDOW_RESIZABLE;
    // TODO: Implement high dpi if it doesn't work on windows: https://nlguillemot.wordpress.com/2016/12/11/high-dpi-rendering/
    if (config.high_dpi) flags |= sdl.SDL_WINDOW_ALLOW_HIGHDPI;
    if (config.mode == .PseudoFullscreen) {
        flags |= sdl.SDL_WINDOW_FULLSCREEN_DESKTOP;
    } else if (config.mode == .Fullscreen) {
        flags |= sdl.SDL_WINDOW_FULLSCREEN;
    }
    return flags;
}

pub fn initDisplayProjection(width: f32, height: f32) Transform {
    var res = Transform.initIdentity();
    // first reduce to [0,1] values
    res.scale(1.0 / width, 1.0 / height);
    // to [0,2] values
    res.scale(2.0, 2.0);
    // to clip space [-1,1]
    res.translate(-1.0, -1.0);
    // flip y since clip space is based on cartesian
    res.scale(1.0, -1.0);
    return res;
}

test "initDisplayProjection" {
    var transform = initDisplayProjection(800, 600);
    try t.eq(transform.transformPoint(.{ 0, 0, 0, 1 }), .{ -1, 1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 800, 0, 0, 1 }), .{ 1, 1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 800, 600, 0, 1 }), .{ 1, -1, 0, 1 });
    try t.eq(transform.transformPoint(.{ 0, 600, 0, 1 }), .{ -1, -1, 0, 1 });
}

fn resizeMsaaFrameBuffer(msaa: MsaaFrameBuffer, width: u32, height: u32) void {
    gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, msaa.fbo);
    gl.glBindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, msaa.tex);
    gl.texImage2DMultisample(gl.GL_TEXTURE_2D_MULTISAMPLE, @intCast(c_int, msaa.num_samples), gl.GL_RGB, @intCast(c_int, width), @intCast(c_int, height), gl.GL_TRUE);
    gl.framebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D_MULTISAMPLE, msaa.tex, 0);
    gl.glBindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, 0);
}

pub fn createMsaaFrameBuffer(width: u32, height: u32, dpr: u8) ?MsaaFrameBuffer {
    // Setup multisampling anti alias.
    // See: https://learnopengl.com/Advanced-OpenGL/Anti-Aliasing
    const max_samples = gl.getMaxSamples();
    log.debug("max samples: {}", .{max_samples});
    if (max_samples >= 2) {
        const msaa_preferred_samples: u32 = switch (dpr) {
            1 => 8,
            // Since the draw buffer is already a supersample, we don't need much msaa samples.
            2 => 4,
            else => 2,
        };
        var ms_fbo: gl.GLuint = 0;
        gl.genFramebuffers(1, &ms_fbo);
        gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, ms_fbo);

        var ms_tex: gl.GLuint = 0;
        gl.glGenTextures(1, &ms_tex);

        gl.glEnable(gl.GL_MULTISAMPLE);
        // gl.glHint(gl.GL_MULTISAMPLE_FILTER_HINT_NV, gl.GL_NICEST);
        const num_samples = std.math.min(max_samples, msaa_preferred_samples);
        gl.glBindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, ms_tex);
        gl.texImage2DMultisample(gl.GL_TEXTURE_2D_MULTISAMPLE, @intCast(c_int, num_samples), gl.GL_RGB, @intCast(c_int, width), @intCast(c_int, height), gl.GL_TRUE);
        gl.framebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D_MULTISAMPLE, ms_tex, 0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, 0);

        log.debug("msaa framebuffer created with {} samples", .{num_samples});
        return MsaaFrameBuffer{
            .fbo = ms_fbo,
            .tex = ms_tex,
            .num_samples = num_samples,
        };
    } else {
        return null;
    }
}

const MsaaFrameBuffer = struct {
    fbo: gl.GLuint,
    tex: gl.GLuint,
    num_samples: u32,
};