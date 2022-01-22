pub const MouseButton = enum {
    Left,
    Middle,
    Right,
    X1,
    X2,
};

pub const MouseEvent = struct {
    button: MouseButton,
    pressed: bool,
    x: i16,
    y: i16,

    pub fn init(button: MouseButton, pressed: bool, x: i16, y: i16) @This() {
        return .{
            .button = button,
            .pressed = pressed,
            .x = x,
            .y = y,
        };
    }
};

pub const MouseMoveEvent = struct {
    x: i16,
    y: i16,

    pub fn init(x: i16, y: i16) @This() {
        return .{
            .x = x,
            .y = y,
        };
    }
};