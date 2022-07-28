const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const w = ui.widgets;
const log = stdx.log.scoped(.button);

pub const TextButton = struct {
    props: struct {
        onClick: ?Function(fn (platform.MouseUpEvent) void) = null,
        bg_color: Color = Color.init(220, 220, 220, 255),
        bg_pressed_color: Color = Color.Gray.darker(),
        border_size: f32 = 1,
        border_color: Color = Color.Gray,
        corner_radius: f32 = 0,
        text: ?[]const u8,
    },

    pub fn build(self: *TextButton, _: *ui.BuildContext) ui.FrameId {
        return w.Button(.{
            .onClick = self.props.onClick,
            .bg_color = self.props.bg_color,
            .bg_pressed_color = self.props.bg_pressed_color,
            .border_size = self.props.border_size,
            .border_color = self.props.border_color,
            .corner_radius = self.props.corner_radius },
            w.Padding(.{ .padding = 10 },
                w.Text(.{
                    .text = self.props.text,
                }),
            ),
        );
    }
};

/// Starts with child's size. If no child widget, it will use a default size. Then grows to minimum constraints.
pub const Button = struct {
    props: struct {
        onClick: ?Function(fn (platform.MouseUpEvent) void) = null,
        bg_color: Color = Color.init(220, 220, 220, 255),
        bg_pressed_color: Color = Color.Gray.darker(),
        border_size: f32 = 1,
        border_color: Color = Color.Gray,
        corner_radius: f32 = 0,
        child: ui.FrameId = ui.NullFrameId,
        halign: ui.HAlign = .Center,
    },

    pressed: bool,

    pub fn build(self: *Button, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn init(self: *Button, c: *ui.InitContext) void {
        self.pressed = false;
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
        c.setMouseUpHandler(c.node, handleMouseUpEvent);
    }

    fn handleMouseUpEvent(node: *ui.Node, e: ui.MouseUpEvent) void {
        var self = node.getWidget(Button);
        if (e.val.button == .Left) {
            if (self.pressed) {
                self.pressed = false;
                if (self.props.onClick) |cb| {
                    cb.call(.{ e.val });
                }
            }
        }
    }

    fn handleMouseDownEvent(node: *ui.Node, e: ui.MouseDownEvent) ui.EventResult {
        var self = node.getWidget(Button);
        if (e.val.button == .Left) {
            e.ctx.requestFocus(onBlur);
            self.pressed = true;
        }
        return .default;
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        var self = node.getWidget(Button);
        self.pressed = false;
    }

    pub fn layout(self: *Button, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        if (self.props.child != ui.NullFrameId) {
            const child_node = c.getNode().children.items[0];
            const child_size = c.computeLayoutWithMax(child_node, cstr.max_width, cstr.max_height);
            var res = child_size;
            res.growToMin(cstr);
            switch (self.props.halign) {
                .Left => c.setLayout(child_node, ui.Layout.initWithSize(0, 0, child_size)),
                .Center => c.setLayout(child_node, ui.Layout.initWithSize((res.width - child_size.width)/2, 0, child_size)),
                .Right => c.setLayout(child_node, ui.Layout.initWithSize(res.width - child_size.width, 0, child_size)),
            }
            return res;
        } else {
            var res = ui.LayoutSize.init(150, 40);
            res.growToMin(cstr);
            return res;
        }
    }

    pub fn render(self: *Button, ctx: *ui.RenderContext) void {
        const bounds = ctx.getAbsBounds();
        const g = ctx.getGraphics();
        if (!self.pressed) {
            g.setFillColor(self.props.bg_color);
        } else {
            g.setFillColor(self.props.bg_pressed_color);
        }
        if (self.props.corner_radius > 0) {
            ctx.fillRoundBBox(bounds, self.props.corner_radius);
            g.setLineWidth(self.props.border_size);
            g.setStrokeColor(self.props.border_color);
            ctx.drawRoundBBox(bounds, self.props.corner_radius);
        } else {
            ctx.fillBBox(bounds);
            g.setLineWidth(self.props.border_size);
            g.setStrokeColor(self.props.border_color);
            ctx.drawBBox(bounds);
        }
    }
};
