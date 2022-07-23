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
        bg_color: Color = Color.Transparent,
        border_color: Color = Color.DarkGray,
        enable_hscroll: bool = true,
        show_border: bool = true,

        /// Triggered when mouse down hits the content rather than the scrollbars.
        onContentMouseDown: ?stdx.Function(fn (platform.MouseDownEvent) void) = null,
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

    dragging_hbar: bool,
    dragging_offset: f32,
    dragging_vbar: bool,

    node: *Node,
    scroll_to_bottom_after_layout: bool,

    const BarSize = 15;

    pub fn init(self: *ScrollView, c: *ui.InitContext) void {
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
        self.dragging_hbar = false;
        self.dragging_vbar = false;
        c.addMouseDownHandler(self, onMouseDown);
        c.addMouseScrollHandler(self, onMouseScroll);
    }

    pub fn build(self: *ScrollView, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    fn onMouseDown(self: *ScrollView, e: ui.MouseDownEvent) ui.EventResult {
        const nbounds = e.ctx.node.getAbsBounds();
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        if (self.has_hbar) {
            const bounds = self.getHBarBounds(nbounds);
            if (xf >= bounds.thumb_x and xf <= bounds.thumb_x + bounds.thumb_width and yf >= bounds.y and yf <= bounds.y + bounds.height) {
                self.dragging_hbar = true;
                self.dragging_offset = xf - bounds.thumb_x;
                e.ctx.removeMouseMoveHandler(*ScrollView, onMouseMove);
                e.ctx.removeMouseUpHandler(*ScrollView, onMouseUp);
                e.ctx.addMouseMoveHandler(self, onMouseMove);
                e.ctx.addGlobalMouseUpHandler(self, onMouseUp);
                e.ctx.requestCaptureMouse(true);
                return .Stop;
            }
        }

        if (self.has_vbar) {
            const bounds = self.getVBarBounds(nbounds);
            if (xf >= bounds.x and xf <= bounds.x + bounds.width and yf >= bounds.thumb_y and yf <= bounds.thumb_y + bounds.height) {
                self.dragging_vbar = true;
                self.dragging_offset = yf - bounds.thumb_y;
                e.ctx.removeMouseMoveHandler(*ScrollView, onMouseMove);
                e.ctx.removeMouseUpHandler(*ScrollView, onMouseUp);
                e.ctx.addMouseMoveHandler(self, onMouseMove);
                e.ctx.addGlobalMouseUpHandler(self, onMouseUp);
                e.ctx.requestCaptureMouse(true);
                return .Stop;
            }
        }

        if (self.props.onContentMouseDown) |cb| {
            cb.call(.{ e.val });
        }

        return .Continue;
    }

    fn onMouseUp(self: *ScrollView, e: ui.MouseUpEvent) void {
        self.dragging_hbar = false;
        self.dragging_vbar = false;
        e.ctx.removeMouseMoveHandler(*ScrollView, onMouseMove);
        e.ctx.removeMouseUpHandler(*ScrollView, onMouseUp);
        e.ctx.requestCaptureMouse(false);
    }

    fn onMouseMove(self: *ScrollView, e: ui.MouseMoveEvent) void {
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        if (self.dragging_hbar) {
            const nbounds = self.node.getAbsBounds();
            const bounds = self.getHBarBounds(nbounds);
            var thumb_x = xf - (bounds.x + self.dragging_offset);
            if (thumb_x < 0) {
                thumb_x = 0;
            }
            if (thumb_x > bounds.width - bounds.thumb_width) {
                thumb_x = bounds.width - bounds.thumb_width;
            }
            // thumbx back to scrollx
            self.scroll_x = thumb_x / bounds.width * self.eff_scroll_width;
        } else if (self.dragging_vbar) {
            const nbounds = self.node.getAbsBounds();
            const bounds = self.getVBarBounds(nbounds);
            var thumb_y = yf - (bounds.y + self.dragging_offset);
            if (thumb_y < 0) {
                thumb_y = 0;
            }
            if (thumb_y > bounds.height - bounds.thumb_height) {
                thumb_y = bounds.height - bounds.thumb_height;
            }
            // thumby back to scrolly
            self.scroll_y = thumb_y / bounds.height * self.eff_scroll_height;
        }
    }

    fn onMouseScroll(self: *ScrollView, e: ui.MouseScrollEvent) void {
        self.scroll_y += e.val.delta_y;
        self.checkScroll();
    }

    pub fn postPropsUpdate(self: *ScrollView) void {
        self.checkScroll();
    }

    pub fn scrollToBottomAfterLayout(self: *ScrollView) void {
        self.scroll_to_bottom_after_layout = true;
    }

    fn checkScroll(self: *ScrollView) void {
        if (self.scroll_y < 0) {
            self.scroll_y = 0;
        }
        if (self.scroll_height > self.node.layout.height) {
            if (self.scroll_y > self.eff_scroll_height - self.node.layout.height) {
                self.scroll_y = self.eff_scroll_height - self.node.layout.height;
            }
        } else {
            if (self.scroll_y > 0) {
                self.scroll_y = 0;
            }
        }
    }

    /// In some cases, it's desirable to change the scroll view after the layout phase (when scroll width/height is updated) and before the render phase.
    /// eg. Scroll to cursor view.
    /// Since layout has already run, the children need to be repositioned.
    pub fn setScrollPosAfterLayout(self: *ScrollView, node: *Node, scroll_x: f32, scroll_y: f32) void {
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
    pub fn layout(self: *ScrollView, c: *ui.LayoutContext) ui.LayoutSize {
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
    fn computeEffScrollDims(self: *ScrollView, width: f32, height: f32) void {
        // The view will show more than the scroll height if the scroll y is close to the bottom.
        if (self.scroll_height > height) {
            self.eff_scroll_height = self.scroll_height + height * 0.5;
        } else {
            self.eff_scroll_height = self.scroll_height;
        }
        if (self.scroll_width > width) {
            self.eff_scroll_width = self.scroll_width + width * 0.5;
        } else {
            self.eff_scroll_width = self.scroll_width;
        }

        self.has_vbar = height < self.eff_scroll_height;
        self.has_hbar = width < self.eff_scroll_width;
    }

    pub fn renderCustom(self: *ScrollView, ctx: *ui.RenderContext) void {
        const bounds = ctx.getAbsBounds();
        const g = ctx.getGraphics();

        if (self.props.bg_color.channels.a > 0) {
            g.setFillColor(self.props.bg_color);
            ctx.fillBBox(bounds);
        }

        g.pushState();
        g.clipRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);

        ctx.renderChildren();

        // Computes the layout of the scrollbars here since it depends on layout phase completed to obtain the final ScrollView size.
        g.popState();

        // Draw borders and scrollbars over the content.
        if (self.props.show_border) {
            g.setStrokeColor(self.props.border_color);
            g.setLineWidth(2);
            ctx.drawBBox(bounds);
        }

        // Draw bottom right corner.
        if (self.has_vbar and self.has_hbar) {
            g.setFillColor(Color.LightGray);
            g.fillRect(bounds.max_x - BarSize, bounds.max_y - BarSize, BarSize, BarSize);
        }

        if (self.has_vbar) {
            const bar_bounds = self.getVBarBounds(bounds);

            // Draw vertical scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(bar_bounds.x, bar_bounds.y, bar_bounds.width, bar_bounds.height);

            // Draw thumb.
            g.setFillColor(Color.Gray);
            g.fillRect(bar_bounds.x, bar_bounds.thumb_y, bar_bounds.width, bar_bounds.thumb_height);
        }

        if (self.has_hbar) {
            const bar_bounds = self.getHBarBounds(bounds);

            // Draw horizontal scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(bar_bounds.x, bar_bounds.y, bar_bounds.width, bar_bounds.height);

            // Draw thumb.
            g.setFillColor(Color.Gray);
            g.fillRect(bar_bounds.thumb_x, bar_bounds.y, bar_bounds.thumb_width, bar_bounds.height);
        }
    }

    fn getVBarBounds(self: ScrollView, bounds: stdx.math.BBox) VBarBounds {
        const height = bounds.computeHeight();
        var max_bar_height = height;
        if (self.has_hbar) {
            max_bar_height -= BarSize;
        }
        const view_to_scroll_height = max_bar_height / self.eff_scroll_height;
        const vert_thumb_length = view_to_scroll_height * height;
        const vert_thumb_y = view_to_scroll_height * self.scroll_y;
        return .{
            .x = bounds.max_x - BarSize,
            .y = bounds.min_y,
            .width = BarSize,
            .height = max_bar_height,
            .thumb_y = bounds.min_y + vert_thumb_y,
            .thumb_height = vert_thumb_length,
        };
    }

    fn getHBarBounds(self: ScrollView, bounds: stdx.math.BBox) HBarBounds {
        const width = bounds.computeWidth();
        var max_bar_width = width;
        if (self.has_vbar) {
            max_bar_width -= BarSize;
        }
        const view_to_scroll_width = max_bar_width / self.eff_scroll_width;
        const hor_thumb_length = view_to_scroll_width * width;
        const hor_thumb_x = view_to_scroll_width * self.scroll_x;
        return .{
            .x = bounds.min_x,
            .y = bounds.max_y - BarSize,
            .width = max_bar_width,
            .height = BarSize,
            .thumb_x = bounds.min_x + hor_thumb_x,
            .thumb_width = hor_thumb_length,
        };
    }
};

const HBarBounds = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    thumb_x: f32,
    thumb_width: f32,
};

const VBarBounds = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    thumb_y: f32,
    thumb_height: f32,
};