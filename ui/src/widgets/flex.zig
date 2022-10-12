const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const log = stdx.log.scoped(.flex);

const ui = @import("../ui.zig");
const module = @import("../module.zig");

/// Lays out children vertically.
pub const Column = struct {
    props: struct {
        bg_color: ?Color = null,
        valign: ui.VAlign = .top,

        /// Prefers child to take up max width of available space.
        expandChildWidth: bool = false,
        spacing: f32 = 0,

        /// Whether the columns's height will expand to the max height of available space.
        /// flex and flex_fit are only used when expand is true.
        expand: bool = false,
        flex: u32 = 1,
        flex_fit: ui.FlexFit = .exact,

        children: ui.FrameListPtr = .{},
    },

    pub fn build(self: *Column, c: *ui.BuildContext) ui.FramePtr {
        return c.fragment(self.props.children.dupe());
    }

    pub fn layout(self: *Column, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        var vacant_size = cstr.getMaxLayoutSize();
        var cur_y: f32 = 0;
        var max_child_width: f32 = 0;

        const total_spacing = if (c.node.children.items.len > 0) self.props.spacing * @intToFloat(f32, c.node.children.items.len-1) else 0;
        vacant_size.height -= total_spacing;

        const min_width = if (self.props.expandChildWidth) vacant_size.width else 0;

        // First pass computes non expanding children.
        var has_expanding_children = false;
        var flex_sum: u32 = 0;
        for (c.node.children.items) |it| {
            // Only Flex and Column make sense to do flex for a parent Column.
            if (it.vtable == module.GenWidgetVTable(Flex)) {
                const flex = it.getWidget(Flex);
                has_expanding_children = true;
                flex_sum += flex.props.flex;
                continue;
            } else if (it.vtable == module.GenWidgetVTable(Column)) {
                const col = it.getWidget(Column);
                if (col.props.expand) {
                    has_expanding_children = true;
                    flex_sum += col.props.flex;
                    continue;
                }
            }
            var child_size = c.computeLayout(it, min_width, 0, vacant_size.width, vacant_size.height);
            c.setLayout(it, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
            cur_y += child_size.height + self.props.spacing;
            vacant_size.height -= child_size.height;
            if (child_size.width > max_child_width) {
                max_child_width = child_size.width;
            }
        }

        if (has_expanding_children) {
            cur_y = 0;
            const flex_unit_size = vacant_size.height / @intToFloat(f32, flex_sum);

            var max_child_size = ui.LayoutSize.init(vacant_size.width, 0);
            var carry_over_height: f32 = 0;
            for (c.node.children.items) |it| {
                var flex: u32 = std.math.maxInt(u32);
                var flex_fit: ui.FlexFit = undefined;
                if (it.vtable == module.GenWidgetVTable(Flex)) {
                    const w = it.getWidget(Flex);
                    flex = w.props.flex;
                    flex_fit = w.props.flex_fit;
                } else if (it.vtable == module.GenWidgetVTable(Column)) {
                    const col = it.getWidget(Column);
                    if (col.props.expand) {
                        flex = col.props.flex;
                        flex_fit = col.props.flex_fit;
                    }
                }
                if (flex == std.math.maxInt(u32)) {
                    // Update the layout pos of sized children since this pass will include expanded children.
                    c.setLayoutPos(it, 0, cur_y);
                    cur_y += c.getLayout(it).height;
                    continue;
                }

                max_child_size.height = flex_unit_size * @intToFloat(f32, flex) + carry_over_height;
                if (carry_over_height > 0) {
                    carry_over_height = 0;
                }
                var child_size: ui.LayoutSize = undefined;
                switch (flex_fit) {
                    .shrinkAndGive => {
                        child_size = c.computeLayout(it, min_width, 0, max_child_size.width, max_child_size.height);
                        c.setLayout(it, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
                        cur_y += child_size.height + self.props.spacing;
                        if (child_size.height < max_child_size.height) {
                            carry_over_height = max_child_size.height - child_size.height;
                        }
                    },
                    else => {
                        child_size = c.computeLayout(it, min_width, max_child_size.height, max_child_size.width, max_child_size.height);
                        c.setLayout(it, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
                        cur_y += child_size.height + self.props.spacing;
                        if (child_size.width > max_child_width) {
                            max_child_width = child_size.width;
                        }
                    }
                }
                if (child_size.width > max_child_width) {
                    max_child_width = child_size.width;
                }
            }
        } else {
            // No expanding children. Check to realign vertically.
            if (self.props.expand and self.props.valign == .bottom) {
                const inner_height = cur_y - self.props.spacing;
                var scratch_y = cstr.max_height - inner_height;
                for (c.node.children.items) |it| {
                    c.setLayoutPos(it, 0, scratch_y);
                    scratch_y += it.layout.height + self.props.spacing;
                }
            }
        }

        if (self.props.expand) {
            return ui.LayoutSize.init(max_child_width, cstr.max_height);
        } else {
            if (c.node.children.items.len > 0) {
                var res = ui.LayoutSize.init(max_child_width, cur_y - self.props.spacing);
                res.growToMin(cstr);
                return res;
            } else {
                return cstr.getMinLayoutSize();
            }
        }
    }

    pub fn render(self: *Column, ctx: *ui.RenderContext) void {
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

pub const Row = struct {
    props: struct {
        bg_color: ?Color = null,
        flex: u32 = 1,
        valign: ui.VAlign = .top,
        halign: ui.HAlign = .left,

        spacing: f32 = 0,

        expandChildHeight: bool = false,

        /// Whether the row's width will shrink to the total width of it's children or expand to the parent container's width.
        /// Expands to the parent container's width by default.
        expand: bool = false,

        children: ui.FrameListPtr = .{},
    },

    pub fn build(self: *Row, c: *ui.BuildContext) ui.FramePtr {
        return c.fragment(self.props.children.dupe());
    }

    pub fn layout(self: *Row, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        var vacant_size = cstr.getMaxLayoutSize();
        var cur_x: f32 = 0;
        var max_child_height: f32 = 0;

        const total_spacing = if (c.node.children.items.len > 0) self.props.spacing * @intToFloat(f32, c.node.children.items.len-1) else 0;
        vacant_size.width -= total_spacing;

        const min_height = if (self.props.expandChildHeight) vacant_size.height else 0;

        // First pass computes non expanding children.
        var has_expanding_children = false;
        var flex_sum: u32 = 0;
        for (c.node.children.items) |it| {
            // Only Flex and Row make sense to do flex for a parent Row.
            if (it.vtable == module.GenWidgetVTable(Flex)) {
                const flex = it.getWidget(Flex);
                has_expanding_children = true;
                flex_sum += flex.props.flex;
                continue;
            } else if (it.vtable == module.GenWidgetVTable(Row)) {
                const row = it.getWidget(Row);
                if (row.props.expand) {
                    has_expanding_children = true;
                    flex_sum += row.props.flex;
                    continue;
                }
            }
            var child_size = c.computeLayout(it, 0, min_height, vacant_size.width, vacant_size.height);
            c.setLayout(it, ui.Layout.init(cur_x, 0, child_size.width, child_size.height));
            cur_x += child_size.width + self.props.spacing;
            vacant_size.width -= child_size.width;
            if (child_size.height > max_child_height) {
                max_child_height = child_size.height;
            }
        }

        if (has_expanding_children) {
            cur_x = 0;
            const flex_unit_size = vacant_size.width / @intToFloat(f32, flex_sum);

            var max_child_size = ui.LayoutSize.init(0, vacant_size.height);
            for (c.node.children.items) |it| {
                var flex: u32 = std.math.maxInt(u32);
                if (it.vtable == module.GenWidgetVTable(Flex)) {
                    const w = it.getWidget(Flex);
                    flex = w.props.flex;
                } else if (it.vtable == module.GenWidgetVTable(Row)) {
                    const row = it.getWidget(Row);
                    flex = row.props.flex;
                }
                if (flex == std.math.maxInt(u32)) {
                    // Update the layout pos of sized children since this pass will include expanded children.
                    c.setLayoutPos(it, cur_x, 0);
                    cur_x += c.getLayout(it).width;
                    continue;
                }

                max_child_size.width = flex_unit_size * @intToFloat(f32, flex);
                var child_size = c.computeLayout(it, max_child_size.width, min_height, max_child_size.width, max_child_size.height);
                c.setLayout(it, ui.Layout.init(cur_x, 0, child_size.width, child_size.height));
                cur_x += child_size.width + self.props.spacing;
                if (child_size.height > max_child_height) {
                    max_child_height = child_size.height;
                }
            }
        } else {
            // No expanding children. Check to realign in x dim.
            if (self.props.halign == .right) {
                const inner_width = cur_x - self.props.spacing;
                var scratch_x = cstr.max_width - inner_width;
                for (c.node.children.items) |it| {
                    c.setLayoutPos(it, scratch_x, 0);
                    scratch_x += it.layout.width + self.props.spacing;
                }
            }
        }

        if (self.props.valign != .top) {
            switch (self.props.valign) {
                .center => {
                    for (c.node.children.items) |child| {
                        c.setLayoutPos(child, child.layout.x, (max_child_height - child.layout.height) * 0.5);
                    }
                },
                else => {},
            }
        }

        if (self.props.expand) {
            return ui.LayoutSize.init(cstr.max_width, max_child_height);
        } else {
            if (c.node.children.items.len > 0) {
                var res = ui.LayoutSize.init(cur_x - self.props.spacing, max_child_height);
                res.growToMin(cstr);
                return res;
            } else {
                return cstr.getMinLayoutSize();
            }
        }
    }

    pub fn render(self: *Row, c: *ui.RenderContext) void {
        const gctx = c.gctx;
        const bounds = c.getAbsBounds();

        const props = self.props;

        if (props.bg_color != null) {
            gctx.setFillColor(props.bg_color.?);
            c.fillBBox(bounds);
        }
        // TODO: draw border
    }
};

/// Interpreted by Column or Row as a flexible widget. The flex property is used determine how it fits in the parent container.
pub const Flex = struct {
    props: struct {
        child: ui.FramePtr = .{},

        /// Flex properties are used by the parent.
        flex: u32 = 1,
        flex_fit: ui.FlexFit = .exact,
    },

    pub fn build(self: *Flex, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    /// Computes the child layout preferring to stretch it and returns the current constraint.
    pub fn layout(self: *Flex, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child.isNull()) {
            return cstr.getMinLayoutSize();
        }

        const node = c.getNode();
        const child = node.children.items[0];
        const child_size = c.computeLayout2(child, cstr);
        c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));

        var res = child_size;
        res.limitToMinMax(cstr);
        return res;
    }
};