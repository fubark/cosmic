const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.root);

pub const OverlayId = u32;

const RootOverlayHandle = struct {
    root: *Root,
    overlay_id: OverlayId,
};

/// The Root widget allows the user's root widget to be wrapped by a container that can provide additional functionality such as modals and popovers.
pub const Root = struct {
    props: struct {
        user_root: ui.FramePtr = .{},
    },

    /// There are currently two groups of overlays.
    /// An overlay is added to the base group if `default` group type is specified and the source widget belongs to the user root or the base group.
    /// An overlay is added to the top group if `default` group type is specified and the source widget belongs to the top group.
    /// An overlay can also be added by explicity using the `base` or `top` group.
    base_overlays: stdx.ds.DenseHandleList(OverlayId, OverlayDesc, true),
    top_overlays: stdx.ds.DenseHandleList(OverlayId, OverlayDesc, true),

    build_buf: std.ArrayList(ui.FramePtr),

    user_root: ui.NodeRef,
    node: *ui.Node,

    overlay_map: ui.NodeRefMap,

    pub fn init(self: *Root, ctx: *ui.InitContext) void {
        self.base_overlays = stdx.ds.DenseHandleList(OverlayId, OverlayDesc, true).init(ctx.alloc);
        self.top_overlays = stdx.ds.DenseHandleList(OverlayId, OverlayDesc, true).init(ctx.alloc);
        self.build_buf = std.ArrayList(ui.FramePtr).init(ctx.alloc);
        self.node = ctx.node;
        self.overlay_map.init(ctx.alloc);
    }

    pub fn deinit(self: *Root, _: *ui.DeinitContext) void {
        self.base_overlays.deinit();
        self.top_overlays.deinit();
        self.build_buf.deinit();
        self.overlay_map.deinit();
    }

    pub fn deinitFrame(frame: ui.Frame, _: *ui.DeinitContext) void {
        const Props = ui.WidgetProps(Root);
        const props = stdx.mem.ptrCastAlign(*Props, frame.props.?);
        if (props.user_root.isPresent()) {
            props.user_root.destroy();
        }
    }

    pub fn build(self: *Root, c: *ui.BuildContext) ui.FramePtr {
        self.build_buf.ensureTotalCapacity(self.base_overlays.size() + self.top_overlays.size()) catch @panic("error");
        self.build_buf.items.len = 0;

        c.bindFrame(self.props.user_root, &self.user_root);

        // Build the overlay items.
        const base_ids = self.base_overlays.ids();
        for (self.base_overlays.items()) |overlay, i| {
            const overlay_id = base_ids[i];
            self.appendOverlayFrame(c, overlay_id, overlay);
        }
        const base_frames = self.build_buf.items[0..self.base_overlays.size()];

        const top_ids = self.top_overlays.ids();
        for (self.top_overlays.items()) |overlay, i| {
            const overlay_id = top_ids[i];
            self.appendOverlayFrame(c, overlay_id, overlay);
        }
        const top_frames = self.build_buf.items[self.base_overlays.size()..];

        // For now the user's root is the first child so it doesn't need a key.
        return u.ZStack(.{}, &.{
            self.props.user_root.dupe(),
            u.ZStack(.{}, base_frames),
            u.ZStack(.{}, top_frames),
        });
    }

    pub fn getPopoverOverlay(self: *Root, id: OverlayId) *PopoverOverlay {
        const child = self.overlay_map.getNode(ui.WidgetKeyId(id)).?;
        return child.getWidget(PopoverOverlay);
    }

    fn appendOverlayFrame(self: *Root, ctx: *ui.BuildContext, id: OverlayId, desc: OverlayDesc) void {
        const S = struct {
            fn popoverRequestClose(h: RootOverlayHandle) void {
                h.root.closePopover(h.overlay_id);
            }
            fn modalRequestClose(h: RootOverlayHandle) void {
                h.root.closeModal(h.overlay_id);
            }
        };
        switch (desc.overlay_type) {
            .Overlay => {
                const frame_ptr = desc.build_fn(desc.build_ctx, ctx);
                self.build_buf.appendAssumeCapacity(frame_ptr);
            },
            .Popover => {
                const frame_id = desc.build_fn(desc.build_ctx, ctx);
                const wrapper = ctx.build(PopoverOverlay, .{
                    .child = frame_id,
                    .bind = &self.overlay_map.bind,
                    .src_node = desc.src_node,
                    .placement = desc.placement,
                    .marginFromSrc = desc.margin_from_src,
                    .closeAfterMouseLeave = desc.closeAfterMouseLeave,
                    .closeAfterMouseClick = desc.closeAfterMouseClick,
                    .onRequestClose = ctx.closure(RootOverlayHandle{ .root = self, .overlay_id = id }, S.popoverRequestClose),
                    .key = ui.WidgetKeyId(id),
                });
                self.build_buf.appendAssumeCapacity(wrapper);
            },
            .Modal => {
                const frame_id = desc.build_fn(desc.build_ctx, ctx);
                const wrapper = ctx.build(ModalOverlay, .{
                    .child = frame_id,
                    .onRequestClose = ctx.closure(RootOverlayHandle{ .root = self, .overlay_id = id }, S.modalRequestClose),
                });
                self.build_buf.appendAssumeCapacity(wrapper);
            },
        }
    }

    pub fn addOverlay(self: *Root, build_ctx: ?*anyopaque, build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FramePtr, top: bool) !OverlayId {
        const desc = OverlayDesc{
            .overlay_type = .Overlay,
            .build_ctx = build_ctx,
            .build_fn = build_fn,
            .close_ctx = null,
            .close_cb = null,
        };
        if (top) {
            return try self.top_overlays.add(desc);
        } else {
            return try self.base_overlays.add(desc);
        }
    }

    pub fn showPopover(self: *Root, src_widget: *ui.Node, build_ctx: ?*anyopaque, build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FramePtr, opts: PopoverOptions) !OverlayId {
        const desc = OverlayDesc{
            .overlay_type = .Popover,
            .build_ctx = build_ctx,
            .build_fn = build_fn,
            .close_ctx = opts.close_ctx,
            .close_cb = opts.close_cb,
            .src_node = src_widget,
            .closeAfterMouseLeave = opts.closeAfterMouseLeave,
            .closeAfterMouseClick = opts.closeAfterMouseClick,
            .placement = opts.placement,
            .margin_from_src = opts.margin_from_src,
        };
        if (opts.top_layer) {
            return try self.top_overlays.add(desc);
        } else {
            return try self.base_overlays.add(desc);
        }
    }

    /// Modals always appear on top of everything.
    pub fn showModal(self: *Root, build_ctx: ?*anyopaque, build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FramePtr, opts: ModalOptions) !OverlayId {
        return try self.top_overlays.add(.{
            .overlay_type = .Modal,
            .build_ctx = build_ctx,
            .build_fn = build_fn,
            .close_ctx = opts.close_ctx,
            .close_cb = opts.close_cb,
        });
    }

    fn getOverlay(self: Root, id: OverlayId) ?OverlayDesc {
        if (self.base_overlays.get(id)) |desc| {
            return desc;
        }
        return self.top_overlays.get(id);
    }

    pub fn removeOverlay(self: *Root, id: OverlayId) void {
        if (self.base_overlays.has(id)) {
            self.base_overlays.remove(id);
            return;
        }
        if (self.top_overlays.has(id)) {
            self.top_overlays.remove(id);
        }
    }

    pub fn closePopover(self: *Root, id: OverlayId) void {
        // Close can be requested multiple times so check the existence of the overlay first.
        // TODO: If ids are reused, the ids will need to be passed around shared pointers.
        if (self.base_overlays.get(id)) |desc| {
            if (desc.close_cb) |cb| {
                cb(desc.close_ctx);
            }
            if (desc.overlay_type == .Popover) {
                self.base_overlays.remove(id);
            }
            return;
        }
        if (self.top_overlays.get(id)) |desc| {
            if (desc.close_cb) |cb| {
                cb(desc.close_ctx);
            }
            if (desc.overlay_type == .Popover) {
                self.top_overlays.remove(id);
            }
        }
    }

    pub fn closeModal(self: *Root, id: OverlayId) void {
        if (self.base_overlays.get(id)) |desc| {
            if (desc.close_cb) |cb| {
                cb(desc.close_ctx);
            }
            if (desc.overlay_type == .Modal) {
                self.base_overlays.remove(id);
            }
            return;
        }
        const desc = self.top_overlays.get(id).?;
        if (desc.overlay_type == .Modal) {
            if (desc.close_cb) |cb| {
                cb(desc.close_ctx);
            }
            self.top_overlays.remove(id);
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
    closeAfterMouseLeave: bool = false,
    closeAfterMouseClick: bool = false,
    placement: PopoverPlacement = .auto,
    margin_from_src: f32 = 20,
    top_layer: bool = false,
};

const PopoverPlacement = enum {
    auto,
    left,
    right,
    bottom,
};

const OverlayDesc = struct {
    build_ctx: ?*anyopaque,
    build_fn: fn (?*anyopaque, *ui.BuildContext) ui.FramePtr,

    close_ctx: ?*anyopaque,
    close_cb: ?fn (?*anyopaque) void,

    overlay_type: OverlayType,

    // Used for popovers.
    src_node: *ui.Node = undefined,
    placement: PopoverPlacement = undefined,
    closeAfterMouseLeave: bool = undefined,
    closeAfterMouseClick: bool = undefined,
    margin_from_src: f32 = undefined,
};

const OverlayType = enum(u2) {
    Overlay = 0,
    Popover = 1,
    Modal = 2,
};

/// An overlay that positions the child modal in a specific alignment over the overlay bounds.
/// Clicking outside of the child modal will close the modal.
pub const ModalOverlay = struct {
    props: struct {
        child: ui.FramePtr,
        valign: ui.VAlign = .center,
        halign: ui.HAlign = .center,
        border_color: Color = Color.DarkGray,
        bg_color: Color = Color.DarkGray.darker(),
        onRequestClose: stdx.Function(fn () void) = .{},
    },

    pub fn init(self: *ModalOverlay, c: *ui.InitContext) void {
        c.setMouseDownHandler(self, onMouseDown);
    }

    fn onMouseDown(self: *ModalOverlay, e: ui.MouseDownEvent) ui.EventResult {
        if (self.props.child.isPresent()) {
            const child = e.ctx.node.children.items[0];
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);

            // If hit outside of the bounds, request to close.
            if (!child.abs_bounds.containsPt(xf, yf)) {
                self.requestClose();
            }
        }
        return .default;
    }

    pub fn requestClose(self: *ModalOverlay) void {
        if (self.props.onRequestClose.isPresent()) {
            self.props.onRequestClose.call(.{});
        }
    }

    pub fn build(self: *ModalOverlay, _: *ui.BuildContext) ui.FramePtr {
        return self.props.child.dupe();
    }

    pub fn layout(self: *ModalOverlay, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child.isPresent()) {
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
        if (self.props.child.isPresent()) {
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
            gctx.strokeRect(child_x, child_y, child_lo.width, child_lo.height);
        }
    }
};

/// An overlay that positions the child popover adjacent to a source widget.
/// Clicking outside of the child popover will close the popover.
pub const PopoverOverlay = struct {
    props: struct {
        child: ui.FramePtr,
        src_node: *ui.Node,
        placement: PopoverPlacement,
        marginFromSrc: f32 = 20,
        closeAfterMouseLeave: bool = false,
        closeAfterMouseClick: bool = false,
        onRequestClose: stdx.Function(fn () void) = .{},
    },

    placement: PopoverPlacement,
    child: ui.NodeRef,

    /// Allow a custom post render. For child popovers that want to draw over the border.
    custom_post_render_ctx: ?*anyopaque,
    custom_post_render: ?fn (?*anyopaque, ctx: *ui.RenderContext) void,

    node: *ui.Node,
    pressed: bool,

    pub const Style = struct {
        bgColor: ?Color = null,
        border: ?u.BorderStyle = null,
    };

    pub const ComputedStyle = struct {
        bgColor: Color = Color.DarkGray.darker(),
        border: ?u.BorderStyle = null,
    };

    pub fn init(self: *PopoverOverlay, c: *ui.InitContext) void {
        self.custom_post_render = null;
        self.custom_post_render_ctx = null;
        self.node = c.node;
        c.setMouseDownHandler(self, onMouseDown);
        if (self.props.closeAfterMouseClick) {
            c.setEnterMouseDownHandler(self, onEnterMouseDown);
            c.setMouseUpHandler(self, onMouseUp);
        }
        self.pressed = false;
    }

    fn onEnterMouseDown(self: *PopoverOverlay, e: ui.MouseDownEvent) ui.EventResult {
        _ = e;
        // Capture before children has a chance to stop propagation.
        self.pressed = true;
        return .default;
    }

    fn onMouseUp(self: *PopoverOverlay, e: ui.MouseUpEvent) void {
        _ = e;
        if (self.props.closeAfterMouseClick) {
            if (self.pressed) {
                self.pressed = false;
                self.requestClose();
            }
        }
    }

    fn onMouseDown(self: *PopoverOverlay, e: ui.MouseDownEvent) ui.EventResult {
        if (self.props.child.isPresent()) {
            const child = e.ctx.node.children.items[0];
            const xf = @intToFloat(f32, e.val.x);
            const yf = @intToFloat(f32, e.val.y);

            // If hit outside of the bounds, request to close.
            if (!child.abs_bounds.containsPt(xf, yf)) {
                self.requestClose();
            }
        }
        return .default;
    }

    pub fn requestClose(self: *PopoverOverlay) void {
        if (self.props.onRequestClose.isPresent()) {
            self.props.onRequestClose.call(.{});
        }
    }

    pub fn build(self: *PopoverOverlay, ctx: *ui.BuildContext) ui.FramePtr {
        ctx.bindFrame(self.props.child, &self.child);

        const style = ctx.getStyle(PopoverOverlay);

        var b_style = u.BorderStyle{};
        ctx.overrideUserStyle(u.BorderT, &b_style, style.border);
        b_style.bgColor = style.bgColor;

        var body = ui.FramePtr{};
        if (self.props.closeAfterMouseLeave) {
            body = u.MouseHoverArea(.{
                // Initialized as hovered so a onHoverChange(false) is guaranteed to fire even if the initial hoverHitTest returns false.
                .initHovered = true,
                .hitTest = ctx.funcExt(self, hoverHitTest),
                .onHoverChange = ctx.funcExt(self, onHoverChange) },
                self.props.child.dupe(),
            );
        } else {
            body = self.props.child.dupe();
        }

        return u.Border(.{ .style = b_style }, body);
    }

    fn hoverHitTest(self: *PopoverOverlay, x: i16, y: i16) bool {
        // Bounds includes the source widget and the popover.
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        return self.child.node.abs_bounds.containsPt(xf, yf) or self.props.src_node.abs_bounds.containsPt(xf, yf);
    }

    fn onHoverChange(self: *PopoverOverlay, e: ui.HoverChangeEvent) void {
        if (!e.hovered) {
            self.requestClose();
        }
    }

    pub fn layout(self: *PopoverOverlay, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraints();

        if (self.props.child.isPresent()) {
            const child = c.node.children.items[0];
            const child_size = c.computeLayoutWithMax(child, cstr.max_width, cstr.max_height);

            // Source widget layout should already be computed.
            const src_abs_bounds = self.props.src_node.computeAbsBounds();

            // Position relative to source widget. 
            switch (self.props.placement) {
                .auto => {
                    if (src_abs_bounds.min_x > cstr.max_width * 0.5) {
                        self.placeUserChild(c, child, child_size, src_abs_bounds, .left);
                    } else {
                        self.placeUserChild(c, child, child_size, src_abs_bounds, .right);
                    }
                },
                else => {
                    self.placeUserChild(c, child, child_size, src_abs_bounds, self.props.placement);
                },
            }
        }
        return cstr.getMaxLayoutSize();
    }

    fn placeUserChild(self: *PopoverOverlay, ctx: *ui.LayoutContext, child: *ui.Node, child_size: ui.LayoutSize, src_abs_bounds: stdx.math.BBox, placement: PopoverPlacement) void {
        switch (placement) {
            .auto => stdx.fatal(),
            .left => {
                // Place popover to the left.
                ctx.setLayout(child, ui.Layout.init(src_abs_bounds.min_x - child_size.width - self.props.marginFromSrc, src_abs_bounds.min_y, child_size.width, child_size.height));
            },
            .right => {
                // Place popover to the right.
                ctx.setLayout(child, ui.Layout.init(src_abs_bounds.max_x + self.props.marginFromSrc, src_abs_bounds.min_y, child_size.width, child_size.height));
            },
            .bottom => {
                // Place popover to the bottom.
                ctx.setLayout(child, ui.Layout.init(src_abs_bounds.min_x, src_abs_bounds.max_y + self.props.marginFromSrc, child_size.width, child_size.height));
            },
        }
        self.placement = placement;
    }

    pub fn renderCustom(self: *PopoverOverlay, c: *ui.RenderContext) void {
        if (self.props.child.isPresent()) {
            c.renderChildren();
        }
        if (self.custom_post_render) |cb| {
            cb(self.custom_post_render_ctx, c);
        }
    }
};