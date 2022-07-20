const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const ScrollView = ui.widgets.ScrollView;

const NullId = std.math.maxInt(u32);
const log = stdx.log.scoped(.list);

pub const ScrollList = struct {
    props: struct {
        children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
        bg_color: Color = Color.White,
    },

    list: ui.WidgetRef(List),

    pub fn build(self: *ScrollList, c: *ui.BuildContext) ui.FrameId {
        return c.decl(ScrollView, .{
            .enable_hscroll = false,
            .bg_color = self.props.bg_color,
            .child = c.decl(List, .{
                .bind = &self.list,
                .bg_color = self.props.bg_color,
                .children = self.props.children,
            }),
        });
    }

    /// Index of ui.NullId represents no selection.
    pub fn getSelectedIdx(self: *ScrollList) u32 {
        return self.list.getWidget().selected_idx;
    }
};

pub const List = struct {
    props: struct {
        children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
        bg_color: Color = Color.White,
    },

    selected_idx: u32,

    pub fn init(self: *List, c: *ui.InitContext) void {
        self.selected_idx = NullId;
        c.addMouseDownHandler(c.node, handleMouseDownEvent);
        c.addKeyDownHandler(self, onKeyDown);
    }

    pub fn build(self: *List, c: *ui.BuildContext) ui.FrameId {
        return c.fragment(self.props.children);
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        _ = node;
    }

    fn onKeyDown(self: *List, e: ui.KeyDownEvent) void {
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

    fn handleMouseDownEvent(node: *ui.Node, e: ui.MouseDownEvent) ui.EventResult {
        var self = node.getWidget(List);
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
        return .Continue;
    }

    pub fn postPropsUpdate(self: *List) void {
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

    pub fn layout(self: *List, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const node = c.getNode();

        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var max_width: f32 = 0;
        var cur_y: f32 = 0;
        for (node.children.items) |child| {
            const child_size = c.computeLayout(child, vacant_size);
            c.setLayout(child, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
            vacant_size.height -= child_size.height;
            cur_y += child_size.height;
            if (child_size.width > max_width) {
                max_width = child_size.width;
            }
        }
        var res = ui.LayoutSize.init(max_width, cur_y);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn renderCustom(self: *List, c: *ui.RenderContext) void {
        const g = c.gctx;
        const alo = c.getAbsLayout();
        const node = c.node;

        g.setFillColor(self.props.bg_color);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        c.renderChildren();

        if (self.selected_idx != NullId) {
            // Highlight selected item.
            g.setStrokeColor(Color.Blue);
            g.setLineWidth(2);
            const child = node.children.items[self.selected_idx];
            g.drawRect(child.abs_pos.x, child.abs_pos.y, alo.width, child.layout.height);
        }
    }
};