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
const RenderContext = ui.RenderContext;
const Config = ui.Config;
const TextMeasureId = ui.TextMeasureId;
const Event = ui.Event;
const IntervalEvent = ui.IntervalEvent;
const FrameId = ui.FrameId;
const FrameListPtr = ui.FrameListPtr;
const NullFrameId = ui.NullFrameId;
const Import = ui.Import;
const log = stdx.log.scoped(.widgets);

pub const Slider = @import("widgets/slider.zig").Slider;
const text_editor = @import("widgets/text_editor.zig");
pub const TextEditor = text_editor.TextEditor;
const TextEditorInner = text_editor.TextEditorInner;
const text_field = @import("widgets/text_field.zig");
pub const TextField = text_field.TextField;
const TextFieldInner = text_field.TextFieldInner;
pub const ScrollView = @import("widgets/scroll_view.zig").ScrollView;
const flex = @import("widgets/flex.zig");
pub const Column = flex.Column;
pub const Row = flex.Row;
pub const Grow = flex.Grow;
const containers = @import("widgets/containers.zig");
pub const Sized = containers.Sized;
pub const Padding = containers.Padding;
pub const Center = containers.Center;
pub const Stretch = containers.Stretch;
const button = @import("widgets/button.zig");
pub const Button = button.Button;
pub const TextButton = button.TextButton;
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
    Import.init(ScrollList),
    Import.init(List),
    Import.init(Stretch),
};

pub const ScrollList = struct {
    const Self = @This();

    props: struct {
        children: FrameListPtr = FrameListPtr.init(0, 0),
    },

    list: ui.WidgetRef(List),

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) ui.FrameId {
        return c.decl(ScrollView, .{
            .pass_stretch_width = true,
            .child = c.decl(List, .{
                .bind = &self.list,
                .children = self.props.children,
            }),
        });
    }

    /// Index of ui.NullId represents no selection.
    pub fn getSelectedIdx(self: *Self) u32 {
        return self.list.widget.selected_idx;
    }
};

const NullId = std.math.maxInt(u32);

pub const List = struct {
    const Self = @This();

    props: struct {
        children: FrameListPtr = FrameListPtr.init(0, 0),
    },

    selected_idx: u32,

    pub fn init(self: *Self, comptime C: Config, c: *C.Init()) void {
        self.selected_idx = NullId;
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
        c.addKeyDownHandler(self, onKeyDown);
    }

    pub fn build(self: *Self, comptime C: Config, c: *C.Build()) ui.FrameId {
        return c.fragment(self.props.children);
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        _ = node;
    }

    fn onKeyDown(self: *Self, e: ui.Event(KeyDownEvent)) void {
        _ = self;
        const ke = e.val;
        switch (ke.code) {
            .ArrowDown => {
                self.selected_idx += 1;
                if (self.selected_idx >= self.props.children.len) {
                    self.selected_idx = self.props.children.len-1;
                } 
            },
            .ArrowUp => {
                if (self.selected_idx > 0) {
                    self.selected_idx -= 1;
                }
            },
            else => {},
        }
    }

    fn handleMouseDownEvent(node: *Node, e: ui.MouseDownEvent) void {
        var self = node.getWidget(Self);
        if (e.val.button == .Left) {
            e.ctx.requestFocus(onBlur);
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);
            if (xf >= node.abs_pos.x and xf <= node.abs_pos.x + node.layout.width) {
                var i: u32 = 0;
                while (i < node.children.items.len) : (i += 1) {
                    const child = node.children.items[i];
                    if (yf < child.abs_pos.y) {
                        break;
                    }
                    if (yf >= child.abs_pos.y and yf <= child.abs_pos.y + child.layout.height) {
                        self.selected_idx = i;
                        break;
                    }
                }
            }
        }
    }

    pub fn postUpdate(self: *Self) void {
        if (self.selected_idx != NullId) {
            if (self.selected_idx >= self.props.children.len) {
                if (self.props.children.len == 0) {
                    self.selected_idx = NullId;
                } else {
                    self.selected_idx = self.props.children.len - 1;
                }
            }
        }
    }

    pub fn layout(self: *Self, comptime C: Config, c: *C.Layout()) LayoutSize {
        _ = self;
        const node = c.getNode();

        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var max_width: f32 = 0;
        var cur_y: f32 = 0;
        for (node.children.items) |child| {
            const child_size = c.computeLayout(child, vacant_size);
            c.setLayout(child, Layout.init(0, cur_y, child_size.width, child_size.height));
            vacant_size.height -= child_size.height;
            cur_y += child_size.height;
            if (child_size.width > max_width) {
                max_width = child_size.width;
            }
        }
        var res = LayoutSize.init(max_width, cur_y);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        _ = self;
        const g = c.g;
        const alo = c.getAbsLayout();

        g.setFillColor(Color.White);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);
    }
    
    pub fn postRender(self: *Self, c: *ui.RenderContext) void {
        _ = self;
        const g = c.g;
        const alo = c.getAbsLayout();

        if (self.selected_idx != NullId) {
            // Highlight selected item.
            g.setStrokeColor(Color.Blue);
            g.setLineWidth(2);
            const child = c.node.children.items[self.selected_idx];
            g.drawRect(child.abs_pos.x, child.abs_pos.y, alo.width, child.layout.height);
        }
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

    pub fn render(self: *Self, c: *ui.RenderContext) void {
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

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        _ = self;
        _ = c;
        return NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        if (self.props.text != null) {
            const font_gid = c.common.getDefaultFontGroup();
            const m = c.common.measureText(font_gid, self.props.font_size, self.props.text.?);
            return ui.LayoutSize.init(m.width, m.height);
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
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
