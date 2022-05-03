const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const Duration = stdx.time.Duration;
const Function = stdx.Function;
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const MouseDownEvent = platform.MouseDownEvent;
const MouseMoveEvent = platform.MouseMoveEvent;
const KeyDownEvent = platform.KeyDownEvent;
const graphics = @import("graphics");
const Color = graphics.Color;
const font = graphics.font;
const FontGroupId = graphics.font.FontGroupId;

const ui = @import("ui.zig");
const LayoutSize = ui.LayoutSize;
const Layout = ui.Layout;
const Node = ui.Node;
const InitContext = ui.InitContext;
const CommonContext = ui.CommonContext;
const BuildContext = ui.BuildContext;
const LayoutContext = ui.LayoutContext;
const RenderContext = ui.RenderContext;
const WidgetRef = ui.WidgetRef;
const Module = ui.Module;
const Config = ui.Config;
const TextMeasureId = ui.TextMeasureId;
const Event = ui.Event;
const IntervalEvent = ui.IntervalEvent;
const FrameId = ui.FrameId;
const FrameListPtr = ui.FrameListPtr;
const NullFrameId = ui.NullFrameId;
const Import = ui.Import;
const log = stdx.log.scoped(.widgets);

pub const BaseWidgets = &[_]Import{
    Import.init(Row),
    Import.init(Column),
    Import.init(Text),
    Import.init(ScrollView),
    Import.init(Slider),
    Import.init(Grow),
    Import.init(Padding),
    Import.init(Button),
    Import.init(TextButton),
    Import.init(TextEditor),
    Import.init(TextEditorInner),
    Import.init(TextField),
    Import.init(TextFieldInner),
    Import.init(Center),
    Import.init(ProgressBar),
    Import.init(Sized),
};

pub const Center = struct {
    const Self = @This();

    props: struct {
        child: FrameId = NullFrameId,
    },

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        const cstr = c.getSizeConstraint();

        if (self.props.child == NullFrameId) {
            return cstr;
        }

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayout(child, cstr);
        child_size.cropTo(cstr);

        c.setLayout(child, Layout.init((cstr.width - child_size.width)/2, (cstr.height - child_size.height)/2, child_size.width, child_size.height));
        return cstr;
    }
};

pub const Row = struct {
    const Self = @This();

    props: struct {
        bg_color: ?Color = null,
        flex: u32 = 1,

        /// Whether the row's width will shrink to the total width of it's children or expand to the parent container's width.
        /// Expands to the parent container's width by default.
        expand: bool = true,

        children: FrameListPtr = FrameListPtr.init(0, 0),
    },

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        return c.fragment(self.props.children);
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var cur_x: f32 = 0;
        var max_child_height: f32 = 0;

        const RowId = comptime Module(C).WidgetIdByType(Row);
        const GrowId = comptime Module(C).WidgetIdByType(Grow);

        // First pass computes non expanding children.
        var has_expanding_children = false;
        var flex_sum: u32 = 0;
        for (c.node.children.items) |it| {
            switch (it.type_id) {
                RowId => {
                    const row = it.getWidget(Row);
                    has_expanding_children = true;
                    flex_sum += row.props.flex;
                    continue;
                },
                GrowId => {
                    const grow = it.getWidget(Grow);
                    has_expanding_children = true;
                    flex_sum += grow.props.flex;
                    continue;
                },
                else => {},
            }
            var child_size = c.computeLayout(it, vacant_size);
            child_size.cropTo(vacant_size);
            c.setLayout(it, Layout.init(cur_x, 0, child_size.width, child_size.height));
            cur_x += child_size.width;
            vacant_size.width -= child_size.width;
            if (child_size.height > max_child_height) {
                max_child_height = child_size.height;
            }
        }

        if (has_expanding_children) {
            cur_x = 0;
            const flex_unit_size = vacant_size.width / @intToFloat(f32, flex_sum);

            var max_child_size = LayoutSize.init(0, vacant_size.height);
            for (c.node.children.items) |it| {
                var flex: u32 = undefined;
                switch (it.type_id) {
                    RowId => {
                        flex = it.getWidget(Row).props.flex;
                    },
                    GrowId => {
                        flex = it.getWidget(Grow).props.flex;
                    },
                    else => {
                        // Update the layout pos of sized children since this pass will include expanded children.
                        c.setLayoutPos(it, cur_x, 0);
                        cur_x += c.getLayout(it).width;
                        continue;
                    },
                }

                max_child_size.width = flex_unit_size * @intToFloat(f32, flex);
                var child_size = c.computeLayoutStretch(it, max_child_size, true, false);
                child_size.cropTo(max_child_size);
                c.setLayout(it, Layout.init(cur_x, 0, child_size.width, child_size.height));
                cur_x += child_size.width;
                if (child_size.height > max_child_height) {
                    max_child_height = child_size.height;
                }
            }
        }

        if (self.props.expand) {
            return LayoutSize.init(cstr.width, max_child_height);
        } else {
            return LayoutSize.init(cur_x, max_child_height);
        }
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        _ = self;
        const g = c.g;
        const alo = c.getAbsLayout();

        const props = self.props;

        if (props.bg_color != null) {
            g.setFillColor(props.bg_color.?);
            g.fillRect(alo.x, alo.y, alo.width, alo.height);
        }
        // TODO: draw border
    }
};

