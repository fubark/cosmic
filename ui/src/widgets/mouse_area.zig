const stdx = @import("stdx");
const platform = @import("platform");

const ui = @import("../ui.zig");

/// Provides mouse over events for a child widget.
pub const MouseHoverArea = struct {
    props: struct {
        onHoverChange: ?stdx.Function(fn (bool, i16, i16) void) = null,
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