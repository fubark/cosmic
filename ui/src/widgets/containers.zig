const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const platform = @import("platform");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.containers);

/// Provides a border around a child widget.
pub const Border = struct {
    props: struct {
        child: ui.FramePtr = .{},
    },

    pub const Style = struct {
        color: ?Color = null,
        size: ?f32 = null,
        cornerRadius: ?f32 = null,
        bgColor: ?Color = null,
    };

    pub const ComputedStyle = struct {
        color: Color = Color.DarkGray,
        size: f32 = 1,
        cornerRadius: f32 = 0,
        bgColor: Color = Color.Transparent,
    };

    pub fn build(self: *Border, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Border, ctx: *ui.LayoutContext) ui.LayoutSize {
        const style = ctx.getStyle(Border);
        const left_offset = style.size;
        const top_offset = style.size;
        const h_size = style.size * 2;
        const v_size = style.size * 2;

        if (self.props.child.isNull()) {
            return ui.LayoutSize.init(h_size, v_size);
        }

        const cstr = ctx.getSizeConstraints();
        const node = ctx.getNode();
        const child = node.children.items[0];

        const min_width = std.math.max(cstr.min_width - h_size, 0);
        const min_height = std.math.max(cstr.min_height - v_size, 0);
        const max_width = std.math.max(cstr.max_width - h_size, 0);
        const max_height = std.math.max(cstr.max_height - v_size, 0);
        const child_size = ctx.computeLayout(child, min_width, min_height, max_width, max_height);
        ctx.setLayout(child, ui.Layout.init(left_offset, top_offset, child_size.width, child_size.height));
        return child_size.toIncSize(h_size, v_size);
    }

    pub fn renderCustom(self: *Border, ctx: *ui.RenderContext) void {
        _ = self;
        const b = ctx.getAbsBounds();

        const style = ctx.getStyle(Border);
        if (!style.bgColor.isTransparent()) {
            ctx.gctx.setFillColor(style.bgColor);
            if (style.cornerRadius > 0) {
                ctx.fillRoundBBox(b, style.cornerRadius);
            } else {
                ctx.fillBBox(b);
            }
        }

        ctx.renderChildren();

        // TODO: Provide optional flag to clip the child.

        // Draw border over children.
        ctx.gctx.setStrokeColor(style.color);
        ctx.gctx.setLineWidth(style.size);
        if (style.cornerRadius > 0) {
            ctx.strokeRoundBBoxInward(b, style.cornerRadius);
        } else {
            ctx.strokeBBoxInward(b);
        }
    }
};

/// Provides padding around a child widget.
pub const Padding = struct {
    props: struct {
        padTop: ?f32 = null,
        padRight: ?f32 = null,
        padBottom: ?f32 = null,
        padLeft: ?f32 = null,
        padding: f32 = 10,
        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Padding, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Padding, c: *ui.LayoutContext) ui.LayoutSize {
        var pad_top = self.props.padTop orelse self.props.padding;
        var pad_right = self.props.padRight orelse self.props.padding;
        var pad_bottom = self.props.padBottom orelse self.props.padding;
        var pad_left = self.props.padLeft orelse self.props.padding;

        const h_pad = pad_left + pad_right;
        const v_pad = pad_top + pad_bottom;

        if (self.props.child.isNull()) {
            return ui.LayoutSize.init(h_pad, v_pad);
        }

        const cstr = c.getSizeConstraints();
        const child = c.getFirstChild();

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

        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Sized, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Sized, ctx: *ui.LayoutContext) ui.LayoutSize {
        return sizedWrapChildLayout(ctx, self.props.width, self.props.height, self.props.child);
    }
};