pub const ProgressBar = struct {
    const Self = @This();

    props: struct {
        max_val: f32 = 100,
        init_val: f32 = 0,
        bar_color: Color = Color.Blue,
    },

    value: f32,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        _ = c;
        self.value = self.props.init_val;
    }

    pub fn setValue(self: *Self, value: f32) void {
        self.value = value;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        const min_width = 200;
        const min_height = 25;

        const cstr = c.getSizeConstraint();
        var res = LayoutSize.init(min_width, min_height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        const g = c.g;
        const alo = c.getAbsLayout();

        g.setFillColor(Color.DarkGray);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);
        g.setFillColor(self.props.bar_color);
        const progress_width = (self.value / self.props.max_val) * alo.width;
        g.fillRect(alo.x, alo.y, progress_width, alo.height);
    }
};

pub const Text = struct {
    const Self = @This();

    props: struct {
        text: ?[]const u8,
        font_size: f32 = 20,
        color: Color = Color.Black,
    },

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        _ = c;
        return NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        if (self.props.text != null) {
            const font_gid = c.common.getDefaultFontGroup();
            const m = c.common.measureText(font_gid, self.props.font_size, self.props.text.?);
            return LayoutSize.init(m.width, m.height);
        } else {
            return LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        const g = c.g;
        const alo = c.getAbsLayout();

        if (self.props.text != null) {
            g.setFillColor(self.props.color);
            const font_gid = c.common.getDefaultFontGroup();
            g.setFontGroup(font_gid, self.props.font_size);
            g.fillText(alo.x, alo.y, self.props.text.?);
        }
    }
};

// TODO: Container with more comprehensive properties.
// pub const Container = struct {
//     const Self = @This();
// };

pub const Sized = struct {
    const Self = @This();

    props: struct {
        /// If width is not provided, this container will shrink to the child's width.
        width: ?f32 = null,

        /// If height is not provided, this container will shrink to the child's height.
        height: ?f32 = null,

        child: FrameId = NullFrameId,
    },

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        var child_cstr = c.getSizeConstraint();
        var prefer_exact_width = c.prefer_exact_width;
        var prefer_exact_height = c.prefer_exact_height;
        if (self.props.width) |width| {
            child_cstr.width = width;
            prefer_exact_width = true;
        }
        if (self.props.height) |height| {
            child_cstr.height = height;
            prefer_exact_height = true;
        }

        const child = c.getNode().children.items[0];
        const child_size = c.computeLayoutStretch(child, child_cstr, prefer_exact_width, prefer_exact_height);
        c.setLayout(child, Layout.init(0, 0, child_size.width, child_size.height));

        var res = LayoutSize.init(0, 0);
        res.width = self.props.width orelse child_size.width;
        res.height = self.props.height orelse child_size.height;
        return res;
    }
};

