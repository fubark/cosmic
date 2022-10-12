const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const sdl = @import("sdl");

const log = stdx.log.scoped(.platform);
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

extern "stdx" fn jsSetSystemCursor(ptr: [*]const u8, len: usize) void;
extern "stdx" fn jsGetClipboard(len: *usize) [*]const u8;
extern "stdx" fn jsSetClipboardText(ptr: [*]const u8, len: usize) void;
extern "stdx" fn jsOpenUrl(ptr: [*]const u8, len: usize) void;

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

var system_cursors: [10]?*sdl.SDL_Cursor = .{ null } ** 10;
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
                    .pointer => stdx.unsupported(),
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
                .pointer => jsSetSystemCursor2("pointer"),
            }
        }
        cur_system_cursor = cursor_t;
    }
}

fn jsSetSystemCursor2(name: []const u8) void {
    jsSetSystemCursor(name.ptr, name.len);
}

pub fn allocClipboardText(alloc: std.mem.Allocator) ![]const u8 {
    if (IsWasm) {
        // TODO: Implement clipboard api (requires permission and async)
        stdx.unsupported();
    } else {
        sdl.ensureVideoInit() catch return error.FailedInit;
        const text = sdl.SDL_GetClipboardText();
        defer sdl.SDL_free(text);
        return try alloc.dupe(u8, std.mem.span(text));
    }
}

pub fn setClipboardText(str: if (IsWasm) []const u8 else [:0]const u8) !void {
    if (IsWasm) {
        jsSetClipboardText(str.ptr, str.len);
    } else {
        sdl.ensureVideoInit() catch return error.Unknown;
        const res = sdl.SDL_SetClipboardText(str);
        if (res != 0) {
            log.debug("unknown error: {} {s}", .{res, sdl.SDL_GetError()});
            return error.Unknown;
        }
    }
}

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
    pointer = 10,
};

pub fn openUrl(url: []const u8) void {
    if (IsWasm) {
        jsOpenUrl(url.ptr, url.len);
    } else {
        stdx.unsupported();
    }
}