pub const MouseButton = enum {
    left,
    middle,
    right,
    x1,
    x2,
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

/// TODO: Rename to MouseWheelEvent
pub const MouseScrollEvent = struct {
    x: i16,
    y: i16,
    delta_y: f32,

    pub fn init(x: i16, y: i16, delta_y: f32) @This() {
        return .{
            .x = x,
            .y = y,
            .delta_y = delta_y,
        };
    }
};