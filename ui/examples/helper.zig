const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const platform = @import("platform");
const Window = graphics.Window;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const EventDispatcher = platform.EventDispatcher;

pub const App = struct {
    const Self = @This();

    g: *graphics.Graphics,
    dispatcher: EventDispatcher,
    win: Window,
    fps_limiter: graphics.DefaultFpsLimiter,
    quit: bool,
    last_frame_time_ms: f64,
    alloc: std.mem.Allocator,

    pub fn init(app: *Self, title: []const u8) void {
        const alloc = stdx.heap.getDefaultAllocator();
        app.alloc = alloc;
        app.dispatcher = EventDispatcher.init(alloc);

        app.win = Window.init(alloc, .{
            .title = title,
            .width = 1200,
            .height = 800,
            .high_dpi = true,
            .resizable = true,
            .mode = .Windowed,
            .anti_alias = true,
        }) catch unreachable;
        app.win.addDefaultHandlers(&app.dispatcher);

        app.g = app.win.getGraphics();
        app.g.setClearColor(Color.init(20, 20, 20, 255));

        // Create an fps limiter in case vsync is off or not supported.
        app.fps_limiter = graphics.DefaultFpsLimiter.init(30);
        app.quit = false;

        const S = struct {
            fn onQuit(ptr: ?*anyopaque) void {
                const self_ = stdx.mem.ptrCastAlign(*App, ptr.?);
                self_.quit = true;
            }
        };
        app.dispatcher.addOnQuit(app, S.onQuit);

        if (builtin.target.isWasm()) {
            app.last_frame_time_ms = stdx.time.getMillisTime();
        }
    }

    pub fn runEventLoop(app: *Self, comptime update: fn (delta_ms: f32) void) void {
        while (!app.quit) {
            app.dispatcher.processEvents();
            app.win.beginFrame();
            app.fps_limiter.beginFrame();
            const delta_ms = app.fps_limiter.getLastFrameDeltaMs();

            update(delta_ms);

            app.win.endFrame();
            const delay = app.fps_limiter.endFrame();
            if (delay > 0) {
                platform.delay(delay);
            }
            // Count swap into frame render time.
            app.win.swapBuffers();
        }
    }

    pub fn deinit(self: *Self) void {
        self.dispatcher.deinit();
        self.win.deinit();
        stdx.heap.deinitDefaultAllocator();
    }
};

pub fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32, app: *App, comptime update: fn (delta_ms: f32) void) *const u8 {
    // Update the input buffer view.
    stdx.wasm.js_buffer.input_buf.items.len = input_buffer_len;

    const delta_ms = cur_time_ms - app.last_frame_time_ms;
    app.last_frame_time_ms = cur_time_ms;

    app.dispatcher.processEvents();
    app.win.beginFrame();

    update(@floatCast(f32, delta_ms));

    app.win.endFrame();
    app.win.swapBuffers();
    return stdx.wasm.js_buffer.writeResult();
}

pub fn wasmInit(comptime init: fn () void) *const u8 {
    const alloc = stdx.heap.getDefaultAllocator();
    stdx.wasm.init(alloc);
    init();
    return stdx.wasm.js_buffer.writeResult();
}

pub fn wasmDeinit(comptime deinit: fn () void) void {
    stdx.wasm.deinit();
    deinit();
}