const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.input);
const sdl = @import("sdl");

const input_sdl = @import("input_sdl.zig");

pub const initSdlKeyDownEvent = input_sdl.initKeyDownEvent;
pub const initSdlKeyUpEvent = input_sdl.initKeyUpEvent;
pub const initSdlMouseDownEvent = input_sdl.initMouseDownEvent;
pub const initSdlMouseUpEvent = input_sdl.initMouseUpEvent;
pub const initSdlMouseMoveEvent = input_sdl.initMouseMoveEvent;

const mouse = @import("mouse.zig");
pub const MouseButton = mouse.MouseButton;
pub const MouseUpEvent = mouse.MouseUpEvent;
pub const MouseDownEvent = mouse.MouseDownEvent;
pub const MouseMoveEvent = mouse.MouseMoveEvent;

const keyboard = @import("keyboard.zig");
pub const KeyDownEvent = keyboard.KeyDownEvent;
pub const KeyUpEvent = keyboard.KeyUpEvent;
pub const KeyCode = keyboard.KeyCode;

pub fn delay(us: u64) void {
    if (!builtin.target.isWasm()) {
        // TODO: How does this compare to std.time.sleep ?
        sdl.SDL_Delay(@intCast(u32, us / 1000));
    } else {
        // There isn't a good sleep mechanism in js since it's run on event loop.
        // stdx.time.sleep(self.target_ms_per_frame - render_time_ms);
    }
}