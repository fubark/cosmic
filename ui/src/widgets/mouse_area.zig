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
        _ = self;
        c.setHoverChangeHandler(c.node, onHoverChange);
    }

    pub fn onHoverChange(node: *ui.Node, e: ui.HoverChangeEvent) void {
        var self = node.getWidget(MouseHoverArea);
        if (self.props.onHoverChange) |cb| {
            cb.call(.{ e.val.hovered, e.val.x, e.val.y });
        }
    }
};

/// Provides mouse events for child widget.
pub const MouseArea = struct {
    props: struct {
        onClick: ?stdx.Function(fn (platform.MouseUpEvent) void) = null,
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
                if (self.props.onClick) |cb| {
                    cb.call(.{ e.val });
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
        return .Continue;
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        var self = node.getWidget(MouseArea);
        self.pressed = false;
    }
};