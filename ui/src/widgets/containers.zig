const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.containers);

/// Provides padding around a child widget.
pub const Padding = struct {
    props: struct {
        pad_top: ?f32 = null,
        pad_right: ?f32 = null,
        pad_bottom: ?f32 = null,
        pad_left: ?f32 = null,
        padding: f32 = 10,
        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn build(self: *Padding, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *Padding, c: *ui.LayoutContext) ui.LayoutSize {
        var pad_top = self.props.pad_top orelse self.props.padding;
        var pad_right = self.props.pad_right orelse self.props.padding;
        var pad_bottom = self.props.pad_bottom orelse self.props.padding;
        var pad_left = self.props.pad_left orelse self.props.padding;

        const h_pad = pad_left + pad_right;
        const v_pad = pad_top + pad_bottom;

        if (self.props.child == ui.NullFrameId) {
            return ui.LayoutSize.init(h_pad, v_pad);
        }

        const cstr = c.getSizeConstraints();
        const node = c.getNode();
        const child = node.children.items[0];

        const min_width = std.math.max(cstr.min_width - h_pad, 0);
        const min_height = std.math.max(cstr.min_height - v_pad, 0);
        const max_width = std.math.max(cstr.max_width - h_pad, 0);
        const max_height = std.math.max(cstr.max_height - v_pad, 0);
        const child_size = c.computeLayout(child, min_width, min_height, max_width, max_height);
        c.setLayout(child, ui.Layout.init(pad_left, pad_top, child_size.width, child_size.height));
        return child_size.toIncSize(h_pad, v_pad);
    }
};

pub const Sized = struct {
    props: struct {
        /// If width is not provided, this container will shrink to the child's width.
        width: ?f32 = null,

        /// If height is not provided, this container will shrink to the child's height.
        height: ?f32 = null,

        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn build(self: *Sized, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *Sized, ctx: *ui.LayoutContext) ui.LayoutSize {
        return sizedWrapChildLayout(ctx, self.props.width, self.props.height, self.props.child);
    }
};

fn sizedWrapChildLayout(ctx: *ui.LayoutContext, m_width: ?f32, m_height: ?f32, child_id: ui.FrameId) ui.LayoutSize {
    var child_cstr = ctx.getSizeConstraints();
    if (m_width) |width| {
        if (width != ui.ExpandedWidth) {
            if (width < child_cstr.max_width) {
                child_cstr.min_width = width;
                child_cstr.max_width = width;
            }
        } else {
            child_cstr.min_width = child_cstr.max_width;
        }
    }
    if (m_height) |height| {
        if (height != ui.ExpandedHeight) {
            if (height < child_cstr.max_height) {
                child_cstr.min_height = height;
                child_cstr.max_height = height;
            }
        } else {
            child_cstr.min_height = child_cstr.max_height;
        }
    }
    if (child_id != ui.NullFrameId) {
        const child = ctx.getNode().children.items[0];
        const child_size = ctx.computeLayout2(child, child_cstr);
        ctx.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));

        var res = child_size;
        res.growToMin(child_cstr);
        return res;
    } else {
        return child_cstr.getMinLayoutSize();
    }
}

pub const Center = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        vcenter: bool = true,
        hcenter: bool = true,
    },

    pub fn build(self: *Center, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Center, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child == ui.NullFrameId) {
            return cstr.getMaxLayoutSize();
        }

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayoutWithMax(child, cstr.max_width, cstr.max_height);

        const x = if (self.props.hcenter) (cstr.max_width - child_size.width) * 0.5 else 0;
        const y = if (self.props.vcenter) (cstr.max_height - child_size.height) * 0.5 else 0;

        c.setLayout(child, ui.Layout.init(x, y, child_size.width, child_size.height));
        return cstr.getMaxLayoutSize();
    }
};

const StretchMethod = enum(u3) {
    None = 0,
    Both = 1,
    Width = 2,
    Height = 3,
    WidthAndKeepRatio = 4,
    HeightAndKeepRatio = 5,
};

/// When method = WidthAndKeepRatio, the width is stretched and the height is adjusted to keep the aspect ratio.
/// When method = HeightAndKeepRatio, the height is stretched and the width is adjusted to keep the aspect ratio.
pub const Stretch = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        method: StretchMethod = .Both,

        /// Width to height ratio.
        aspect_ratio: f32 = 1,
    },

    pub fn build(self: *Stretch, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *Stretch, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        var child_cstr = cstr.getMaxLayoutSize();
        switch (self.props.method) {
            .WidthAndKeepRatio => child_cstr.height = child_cstr.width / self.props.aspect_ratio,
            .HeightAndKeepRatio => child_cstr.width = child_cstr.height * self.props.aspect_ratio,
            else => {},
        }

        if (self.props.child == ui.NullFrameId) {
            return child_cstr;
        }

        const h_stretch = self.props.method == .Both or self.props.method == .Width or self.props.method == .WidthAndKeepRatio or self.props.method == .HeightAndKeepRatio;
        const v_stretch = self.props.method == .Both or self.props.method == .Height or self.props.method == .WidthAndKeepRatio or self.props.method == .HeightAndKeepRatio;

        const node = c.getNode();
        const child = node.children.items[0];
        const min_width = if (h_stretch) child_cstr.width else 0;
        const min_height = if (v_stretch) child_cstr.height else 0;
        const child_size = c.computeLayout(child, min_width, min_height, child_cstr.width, child_cstr.height);
        c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));
        return child_size;
    }
};

