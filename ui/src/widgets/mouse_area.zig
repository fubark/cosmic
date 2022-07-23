const stdx = @import("stdx");
const platform = @import("platform");

const ui = @import("../ui.zig");

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
        c.addMouseUpHandler(c.node, onMouseUp);
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