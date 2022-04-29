pub const MouseButton = enum {
    Left,
    Middle,
    Right,
    X1,
    X2,
};

pub const MouseUpEvent = struct {
    button: MouseButton,
    x: i16,
    y: i16,
    clicks: u8,

    pub fn init(button: MouseButton, x: i16, y: i16, clicks: u8) @This() {
        return .{
            .button = button,
            .x = x,
            .y = y,
            .clicks = clicks,
        };
    }
};

pub const MouseDownEvent = struct {
    button: MouseButton,
    x: i16,
    y: i16,
    clicks: u8,

    pub fn init(button: MouseButton, x: i16, y: i16, clicks: u8) @This() {
        return .{
            .button = button,
            .x = x,
            .y = y,
            .clicks = clicks,
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