/// Lays out children vertically.
pub const Column = struct {
    const Self = @This();

    props: struct {
        bg_color: ?Color = null,
        flex: u32 = 1,

        /// Whether the columns's height will shrink to the total height of it's children or expand to the parent container's height.
        /// Expands to the parent container's height by default.
        expand: bool = true,

        children: FrameListPtr = FrameListPtr.init(0, 0),
    },

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        return c.fragment(self.props.children);
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var cur_y: f32 = 0;
        var max_child_width: f32 = 0;

        const ColumnId = comptime Module(C).WidgetIdByType(Column);
        const GrowId = comptime Module(C).WidgetIdByType(Grow);

        // First pass computes non expanding children.
        var has_expanding_children = false;
        var flex_sum: u32 = 0;
        for (c.node.children.items) |it| {
            switch (it.type_id) {
                ColumnId => {
                    const col = it.getWidget(Column);
                    has_expanding_children = true;
                    flex_sum += col.props.flex;
                    continue;
                },
                GrowId => {
                    const grow = it.getWidget(Grow);
                    has_expanding_children = true;
                    flex_sum += grow.props.flex;
                    continue;
                },
                else => {},
            }
            var child_size = c.computeLayout(it, vacant_size);
            child_size.cropTo(vacant_size);
            c.setLayout(it, Layout.init(0, cur_y, child_size.width, child_size.height));
            cur_y += child_size.height;
            vacant_size.height -= child_size.height;
            if (child_size.width > max_child_width) {
                max_child_width = child_size.width;
            }
        }

        if (has_expanding_children) {
            cur_y = 0;
            const flex_unit_size = vacant_size.height / @intToFloat(f32, flex_sum);

            var max_child_size = LayoutSize.init(vacant_size.width, 0);
            for (c.node.children.items) |it| {
                var flex: u32 = undefined;
                switch (it.type_id) {
                    ColumnId => {
                        flex = it.getWidget(Column).props.flex;
                    },
                    GrowId => {
                        flex = it.getWidget(Grow).props.flex;
                    },
                    else => {
                        // Update the layout pos of sized children since this pass will include expanded children.
                        c.setLayoutPos(it, 0, cur_y);
                        cur_y += c.getLayout(it).height;
                        continue;
                    },
                }

                max_child_size.height = flex_unit_size * @intToFloat(f32, flex);
                var child_size = c.computeLayoutStretch(it, max_child_size, false, true);
                child_size.cropTo(max_child_size);
                c.setLayout(it, Layout.init(0, cur_y, child_size.width, child_size.height));
                cur_y += child_size.height;
                if (child_size.width > max_child_width) {
                    max_child_width = child_size.width;
                }
            }
        }

        if (self.props.expand) {
            return LayoutSize.init(max_child_width, cstr.height);
        } else {
            return LayoutSize.init(max_child_width, cur_y);
        }
    }

    pub fn render(self: *Self, ctx: *RenderContext) void {
        _ = self;
        _ = ctx;
        // const g = c.g;
        // const n = c.node;

        const props = self.props;

        if (props.bg_color != null) {
            // g.setFillColor(props.bg_color.?);
            // g.fillRect(n.layout.x, n.layout.y, n.layout.width, n.layout.height);
        }
        // TODO: draw border
    }
};

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

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
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
        on_click: ?Function(MouseUpEvent) = null,
        bg_color: Color = Color.Gray.lighter(),
        bg_pressed_color: Color = Color.Gray.darker(),
        border_size: f32 = 1,
        border_color: Color = Color.Gray,
        corner_radius: f32 = 0,
        child: FrameId = NullFrameId,
    },

    pressed: bool,

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        self.pressed = false;
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
        c.addMouseUpHandler(c.node, handleMouseUpEvent);
    }

    fn handleMouseUpEvent(node: *Node, e: Event(MouseUpEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            if (self.pressed) {
                self.pressed = false;
                if (self.props.on_click) |cb| {
                    cb.call(e.val);
                }
            }
        }
    }

    fn handleMouseDownEvent(node: *Node, e: Event(MouseDownEvent)) void {
        _ = e;
        var self = node.getWidget(Self);
        self.pressed = true;
    }

    /// Defaults to a fixed size if there is no child widget.
    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        const cstr = c.getSizeConstraint();

        var res: LayoutSize = undefined;
        if (self.props.child != NullFrameId) {
            const child_node = c.getNode().children.items[0];
            var child_size = c.computeLayout(child_node, cstr);
            child_size.cropTo(cstr);
            c.setLayout(child_node, Layout.initWithSize(0, 0, child_size));
            res = child_size;
        } else {
            res = LayoutSize.init(150, 40);
        }
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        if (c.prefer_exact_height) {
            res.height = cstr.height;
        }
        return res;
    }

    pub fn render(self: *Self, ctx: *RenderContext) void {
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

pub const Slider = struct {
    const Self = @This();

    const ThumbWidth = 25;
    const Height = 25;

    props: struct {
        value: i32 = 0,
        minValue: i32 = 0,
        maxValue: i32 = 100,
        onChangeEnd: ?Function(i32) = null,
        onChange: ?Function(i32) = null,
    },

    value: i32,
    pressed: bool,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        std.debug.assert(self.props.minValue <= self.props.maxValue);
        self.value = self.props.value;
        self.pressed = false;
        if (self.value < self.props.minValue) {
            self.value = self.props.minValue;
        } else if (self.value > self.props.maxValue) {
            self.value = self.props.maxValue;
        }

        c.addMouseUpHandler(c.node, handleMouseUpEvent);
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
    }

    fn handleMouseUpEvent(node: *Node, e: Event(MouseUpEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left and self.pressed) {
            self.pressed = false;
            e.ctx.removeMouseMoveHandler(*Node, handleMouseMoveEvent);
            self.updateValueFromMouseX(node, e.val.x);
            if (self.props.onChangeEnd) |cb| {
                _ = cb;
                cb.call(self.value);
            }
        }
    }

    fn handleMouseDownEvent(node: *Node, e: Event(MouseDownEvent)) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            self.pressed = true;
            e.ctx.addMouseMoveHandler(node, handleMouseMoveEvent);
        }
    }

    fn updateValueFromMouseX(self: *Self, node: *Node, mouse_x: i16) void {
        const num_values = self.props.maxValue - self.props.minValue + 1;
        const rel_x = @intToFloat(f32, mouse_x) - node.layout.x - @intToFloat(f32, ThumbWidth)/2;
        const ratio = rel_x / (node.layout.width - ThumbWidth);
        self.value = @floatToInt(i32, @intToFloat(f32, self.props.minValue) + ratio * @intToFloat(f32, num_values));
        if (self.value > self.props.maxValue) {
            self.value = self.props.maxValue;
        } else if (self.value < self.props.minValue) {
            self.value = self.props.minValue;
        }
    }

    fn handleMouseMoveEvent(node: *Node, e: Event(MouseMoveEvent)) void {
        var self = node.getWidget(Self);
        self.updateValueFromMouseX(node, e.val.x);
        if (self.props.onChange) |cb| {
            cb.call(self.value);
        }
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        _ = c;
        return NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        _ = c;
        const min_width = ThumbWidth;
        const min_height = Height;
        const cstr = c.getSizeConstraint();
        const width = std.math.max(cstr.width, min_width);
        return LayoutSize.init(width, min_height);
    }

    pub fn render(self: *Self, ctx: *RenderContext) void {
        const g = ctx.g;
        const alo = ctx.getAbsLayout();
        g.setFillColor(Color.LightGray);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        const val_range = self.props.maxValue - self.props.minValue;
        const ratio = @intToFloat(f32, self.value - self.props.minValue) / @intToFloat(f32, val_range);
        var thumb_x = alo.x + (alo.width - ThumbWidth) * ratio;
        g.setFillColor(Color.Red);
        g.fillRect(thumb_x, alo.y, ThumbWidth, Height);
    }
};

