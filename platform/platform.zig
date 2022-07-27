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
    if (comptime !builtin.target.isWasm()) {
        // TODO: How does this compare to std.time.sleep ?
        // std.time.sleep(us * 1000);
        sdl.SDL_Delay(@intCast(u32, us / 1000));
    } else {
        // There isn't a good sleep mechanism in js since it's run on event loop.
        // stdx.time.sleep(self.target_ms_per_frame - render_time_ms);
    }
}

pub fn captureMouse(capture: bool) void {
    if (comptime !builtin.target.isWasm()) {
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

var system_cursors: [10]?*sdl.SDL_Cursor = .{ null, null, null, null, null, null, null, null, null, null };
var cur_system_cursor: SystemCursorType = .default;
pub fn setSystemCursor(cursor_t: SystemCursorType) void {
    if (cur_system_cursor != cursor_t) {
        if (comptime !builtin.target.isWasm()) {
            const idx = @enumToInt(cursor_t);
            if (system_cursors[idx] == null) {
                const sdl_cursor: c_uint = switch (cursor_t) {
                    .default => sdl.SDL_SYSTEM_CURSOR_ARROW,
                    .crosshair => sdl.SDL_SYSTEM_CURSOR_CROSSHAIR,
                    .size_nwse => sdl.SDL_SYSTEM_CURSOR_SIZENWSE,
                    .size_nesw => sdl.SDL_SYSTEM_CURSOR_SIZENESW,
                    .size_we => sdl.SDL_SYSTEM_CURSOR_SIZEWE,
                    .size_ns => sdl.SDL_SYSTEM_CURSOR_SIZENS,
                    .size_all => sdl.SDL_SYSTEM_CURSOR_SIZEALL,
                    .stop => sdl.SDL_SYSTEM_CURSOR_NO,
                    .hand => sdl.SDL_SYSTEM_CURSOR_HAND,
                    .wait => sdl.SDL_SYSTEM_CURSOR_WAIT,
                };
                const res = sdl.SDL_CreateSystemCursor(sdl_cursor);
                if (res == null) {
                    @panic("error");
                }
                system_cursors[idx] = res;
            }
            sdl.SDL_SetCursor(system_cursors[idx].?);
        } else {
            switch (cursor_t) {
                .default => jsSetSystemCursor2("auto"),
                .crosshair => jsSetSystemCursor2("crosshair"),
                .size_nwse => jsSetSystemCursor2("nwse-resize"),
                .size_nesw => jsSetSystemCursor2("nesw-resize"),
                .size_we => jsSetSystemCursor2("ew-resize"),
                .size_ns => jsSetSystemCursor2("ns-resize"),
                .size_all => jsSetSystemCursor2("move"),
                .stop => jsSetSystemCursor2("not-allowed"),
                .hand => jsSetSystemCursor2("grab"),
                .wait => jsSetSystemCursor2("wait"),
            }
        }
        cur_system_cursor = cursor_t;
    }
}

fn jsSetSystemCursor2(name: []const u8) void {
    jsSetSystemCursor(name.ptr, name.len);
}

extern "stdx" fn jsSetSystemCursor(ptr: [*]const u8, len: usize) void;

pub fn deinit() void {
    if (comptime !builtin.target.isWasm()) {
        for (system_cursors) |mb_cursor| {
            if (mb_cursor) |cursor| {
                sdl.SDL_FreeCursor(cursor);
            }
        }
    }
}

const SystemCursorType = enum(u4) {
    default = 0,
    crosshair = 1,
    size_nwse = 2,
    size_nesw = 3,
    size_we = 4,
    size_ns = 5,
    size_all = 6,
    stop = 7,
    hand = 8,
    wait = 9,
};