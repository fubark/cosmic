const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const sdl = @import("sdl");

pub const GraphicsBackend = @import("backend.zig").GraphicsBackend;

const input_sdl = @import("input_sdl.zig");
pub const initSdlKeyDownEvent = input_sdl.initKeyDownEvent;
pub const initSdlKeyUpEvent = input_sdl.initKeyUpEvent;
pub const initSdlMouseDownEvent = input_sdl.initMouseDownEvent;
pub const initSdlMouseUpEvent = input_sdl.initMouseUpEvent;
pub const initSdlMouseMoveEvent = input_sdl.initMouseMoveEvent;
pub const initSdlMouseScrollEvent = input_sdl.initMouseScrollEvent;

const input_web = @import("input_web.zig");
pub const webToCanonicalKeyCode = input_web.toCanonicalKeyCode;

const mouse = @import("mouse.zig");
pub const MouseButton = mouse.MouseButton;
pub const MouseUpEvent = mouse.MouseUpEvent;
pub const MouseDownEvent = mouse.MouseDownEvent;
pub const MouseMoveEvent = mouse.MouseMoveEvent;
pub const MouseScrollEvent = mouse.MouseScrollEvent;

const keyboard = @import("keyboard.zig");
pub const KeyDownEvent = keyboard.KeyDownEvent;
pub const KeyUpEvent = keyboard.KeyUpEvent;
pub const KeyCode = keyboard.KeyCode;

const event_dispatcher = @import("event_dispatcher.zig");
pub const EventDispatcher = event_dispatcher.EventDispatcher;
pub const EventResult = event_dispatcher.EventResult;

pub fn delay(us: u64) void {
    if (!builtin.target.isWasm()) {
        // TODO: How does this compare to std.time.sleep ?
        // std.time.sleep(us * 1000);
        sdl.SDL_Delay(@intCast(u32, us / 1000));
    } else {
        // There isn't a good sleep mechanism in js since it's run on event loop.
        // stdx.time.sleep(self.target_ms_per_frame - render_time_ms);
    }
}

pub fn captureMouse(capture: bool) void {
    if (!builtin.target.isWasm()) {
        _ = sdl.SDL_CaptureMouse(@boolToInt(capture));
    } else {
    }
}

pub const window_sdl = @import("window_sdl.zig");
const window = @import("window.zig");
pub const Window = window.Window;
pub const quit = window.quit;

pub const WindowResizeEvent = struct {
    /// Logical sizes.
    width: u16,
    height: u16,

    pub fn init(width: u16, height: u16) WindowResizeEvent {
        return .{
            .width = width,
            .height = height,
        };
    }
};

pub const FetchResultEvent = struct {
    fetch_id: u32,
    buf: []const u8,
};