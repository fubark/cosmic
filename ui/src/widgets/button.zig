const std = @import("std");
const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const w = ui.widgets;
const log = stdx.log.scoped(.button);

const NullId = std.math.maxInt(u32);

pub const TextButton = struct {
    props: struct {
        onClick: Function(fn (ui.MouseUpEvent) void) = .{},
        text: []const u8 = "",
        icon: ui.IconDecl = .{ .image_id = NullId, .tint = undefined },
    },

    pub const Style = struct {
        button: ?Button.Style = null,
    };

    pub const ComputedStyle = struct {
        button: ?Button.Style = null,
    };

    pub fn build(self: *TextButton, ctx: *ui.BuildContext) ui.FrameId {
        var body: ui.FrameId = undefined;
        if (self.props.icon.image_id == NullId) {
            body = w.Text(.{
                .text = self.props.text,
            });
        } else {
            body = w.Row(.{}, &.{
                w.Image(.{ .imageId = self.props.icon.image_id, .tint = self.props.icon.tint }),
                w.Text(.{
                    .text = self.props.text,
                }),
            });
        }

        const style = ctx.getStyle(TextButton);
        const button_style: ?*const Button.Style = if (style.button != null) &style.button.? else null;
        return w.Button(.{
            .onClick = self.props.onClick,
            .style = button_style, },
            w.Padding(.{ .padding = 10 },
                body,
            ),
        );
    }
};

pub const ButtonMods = packed union {
    inner: packed struct {
        pressed: bool,
    },
    value: u8,
};

/// Starts with child's size. If no child widget, it will use a default size. Then grows to minimum constraints.
pub const Button = struct {
    props: struct {
        onClick: Function(fn (ui.MouseUpEvent) void) = .{},
        child: ui.FrameId = ui.NullFrameId,
        halign: ui.HAlign = .center,
    },

    mods: ButtonMods = ButtonMods{ .value = 0 },

    pub const Style = struct {
        bgColor: ?Color = null,
        bgColorPressed: ?Color = null,
        borderSize: ?f32 = null,
        borderColor: ?Color = null,
        cornerRadius: ?f32 = null,
    };

    pub const ComputedStyle = struct {
        bgColor: Color = Color.init(220, 220, 220, 255),
        borderSize: f32 = 1,
        borderColor: Color = Color.Gray,
        cornerRadius: f32 = 0,

        pub fn defaultUpdate(style: *ComputedStyle, mods: ButtonMods) void {
            if (mods.inner.pressed) {
                style.bgColor = Color.Gray.darker();
            }
        }
    };

    pub fn build(self: *Button, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn init(self: *Button, c: *ui.InitContext) void {
        _ = self;
        c.setMouseDownHandler(c.node, handleMouseDownEvent);
        c.setMouseUpHandler(c.node, handleMouseUpEvent);
    }

    fn handleMouseUpEvent(node: *ui.Node, e: ui.MouseUpEvent) void {
        var self = node.getWidget(Button);
        if (e.val.button == .left) {
            if (self.mods.inner.pressed) {
                self.mods.inner.pressed = false;
                if (self.props.onClick.isPresent()) {
                    self.props.onClick.call(.{ e });
                }
            }
        }
    }

    fn handleMouseDownEvent(node: *ui.Node, e: ui.MouseDownEvent) ui.EventResult {
        var self = node.getWidget(Button);
        if (e.val.button == .left) {
            e.ctx.requestFocus(.{ .onBlur = onBlur });
            self.mods.inner.pressed = true;
            // TODO: trigger compute style.
            return .stop;
        }
        return .default;
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        var self = node.getWidget(Button);
        self.mods.inner.pressed = false;
    }

    pub fn layout(self: *Button, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        if (self.props.child != ui.NullFrameId) {
            const child_node = c.getNode().children.items[0];
            const child_size = c.computeLayoutWithMax(child_node, cstr.max_width, cstr.max_height);
            var res = child_size;
            res.growToMin(cstr);
            switch (self.props.halign) {
                .left => c.setLayout(child_node, ui.Layout.initWithSize(0, 0, child_size)),
                .center => c.setLayout(child_node, ui.Layout.initWithSize((res.width - child_size.width)/2, 0, child_size)),
                .right => c.setLayout(child_node, ui.Layout.initWithSize(res.width - child_size.width, 0, child_size)),
            }
            return res;
        } else {
            var res = ui.LayoutSize.init(150, 40);
            res.growToMin(cstr);
            return res;
        }
    }

    pub fn render(self: *Button, ctx: *ui.RenderContext) void {
        _ = self;
        const style = ctx.getStyle(Button);
        const bounds = ctx.getAbsBounds();
        const g = ctx.getGraphics();
        g.setFillColor(style.bgColor);
        if (style.cornerRadius > 0) {
            ctx.fillRoundBBox(bounds, style.cornerRadius);
            g.setLineWidth(style.borderSize);
            g.setStrokeColor(style.borderColor);
            ctx.drawRoundBBox(bounds, style.cornerRadius);
        } else {
            ctx.fillBBox(bounds);
            g.setLineWidth(style.borderSize);
            g.setStrokeColor(style.borderColor);
            ctx.drawBBox(bounds);
        }
    }
};