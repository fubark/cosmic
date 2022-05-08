const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const MouseDownEvent = platform.MouseDownEvent;

const ui = @import("../ui.zig");
const Padding = ui.widgets.Padding;
const Text = ui.widgets.Text;

pub const TextButton = struct {
    const Self = @This();

    props: struct {
        onClick: ?Function(MouseUpEvent) = null,
        bg_color: Color = Color.init(220, 220, 220, 255),
        bg_pressed_color: Color = Color.Gray.darker(),
        border_size: f32 = 1,
        border_color: Color = Color.Gray,
        corner_radius: f32 = 0,
        text: ?[]const u8,
    },

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        return c.decl(Button, .{
            .onClick = self.props.onClick,
            .bg_color = self.props.bg_color,
            .bg_pressed_color = self.props.bg_pressed_color,
            .border_size = self.props.border_size,
            .border_color = self.props.border_color,
            .corner_radius = self.props.corner_radius,
            .child = c.decl(Padding, .{
                .padding = 10,
                .child = c.decl(Text, .{
                    .text = self.props.text,
                }),
            }),
        });
    }
};

pub const Button = struct {
    const Self = @This();

    props: struct {
        onClick: ?Function(MouseUpEvent) = null,
        bg_color: Color = Color.init(220, 220, 220, 255),
        bg_pressed_color: Color = Color.Gray.darker(),
        border_size: f32 = 1,
        border_color: Color = Color.Gray,
        corner_radius: f32 = 0,
        child: ui.FrameId = ui.NullFrameId,
        halign: ui.HAlign = .Center,
    },

    pressed: bool,

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.pressed = false;
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
        c.addMouseUpHandler(c.node, handleMouseUpEvent);
    }

    fn handleMouseUpEvent(node: *ui.Node, e: ui.Event(MouseUpEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            if (self.pressed) {
                self.pressed = false;
                if (self.props.onClick) |cb| {
                    cb.call(e.val);
                }
            }
        }
    }

    fn handleMouseDownEvent(node: *ui.Node, e: ui.Event(MouseDownEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            e.ctx.requestFocus(onBlur);
            self.pressed = true;
        }
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        var self = node.getWidget(Self);
        self.pressed = false;
    }

    /// Defaults to a fixed size if there is no child widget.
    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        const cstr = c.getSizeConstraint();

        var res: ui.LayoutSize = cstr;
        if (self.props.child != ui.NullFrameId) {
            const child_node = c.getNode().children.items[0];
            var child_size = c.computeLayout(child_node, cstr);
            child_size.cropTo(cstr);
            res = child_size;
            if (c.prefer_exact_width) {
                res.width = cstr.width;
            }
            if (c.prefer_exact_height) {
                res.height = cstr.height;
            }
            switch (self.props.halign) {
                .Left => c.setLayout(child_node, ui.Layout.initWithSize(0, 0, child_size)),
                .Center => c.setLayout(child_node, ui.Layout.initWithSize((res.width - child_size.width)/2, 0, child_size)),
                .Right => c.setLayout(child_node, ui.Layout.initWithSize(res.width - child_size.width, 0, child_size)),
            }
            return res;
        } else {
            res = ui.LayoutSize.init(150, 40);
            if (c.prefer_exact_width) {
                res.width = cstr.width;
            }
            if (c.prefer_exact_height) {
                res.height = cstr.height;
            }
            return res;
        }
    }

    pub fn render(self: *Self, ctx: *ui.RenderContext) void {
        const alo = ctx.getAbsLayout();
        const g = ctx.getGraphics();
        if (!self.pressed) {
            g.setFillColor(self.props.bg_color);
        } else {
            g.setFillColor(self.props.bg_pressed_color);
        }
        if (self.props.corner_radius > 0) {
            g.fillRoundRect(alo.x, alo.y, alo.width, alo.height, self.props.corner_radius);
            g.setLineWidth(self.props.border_size);
            g.setStrokeColor(self.props.border_color);
            g.drawRoundRect(alo.x, alo.y, alo.width, alo.height, self.props.corner_radius);
        } else {
            g.fillRect(alo.x, alo.y, alo.width, alo.height);
            g.setLineWidth(self.props.border_size);
            g.setStrokeColor(self.props.border_color);
            g.drawRect(alo.x, alo.y, alo.width, alo.height);
        }
    }
};
