const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const platform = @import("platform");
const Window = platform.Window;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const EventDispatcher = platform.EventDispatcher;
const log = stdx.log.scoped(.helper);

pub const App = struct {
    ui_mod: ui.Module,
    gctx: *graphics.Graphics,
    renderer: graphics.WindowRenderer,
    cam: graphics.Camera,
    dispatcher: EventDispatcher,
    win: Window,
    fps_limiter: graphics.DefaultFpsLimiter,
    quit: bool,
    last_frame_time_ms: f64,
    alloc: std.mem.Allocator,

    pub fn init(self: *App, title: []const u8) !void {
        const alloc = stdx.heap.getDefaultAllocator();
        self.alloc = alloc;
        self.dispatcher = EventDispatcher.init(alloc);

        self.win = Window.init(alloc, .{
            .title = title,
            .width = 1200,
            .height = 800,
            .high_dpi = true,
            .resizable = true,
            .mode = .Windowed,
            .anti_alias = false,
        }) catch unreachable;
        self.win.addDefaultHandlers(&self.dispatcher);

        try self.renderer.init(alloc, &self.win);
        self.gctx = self.renderer.getGraphics();
        self.gctx.setClearColor(Color.init(20, 20, 20, 255));

        self.cam.init2D(self.win.getWidth(), self.win.getHeight());

        // Create an fps limiter in case vsync is off or not supported.
        self.fps_limiter = graphics.DefaultFpsLimiter.init(30);
        self.quit = false;

        const S = struct {
            fn onQuit(ptr: ?*anyopaque) void {
                const self_ = stdx.mem.ptrCastAlign(*App, ptr.?);
                self_.quit = true;
            }
        };
        self.dispatcher.addOnQuit(self, S.onQuit);

        if (builtin.target.isWasm()) {
            self.last_frame_time_ms = stdx.time.getMillisTime();
        }

        self.ui_mod.init(self.alloc, self.gctx);
        self.ui_mod.addInputHandlers(&self.dispatcher);
    }

    pub fn runEventLoop(app: *App, comptime update: fn (delta_ms: f32) void) void {
        while (!app.quit) {
            app.dispatcher.processEvents();

            app.renderer.beginFrame(app.cam);
            app.fps_limiter.beginFrame();
            const delta_ms = app.fps_limiter.getLastFrameDeltaMs();
            update(delta_ms);
            app.renderer.endFrame();

            const delay = app.fps_limiter.endFrame();
            if (delay > 0) {
                platform.delay(delay);
            }
        }
    }

    pub fn deinit(self: *App) void {
        self.ui_mod.deinit();
        self.dispatcher.deinit();
        self.renderer.deinit(self.alloc);
        self.win.deinit();
        stdx.heap.deinitDefaultAllocator();
    }
};

pub fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32, app: *App, comptime update: fn (delta_ms: f32) void) [*]const u8 {
    // Update the input buffer view.
    stdx.wasm.js_buffer.input_buf.items.len = input_buffer_len;

    const delta_ms = cur_time_ms - app.last_frame_time_ms;
    app.last_frame_time_ms = cur_time_ms;

    app.dispatcher.processEvents();
    app.renderer.beginFrame(app.cam);

    update(@floatCast(f32, delta_ms));

    app.renderer.endFrame();
    return stdx.wasm.js_buffer.writeResult();
}

pub fn wasmInit(app: *App, title: []const u8) [*]const u8 {
    const alloc = stdx.heap.getDefaultAllocator();
    stdx.wasm.init(alloc);
    app.init(title) catch stdx.fatal();
    return stdx.wasm.js_buffer.writeResult();
}