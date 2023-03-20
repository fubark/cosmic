const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const w = ui.widgets;

const NullId = std.math.maxInt(u32);
const log = stdx.log.scoped(.list);

pub const ScrollList = struct {
    props: *const struct {
        children: ui.FrameListPtr = .{},
        bg_color: Color = Color.White,
    },

    list: ui.WidgetRef(List),

    pub fn build(self: *ScrollList, c: *ui.BuildContext) ui.FramePtr {
        const sv_style = w.ScrollViewStyle{
            .bgColor = self.props.bg_color,
        };
        return w.ScrollView(.{
            .enable_hscroll = false,
            .style = sv_style },
            w.Stretch(.{ .method = .Width },
                c.build(List, .{
                    .bind = &self.list,
                    .bg_color = self.props.bg_color,
                    .children = self.props.children.dupe(),
                }),
            ),
        );
    }

    /// Index of ui.NullId represents no selection.
    pub fn getSelectedIdx(self: *ScrollList) u32 {
        return self.list.getWidget().selected_idx;
    }
};

/// Fills maximum space and lays out children in a column.
pub const List = struct {
    props: *const struct {
        children: ui.FrameListPtr = .{},
        bg_color: Color = Color.White,
    },

    selected_idx: u32,

    pub fn init(self: *List, c: *ui.InitContext) void {
        self.selected_idx = NullId;
        c.setMouseDownHandler(c.node, onMouseDown);
        c.setKeyDownHandler(self, onKeyDown);
    }

    pub fn build(self: *List, c: *ui.BuildContext) ui.FramePtr {
        return c.fragment(self.props.children.dupe());
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        _ = node;
    }

    fn onKeyDown(self: *List, e: ui.KeyDownEvent) void {
        const ke = e.val;
        switch (ke.code) {
            .ArrowDown => {
                self.selected_idx += 1;
                const len = self.props.children.size();
                if (self.selected_idx >= len) {
                    self.selected_idx = @intCast(u32, len)-1;
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

    fn onMouseDown(node: *ui.Node, e: ui.MouseDownEvent) ui.EventResult {
        var self = node.getWidget(List);
        if (e.val.button == .left) {
            e.ctx.requestFocus(.{ .onBlur = onBlur });
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);
            if (xf >= node.abs_bounds.min_x and xf <= node.abs_bounds.max_x) {
                var i: u32 = 0;
                while (i < node.children.items.len) : (i += 1) {
                    const child = node.children.items[i];
                    if (yf < child.abs_bounds.min_y) {
                        break;
                    }
                    if (yf >= child.abs_bounds.min_y and yf <= child.abs_bounds.max_y) {
                        self.selected_idx = i;
                        break;
                    }
                }
            }
            return .stop;
        }
        return .default;
    }

    pub fn postPropsUpdate(self: *List, _: *ui.UpdateContext) void {
        if (self.selected_idx != NullId) {
            const len = self.props.children.size();
            if (self.selected_idx >= len) {
                if (len == 0) {
                    self.selected_idx = NullId;
                } else {
                    self.selected_idx = @intCast(u32, len) - 1;
                }
            }
        }
    }

    pub fn layout(_: *List, c: *ui.LayoutContext) ui.LayoutSize {
        const node = c.getNode();
        const cstr = c.getSizeConstraints();
        var vacant_size = cstr.getMaxLayoutSize();
        var max_width: f32 = 0;
        var cur_y: f32 = 0;
        for (node.children.items) |child| {
            const child_size = c.computeLayoutWithMax(child, vacant_size.width, vacant_size.height);
            c.setLayout(child, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
            vacant_size.height -= child_size.height;
            cur_y += child_size.height;
            if (child_size.width > max_width) {
                max_width = child_size.width;
            }
        }
        var res = ui.LayoutSize.init(max_width, cur_y);
        res.growToMin(cstr);
        return res;
    }

    pub fn renderCustom(self: *List, c: *ui.RenderContext) void {
        const g = c.gctx;
        const bounds = c.getAbsBounds();
        const node = c.node;

        g.setFillColor(self.props.bg_color);
        c.fillBBox(bounds);

        c.renderChildren();

        if (self.selected_idx != NullId) {
            // Highlight selected item.
            g.setStrokeColor(Color.Blue);
            g.setLineWidth(2);
            const child = node.children.items[self.selected_idx];
            g.strokeRectBounds(child.abs_bounds.min_x, child.abs_bounds.min_y, bounds.max_x, child.abs_bounds.max_y);
        }
    }
};