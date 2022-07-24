const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const ZStack = ui.widgets.ZStack;
const log = stdx.log.scoped(.root);

pub const OverlayId = u32;

const RootOverlayHandle = struct {
    root: *Root,
    overlay_id: OverlayId,
};

/// The Root widget allows the user's root widget to be wrapped by a container that can provide additional functionality such as modals and popovers.
pub const Root = struct {
    props: struct {
        user_root: ui.FrameId = ui.NullFrameId,
    },

    overlays: std.ArrayList(OverlayItem),
    build_buf: std.ArrayList(ui.FrameId),
    next_id: OverlayId,

    user_root: ui.NodeRef,

    pub fn init(self: *Root, c: *ui.InitContext) void {
        self.overlays = std.ArrayList(OverlayItem).init(c.alloc);
        self.build_buf = std.ArrayList(ui.FrameId).init(c.alloc);
        self.next_id = 1;
    }

    pub fn deinit(node: *ui.Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Root);
        self.overlays.deinit();
        self.build_buf.deinit();
    }

    pub fn build(self: *Root, c: *ui.BuildContext) ui.FrameId {
        self.build_buf.ensureTotalCapacity(1 + self.overlays.items.len) catch @panic("error");
        self.build_buf.items.len = 0;
        self.build_buf.appendAssumeCapacity(self.props.user_root);

        c.bindFrame(self.props.user_root, &self.user_root);

        const S = struct {
            fn popoverRequestClose(h: RootOverlayHandle) void {
                const item = h.root.getOverlay(h.overlay_id).?;
                if (item.close_cb) |cb| {
                    cb(item.close_ctx);
                }
                h.root.closePopover(h.overlay_id);
            }
            fn modalRequestClose(h: RootOverlayHandle) void {
                const item = h.root.getOverlay(h.overlay_id).?;
                if (item.close_cb) |cb| {
                    cb(item.close_ctx);
                }
                h.root.closeModal(h.overlay_id);
            }
        };

        // Build the overlay items.
        for (self.overlays.items) |overlay| {
            switch (overlay.tag) {
                .Popover => {
                    const frame_id = overlay.build_fn(overlay.build_ctx, c);
                    const wrapper = c.build(PopoverOverlay, .{
                        .child = frame_id,
                        .src_node = overlay.src_node,
                        .onRequestClose = c.closure(RootOverlayHandle{ .root = self, .overlay_id = overlay.id }, S.popoverRequestClose),
                    });
                    self.build_buf.appendAssumeCapacity(wrapper);
                },
                .Modal => {
                    const frame_id = overlay.build_fn(overlay.build_ctx, c);
                    const wrapper = c.build(ModalOverlay, .{
                        .child = frame_id,
                        .onRequestClose = c.closure(RootOverlayHandle{ .root = self, .overlay_id = overlay.id }, S.modalRequestClose),
                    });
                    self.build_buf.appendAssumeCapacity(wrapper);
                },
            }
        }

        // For now the user's root is the first child so it doesn't need a key.
        return c.build(ZStack, .{
            .children = c.list(self.build_buf.items),
        }); 
    }

    pub fn showPopover(self: *Root, src_widget: *ui.Node, build_ctx: ?*anyopaque, build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FrameId, opts: PopoverOptions) OverlayId {
        defer self.next_id += 1;
        _ = self.overlays.append(.{
            .id = self.next_id,
            .tag = .Popover,
            .build_ctx = build_ctx,
            .build_fn = build_fn,
            .close_ctx = opts.close_ctx,
            .close_cb = opts.close_cb,
            .src_node = src_widget,
        }) catch @panic("error");
        return self.next_id;
    }

    pub fn showModal(self: *Root, build_ctx: ?*anyopaque, build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FrameId, opts: ModalOptions) OverlayId {
        defer self.next_id += 1;
        _ = self.overlays.append(.{
            .id = self.next_id,
            .tag = .Modal,
            .build_ctx = build_ctx,
            .build_fn = build_fn,
            .close_ctx = opts.close_ctx,
            .close_cb = opts.close_cb,
            .src_node = undefined,
        }) catch @panic("error");
        return self.next_id;
    }

    fn getOverlay(self: Root, id: OverlayId) ?OverlayItem {
        for (self.overlays.items) |it| {
            if (it.id == id) {
                return it;
            }
        }
        return null;
    }

    pub fn closePopover(self: *Root, id: OverlayId) void {
        for (self.overlays.items) |it, i| {
            if (it.tag == .Popover and it.id == id) {
                _ = self.overlays.orderedRemove(i);
                break;
            }
        }
    }

    pub fn closeModal(self: *Root, id: OverlayId) void {
        for (self.overlays.items) |it, i| {
            if (it.tag == .Modal and it.id == id) {
                _ = self.overlays.orderedRemove(i);
                break;
            }
        }
    }
};

