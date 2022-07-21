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
        valign: ui.VAlign = .Top,
        stretch_width: bool = false,
        spacing: f32 = 0,

        /// Whether the columns's height will shrink to the total height of it's children or expand to the parent container's height.
        /// Expands to the parent container's height by default.
        /// flex and flex_fit are only used when expand is true.
        expand: bool = true,
        flex: u32 = 1,
        flex_fit: ui.FlexFit = .Exact,

        children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = self;
        return c.fragment(self.props.children);
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var cur_y: f32 = 0;
        var max_child_width: f32 = 0;

        const total_spacing = if (c.node.children.items.len > 0) self.props.spacing * @intToFloat(f32, c.node.children.items.len-1) else 0;
        vacant_size.height -= total_spacing;

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
            var child_size = c.computeLayoutStretch(it, vacant_size, self.props.stretch_width, false);
            child_size.cropTo(vacant_size);
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
                    .ShrinkAndGive => {
                        child_size = c.computeLayoutStretch(it, max_child_size, self.props.stretch_width, false);
                        child_size.cropTo(max_child_size);
                        c.setLayout(it, ui.Layout.init(0, cur_y, child_size.width, child_size.height));
                        cur_y += child_size.height + self.props.spacing;
                        if (child_size.height < max_child_size.height) {
                            carry_over_height = max_child_size.height - child_size.height;
                        }
                    },
                    else => {
                        child_size = c.computeLayoutStretch(it, max_child_size, self.props.stretch_width, true);
                        child_size.cropTo(max_child_size);
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
            if (self.props.expand and self.props.valign == .Bottom) {
                const inner_height = cur_y - self.props.spacing;
                var scratch_y = cstr.height - inner_height;
                for (c.node.children.items) |it| {
                    c.setLayoutPos(it, 0, scratch_y);
                    scratch_y += it.layout.height + self.props.spacing;
                }
            }
        }

        if (self.props.expand) {
            return ui.LayoutSize.init(max_child_width, cstr.height);
        } else {
            if (c.node.children.items.len > 0) {
                return ui.LayoutSize.init(max_child_width, cur_y - self.props.spacing);
            } else {
                return ui.LayoutSize.init(max_child_width, cur_y);
            }
        }
    }

    pub fn render(self: *Self, ctx: *ui.RenderContext) void {
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

pub const Row = struct {
    props: struct {
        bg_color: ?Color = null,
        flex: u32 = 1,
        valign: ui.VAlign = .Top,
        halign: ui.HAlign = .Left,

        spacing: f32 = 0,

        /// Whether the row's width will shrink to the total width of it's children or expand to the parent container's width.
        /// Expands to the parent container's width by default.
        expand: bool = true,

        children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = self;
        return c.fragment(self.props.children);
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        var vacant_size = cstr;
        var cur_x: f32 = 0;
        var max_child_height: f32 = 0;

        const total_spacing = if (c.node.children.items.len > 0) self.props.spacing * @intToFloat(f32, c.node.children.items.len-1) else 0;
        vacant_size.width -= total_spacing;

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
            var child_size = c.computeLayout(it, vacant_size);
            child_size.cropTo(vacant_size);
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
                var child_size = c.computeLayoutStretch(it, max_child_size, true, false);
                child_size.cropTo(max_child_size);
                c.setLayout(it, ui.Layout.init(cur_x, 0, child_size.width, child_size.height));
                cur_x += child_size.width + self.props.spacing;
                if (child_size.height > max_child_height) {
                    max_child_height = child_size.height;
                }
            }
        } else {
            // No expanding children. Check to realign in x dim.
            if (self.props.expand and self.props.halign == .Right) {
                const inner_width = cur_x - self.props.spacing;
                var scratch_x = cstr.width - inner_width;
                for (c.node.children.items) |it| {
                    c.setLayoutPos(it, scratch_x, 0);
                    scratch_x += it.layout.width + self.props.spacing;
                }
            }
        }

        if (self.props.valign != .Top) {
            switch (self.props.valign) {
                .Center => {
                    for (c.node.children.items) |child| {
                        c.setLayoutPos(child, child.layout.x, (max_child_height - child.layout.height) * 0.5);
                    }
                },
                else => {},
            }
        }

        if (self.props.expand) {
            return ui.LayoutSize.init(cstr.width, max_child_height);
        } else {
            if (c.node.children.items.len > 0) {
                return ui.LayoutSize.init(cur_x - self.props.spacing, max_child_height);
            } else {
                return ui.LayoutSize.init(cur_x, max_child_height);
            }
        }
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        _ = self;
        const g = c.gctx;
        const alo = c.getAbsLayout();

        const props = self.props;

        if (props.bg_color != null) {
            g.setFillColor(props.bg_color.?);
            g.fillRect(alo.x, alo.y, alo.width, alo.height);
        }
        // TODO: draw border
    }
};

/// Interpreted by Column or Row as a flexible widget. The flex property is used determine how it fits in the parent container.
pub const Flex = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        flex: u32 = 1,
        flex_fit: ui.FlexFit = .Exact,

        /// When false, stretching is inherited by the parent.
        stretch_width: bool = false,
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    /// Computes the child layout preferring to stretch it and returns the current constraint.
    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const cstr = c.getSizeConstraint();
        const node = c.getNode();

        if (node.children.items.len == 0) {
            var res = ui.LayoutSize.init(0, 0);
            if (c.prefer_exact_width) {
                res.width = cstr.width;
            }
            if (c.prefer_exact_height) {
                res.height = cstr.height;
            }
            return res;
        }

        const child = node.children.items[0];
        const stretch_width = if (self.props.stretch_width) true else c.prefer_exact_width;
        const child_size = c.computeLayoutStretch(child, cstr, stretch_width, c.prefer_exact_height);
        var res = child_size;
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        if (c.prefer_exact_height) {
            res.height = cstr.height;
        }
        c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));
        return res;
    }
};