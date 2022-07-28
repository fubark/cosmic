const std = @import("std");
const platform = @import("platform");

const ui = @import("ui.zig");
const module = @import("module.zig");

pub const IntervalEvent = struct {
    progress_ms: f32,
    ctx: *EventContext,
};

pub const KeyDownEvent = Event(platform.KeyDownEvent);
pub const KeyUpEvent = Event(platform.KeyUpEvent);
pub const MouseDownEvent = Event(platform.MouseDownEvent);
pub const MouseUpEvent = Event(platform.MouseUpEvent);
pub const MouseMoveEvent = Event(platform.MouseMoveEvent);
pub const MouseScrollEvent = Event(platform.MouseScrollEvent);

pub const HoverChangeEvent = struct {
    ctx: *EventContext,
    x: i16,
    y: i16,
    hovered: bool,
};

pub const DragStartEvent = struct {
    /// Absolute position of the child widget that is wrapped.
    src_x: u32,
    src_y: u32,

    /// Mouse position.
    x: i16,
    y: i16,

    pub fn getSrcOffsetX(self: DragStartEvent) i16 {
        return self.x - @intCast(i16, self.src_x);
    }

    pub fn getSrcOffsetY(self: DragStartEvent) i16 {
        return self.y - @intCast(i16, self.src_y);
    }
};

pub fn Event(comptime EventType: type) type {
    return struct {
        ctx: *EventContext,
        val: EventType,
    };
}

pub const DragMoveEvent = struct {
    ctx: *EventContext,
    x: i16,
    y: i16,
};

pub const EventContext = struct {
    alloc: std.mem.Allocator,
    common: *ui.CommonContext,
    node: *ui.Node,

    pub fn init(mod: *ui.Module) EventContext {
        return .{
            .common = &mod.common.ctx,
            .alloc = mod.alloc,
            .node = undefined,
        };
    }

    pub usingnamespace module.MixinContextInputOps(EventContext);
    pub usingnamespace module.MixinContextNodeOps(EventContext);
    pub usingnamespace module.MixinContextFontOps(EventContext);
    pub usingnamespace module.MixinContextEventOps(EventContext);
    pub usingnamespace module.MixinContextSharedOps(EventContext);
};

pub fn KeyDownHandler(comptime Context: type) type {
    return fn (Context, KeyDownEvent) void;
}

pub fn KeyUpHandler(comptime Context: type) type {
    return fn (Context, KeyUpEvent) void;
}

pub fn MouseMoveHandler(comptime Context: type) type {
    return fn (Context, MouseMoveEvent) void;
}

pub fn MouseDownHandler(comptime Context: type) type {
    return fn (Context, MouseDownEvent) EventResult;
}

pub fn MouseUpHandler(comptime Context: type) type {
    return fn (Context, MouseUpEvent) void;
}

pub fn MouseScrollHandler(comptime Context: type) type {
    return fn (Context, MouseScrollEvent) void;
}

pub fn HoverChangeHandler(comptime Context: type) type {
    return fn (Context, HoverChangeEvent) void;
}

pub fn IntervalHandler(comptime Context: type) type {
    return fn (Context, IntervalEvent) void;
}

pub const EventResult = enum(u1) {
    /// Allow the engine to continue with the default behavior.
    /// Usually these means the event continues to propagate down to the children.
    default = 0,
    /// Stop the event from propagating to children.
    stop = 1,
};