fn sizedWrapChildLayout(ctx: *ui.LayoutContext, m_width: ?f32, m_height: ?f32, child_frame: ui.FramePtr) ui.LayoutSize {
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
    if (child_frame.isPresent()) {
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
        child: ui.FramePtr = .{},
        vcenter: bool = true,
        hcenter: bool = true,
    },

    pub fn build(self: *Center, c: *ui.BuildContext) ui.FramePtr {
        _ = c;
        return self.props.child.dupe();
    }

    pub fn layout(self: *Center, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child.isNull()) {
            return cstr.getMaxLayoutSize();
        }

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayoutWithMax(child, cstr.max_width, cstr.max_height);

        // Wrap child height otherwise take up finite parent height.
        const height = if (cstr.max_height == ui.ExpandedHeight) child_size.height else cstr.max_height;

        const x = if (self.props.hcenter) (cstr.max_width - child_size.width) * 0.5 else 0;
        const y = if (self.props.vcenter) (height - child_size.height) * 0.5 else 0;

        c.setLayout(child, ui.Layout.init(x, y, child_size.width, child_size.height));
        return ui.LayoutSize.init(cstr.max_width, height);
    }
};

/// Respects parent constraints and keeps the child's aspect ratio.
/// Only child widgets that support resize work.
pub const KeepAspectRatio = struct {
    props: struct {
        child: ui.FramePtr = .{},
    },

    pub fn build(self: *KeepAspectRatio, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *KeepAspectRatio, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.child.isNull()) {
            return ui.LayoutSize.init(0, 0);
        }

        const cstr = c.getSizeConstraints();

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayoutInherit(child);
        if (child_size.width > cstr.max_width) {
            child_size.height = cstr.max_width * child_size.height / child_size.width;
            child_size.width = cstr.max_width;
        }
        if (child_size.height > cstr.max_height) {
            child_size.width = cstr.max_height * child_size.width / child_size.height;
            child_size.height = cstr.max_height;
        }
        c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));

        // TODO: Handle min size.
        return child_size;
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
        child: ui.FramePtr = .{},
        method: StretchMethod = .Both,

        /// Width to height ratio.
        aspect_ratio: f32 = 1,
    },

    pub fn build(self: *Stretch, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Stretch, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        var child_cstr = cstr.getMaxLayoutSize();
        switch (self.props.method) {
            .WidthAndKeepRatio => child_cstr.height = child_cstr.width / self.props.aspect_ratio,
            .HeightAndKeepRatio => child_cstr.width = child_cstr.height * self.props.aspect_ratio,
            else => {},
        }

        if (self.props.child.isNull()) {
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
/// Stacks children over each other. The first child will be rendered first and receive input events last.
pub const ZStack = struct {
    props: struct {
        children: ui.FrameListPtr = .{},
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

    pub fn deinit(self: *ZStack, _: *ui.DeinitContext) void {
        self.ordered_children.deinit();
        self.child_event_ordering.deinit();
    }

    pub fn build(self: *ZStack, c: *ui.BuildContext) ui.FramePtr {
        // Ordering is determined at build step.
        if (self.props.children.isPresent()) {
            const children = self.props.children.get();
            const len = children.size();

            self.ordered_children.ensureTotalCapacity(len) catch @panic("error");
            self.ordered_children.items.len = 0;

            // For now, the order is the same.
            var i: u32 = 0;
            while (i < len) : (i += 1) {
                self.ordered_children.appendAssumeCapacity(i);
            }
        } else {
            self.ordered_children.items.len = 0;
        }

        return c.fragment(self.props.children.dupe());
    }

    pub fn postUpdate(self: *ZStack, ctx: *ui.UpdateContext) void {
        // Child event ordering is z-index desc.
        if (self.props.children.isPresent()) {
            const len = ctx.node.children.items.len;
            self.child_event_ordering.ensureTotalCapacity(len) catch @panic("error");
            self.child_event_ordering.items.len = 0;
            var i = @intCast(u32, len);
            while (i > 0) {
                i -= 1;
                self.child_event_ordering.appendAssumeCapacity(ctx.node.children.items[i]);
            }
        } else {
            self.child_event_ordering.items.len = 0;
        }
        ctx.node.setChildEventOrdering(self.child_event_ordering.items);
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

        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Container, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
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
            ctx.strokeBBoxInward(ctx.getAbsBounds());
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
        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Positioned, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Positioned, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();
        if (self.props.child.isNull()) {
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

pub const TabView = struct {
    props: struct {
        numTabs: u32 = 0,
        buildTab: stdx.Function(fn (*ui.BuildContext, idx: u32, active: bool) ui.FramePtr) = .{},
        buildContent: stdx.Function(fn (*ui.BuildContext, idx: u32) ui.FramePtr) = .{},
    },

    tab_idx: u32,

    pub const Style = struct {
        tabBgColor: ?Color = null,
        activeTabBgColor: ?Color = null,
    };

    pub const ComputedStyle = struct {
        tabBgColor: Color = Color.Transparent,
        activeTabBgColor: Color = Color.White,
    };

    pub fn init(self: *TabView, _: *ui.InitContext) void {
        self.tab_idx = 0;
    }

    pub fn build(self: *TabView, ctx: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn buildTab(self_: *TabView, ctx_: *ui.BuildContext, idx: u32) ui.FramePtr {
                const style = ctx_.getStyle(TabView);
                const active = self_.tab_idx == idx;
                const user_inner = self_.props.buildTab.call(.{ ctx_, idx, active });
                const bgColor = if (active) style.activeTabBgColor else style.tabBgColor;
                return u.MouseArea(.{ .onClick = ctx_.closurePtrId(self_, idx, onClickTab) },
                    u.Container(.{ .bgColor = bgColor },
                        u.Padding(.{ .padding = 0, .padLeft = 5, .padRight = 5 },
                            user_inner,
                        ),
                    ),
                );
            }
        };
        var content = ui.FramePtr{};
        if (self.props.buildContent.isPresent()) {
            content = self.props.buildContent.call(.{ ctx, self.tab_idx });
        }

        var tabs: []const ui.FramePtr = &.{};
        if (self.props.buildTab.isPresent()) {
            tabs = ctx.tempRange(self.props.numTabs, self, S.buildTab);
        }
        return u.Column(.{ .expand_child_width = true }, &.{
            u.Row(.{}, tabs),
            u.Flex(.{}, content),
        });
    }

    pub fn onClickTab(ptr_id: ui.PtrId, _: ui.MouseUpEvent) void {
        const self = ptr_id.castPtr(*TabView);
        const idx = @intCast(u32, ptr_id.id);
        self.tab_idx = idx;
    }
};

pub const Link = struct {
    props: struct {
        uri: ui.SlicePtr(u8) = .{},
        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Link, ctx: *ui.BuildContext) ui.FramePtr {
        return u.MouseArea(.{ .onClick = ctx.funcExt(self, onClick) },
            self.props.child.dupe(),
        );
    }

    fn onClick(self: *Link, e: ui.MouseUpEvent) void {
        _ = e;
        const uri = self.props.uri.slice();
        if (std.mem.startsWith(u8, uri, "https://") or std.mem.startsWith(u8, uri, "http://")) {
            platform.openUrl(uri);
        }
    }
};

/// Constrained wrapper over a child widget.
pub const Constrained = struct {
    props: struct {
        minWidth: ?f32 = null,
        minHeight: ?f32 = null,
        maxWidth: ?f32 = null,
        maxHeight: ?f32 = null,
        child: ui.FramePtr = .{},
    },

    pub fn build(self: *Constrained, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *Constrained, ctx: *ui.LayoutContext) ui.LayoutSize {
        var cstr = ctx.getSizeConstraints();
        cstr.min_width = self.props.minWidth orelse cstr.min_width;
        cstr.min_height = self.props.minHeight orelse cstr.min_height;
        cstr.max_width = self.props.maxWidth orelse cstr.max_width;
        cstr.max_height = self.props.maxHeight orelse cstr.max_height;

        if (self.props.child.isNull()) {
            return ui.LayoutSize.init(cstr.min_width, cstr.min_height);
        }

        const child = ctx.getFirstChild();
        var childSize = ctx.computeLayout2(child, cstr);
        ctx.setLayout2(child, 0, 0, childSize.width, childSize.height);
        childSize.limitToMinMax(cstr);

        return childSize;
    }
};