const std = @import("std");
const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const MouseDownEvent = platform.MouseDownEvent;
const MouseMoveEvent = platform.MouseMoveEvent;

const ui = @import("../ui.zig");
const Node = ui.Node;

pub const Slider = struct {
    const Self = @This();

    const ThumbWidth = 25;
    const Height = 25;

    props: struct {
        init_val: i32 = 0,
        min_val: i32 = 0,
        max_val: i32 = 100,
        onChangeEnd: ?Function(fn (i32) void) = null,
        onChange: ?Function(fn (i32) void) = null,
        thumb_color: Color = Color.Blue,
    },

    last_value: i32,
    value: i32,
    pressed: bool,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        std.debug.assert(self.props.min_val <= self.props.max_val);
        self.value = self.props.init_val;
        self.pressed = false;
        if (self.value < self.props.min_val) {
            self.value = self.props.min_val;
        } else if (self.value > self.props.max_val) {
            self.value = self.props.max_val;
        }

        c.addMouseDownHandler(c.node, handleMouseDownEvent);
    }

    fn handleMouseUpEvent(node: *Node, e: ui.Event(MouseUpEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left and self.pressed) {
            self.pressed = false;
            e.ctx.removeMouseUpHandler(*Node, handleMouseUpEvent);
            e.ctx.removeMouseMoveHandler(*Node, handleMouseMoveEvent);
            self.updateValueFromMouseX(node, e.val.x);
            if (self.last_value != self.value) {
                if (self.props.onChange) |cb| {
                    cb.call(.{ self.value });
                }
                if (self.props.onChangeEnd) |cb| {
                    cb.call(.{ self.value });
                }
            }
        }
    }

    fn handleMouseDownEvent(node: *Node, e: ui.Event(MouseDownEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            self.pressed = true;
            self.last_value = self.value;
            e.ctx.removeMouseUpHandler(*Node, handleMouseUpEvent);
            e.ctx.addGlobalMouseUpHandler(node, handleMouseUpEvent);
            e.ctx.addMouseMoveHandler(node, handleMouseMoveEvent);
        }
    }

    fn updateValueFromMouseX(self: *Self, node: *Node, mouse_x: i16) void {
        const num_values = self.props.max_val - self.props.min_val + 1;
        const rel_x = @intToFloat(f32, mouse_x) - node.abs_pos.x - @intToFloat(f32, ThumbWidth)/2;
        const ratio = rel_x / (node.layout.width - ThumbWidth);
        self.value = @floatToInt(i32, @intToFloat(f32, self.props.min_val) + ratio * @intToFloat(f32, num_values));
        if (self.value > self.props.max_val) {
            self.value = self.props.max_val;
        } else if (self.value < self.props.min_val) {
            self.value = self.props.min_val;
        }
    }

    fn handleMouseMoveEvent(node: *Node, e: ui.Event(MouseMoveEvent)) void {
        var self = node.getWidget(Self);
        self.updateValueFromMouseX(node, e.val.x);
        if (self.last_value != self.value) {
            if (self.props.onChange) |cb| {
                cb.call(.{ self.value });
            }
        }
        self.last_value = self.value;
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        _ = self;
        _ = c;
        return ui.NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        _ = self;
        const min_width: f32 = 200;
        const min_height = Height;
        const cstr = c.getSizeConstraint();
        
        var res = ui.LayoutSize.init(min_width, min_height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, ctx: *ui.RenderContext) void {
        const g = ctx.g;
        const alo = ctx.getAbsLayout();
        g.setFillColor(Color.LightGray);
        g.fillRect(alo.x, alo.y+alo.height/2 - 5, alo.width, 10);

        const val_range = self.props.max_val - self.props.min_val;
        const ratio = @intToFloat(f32, self.value - self.props.min_val) / @intToFloat(f32, val_range);
        var thumb_x = alo.x + (alo.width - ThumbWidth) * ratio;
        g.setFillColor(self.props.thumb_color);
        g.fillRect(thumb_x, alo.y, ThumbWidth, Height);
    }
};