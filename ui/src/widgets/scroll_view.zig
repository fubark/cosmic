const std = @import("std");
const stdx = @import("stdx");
const platform = @import("platform");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("../ui.zig");
const Node = ui.Node;
const FrameListPtr = ui.FrameListPtr;

const log = stdx.log.scoped(.scroll_view);

/// Currently, the scrollbars do not contribute to the child container space and act like overlays.
/// Doing so would require more complex logic and would either need to recompute the layout or defer recompute to the next frame.
/// A similar effect can be achieved with padding or making the scrollbars thinner. People don't like big scrollbars anyway.
pub const ScrollView = struct {
    const Self = @This();
    const bar_size = 15;

    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        bg_color: Color = Color.White,
        border_color: Color = Color.DarkGray,
        pass_stretch_width: bool = false,
    },

    /// Internal vars. They should not be modified after the layout phase.
    /// Adjusting the scroll pos after layout and before render must call setScrollPosAfterLayout()
    scroll_x: f32,
    scroll_y: f32,
    scroll_width: f32,
    scroll_height: f32,

    node: *Node,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        _ = c;
        self.scroll_x = 0;
        self.scroll_y = 0;
        self.scroll_width = 0;
        self.scroll_height = 0;
        self.node = c.node;
        c.addMouseScrollHandler(self, onMouseScroll);
    }

    fn onMouseScroll(self: *Self, e: ui.Event(platform.MouseScrollEvent)) void {
        self.scroll_y += e.val.delta_y;
        self.checkScroll();
    }

    pub fn postUpdate(self: *Self) void {
        self.checkScroll();
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

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
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
    }

    /// Take up the same amount of space as it's children stacked over each other.
    /// Records scroll width and height.
    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        const node = c.getNode();
        const size_cstr = ui.LayoutSize.init(std.math.inf(f32), std.math.inf(f32));
        self.scroll_height = 0;
        self.scroll_width = 0;

        if (self.props.child != ui.NullFrameId) {
            const child = node.children.items[0];
            var child_size: ui.LayoutSize = undefined;
            if (c.prefer_exact_width and self.props.pass_stretch_width) {
                child_size = c.computeLayoutStretch(child, ui.LayoutSize.init(c.getSizeConstraint().width, std.math.inf(f32)), true, false);
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
        return res;
    }

    pub fn render(self: *Self, ctx: *ui.RenderContext) void {
        _ = self;
        const alo = ctx.getAbsLayout();
        const g = ctx.getGraphics();

        g.setFillColor(self.props.bg_color);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        ctx.g.pushState();
        ctx.g.clipRect(alo.x, alo.y, alo.width, alo.height);
    }

    /// Computes the layout of the scrollbars here since it depends on layout phase completed to obtain the final ScrollView size.
    pub fn postRender(self: *Self, ctx: *ui.RenderContext) void {
        _ = self;
        ctx.g.popState();

        // Draw borders and scrollbars over the content.

        const alo = ctx.getAbsLayout();

        const g = ctx.getGraphics();
        g.setStrokeColor(self.props.border_color);
        g.setLineWidth(2);
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