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
const log = stdx.log.scoped(.slider);

pub const Slider = SliderBase(false);
pub const SliderFloat = SliderBase(true);

pub fn SliderBase(comptime is_float: bool) type {
    const Value = if (is_float) f32 else i32;
    return struct {
        props: struct {
            init_val: Value = 0,
            min_val: Value = 0,
            max_val: Value = if (is_float) 1 else 100,
            onChangeEnd: ?Function(fn (Value) void) = null,
            onChange: ?Function(fn (Value) void) = null,
            thumb_color: Color = Color.Blue,
            display_value: bool = true,
        },

        drag_start_value: Value,
        last_value: Value,
        value: Value,
        pressed: bool,
        node: *ui.Node,

        const Self = @This();
        const ThumbWidth = 25;
        const Height = 25;

        pub fn init(self: *Self, c: *ui.InitContext) void {
            std.debug.assert(self.props.min_val <= self.props.max_val);
            self.node = c.node;
            self.value = self.props.init_val;
            self.pressed = false;
            if (self.value < self.props.min_val) {
                self.value = self.props.min_val;
            } else if (self.value > self.props.max_val) {
                self.value = self.props.max_val;
            }

            c.addMouseDownHandler(c.node, handleMouseDownEvent);
        }

        fn handleMouseUpEvent(node: *ui.Node, e: ui.Event(MouseUpEvent)) void {
            var self = node.getWidget(Self);
            if (e.val.button == .Left and self.pressed) {
                self.pressed = false;
                self.updateValueFromMouseX(node, e.val.x);
                if (self.drag_start_value != self.value) {
                    if (self.props.onChange) |cb| {
                        cb.call(.{ self.value });
                    }
                    if (self.props.onChangeEnd) |cb| {
                        cb.call(.{ self.value });
                    }
                }
            }
            e.ctx.clearGlobalMouseUpHandler();
            e.ctx.clearGlobalMouseMoveHandler();
        }

        fn handleMouseDownEvent(node: *ui.Node, e: ui.Event(MouseDownEvent)) ui.EventResult {
            var self = node.getWidget(Self);
            if (e.val.button == .Left) {
                self.pressed = true;
                self.last_value = self.value;
                self.drag_start_value = self.value;
                e.ctx.setGlobalMouseUpHandler(node, handleMouseUpEvent);
                e.ctx.setGlobalMouseMoveHandler(node, handleMouseMoveEvent);
            }
            return .default;
        }

        fn updateValueFromMouseX(self: *Self, node: *ui.Node, mouse_x: i16) void {
            const num_values = self.props.max_val - self.props.min_val + 1;
            const rel_x = @intToFloat(f32, mouse_x) - node.abs_bounds.min_x - @intToFloat(f32, ThumbWidth)/2;
            const ratio = rel_x / (node.layout.width - ThumbWidth);
            if (is_float) {
                self.value = self.props.min_val + ratio * (self.props.max_val - self.props.min_val);
            } else {
                self.value = @floatToInt(i32, @intToFloat(f32, self.props.min_val) + ratio * @intToFloat(f32, num_values));
            }
            if (self.value > self.props.max_val) {
                self.value = self.props.max_val;
            } else if (self.value < self.props.min_val) {
                self.value = self.props.min_val;
            }
        }

        fn handleMouseMoveEvent(node: *ui.Node, e: ui.Event(MouseMoveEvent)) void {
            var self = node.getWidget(Self);
            self.updateValueFromMouseX(node, e.val.x);
            if (self.last_value != self.value) {
                if (self.props.onChange) |cb| {
                    cb.call(.{ self.value });
                }
            }
            self.last_value = self.value;
        }

        pub fn layout(_: *Self, c: *ui.LayoutContext) ui.LayoutSize {
            const min_width: f32 = 200;
            const min_height = Height;
            const cstr = c.getSizeConstraints();

            var res = ui.LayoutSize.init(min_width, min_height);
            res.growToWidth(cstr.min_width);
            res.cropToWidth(cstr.max_width);
            return res;
        }

        pub fn getBarLayout(self: Self) ui.Layout {
            return ui.Layout.init(ThumbWidth/2, self.node.layout.height/2 - 5, self.node.layout.width - ThumbWidth, 10);
        }

        pub fn getThumbLayoutX(self: Self) f32 {
            const val_range = self.props.max_val - self.props.min_val;
            const ratio = @intToFloat(f32, self.value - self.props.min_val) / @intToFloat(f32, val_range);
            return (self.node.layout.width - ThumbWidth) * ratio + ThumbWidth/2;
        }

        pub fn render(self: *Self, ctx: *ui.RenderContext) void {
            const g = ctx.gctx;
            const bounds = ctx.getAbsBounds();
            const gutter_x = bounds.min_x + ThumbWidth/2;
            g.setFillColor(Color.init(40, 40, 40, 255));
            const center_y = bounds.computeCenterY();
            g.fillRectBounds(gutter_x, center_y - 5, bounds.max_x - ThumbWidth/2, center_y + 5);

            const val_range = self.props.max_val - self.props.min_val;
            const ratio = if (is_float) (self.value - self.props.min_val) / val_range else @intToFloat(f32, self.value - self.props.min_val) / @intToFloat(f32, val_range);
            const width = bounds.computeWidth();
            const thumb_x = bounds.min_x + (width - ThumbWidth) * ratio;
            g.setFillColor(self.props.thumb_color);
            g.fillRect(thumb_x, bounds.min_y, ThumbWidth, Height);

            if (self.props.display_value) {
                const font_id = g.getDefaultFontId();
                g.setFont(font_id, 12);
                g.setFillColor(Color.White);
                if (is_float) {
                    g.fillTextExt(gutter_x + 5, bounds.min_y + Height/2, "{d:.2}", .{ self.value }, .{
                        .baseline = .Middle,
                    });
                } else {
                    g.fillTextExt(gutter_x + 5, bounds.min_y + Height/2, "{}", .{ self.value }, .{
                        .baseline = .Middle,
                    });
                }
            }
        }
    };
}