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
        self.dragging_hbar = false;
        self.dragging_vbar = false;
        c.addMouseDownHandler(self, onMouseDown);
        c.addMouseScrollHandler(self, onMouseScroll);
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    fn onMouseDown(self: *Self, e: ui.MouseDownEvent) ui.EventResult {
        const alo = e.ctx.node.getAbsLayout();
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        if (self.has_hbar) {
            const bounds = self.getHBarBounds(alo);
            if (xf >= bounds.thumb_x and xf <= bounds.thumb_x + bounds.thumb_width and yf >= bounds.y and yf <= bounds.y + bounds.height) {
                self.dragging_hbar = true;
                self.dragging_offset = xf - bounds.thumb_x;
                e.ctx.removeMouseMoveHandler(*Self, onMouseMove);
                e.ctx.removeMouseUpHandler(*Self, onMouseUp);
                e.ctx.addMouseMoveHandler(self, onMouseMove);
                e.ctx.addGlobalMouseUpHandler(self, onMouseUp);
                e.ctx.requestCaptureMouse(true);
                return .Stop;
            }
        }

        if (self.has_vbar) {
            const bounds = self.getVBarBounds(alo);
            if (xf >= bounds.x and xf <= bounds.x + bounds.width and yf >= bounds.thumb_y and yf <= bounds.thumb_y + bounds.height) {
                self.dragging_vbar = true;
                self.dragging_offset = yf - bounds.thumb_y;
                e.ctx.removeMouseMoveHandler(*Self, onMouseMove);
                e.ctx.removeMouseUpHandler(*Self, onMouseUp);
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

    fn onMouseUp(self: *Self, e: ui.MouseUpEvent) void {
        self.dragging_hbar = false;
        self.dragging_vbar = false;
        e.ctx.removeMouseMoveHandler(*Self, onMouseMove);
        e.ctx.removeMouseUpHandler(*Self, onMouseUp);
        e.ctx.requestCaptureMouse(false);
    }

    fn onMouseMove(self: *Self, e: ui.MouseMoveEvent) void {
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        if (self.dragging_hbar) {
            const alo = self.node.getAbsLayout();
            const bounds = self.getHBarBounds(alo);
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
            const alo = self.node.getAbsLayout();
            const bounds = self.getVBarBounds(alo);
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
            const bounds = self.getVBarBounds(alo);

            // Draw vertical scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(bounds.x, bounds.y, bounds.width, bounds.height);

            // Draw thumb.
            g.setFillColor(Color.Gray);
            g.fillRect(bounds.x, bounds.thumb_y, bounds.width, bounds.thumb_height);
        }

        if (self.has_hbar) {
            const bounds = self.getHBarBounds(alo);

            // Draw horizontal scrollbar.
            g.setFillColor(Color.LightGray);
            g.fillRect(bounds.x, bounds.y, bounds.width, bounds.height);

            // Draw thumb.
            g.setFillColor(Color.Gray);
            g.fillRect(bounds.thumb_x, bounds.y, bounds.thumb_width, bounds.height);
        }
    }

    fn getVBarBounds(self: Self, alo: ui.Layout) VBarBounds {
        var max_bar_height = alo.height;
        if (self.has_hbar) {
            max_bar_height -= BarSize;
        }
        const view_to_scroll_height = max_bar_height / self.eff_scroll_height;
        const vert_thumb_length = view_to_scroll_height * alo.height;
        const vert_thumb_y = view_to_scroll_height * self.scroll_y;
        return .{
            .x = alo.x + alo.width - BarSize,
            .y = alo.y,
            .width = BarSize,
            .height = max_bar_height,
            .thumb_y = alo.y + vert_thumb_y,
            .thumb_height = vert_thumb_length,
        };
    }

    fn getHBarBounds(self: Self, alo: ui.Layout) HBarBounds {
        var max_bar_width = alo.width;
        if (self.has_vbar) {
            max_bar_width -= BarSize;
        }
        const view_to_scroll_width = max_bar_width / self.eff_scroll_width;
        const hor_thumb_length = view_to_scroll_width * alo.width;
        const hor_thumb_x = view_to_scroll_width * self.scroll_x;
        return .{
            .x = alo.x,
            .y = alo.y + alo.height - BarSize,
            .width = max_bar_width,
            .height = BarSize,
            .thumb_x = alo.x + hor_thumb_x,
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