const ModalOptions = struct {
    close_ctx: ?*anyopaque = null,
    close_cb: ?fn (?*anyopaque) void = null,
};

const PopoverOptions = struct {
    close_ctx: ?*anyopaque = null,
    close_cb: ?fn (?*anyopaque) void = null,
};

const OverlayItem = struct {
    id: OverlayId,

    build_ctx: ?*anyopaque,
    build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FrameId,

    close_ctx: ?*anyopaque,
    close_cb: ?fn (?*anyopaque) void,

    tag: OverlayTag,

    // Used for popovers.
    src_node: *ui.Node,
};

const OverlayTag = enum(u1) {
    Popover = 0,
    Modal = 1,
};

/// An overlay that positions the child modal in a specific alignment over the overlay bounds.
/// Clicking outside of the child modal will close the modal.
pub const ModalOverlay = struct {
    props: struct {
        child: ui.FrameId,
        valign: ui.VAlign = .Center,
        halign: ui.HAlign = .Center,
        border_color: Color = Color.DarkGray,
        bg_color: Color = Color.DarkGray.darker(),
        onRequestClose: ?stdx.Function(fn () void) = null,
    },

    pub fn init(self: *ModalOverlay, c: *ui.InitContext) void {
        _ = self;
        c.addMouseDownHandler(self, onMouseDown);
    }

    fn onMouseDown(self: *ModalOverlay, e: ui.MouseDownEvent) ui.EventResult {
        if (self.props.child != ui.NullFrameId) {
            const child = e.ctx.node.children.items[0];
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);

            // If hit outside of the bounds, request to close.
            if (!child.abs_bounds.containsPt(xf, yf)) {
                self.requestClose();
            }
        }
        return .Continue;
    }

    pub fn requestClose(self: *ModalOverlay) void {
        if (self.props.onRequestClose) |cb| {
            cb.call(.{});
        }
    }

    pub fn build(self: *ModalOverlay, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *ModalOverlay, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child != ui.NullFrameId) {
            const child = c.node.children.items[0];
            const child_size = c.computeLayoutWithMax(child, cstr.max_width, cstr.max_height);

            // Currently always centers.
            const x = (cstr.max_width - child_size.width) * 0.5;
            const y = (cstr.max_height - child_size.height) * 0.5;
            c.setLayout(child, ui.Layout.init(x, y, child_size.width, child_size.height));
        }
        return cstr.getMaxLayoutSize();
    }

    pub fn renderCustom(self: *ModalOverlay, c: *ui.RenderContext) void {
        if (self.props.child != ui.NullFrameId) {
            const bounds = c.getAbsBounds();
            const child_lo = c.node.children.items[0].layout;
            const child_x = bounds.min_x + child_lo.x;
            const child_y = bounds.min_y + child_lo.y;

            const gctx = c.gctx;
            gctx.setFillColor(self.props.bg_color);
            gctx.fillRect(child_x, child_y, child_lo.width, child_lo.height);

            c.renderChildren();

            gctx.setStrokeColor(self.props.border_color);
            gctx.setLineWidth(2);
            gctx.drawRect(child_x, child_y, child_lo.width, child_lo.height);
        }
    }
};