/// Provides padding around a child widget.
pub const Padding = struct {
    const Self = @This();

    props: struct {
        pad_top: ?f32 = null,
        pad_right: ?f32 = null,
        pad_bottom: ?f32 = null,
        pad_left: ?f32 = null,
        padding: f32 = 10,
        child: FrameId = NullFrameId,
    },

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        _ = c;
        _ = self;
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;

        var pad_top = self.props.pad_top orelse self.props.padding;
        var pad_right = self.props.pad_right orelse self.props.padding;
        var pad_bottom = self.props.pad_bottom orelse self.props.padding;
        var pad_left = self.props.pad_left orelse self.props.padding;

        const h_pad = pad_left + pad_right;
        const v_pad = pad_top + pad_bottom;

        const cstr = c.getSizeConstraint();
        const node = c.getNode();
        if (node.children.items.len == 0) {
            return LayoutSize.init(h_pad, v_pad);
        }

        const child = node.children.items[0];
        if (!c.prefer_exact_width_or_height) {
            const child_cstr = cstr.toIncSize(-h_pad, -v_pad);
            var child_size = c.computeLayout(child, child_cstr);
            c.setLayout(child, Layout.init(pad_left, pad_top, child_size.width, child_size.height));
            return child_size.toIncSize(h_pad, v_pad);
        } else {
            const child_cstr = cstr.toIncSize(-h_pad, -v_pad);
            const child_size = c.computeLayoutStretch(child, child_cstr, c.prefer_exact_width, c.prefer_exact_height);
            c.setLayout(child, Layout.init(pad_left, pad_top, child_size.width, child_size.height));
            return child_size.toIncSize(h_pad, v_pad);
        }
    }
};

/// Grows a child widget's width, or height, or both depending on parent's preference.
/// Exposes a flex property for the parent which can be used or ignored.
pub const Grow = struct {
    const Self = @This();

    props: struct {
        child: FrameId = NullFrameId,
        flex: u32 = 1,

        /// By default, Grow will consider the parent prefs to determine which axis to grow.
        /// These will override those prefs.
        grow_width: ?bool = null,
        grow_height: ?bool = null,
    },

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        _ = c;
        _ = self;
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = c;
        return self.props.child;
    }

    /// Computes the child layout preferring to stretch it and returns the current constraint.
    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        const node = c.getNode();

        var prefer_exact_width = self.props.grow_width orelse c.prefer_exact_width;
        var prefer_exact_height = self.props.grow_height orelse c.prefer_exact_height;

        if (node.children.items.len == 0) {
            var res = LayoutSize.init(0, 0);
            if (prefer_exact_width) {
                res.width = cstr.width;
            }
            if (prefer_exact_height) {
                res.height = cstr.height;
            }
            return res;
        }

        const child = node.children.items[0];
        const child_size = c.computeLayoutStretch(child, cstr, prefer_exact_width, prefer_exact_height);
        var res = child_size;
        if (prefer_exact_width) {
            res.width = cstr.width;
        }
        if (prefer_exact_height) {
            res.height = cstr.height;
        }
        c.setLayout(child, Layout.init(0, 0, child_size.width, child_size.height));
        return res;
    }
};

/// Currently, the scrollbars do not contribute to the child container space and act like overlays.
/// Doing so would require more complex logic and would either need to recompute the layout or defer recompute to the next frame.
/// A similar effect can be achieved with padding or making the scrollbars thinner. People don't like big scrollbars anyway.
pub const ScrollView = struct {
    const Self = @This();
    const bar_size = 15;

    props: struct {
        children: FrameListPtr = FrameListPtr.init(0, 0),
    },

    /// Internal vars. They should not be modified after the layout phase.
    /// Adjusting the scroll pos after layout and before render must call setScrollPosAfterLayout()
    scroll_x: f32,
    scroll_y: f32,
    scroll_width: f32,
    scroll_height: f32,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        _ = c;
        self.scroll_x = 0;
        self.scroll_y = 0;
        self.scroll_width = 0;
        self.scroll_height = 0;
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        return c.fragment(self.props.children);
    }

    /// In some cases, it's desirable to change the scroll view after the layout phase (when scroll width/height is updated) and before the render phase.
    /// eg. Scroll to cursor view.
    /// Since layout has already run, the children need to be repositioned.
    pub fn setScrollPosAfterLayout(self: *Self, node: *Node, scroll_x: f32, scroll_y: f32) void {
        self.scroll_x = scroll_x;
        self.scroll_y = scroll_y;
        for (node.children.items) |it| {
            it.layout.x = -scroll_x;
            it.layout.y = -scroll_y;
        }
    }

    /// Take up the same amount of space as it's children stacked over each other.
    /// Records scroll width and height.
    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        const node = c.getNode();
        const size_cstr = LayoutSize.init(std.math.inf(f32), std.math.inf(f32));
        self.scroll_height = 0;
        self.scroll_width = 0;
        for (node.children.items) |it| {
            const child_size = c.computeLayout(it, size_cstr);
            if (child_size.height > self.scroll_height) {
                self.scroll_height = child_size.height;
            }
            if (child_size.width > self.scroll_width) {
                self.scroll_width = child_size.width;
            }
            c.setLayout(it, Layout.init(-self.scroll_x, -self.scroll_y, child_size.width, child_size.height));
        }

        const cstr = c.getSizeConstraint();
        var res = LayoutSize.init(self.scroll_width, self.scroll_height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        } else {
            res.cropToWidth(cstr.width);
        }
        if (c.prefer_exact_height) {
            res.height = cstr.height;
        } else {
            res.cropToHeight(cstr.height);
        }
        return res;
    }

    pub fn render(self: *Self, ctx: *RenderContext) void {
        _ = self;
        const alo = ctx.getAbsLayout();
        ctx.g.pushState();
        ctx.g.clipRect(alo.x, alo.y, alo.width, alo.height);
    }

    /// Computes the layout of the scrollbars here since it depends on layout phase completed to obtain the final ScrollView size.
    pub fn postRender(self: *Self, ctx: *RenderContext) void {
        _ = self;
        ctx.g.popState();

        // Draw borders and scrollbars over the content.

        const alo = ctx.getAbsLayout();

        const g = ctx.getGraphics();
        g.setStrokeColor(Color.Red);
        g.drawRect(alo.x, alo.y, alo.width, alo.height);

        // The view will show more than the scroll height if the scroll y is close to the bottom.
        const eff_scroll_height = std.math.max(self.scroll_height, self.scroll_y + alo.height);
        const eff_scroll_width = std.math.max(self.scroll_width, self.scroll_x + alo.width);

        const draw_vert_bar = alo.height < eff_scroll_height;
        const draw_horz_bar = alo.width < eff_scroll_width;

        // Draw bottom right corner.
        if (draw_vert_bar and draw_horz_bar) {
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x + alo.width - bar_size, alo.y + alo.height - bar_size, bar_size, bar_size);
        }

        if (draw_vert_bar) {
            var max_bar_height = alo.height;
            if (draw_horz_bar) {
                max_bar_height -= bar_size;
            }

            // Draw vertical scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x + alo.width - bar_size, alo.y, bar_size, max_bar_height);

            // Draw thumb.
            const view_to_scroll_height = max_bar_height / eff_scroll_height;
            const vert_thumb_length = view_to_scroll_height * alo.height;
            const vert_thumb_y = view_to_scroll_height * self.scroll_y;
            g.setFillColor(Color.Gray);
            g.fillRect(alo.x + alo.width - bar_size, alo.y + vert_thumb_y, bar_size, vert_thumb_length);
        }

        if (draw_horz_bar) {
            var max_bar_width = alo.width;
            if (draw_vert_bar) {
                max_bar_width -= bar_size;
            }

            // Draw horizontal scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x, alo.y + alo.height - bar_size, max_bar_width, bar_size);

            // Draw thumb.
            const view_to_scroll_width = max_bar_width / eff_scroll_width;
            const hor_thumb_length = view_to_scroll_width * alo.width;
            const hor_thumb_x = view_to_scroll_width * self.scroll_x;
            g.setFillColor(Color.Gray);
            g.fillRect(alo.x + hor_thumb_x, alo.y + alo.height - bar_size, hor_thumb_length, bar_size);
        }
    }
};