// TODO: Children can override the order by providing a z-index property. All children default to 0 z-index which results in the natural order.
//       A higher z-index would raise the child up.
/// Stacks children over each other. The first child will be rendered last and receive input events last.
pub const ZStack = struct {
    props: struct {
        children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
    },

    /// Ordered by z-index asc.
    ordered_children: std.ArrayList(u32),

    /// Ordered by z-index desc.
    child_event_ordering: std.ArrayList(*ui.Node),

    pub const ChildrenCanOverlap = true;

    pub fn init(self: *ZStack, c: *ui.InitContext) void {
        self.ordered_children = std.ArrayList(u32).init(c.alloc);
        self.child_event_ordering = std.ArrayList(*ui.Node).init(c.alloc);
    }

    pub fn deinit(self: *ZStack, _: std.mem.Allocator) void {
        self.ordered_children.deinit();
        self.child_event_ordering.deinit();
    }

    pub fn build(self: *ZStack, c: *ui.BuildContext) ui.FrameId {
        // Ordering is determined at build step.
        self.ordered_children.ensureTotalCapacity(self.props.children.len) catch @panic("error");
        self.ordered_children.items.len = 0;

        // For now, the order is the same.
        var i: u32 = 0;
        while (i < self.props.children.len) : (i += 1) {
            self.ordered_children.appendAssumeCapacity(i);
        }

        return c.fragment(self.props.children);
    }

    pub fn postUpdate(node: *ui.Node) void {
        const self = node.getWidget(ZStack);

        // Child event ordering is z-index desc.
        self.child_event_ordering.ensureTotalCapacity(self.props.children.len) catch @panic("error");
        self.child_event_ordering.items.len = 0;
        var i = @intCast(u32, self.props.children.len);
        while (i > 0) {
            i -= 1;
            self.child_event_ordering.appendAssumeCapacity(node.children.items[i]);
        }
        node.setChildEventOrdering(self.child_event_ordering.items);
    }

    /// Return ordering sorted by z-index desc.
    pub fn childEventOrdering(self: *ZStack) []const u32 {
        return self.child_event_ordering.items;
    }

    pub fn renderCustom(self: *ZStack, c: *ui.RenderContext) void {
        const node = c.node;

        // Rendered by z-index asc.
        for (self.ordered_children.items) |idx| {
            const child = node.children.items[idx];
            c.renderChildNode(node, child);
        }
    }
};

pub const Container = struct {
    props: struct {
        bgColor: Color = Color.Transparent,

        /// If width is not provided, this container will shrink to the child's width.
        width: ?f32 = null,

        /// If height is not provided, this container will shrink to the child's height.
        height: ?f32 = null,

        /// Outline is drawn if size is greater than 0.
        outlineSize: f32 = 0,
        outlineColor: Color = Color.Transparent,

        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn build(self: *Container, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *Container, ctx: *ui.LayoutContext) ui.LayoutSize {
        return sizedWrapChildLayout(ctx, self.props.width, self.props.height, self.props.child);
    }

    pub fn render(self: *Container, ctx: *ui.RenderContext) void {
        const bounds = ctx.getAbsBounds();
        const gctx = ctx.gctx;

        if (self.props.bgColor.channels.a > 0) {
            gctx.setFillColor(self.props.bgColor);
            ctx.fillBBox(bounds);
        }
    }

    pub fn postRender(self: *Container, ctx: *ui.RenderContext) void {
        const gctx = ctx.gctx;
        if (self.props.outlineSize > 0) {
            gctx.setStrokeColor(self.props.outlineColor);
            gctx.setLineWidth(self.props.outlineSize);
            ctx.drawBBox(ctx.getAbsBounds());
        }
    }
};

/// Takes up max available space and positions child to relative itself.
pub const Positioned = struct {
    props: struct {
        /// Relative x from parent.
        x: f32,
        /// Relative y from parent.
        y: f32,
        width: ?f32 = null,
        height: ?f32 = null,
        child: ui.FrameId = ui.NullFrameId,
    },

    pub fn build(self: *Positioned, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *Positioned, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        if (self.props.child == ui.NullFrameId) {
            return cstr.getMaxLayoutSize();
        }

        const node = c.getNode();
        const child = node.children.items[0];

        const max_child_width = self.props.width orelse cstr.max_width - self.props.x;
        const max_child_height = self.props.height orelse cstr.max_height - self.props.y;
        const child_size = c.computeLayoutWithMax(child, max_child_width, max_child_height);
        c.setLayout(child, ui.Layout.init(self.props.x, self.props.y, child_size.width, child_size.height));
        return cstr.getMaxLayoutSize();
    }
};