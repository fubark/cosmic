const stdx = @import("stdx");
const platform = @import("platform");

const ui = @import("../ui.zig");
const log = stdx.log.scoped(.mouse_area);

/// Provides drag events for a child widget.
/// Once dragging has started, it gets drag focus and will receive dragmove and dragend events outside of its bounds.
pub const MouseDragArea = struct {
    props: struct {
        hitTest: stdx.Function(fn (i16, i16) bool) = .{},
        onDragStart: stdx.Function(fn (ui.DragStartEvent) void) = .{},
        onDragMove: stdx.Function(fn (ui.DragMoveEvent) void) = .{},
        onDragEnd: stdx.Function(fn (i16, i16) void) = .{},
        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn init(self: *MouseDragArea, ctx: *ui.InitContext) void {
        ctx.addMouseDownHandler(self, onMouseDown);
    }

    pub fn build(self: *MouseDragArea, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    fn onMouseDown(self: *MouseDragArea, e: ui.MouseDownEvent) ui.EventResult {
        if (self.props.hitTest.isPresent()) {
            if (!self.props.hitTest.call(.{ e.val.x, e.val.y })) {
                return .default;
            }
        }
        if (self.props.onDragStart.isPresent()) {
            const start_e = ui.DragStartEvent{
                .src_x = @floatToInt(u32, e.ctx.node.abs_bounds.min_x),
                .src_y = @floatToInt(u32, e.ctx.node.abs_bounds.min_y),
                .x = e.val.x,
                .y = e.val.y,
            };
            self.props.onDragStart.call(.{ start_e });
        }
        e.ctx.setGlobalMouseMoveHandler(self, onMouseMove);
        e.ctx.setGlobalMouseUpHandler(self, onMouseUp);
        e.ctx.requestCaptureMouse(true);
        return .stop;
    }

    fn onMouseMove(self: *MouseDragArea, e: ui.MouseMoveEvent) void {
        if (self.props.onDragMove.isPresent()) {
            const move_e = ui.DragMoveEvent{
                .ctx = e.ctx,
                .x = e.val.x,
                .y = e.val.y,
            };
            self.props.onDragMove.call(.{ move_e });
        }
    }

    fn onMouseUp(self: *MouseDragArea, e: ui.MouseUpEvent) void {
        if (self.props.onDragEnd.isPresent()) {
            self.props.onDragEnd.call(.{ e.val.x, e.val.y });
        }
        e.ctx.clearGlobalMouseMoveHandler();
        e.ctx.clearGlobalMouseUpHandler();
        e.ctx.requestCaptureMouse(false);
    }
};

/// Provides mouse over events for a child widget.
pub const MouseHoverArea = struct {
    props: struct {
        hitTest: stdx.Function(fn (i16, i16) bool) = .{},
        onHoverChange: stdx.Function(fn (ui.HoverChangeEvent) void) = .{},
        onHoverMove: stdx.Function(fn (i16, i16) void) = .{},
        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn build(self: *MouseHoverArea, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn init(self: *MouseHoverArea, c: *ui.InitContext) void {
        if (self.props.hitTest.isPresent()) {
            c.setHoverChangeHandler2(self, onHoverChange, hitTest);
        } else {
            c.setHoverChangeHandler(self, onHoverChange);
        }
    }

    fn onHoverChange(self: *MouseHoverArea, e: ui.HoverChangeEvent) void {
        if (self.props.onHoverChange.isPresent()) {
            self.props.onHoverChange.call(.{ e });
        }
        if (e.hovered) {
            e.ctx.setGlobalMouseMoveHandler(self, onMouseMove);
        } else {
            e.ctx.clearGlobalMouseMoveHandler();
        }
    }

    fn onMouseMove(self: *MouseHoverArea, e: ui.MouseMoveEvent) void {
        if (self.props.onHoverMove.isPresent()) {
            self.props.onHoverMove.call(.{ e.val.x, e.val.y });
        }
    }

    fn hitTest(self: *MouseHoverArea, x: i16, y: i16) bool {
        return self.props.hitTest.call(.{ x, y });
    }
};

/// Provides mouse events for child widget.
pub const MouseArea = struct {
    props: struct {
        onClick: stdx.Function(fn (ui.MouseUpEvent) void) = .{},
        child: ui.FrameId = ui.NullFrameId,
    },

    pressed: bool,

    pub fn build(self: *MouseArea, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn init(self: *MouseArea, c: *ui.InitContext) void {
        self.pressed = false;
        c.addMouseDownHandler(c.node, onMouseDown);
        c.setMouseUpHandler(c.node, onMouseUp);
    }

    fn onMouseUp(node: *ui.Node, e: ui.MouseUpEvent) void {
        var self = node.getWidget(MouseArea);
        if (e.val.button == .Left) {
            if (self.pressed) {
                self.pressed = false;
                if (self.props.onClick.isPresent()) {
                    self.props.onClick.call(.{ e });
                }
            }
        }
    }

    fn onMouseDown(node: *ui.Node, e: ui.MouseDownEvent) ui.EventResult {
        var self = node.getWidget(MouseArea);
        if (e.val.button == .Left) {
            e.ctx.requestFocus(onBlur);
            self.pressed = true;
        }
        return .default;
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        var self = node.getWidget(MouseArea);
        self.pressed = false;
    }
};