/// Handles a single line of text input.
pub const TextField = struct {
    const Self = @This();

    props: struct {
        text_color: Color = Color.Black,
        font_size: f32 = 20,
        onChangeEnd: ?Function([]const u8) = null,
        padding: f32 = 10,
        width: ?f32 = null,
    },

    buf: std.ArrayList(u8),
    font_gid: FontGroupId,

    inner: WidgetRef(TextFieldInner),

    /// Used to determine if the text changed since it received focus.
    last_buf_hash: [16]u8,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        self.buf = std.ArrayList(u8).init(c.alloc);
        self.font_gid = c.getDefaultFontGroup();
        self.last_buf_hash = undefined;
        c.addKeyDownHandler(self, Self.onKeyDown);
        c.addMouseDownHandler(self, Self.onMouseDown);
    }

    pub fn deinit(node: *Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        self.buf.deinit();
    }

    pub fn setValueFmt(self: *Self, comptime format: []const u8, args: anytype) void {
        self.buf.resize(@intCast(usize, std.fmt.count(format, args))) catch unreachable;
        _ = std.fmt.bufPrint(self.buf.items, format, args) catch unreachable;
    }

    fn onMouseDown(self: *Self, e: Event(MouseDownEvent)) void {
        _ = self;
        _ = e;
        e.ctx.requestFocus(onBlur);
        self.inner.widget.setFocused();
        std.crypto.hash.Md5.hash(self.buf.items, &self.last_buf_hash, .{});

        // Map mouse pos to caret pos.
        const xf = @intToFloat(f32, e.val.x);
        self.inner.widget.caret_idx = self.getCaretIdx(e.ctx.common, xf - self.inner.node.abs_pos.x + self.inner.widget.scroll_x);
    }

    fn onBlur(node: *Node, ctx: *CommonContext) void {
        _ = ctx;
        const self = node.getWidget(Self);
        self.inner.widget.focused = false;
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(self.buf.items, &hash, .{});
        if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
            self.fireOnChangeEnd();
        }
    }

    fn fireOnChangeEnd(self: *Self) void {
        if (self.props.onChangeEnd) |cb| {
            cb.call(self.buf.items);
        }
    }

    fn getCaretIdx(self: *Self, ctx: *CommonContext, x: f32) u32 {
        var iter = ctx.measureTextIter(self.font_gid, self.props.font_size, self.buf.items);
        if (iter.nextCodepoint()) {
            if (x < iter.state.advance_width/2) {
                return 0;
            }
        } else {
            return 0;
        }
        var idx: u32 = 1;
        var cur_x: f32 = iter.state.advance_width;
        while (iter.nextCodepoint()) {
            if (x < cur_x + iter.state.advance_width/2) {
                return idx;
            }
            cur_x = std.math.round(cur_x + iter.state.kern);
            cur_x += iter.state.advance_width;
            idx += 1;
        }
        return idx;
    }

    fn onKeyDown(self: *Self, e: Event(KeyDownEvent)) void {
        _ = self;
        const ke = e.val;
        if (ke.code == .Backspace) {
            if (self.inner.widget.caret_idx > 0) {
                if (self.buf.items.len == self.inner.widget.caret_idx) {
                    self.buf.resize(self.buf.items.len-1) catch unreachable;
                } else {
                    _ = self.buf.orderedRemove(self.inner.widget.caret_idx-1);
                }
                // self.postLineUpdate(self.caret_line);
                self.inner.widget.caret_idx -= 1;
                self.inner.widget.keepCaretFixedInView();
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .Enter) {
            var hash: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(self.buf.items, &hash, .{});
            if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
                self.fireOnChangeEnd();
                self.last_buf_hash = hash;
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .ArrowLeft) {
            if (self.inner.widget.caret_idx > 0) {
                self.inner.widget.caret_idx -= 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .ArrowRight) {
            if (self.inner.widget.caret_idx < self.buf.items.len) {
                self.inner.widget.caret_idx += 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        } else {
            if (ke.getPrintChar()) |ch| {
                if (self.inner.widget.caret_idx == self.buf.items.len) {
                    self.buf.append(ch) catch unreachable;
                } else {
                    self.buf.insert(self.inner.widget.caret_idx, ch) catch unreachable;
                }
                // self.postLineUpdate(self.caret_line);
                self.inner.widget.caret_idx += 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        }
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        return c.decl(Padding, .{
            .padding = self.props.padding,
            .child = c.decl(TextFieldInner, .{
                .bind = &self.inner,
                .text = self.buf.items,
                .font_size = self.props.font_size,
                .font_gid = self.font_gid,
            }),
        });
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        const cstr = c.getSizeConstraint();
        const child = c.getNode().children.items[0];
        if (self.props.width) |width| {
            const child_size = c.computeLayoutStretch(child, LayoutSize.init(width, cstr.height), true, c.prefer_exact_height);
            c.setLayout(child, Layout.init(0, 0, child_size.width, child_size.height));
            return child_size;
        } else {
            const child_size = c.computeLayout(child, cstr);
            c.setLayout(child, Layout.init(0, 0, child_size.width, child_size.height));
            return child_size;
        }
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        _ = self;
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        // Background.
        g.setFillColor(Color.White);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        if (c.isFocused()) {
            g.setStrokeColor(Color.Blue);
            g.setLineWidth(2);
            g.drawRect(alo.x, alo.y, alo.width, alo.height);
        }
    }
};

pub const TextFieldInner = struct {
    const Self = @This();

    props: struct {
        text_color: Color = Color.Black,
        font_size: f32 = 20,
        font_gid: FontGroupId,
        text: []const u8 = "",
    },

    scroll_x: f32,
    text_width: f32,

    caret_idx: u32,
    caret_pos_x: f32,

    caret_anim_id: u32,
    caret_anim_show: bool,

    focused: bool,
    ctx: *CommonContext,
    node: *Node,

    /// [0,1]
    fixed_in_view: f32,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        self.scroll_x = 0;
        self.caret_idx = 0;
        self.caret_pos_x = 0;
        self.caret_anim_show = true;
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, onCaretInterval);
        self.focused = false;
        self.ctx = c.common;
        self.node = c.node;
    }

    pub fn postUpdate(self: *Self) void {
        // Make sure caret_idx is in bounds.
        if (self.caret_idx > self.props.text.len) {
            self.caret_idx = @intCast(u32, self.props.text.len);
        }
    }

    fn setFocused(self: *Self) void {
        self.focused = true;
        self.resetCaretAnim();
    }

    fn resetCaretAnim(self: *Self) void {
        self.caret_anim_show = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn onCaretInterval(self: *Self, e: IntervalEvent) void {
        _ = e;
        self.caret_anim_show = !self.caret_anim_show;
    }

    fn keepCaretFixedInView(self: *Self) void {
        const S = struct {
            fn cb(self_: *Self) void {
                self_.scroll_x = self_.caret_pos_x - self_.fixed_in_view * self_.node.layout.width;
                if (self_.scroll_x < 0) {
                    self_.scroll_x = 0;
                }
            }
        };
        self.fixed_in_view = (self.caret_pos_x - self.scroll_x) / self.node.layout.width;
        if (self.fixed_in_view < 0) {
            self.fixed_in_view = 0;
        } else if (self.fixed_in_view > 1) {
            self.fixed_in_view = 1;
        }
        self.ctx.nextPostLayout(self, S.cb);
    }

    fn keepCaretInView(self: *Self) void {
        const S = struct {
            fn cb(self_: *Self) void {
                const layout_width = self_.node.layout.width;

                if (self_.caret_pos_x > self_.scroll_x + layout_width - 2) {
                    // Caret is to the right of the view. Add a tiny padding since it's at the edge.
                    self_.scroll_x = self_.caret_pos_x - layout_width + 2;
                } else if (self_.caret_pos_x < self_.scroll_x) {
                    // Caret is to the left of the view
                    self_.scroll_x = self_.caret_pos_x;
                }
            }
        };
        self.ctx.nextPostLayout(self, S.cb);
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        const cstr = c.getSizeConstraint();

        // log.debug("here", .{});
        const vmetrics = c.getPrimaryFontVMetrics(self.props.font_gid, self.props.font_size);
        // log.debug("here2", .{});
        const metrics = c.measureText(self.props.font_gid, self.props.font_size, self.props.text);
        // log.debug("here3", .{});
        self.text_width = metrics.width;
        self.caret_pos_x = c.measureText(self.props.font_gid, self.props.font_size, self.props.text[0..self.caret_idx]).width;
        // log.debug("here4", .{});

        var res = LayoutSize.init(metrics.width, vmetrics.height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        } else if (res.width > cstr.width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        const needs_clipping = self.scroll_x > 0 or alo.width < self.text_width;
        if (needs_clipping) {
            g.pushState();
            g.clipRect(alo.x, alo.y, alo.width, alo.height);
        }
        g.setFillColor(self.props.text_color);
        g.setFontGroup(self.props.font_gid, self.props.font_size);
        g.fillText(alo.x - self.scroll_x, alo.y, self.props.text);

        // Draw caret.
        if (self.focused) {
            if (self.caret_anim_show) {
                g.fillRect(std.math.round(alo.x - self.scroll_x + self.caret_pos_x), alo.y, 1, alo.height);
            }
        }

        if (needs_clipping) {
            g.popState();
        }
    }
};

/// Note: This widget is very incomplete. It could borrow some techniques used in TextField.
/// Also this will be renamed to TextArea and expose a maxLines property as well as things that might be useful for an advanced TextEditor.
pub const TextEditor = struct {
    const Self = @This();

    props: struct {
        content: []const u8,
        font_family: ?[]const u8 = null,
        width: f32 = 400,
        height: f32 = 300,
        text_color: Color = Color.Black,
    },

    lines: std.ArrayList(Line),
    caret_line: usize,
    caret_col: usize,
    inner: ?WidgetRef(TextEditorInner),
    scroll_view: WidgetRef(ScrollView),

    // Current font group used.
    font_gid: FontGroupId,
    font_size: f32,
    font_vmetrics: font.VMetrics,
    font_line_height: u32,
    font_line_offset_y: f32, // y offset to first text line is drawn

    ctx: *CommonContext,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        const props = self.props;

        var font_gid = c.getDefaultFontGroup();
        if (props.font_family) |font_family| {
            font_gid = c.getFontGroupBySingleFontName(font_family);
        }

        self.lines = std.ArrayList(Line).init(c.alloc);
        self.caret_line = 0;
        self.caret_col = 0;
        self.inner = null;
        self.scroll_view = undefined;
        self.ctx = c.common;
        self.font_gid = font_gid;
        self.setFontSize(24);

        var iter = std.mem.split(u8, props.content, "\n");
        self.lines = std.ArrayList(Line).init(c.alloc);
        while (iter.next()) |it| {
            const measure = c.createTextMeasure(font_gid, self.font_size);
            var line = Line.init(c.alloc, measure);
            line.text.appendSlice(it) catch unreachable;
            self.lines.append(line) catch unreachable;
        }

        // Ensure at least one line.
        if (self.lines.items.len == 0) {
            const measure = c.createTextMeasure(font_gid, self.font_size);
            const line = Line.init(c.alloc, measure);
            self.lines.append(line) catch unreachable;
        }

        c.addKeyDownHandler(self, Self.handleKeyDownEvent);
    }

    pub fn deinit(node: *Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        for (self.lines.items) |line| {
            line.text.deinit();
        }
        self.lines.deinit();
    }

    pub fn setFontSize(self: *Self, font_size: f32) void {
        const font_vmetrics = self.ctx.getPrimaryFontVMetrics(self.font_gid, font_size);
        // log.warn("METRICS {}", .{font_vmetrics});
        self.font_size = font_size;

        const font_line_height_factor: f32 = 1.2;
        const font_line_height = std.math.round(font_line_height_factor * font_size);
        const font_line_offset_y = (font_line_height - font_vmetrics.ascender) / 2;
        // log.warn("{} {} {}", .{font_vmetrics.height, font_line_height, font_line_offset_y});

        self.font_vmetrics = font_vmetrics;
        self.font_line_height = @floatToInt(u32, font_line_height);
        self.font_line_offset_y = font_line_offset_y;

        for (self.lines.items) |line| {
            self.ctx.getTextMeasure(line.measure).setFont(self.font_gid, font_size);
        }

        if (self.inner) |inner| {
            self.ctx.getTextMeasure(inner.widget.to_caret_measure).setFont(self.font_gid, font_size);
        }
    }

    // fn destroyLine(self: *Self, c: *ModuleContext, line: Line) void {
    //     _ = self;
    //     c.destroyTextMeasure(line.measure);
    //     line.deinit();
    // }

    pub fn postInit(self: *Self, comptime C: Config, c: *C.Init()) void {
        self.inner = c.findChildWidgetByType(TextEditorInner).?;
        self.scroll_view = c.findChildWidgetByType(ScrollView).?;
    }

    fn getCaretBottomY(self: *Self) f32 {
        return @intToFloat(f32, self.caret_line + 1) * @intToFloat(f32, self.font_line_height);
    }

    fn getCaretTopY(self: *Self) f32 {
        return @intToFloat(f32, self.caret_line) * @intToFloat(f32, self.font_line_height);
    }

    fn getCaretX(self: *Self) f32 {
        return self.ctx.getTextMeasure(self.inner.?.widget.to_caret_measure).metrics().width;
    }

    fn postLineUpdate(self: *Self, idx: usize) void {
        const line = &self.lines.items[idx];
        self.ctx.getTextMeasure(line.measure).setText(line.text.items);
        self.inner.?.widget.resetCaretAnimation();
    }

    fn postCaretUpdate(self: *Self) void {
        self.inner.?.widget.postCaretUpdate();

        // Scroll to caret.
        const S = struct {
            fn cb(self_: *Self) void {
                const sv = self_.scroll_view;

                const caret_x = self_.getCaretX();
                const caret_bottom_y = self_.getCaretBottomY();
                const caret_top_y = self_.getCaretTopY();
                const view_width = sv.getWidth();
                const view_height = sv.getHeight();

                if (caret_bottom_y > sv.widget.scroll_y + view_height) {
                    // Below current view
                    sv.widget.setScrollPosAfterLayout(sv.node, sv.widget.scroll_x, caret_bottom_y - view_height);
                } else if (caret_top_y < sv.widget.scroll_y) {
                    // Above current view
                    sv.widget.setScrollPosAfterLayout(sv.node, sv.widget.scroll_x, caret_top_y);
                }
                if (caret_x > sv.widget.scroll_x + view_width) {
                    // Right of current view
                    sv.widget.setScrollPosAfterLayout(sv.node, caret_x - view_width, sv.widget.scroll_y);
                } else if (caret_x < sv.widget.scroll_x) {
                    // Left of current view
                    sv.widget.setScrollPosAfterLayout(sv.node, caret_x, sv.widget.scroll_y);
                }
            }
        };
        self.ctx.nextPostLayout(self, S.cb);
    }

    fn handleKeyDownEvent(self: *Self, e: Event(KeyDownEvent)) void {
        _ = self;
        const c = e.ctx.common;
        const val = e.val;
        const line = &self.lines.items[self.caret_line];
        if (val.code == .Backspace) {
            if (self.caret_col > 0) {
                if (line.text.items.len == self.caret_col) {
                    line.text.resize(line.text.items.len-1) catch unreachable;
                } else {
                    _ = line.text.orderedRemove(self.caret_col);
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col -= 1;
                self.postCaretUpdate();
            } else if (self.caret_line > 0) {
                // Join current line with previous.
                var prev_line = self.lines.items[self.caret_line-1];
                self.caret_col = prev_line.text.items.len;
                prev_line.text.appendSlice(line.text.items) catch unreachable;
                line.deinit();
                _ = self.lines.orderedRemove(self.caret_line);
                self.postLineUpdate(self.caret_line-1);

                self.caret_line -= 1;
                self.postCaretUpdate();
            }
        } else if (val.code == .Enter) {
            const measure = c.createTextMeasure(self.font_gid, self.font_size);
            const new_line = Line.init(c.alloc, measure);
            self.lines.insert(self.caret_line + 1, new_line) catch unreachable;
            self.postLineUpdate(self.caret_line + 1);

            self.caret_line += 1;
            self.caret_col = 0;
            self.postCaretUpdate();
        } else {
            if (val.getPrintChar()) |ch| {
                if (self.caret_col == line.text.items.len) {
                    line.text.append(ch) catch unreachable;
                } else {
                    line.text.insert(self.caret_col, ch) catch unreachable;
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col += 1;
                self.postCaretUpdate();
            }
        }
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = self;
        return c.decl(ScrollView, .{
            .children = c.list(.{
                c.decl(TextEditorInner, .{
                    .editor = self,
                }),
            }),
        });
    }
};

const Line = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    text: std.ArrayList(u8),

    measure: TextMeasureId,

    fn init(alloc: std.mem.Allocator, measure: TextMeasureId) Self {
        return .{
            .alloc = alloc,
            .text = std.ArrayList(u8).init(alloc),
            .measure = measure,
        };
    }

    fn deinit(self: Self) void {
        self.text.deinit();
    }
};

pub const TextEditorInner = struct {
    const Self = @This();

    props: struct {
        editor: *TextEditor,
    },

    caret_anim_show_toggle: bool,
    caret_anim_id: ui.IntervalId,
    to_caret_measure: ui.TextMeasureId,
    editor: *TextEditor,
    ctx: *CommonContext,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        const props = self.props;
        self.to_caret_measure = c.createTextMeasure(props.editor.font_gid, props.editor.font_size);
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, Self.handleCaretInterval);
        self.caret_anim_show_toggle = true;
        self.editor = props.editor;
        self.ctx = c.common;
    }

    fn resetCaretAnimation(self: *Self) void {
        self.caret_anim_show_toggle = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn postCaretUpdate(self: *Self) void {
        const line = self.editor.lines.items[self.editor.caret_line].text.items;
        self.ctx.getTextMeasure(self.to_caret_measure).setText(line[0..self.editor.caret_col]);
    }

    fn handleCaretInterval(self: *Self, e: IntervalEvent) void {
        _ = e;
        self.caret_anim_show_toggle = !self.caret_anim_show_toggle;
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) FrameId {
        _ = Config;
        _ = self;
        _ = c;
        return NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        var height: f32 = 0;
        var max_width: f32 = 0;
        for (self.editor.lines.items) |it| {
            const metrics = c.common.getTextMeasure(it.measure).metrics();
            if (metrics.width > max_width) {
                max_width = metrics.width;
            }
            height += @intToFloat(f32, self.editor.font_line_height);
        }
        return LayoutSize.init(max_width, height);
    }

    pub fn render(self: *Self, c: *RenderContext) void {
        _ = self;
        const editor = self.editor;

        const lo = c.getAbsLayout();

        const g = c.getGraphics();
        const line_height = @intToFloat(f32, editor.font_line_height);

        g.setFont(editor.font_gid, editor.font_size);
        g.setFillColor(self.editor.props.text_color);
        // TODO: Use binary search when word wrap is enabled and we can't determine the first visible line with O(1)
        const visible_start_idx = std.math.max(0, @floatToInt(i32, std.math.floor(editor.scroll_view.widget.scroll_y / line_height)));
        const visible_end_idx = std.math.min(editor.lines.items.len, @floatToInt(i32, std.math.ceil((editor.scroll_view.widget.scroll_y + editor.scroll_view.getHeight()) / line_height)));
        // log.warn("{} {}", .{visible_start_idx, visible_end_idx});
        const line_offset_y = editor.font_line_offset_y;
        var i: usize = @intCast(usize, visible_start_idx);
        while (i < visible_end_idx) : (i += 1) {
            const line = editor.lines.items[i];
            g.fillText(lo.x, lo.y + line_offset_y + @intToFloat(f32, i) * line_height, line.text.items);
        }

        // Draw caret.
        if (self.caret_anim_show_toggle) {
            g.setFillColor(self.editor.props.text_color);
            const width = c.common.getTextMeasure(self.to_caret_measure).metrics().width;
            // log.warn("width {d:2}", .{width});
            const height = self.editor.font_vmetrics.height;
            g.fillRect(std.math.round(lo.x + width), lo.y + @intToFloat(f32, self.editor.caret_line) * line_height, 1, height);
        }
    }
};