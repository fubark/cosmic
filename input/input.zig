const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.input);

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