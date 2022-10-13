const std = @import("std");
const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.button);

const NullId = std.math.maxInt(u32);

pub const IconButton = struct {
    props: *const struct {
        onClick: Function(fn (ui.MouseUpEvent) void) = .{},
        icon: ui.IconT,
        halign: ui.HAlign = .center,
    },

    pub const Style = struct {
        bgColor: ?Color = null,
        border: ?u.BorderStyle = null,
        padding: ?f32 = null,
    };

    pub const ComputedStyle = struct {
        bgColor: Color = Color.init(220, 220, 220, 255),
        border: ?u.BorderStyle = null,
        padding: f32 = 10,
    };

    pub fn build(self: *IconButton, ctx: *ui.BuildContext) ui.FramePtr {
        var body: ui.FramePtr = .{};

        const style = ctx.getStyle(IconButton);
        if (self.props.icon.image_id != NullId) {
            body = u.Image(.{ .imageId = self.props.icon.image_id, .tint = self.props.icon.tint, .width = self.props.icon.size, .height = self.props.icon.size });
        }

        const b_style = u.ButtonStyle{
            .bgColor = style.bgColor,
            .border = style.border,
        };
        return u.Button(.{
            .onClick = self.props.onClick,
            .halign = self.props.halign,
            .style = b_style, },
            u.Padding(.{ .padding = style.padding },
                body,
            ),
        );
    }
};

pub const TextButton = struct {
    props: *const struct {
        onClick: Function(fn (ui.MouseUpEvent) void) = .{},
        text: []const u8 = "",
        icon: ui.IconT = ui.Icon(NullId, .{}),
    },

    pub const Style = struct {
        border: ?u.BorderStyle = null,
        bgColor: ?Color = null,
        padding: ?f32 = null,
        text: ?u.TextStyle = null,
        halign: ?ui.HAlign = null,
    };

    pub const ComputedStyle = struct {
        border: ?u.BorderStyle = null,
        bgColor: Color = Color.init(220, 220, 220, 255),
        padding: f32 = 10,
        text: ?u.TextStyle = null,
        halign: ui.HAlign = .center,
    };

    pub fn build(self: *TextButton, ctx: *ui.BuildContext) ui.FramePtr {
        var body: ui.FramePtr = undefined;

        const style = ctx.getStyle(TextButton);
        const text_style = ctx.getStylePropPtr(style, "text");
        if (self.props.icon.image_id == NullId) {
            body = u.Text(.{
                .text = self.props.text,
                .style = text_style,
            });
        } else {
            body = u.Row(.{ .valign = .center }, &.{
                u.Image(.{ .imageId = self.props.icon.image_id, .tint = self.props.icon.tint, .width = self.props.icon.size, .height = self.props.icon.size }),
                u.Text(.{
                    .text = self.props.text,
                    .style = text_style,
                }),
            });
        }

        const b_style = u.ButtonStyle{
            .bgColor = style.bgColor,
            .border = style.border,
        };
        return u.Button(.{
            .onClick = self.props.onClick,
            .halign = style.halign,
            .style = b_style, },
            u.Padding(.{ .padding = style.padding },
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
    props: *const struct {
        onClick: Function(fn (ui.MouseUpEvent) void) = .{},
        child: ui.FramePtr = .{},
        halign: ui.HAlign = .center,
        valign: ui.VAlign = .center,
    },

    mods: ButtonMods = ButtonMods{ .value = 0 },

    pub const Style = struct {
        bgColor: ?Color = null,
        border: ?u.BorderStyle = null,
    };

    pub const ComputedStyle = struct {
        bgColor: Color = Color.init(220, 220, 220, 255),
        border: ?u.BorderStyle = null,

        pub fn defaultUpdate(style: *ComputedStyle, mods: ButtonMods) void {
            if (mods.inner.pressed) {
                style.bgColor = Color.Gray.darker();
            }
        }
    };

    pub fn build(self: *Button, ctx: *ui.BuildContext) ui.FramePtr {
        const style = ctx.getStyle(Button);
        
        var b_style = u.BorderStyle{};
        ctx.overrideUserStyle(u.BorderT, &b_style, style.border);
        b_style.bgColor = style.bgColor;
        return u.Border(.{ .style = b_style }, self.props.child.dupe());
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
        if (self.props.child.isPresent()) {
            const border_node = c.getNode().children.items[0];
            var border_size = c.computeLayoutWithMax(border_node, cstr.max_width, cstr.max_height);
            const child_node = border_node.children.items[0];
            const child_size = child_node.layout;
            const border_extra_width = border_size.width - child_size.width;
            const border_extra_height = border_size.height - child_size.height;
            
            // Make border decorator just as big.
            border_size.growToMin(cstr);
            c.setLayout2(border_node, 0, 0, border_size.width, border_size.height);

            // Align child in the border decorator.
            var x: f32 = 0;
            var y: f32 = 0;

            switch (self.props.halign) {
                .left => {},
                .center => {
                    x = (border_size.width - border_extra_width - child_size.width)/2;
                },
                .right => {
                    x = border_size.width - border_extra_width - child_size.width;
                },
            }
            switch (self.props.valign) {
                .top => {},
                .center => {
                    y = (border_size.height - border_extra_height - child_size.height)/2;
                },
                .bottom => {
                    y = border_size.height - border_extra_height - child_size.height;
                },
            }
            c.setLayout2(child_node, x, y, child_size.width, child_size.height);

            return border_size;
        } else {
            var res = ui.LayoutSize.init(150, 40);
            res.growToMin(cstr);
            return res;
        }
    }
};