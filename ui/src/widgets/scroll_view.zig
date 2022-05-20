const std = @import("std");
const stdx = @import("stdx");
const platform = @import("platform");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("../ui.zig");
const Node = ui.Node;
const FrameListPtr = ui.FrameListPtr;

const log = stdx.log.scoped(.scroll_view);

/// By default, scroll view will stretch to it's child. Must be constrained by parent sizer (eg. Sized, Flex) to trigger scrollbars. 
pub const ScrollView = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        bg_color: Color = Color.White,
        border_color: Color = Color.DarkGray,
        enable_hscroll: bool = true,
        show_border: bool = true,
    },

    /// Internal vars. They should not be modified after the layout phase.
    /// Adjusting the scroll pos after layout and before render must call setScrollPosAfterLayout()
    scroll_x: f32,
    scroll_y: f32,
    scroll_width: f32,
    scroll_height: f32,

    eff_scroll_width: f32,
    eff_scroll_height: f32,
    has_vbar: bool,
    has_hbar: bool,

    node: *Node,
    scroll_to_bottom_after_layout: bool,

    const Self = @This();
    const BarSize = 15;

    pub fn init(self: *Self, c: *ui.InitContext) void {
        self.scroll_x = 0;
        self.scroll_y = 0;
        self.scroll_width = 0;
        self.scroll_height = 0;
        self.node = c.node;
        self.scroll_to_bottom_after_layout = false;
        self.eff_scroll_width = 0;
        self.eff_scroll_height = 0;
        self.has_vbar = false;
        self.has_hbar = false;
        c.addMouseScrollHandler(self, onMouseScroll);
    }

    fn onMouseScroll(self: *Self, e: ui.MouseScrollEvent) void {
        self.scroll_y += e.val.delta_y;
        self.checkScroll();
    }

    pub fn postPropsUpdate(self: *Self) void {
        self.checkScroll();
    }

    pub fn scrollToBottomAfterLayout(self: *Self) void {
        self.scroll_to_bottom_after_layout = true;
    }

    fn checkScroll(self: *Self) void {
        if (self.scroll_y < 0) {
            self.scroll_y = 0;
        }
        if (self.scroll_height > self.node.layout.height) {
            if (self.scroll_y > self.scroll_height - self.node.layout.height) {
                self.scroll_y = self.scroll_height - self.node.layout.height;
            }
        } else {
            if (self.scroll_y > 0) {
                self.scroll_y = 0;
            }
        }
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
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
        self.computeEffScrollDims(node.layout.width, node.layout.height);
    }

    /// Take up the same amount of space as it's child or constrained by the parent.
    /// Updates scroll width and height.
    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        const node = c.getNode();
        const size_cstr = ui.LayoutSize.init(std.math.inf(f32), std.math.inf(f32));

        self.scroll_height = 0;
        self.scroll_width = 0;

        if (self.props.child != ui.NullFrameId) {
            const child = node.children.items[0];
            var child_size: ui.LayoutSize = undefined;
            if (c.prefer_exact_width and !self.props.enable_hscroll) {
                if (self.has_vbar) {
                    child_size = c.computeLayoutStretch(child, ui.LayoutSize.init(c.getSizeConstraint().width - BarSize, std.math.inf(f32)), true, false);
                } else {
                    child_size = c.computeLayoutStretch(child, ui.LayoutSize.init(c.getSizeConstraint().width, std.math.inf(f32)), true, false);
                }
            } else {
                child_size = c.computeLayout(child, size_cstr);
            }
            if (child_size.height > self.scroll_height) {
                self.scroll_height = child_size.height;
            }
            if (child_size.width > self.scroll_width) {
                self.scroll_width = child_size.width;
            }
            c.setLayout(child, ui.Layout.init(-self.scroll_x, -self.scroll_y, child_size.width, child_size.height));
        }

        const cstr = c.getSizeConstraint();
        var res = ui.LayoutSize.init(self.scroll_width, self.scroll_height);
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

        if (self.scroll_to_bottom_after_layout) {
            if (self.scroll_height > res.height) {
                self.scroll_y = self.scroll_height - res.height;
            }
            self.scroll_to_bottom_after_layout = false;
        }

        var prev_has_vbar = self.has_vbar;
        self.computeEffScrollDims(res.width, res.height);
        if (!prev_has_vbar and self.has_vbar and c.prefer_exact_width) {
            // Recompute layout when turning on the vbar when prefer_exact_width is on.
            return self.layout(c);
        }

        return res;
    }

    /// Computes the effective scroll width/height.
    fn computeEffScrollDims(self: *Self, width: f32, height: f32) void {
        // The view will show more than the scroll height if the scroll y is close to the bottom.
        self.eff_scroll_height = std.math.max(self.scroll_height, self.scroll_y + height);
        self.eff_scroll_width = std.math.max(self.scroll_width, self.scroll_x + width);

        self.has_vbar = height < self.eff_scroll_height;
        self.has_hbar = width < self.eff_scroll_width;
    }

    pub fn renderCustom(self: *Self, ctx: *ui.RenderContext) void {
        const alo = ctx.getAbsLayout();
        const g = ctx.getGraphics();

        g.setFillColor(self.props.bg_color);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        g.pushState();
        g.clipRect(alo.x, alo.y, alo.width, alo.height);

        ctx.renderChildren();

        // Computes the layout of the scrollbars here since it depends on layout phase completed to obtain the final ScrollView size.
        g.popState();

        // Draw borders and scrollbars over the content.
        if (self.props.show_border) {
            g.setStrokeColor(self.props.border_color);
            g.setLineWidth(2);
            g.drawRect(alo.x, alo.y, alo.width, alo.height);
        }

        // Draw bottom right corner.
        if (self.has_vbar and self.has_hbar) {
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x + alo.width - BarSize, alo.y + alo.height - BarSize, BarSize, BarSize);
        }

        if (self.has_vbar) {
            var max_bar_height = alo.height;
            if (self.has_hbar) {
                max_bar_height -= BarSize;
            }

            // Draw vertical scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x + alo.width - BarSize, alo.y, BarSize, max_bar_height);

            // Draw thumb.
            const view_to_scroll_height = max_bar_height / self.eff_scroll_height;
            const vert_thumb_length = view_to_scroll_height * alo.height;
            const vert_thumb_y = view_to_scroll_height * self.scroll_y;
            g.setFillColor(Color.Gray);
            g.fillRect(alo.x + alo.width - BarSize, alo.y + vert_thumb_y, BarSize, vert_thumb_length);
        }

        if (self.has_hbar) {
            var max_bar_width = alo.width;
            if (self.has_vbar) {
                max_bar_width -= BarSize;
            }

            // Draw horizontal scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(alo.x, alo.y + alo.height - BarSize, max_bar_width, BarSize);

            // Draw thumb.
            const view_to_scroll_width = max_bar_width / self.eff_scroll_width;
            const hor_thumb_length = view_to_scroll_width * alo.width;
            const hor_thumb_x = view_to_scroll_width * self.scroll_x;
            g.setFillColor(Color.Gray);
            g.fillRect(alo.x + hor_thumb_x, alo.y + alo.height - BarSize, hor_thumb_length, BarSize);
        }
    }
};