/// An overlay that positions the child popover adjacent to a source widget.
/// Clicking outside of the child popover will close the popover.
pub const PopoverOverlay = struct {
    props: struct {
        child: ui.FrameId,
        src_node: *ui.Node,
        border_color: Color = Color.DarkGray,
        bg_color: Color = Color.DarkGray.darker(),
        onRequestClose: ?stdx.Function(fn () void) = null,
    },

    to_left: bool,

    /// Allow a custom post render. For child popovers that want to draw over the border.
    custom_post_render_ctx: ?*anyopaque,
    custom_post_render: ?fn (?*anyopaque, ctx: *ui.RenderContext) void,

    const MarginFromSource = 20;
    const ArrowSize = 30;

    pub fn init(self: *PopoverOverlay, c: *ui.InitContext) void {
        _ = self;
        self.custom_post_render = null;
        self.custom_post_render_ctx = null;
        c.addMouseDownHandler(self, onMouseDown);
    }

    fn onMouseDown(self: *PopoverOverlay, e: ui.MouseDownEvent) ui.EventResult {
        if (self.props.child != ui.NullFrameId) {
            const child = e.ctx.node.children.items[0];
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);

            // If hit outside of the bounds, request to close.
            if (!child.abs_bounds.containsPt(xf, yf)) {
                self.requestClose();
            }
        }
        return .Continue;
    }

    pub fn requestClose(self: *PopoverOverlay) void {
        if (self.props.onRequestClose) |cb| {
            cb.call(.{});
        }
    }

    pub fn build(self: *PopoverOverlay, _: *ui.BuildContext) ui.FrameId {
        return self.props.child;
    }

    pub fn layout(self: *PopoverOverlay, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child != ui.NullFrameId) {
            const child = c.node.children.items[0];
            const child_size = c.computeLayoutWithMax(child, cstr.max_width, cstr.max_height);

            // Position relative to source widget. Source widget layout should already be computed.
            const src_abs_pos = self.props.src_node.computeCurrentAbsPos();
            if (src_abs_pos.x > cstr.max_width * 0.5) {
                // Display popover to the left.
                c.setLayout(child, ui.Layout.init(src_abs_pos.x - child_size.width - MarginFromSource, src_abs_pos.y, child_size.width, child_size.height));
                self.to_left = true;
            } else {
                // Display popover to the right.
                c.setLayout(child, ui.Layout.init(src_abs_pos.x + self.props.src_node.layout.width + MarginFromSource, src_abs_pos.y, child_size.width, child_size.height));
                self.to_left = false;
            }
        }
        return cstr.getMaxLayoutSize();
    }

    pub fn renderCustom(self: *PopoverOverlay, c: *ui.RenderContext) void {
        if (self.props.child != ui.NullFrameId) {
            const bounds = c.getAbsBounds();
            const child_lo = c.node.children.items[0].layout;
            const child_x = bounds.min_x + child_lo.x;
            const child_y = bounds.min_y + child_lo.y;

            const g = c.gctx;
            g.setFillColor(self.props.bg_color);
            g.fillRect(child_x, child_y, child_lo.width, child_lo.height);
            if (self.to_left) {
                g.fillTriangle(child_x + child_lo.width, child_y, child_x + child_lo.width, child_y + ArrowSize, child_x + child_lo.width + ArrowSize/2, child_y + ArrowSize/2);
            } else {
                g.fillTriangle(child_x, child_y, child_x - ArrowSize/2, child_y + ArrowSize/2, child_x, child_y + ArrowSize);
            }

            c.renderChildren();

            g.setStrokeColor(self.props.border_color);
            g.setLineWidth(2);
            g.drawRect(child_x, child_y, child_lo.width, child_lo.height);
        }
        if (self.custom_post_render) |cb| {
            cb(self.custom_post_render_ctx, c);
        }
    }
};