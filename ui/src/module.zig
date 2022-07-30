const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const t = stdx.testing;
const Closure = stdx.Closure;
const ClosureIface = stdx.ClosureIface;
const Function = stdx.Function;
const Duration = stdx.time.Duration;
const string = stdx.string;
const graphics = @import("graphics");
const platform = @import("platform");
const EventDispatcher = platform.EventDispatcher;

const ui = @import("ui.zig");
const events = @import("events.zig");
const Frame = ui.Frame;
const BindNode = @import("frame.zig").BindNode;
const ui_render = @import("render.zig");
const LayoutSize = ui.LayoutSize;
const NullId = stdx.ds.CompactNull(u32);
const NullFrameId = NullId;
const TextMeasure = ui.TextMeasure;
pub const TextMeasureId = usize;
pub const IntervalId = u32;
const log = stdx.log.scoped(.module);

const build_ = @import("build.zig");
const BuildContext = build_.BuildContext;

/// Using a global BuildContext makes widget declarations more idiomatic.
pub var gbuild_ctx: *BuildContext = undefined;

pub fn getWidgetIdByType(comptime Widget: type) ui.WidgetTypeId {
    return @ptrToInt(GenWidgetVTable(Widget));
}

/// Generates the vtable for a Widget.
pub fn GenWidgetVTable(comptime Widget: type) *const ui.WidgetVTable {
    const gen = struct {

        fn create(alloc: std.mem.Allocator, node: *ui.Node, ctx_ptr: *anyopaque, props_ptr: ?[*]const u8) *anyopaque {
            const ctx = stdx.mem.ptrCastAlign(*InitContext, ctx_ptr);

            const new: *Widget = if (@sizeOf(Widget) > 0) b: {
                break :b alloc.create(Widget) catch unreachable;
            } else undefined;

            if (@sizeOf(Widget) > 0) {
                if (comptime WidgetHasProps(Widget)) {
                    if (props_ptr) |props| {
                        const Props = WidgetProps(Widget);
                        new.props = std.mem.bytesToValue(Props, props[0..@sizeOf(Props)]);
                    }
                }
            }
            if (@hasDecl(Widget, "init")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *InitContext) void, @TypeOf(Widget.init))) {
                    @compileError("Invalid init function: " ++ @typeName(@TypeOf(Widget.init)) ++ " Widget: " ++ @typeName(Widget));
                }
                // Call widget's init to set state.
                new.init(ctx);
            }
            // Set bind.
            if (node.bind) |bind| {
                stdx.mem.ptrCastAlign(*ui.WidgetRef(Widget), bind).* = ui.WidgetRef(Widget).init(node);
            }
            if (@sizeOf(Widget) > 0) {
                return new;
            } else {
                // Use a dummy pointer when size = 0.
                var dummy: bool = undefined;
                return &dummy;
            }
        }

        fn postInit(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) void {
            const ctx = stdx.mem.ptrCastAlign(*InitContext, ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "postInit")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *InitContext) void, @TypeOf(Widget.postInit))) {
                    @compileError("Invalid postInit function: " ++ @typeName(@TypeOf(Widget.postInit)) ++ " Widget: " ++ @typeName(Widget));
                }
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.postInit(ctx);
                } else {
                    widget.postInit(ctx);
                }
            }
        }

        fn updateProps(widget_ptr: *anyopaque, props_ptr: [*]const u8) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (comptime WidgetHasProps(Widget)) {
                const Props = WidgetProps(Widget);
                widget.props = std.mem.bytesToValue(Props, props_ptr[0..@sizeOf(Props)]);
            }
            if (@hasDecl(Widget, "postPropsUpdate")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget) void, @TypeOf(Widget.postPropsUpdate))) {
                    @compileError("Invalid postPropsUpdate function: " ++ @typeName(@TypeOf(Widget.postPropsUpdate)) ++ " Widget: " ++ @typeName(Widget));
                }
                widget.postPropsUpdate();
            }
        }

        fn postUpdate(node: *ui.Node) void {
            if (@hasDecl(Widget, "postUpdate")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*ui.Node) void, @TypeOf(Widget.postUpdate))) {
                    @compileError("Invalid postUpdate function: " ++ @typeName(@TypeOf(Widget.postUpdate)) ++ " Widget: " ++ @typeName(Widget));
                }
                Widget.postUpdate(node);
            }
        }

        fn build(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) ui.FrameId {
            const ctx = stdx.mem.ptrCastAlign(*BuildContext, ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);

            if (!@hasDecl(Widget, "build")) {
                // No build function. Return null child.
                return NullFrameId;
            } else {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *BuildContext) ui.FrameId, @TypeOf(Widget.build))) {
                    @compileError("Invalid build function: " ++ @typeName(@TypeOf(Widget.build)) ++ " Widget: " ++ @typeName(Widget));
                }
            }
            if (@sizeOf(Widget) == 0) {
                const empty: *Widget = undefined;
                return empty.build(ctx);
            } else {
                return widget.build(ctx);
            }
        }

        fn render(node: *ui.Node, ctx: *RenderContext, parent_abs_x: f32, parent_abs_y: f32) void {
            // Attach node to ctx.
            ctx.node = node;
            // Compute node's absolute bounds based on it's relative position and the parent.
            const abs_x = parent_abs_x + node.layout.x;
            const abs_y = parent_abs_y + node.layout.y;
            node.abs_bounds = .{
                .min_x = abs_x,
                .min_y = abs_y,
                .max_x = abs_x + node.layout.width,
                .max_y = abs_y + node.layout.height,
            };
            if (builtin.mode == .Debug) {
                if (node.debug) {
                    log.debug("render {}", .{node.abs_bounds});
                }
            }
            if (@hasDecl(Widget, "renderCustom")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *RenderContext) void, @TypeOf(Widget.renderCustom))) {
                    @compileError("Invalid renderCustom function: " ++ @typeName(@TypeOf(Widget.renderCustom)) ++ " Widget: " ++ @typeName(Widget));
                }
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.renderCustom(ctx);
                } else {
                    const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                    widget.renderCustom(ctx);
                }
            } else if (@hasDecl(Widget, "render")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *RenderContext) void, @TypeOf(Widget.render))) {
                    @compileError("Invalid render function: " ++ @typeName(@TypeOf(Widget.render)) ++ " Widget: " ++ @typeName(Widget));
                }
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.render(ctx);
                } else {
                    const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                    widget.render(ctx);
                }
                ui_render.defaultRenderChildren(node, ctx);
            } else {
                ui_render.defaultRenderChildren(node, ctx);
            }
        }

        fn layout(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) LayoutSize {
            const ctx = stdx.mem.ptrCastAlign(*LayoutContext, ctx_ptr);
            if (builtin.mode == .Debug) {
                if (ctx.node.debug) {
                    log.debug("layout: {}", .{ctx.getSizeConstraints()});
                }
            }
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "layout")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *LayoutContext) LayoutSize, @TypeOf(Widget.layout))) {
                    @compileError("Invalid layout function: " ++ @typeName(@TypeOf(Widget.layout)) ++ " Widget: " ++ @typeName(Widget));
                }

                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    return empty.layout(ctx);
                } else {
                    return widget.layout(ctx);
                }
            } else {
                return defaultLayout(ctx);
            }
        }

        /// The default layout passes the constraints to the children and reports the size of its children.
        /// Multiple children are stacked over each other like a ZStack.
        fn defaultLayout(c: *LayoutContext) LayoutSize {
            var max_width: f32 = 0;
            var max_height: f32 = 0;
            for (c.node.children.items) |child| {
                const child_size = c.computeLayoutInherit(child);
                c.setLayout(child, Layout.init(0, 0, child_size.width, child_size.height));
                if (child_size.width > max_width) {
                    max_width = child_size.width;
                }
                if (child_size.height > max_height) {
                    max_height = child_size.height;
                }
            }
            var res = LayoutSize.init(max_width, max_height);
            res.growToMin(c.cstr);
            return res;
        }

        fn destroy(node: *ui.Node, alloc: std.mem.Allocator) void {
            if (@sizeOf(Widget) == 0) {
                if (@hasDecl(Widget, "deinit")) {
                    const empty: *Widget = undefined;
                    empty.deinit(alloc);
                }
            } else {
                const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                if (@hasDecl(Widget, "deinit")) {
                    widget.deinit(alloc);
                }
                alloc.destroy(widget);
            }
        }

        const vtable = ui.WidgetVTable{
            .create = create,
            .postInit = postInit,
            .updateProps = updateProps,
            .postUpdate = postUpdate,
            .build = build,
            .render = render,
            .layout = layout,
            .destroy = destroy,
            .has_post_update = @hasDecl(Widget, "postUpdate"),
            .children_can_overlap = @hasDecl(Widget, "ChildrenCanOverlap") and Widget.ChildrenCanOverlap,
            .name = @typeName(Widget),
        };
    };

    return &gen.vtable;
}

pub const FragmentVTable = GenWidgetVTable(struct {});

const EventType = enum(u2) {
    mouseup = 0,
    global_mouseup = 1,
    global_mousemove = 2,
    hoverchange = 3,
};

const EventHandlerRef = struct {
    event_type: EventType,
    node: *ui.Node,
};

pub const Module = struct {
    // TODO: Provide widget id map at the root level.

    alloc: std.mem.Allocator,

    root_node: ?*ui.Node,
    user_root: ui.NodeRef,

    init_ctx: InitContext,
    build_ctx: BuildContext,
    layout_ctx: LayoutContext,
    render_ctx: RenderContext,
    event_ctx: ui.EventContext,
    mod_ctx: ModuleContext,

    common: ModuleCommon,

    text_measure_batch_buf: std.ArrayList(*graphics.TextMeasure),

    pub fn init(
        self: *Module,
        alloc: std.mem.Allocator,
        g: *graphics.Graphics,
    ) void {
        self.* = .{
            .alloc = alloc,
            .root_node = null,
            .user_root = .{},
            .init_ctx = InitContext.init(self),
            .build_ctx = undefined,
            .layout_ctx = LayoutContext.init(self, g),
            .event_ctx = ui.EventContext.init(self),
            .render_ctx = undefined,
            .mod_ctx = ModuleContext.init(self),
            .common = undefined,
            .text_measure_batch_buf = std.ArrayList(*graphics.TextMeasure).init(alloc),
        };
        self.common.init(alloc, self, g);
        self.build_ctx = BuildContext.init(alloc, self.common.arena_alloc, self);
        self.render_ctx = RenderContext.init(&self.common.ctx, g);
    }

    pub fn deinit(self: *Module) void {
        self.build_ctx.deinit();
        self.text_measure_batch_buf.deinit();

        // Destroy widget nodes.
        if (self.root_node != null) {
            const S = struct {
                fn visit(mod: *Module, node: *ui.Node) void {
                    mod.destroyNode(node);
                }
            };
            const walker = stdx.algo.recursive.ChildArrayListWalker(*ui.Node);
            stdx.algo.recursive.walkPost(*Module, self, *ui.Node, self.root_node.?, walker, S.visit);
        }

        self.common.deinit();
    }

    pub fn setContextProvider(self: *Module, provider: fn (key: u32) ?*anyopaque) void {
        self.common.context_provider = provider;
    }

    /// Attaches handlers to the event dispatcher.
    pub fn addInputHandlers(self: *Module, dispatcher: *EventDispatcher) void {
        const S = struct {
            fn onKeyDown(ctx: ?*anyopaque, e: platform.KeyDownEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                self_.processKeyDownEvent(e);
            }
            fn onKeyUp(ctx: ?*anyopaque, e: platform.KeyUpEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                self_.processKeyUpEvent(e);
            }
            fn onMouseDown(ctx: ?*anyopaque, e: platform.MouseDownEvent) platform.EventResult {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                return self_.processMouseDownEvent(e);
            }
            fn onMouseUp(ctx: ?*anyopaque, e: platform.MouseUpEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                self_.processMouseUpEvent(e);
            }
            fn onMouseScroll(ctx: ?*anyopaque, e: platform.MouseScrollEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                self_.processMouseScrollEvent(e);
            }
            fn onMouseMove(ctx: ?*anyopaque, e: platform.MouseMoveEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Module, ctx);
                self_.processMouseMoveEvent(e);
            }
        };
        dispatcher.addOnKeyDown(self, S.onKeyDown);
        dispatcher.addOnKeyUp(self, S.onKeyUp);
        dispatcher.addOnMouseDown(self, S.onMouseDown);
        dispatcher.addOnMouseUp(self, S.onMouseUp);
        dispatcher.addOnMouseScroll(self, S.onMouseScroll);
        dispatcher.addOnMouseMove(self, S.onMouseMove);
    }

    pub fn getUserRoot(self: Module, comptime Widget: type) ?*Widget {
        if (self.root_node != null) {
            const root = self.root_node.?.getWidget(ui.widgets.Root);
            if (root.user_root.binded) {
                return root.user_root.node.getWidget(Widget);
            } 
        }
        return null;
    }

    fn getWidget(self: *Module, comptime Widget: type, node: *ui.Node) *Widget {
        _ = self;
        return stdx.mem.ptrCastAlign(*Widget, node.widget);
    }

    pub fn processMouseUpEvent(self: *Module, e: platform.MouseUpEvent) void {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);

        self.common.last_focused_widget = self.common.focused_widget;
        self.common.hit_last_focused = false;

        // Trigger global handlers first.
        for (self.common.global_mouse_up_list.items) |node| {
            const sub = self.common.node_global_mouseup_map.get(node).?;
            if (!sub.to_remove) {
                if (node == self.common.last_focused_widget) {
                    self.common.hit_last_focused = true;
                }
                sub.handleEvent(&self.event_ctx, e);
            }
        }

        // Greedy hit test starting from the root.
        if (self.root_node) |node| {
            _ = self.processMouseUpEventRecurse(node, xf, yf, e);
        }

        if (self.common.last_focused_widget != null and self.common.last_focused_widget == self.common.focused_widget and !self.common.hit_last_focused) {
            self.common.focused_onblur(self.common.focused_widget.?, &self.common.ctx);
            self.common.focused_widget = null;
            self.common.focused_onblur = undefined;
        }
    }

    fn processMouseUpEventRecurse(self: *Module, node: *ui.Node, xf: f32, yf: f32, e: platform.MouseUpEvent) bool {
        if (node.abs_bounds.containsPt(xf, yf)) {
            if (node == self.common.last_focused_widget) {
                self.common.hit_last_focused = true;
            }
            if (node.hasHandler(ui.EventHandlerMasks.mouseup)) {
                const sub = self.common.node_mouseup_map.get(node).?;
                sub.handleEvent(&self.event_ctx, e);
            }
            const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
            var stop = false;
            for (event_children) |child| {
                if (self.processMouseUpEventRecurse(child, xf, yf, e)) {
                    stop = true;
                    break;
                }
            }
            return stop;
        } else return false;
    }

    /// Start at the root node and propagate downwards on the first hit box.
    /// TODO: Handlers should be able to return Stop to prevent propagation.
    pub fn processMouseDownEvent(self: *Module, e: platform.MouseDownEvent) platform.EventResult {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);
        self.common.last_focused_widget = self.common.focused_widget;
        self.common.hit_last_focused = false;
        var hit_widget = false;
        if (self.root_node) |node| {
            if (node.abs_bounds.containsPt(xf, yf)) {
                _ = self.processMouseDownEventRecurse(node, xf, yf, e, &hit_widget);
            }
        }
        // If the existing focused widget wasn't hit and no other widget requested focus, trigger blur.
        if (self.common.last_focused_widget != null and self.common.last_focused_widget == self.common.focused_widget and !self.common.hit_last_focused) {
            self.common.focused_onblur(self.common.focused_widget.?, &self.common.ctx);
            self.common.focused_widget = null;
            self.common.focused_onblur = undefined;
        }
        if (hit_widget) {
            return .Stop;
        } else {
            return .Continue;
        }
    }

    fn processMouseDownEventRecurse(self: *Module, node: *ui.Node, xf: f32, yf: f32, e: platform.MouseDownEvent, hit_widget: *bool) bool {
        if (node == self.common.last_focused_widget) {
            self.common.hit_last_focused = true;
            hit_widget.* = true;
        }
        var cur = node.mouse_down_list;
        if (cur != NullId) {
            // If there is a handler, assume the event hits the widget.
            // If the widget performs clearMouseHitFlag() in any of the handlers, the flag is reset so it does not change hit_widget.
            self.common.widget_hit_flag = true;
        }
        var propagate = true;
        while (cur != NullId) {
            const sub = self.common.mouse_down_event_subs.getNoCheck(cur);
            if (sub.handleEvent(&self.event_ctx, e) == .stop) {
                propagate = false;
                break;
            }
            cur = self.common.mouse_down_event_subs.getNextNoCheck(cur);
        }
        if (self.common.widget_hit_flag) {
            hit_widget.* = true;
        }
        if (!propagate) {
            return true;
        }
        const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
        if (!node.vtable.children_can_overlap) {
            // Greedy hit check. Skips siblings.
            for (event_children) |child| {
                if (child.abs_bounds.containsPt(xf, yf)) {
                    if (self.processMouseDownEventRecurse(child, xf, yf, e, hit_widget)) {
                        propagate = false;
                    }
                    break;
                }
            }
        } else {
            // Continues to hit check siblings until `stop` is received.
            for (event_children) |child| {
                if (child.abs_bounds.containsPt(xf, yf)) {
                    if (self.processMouseDownEventRecurse(child, xf, yf, e, hit_widget)) {
                        propagate = false;
                        break;
                    }
                }
            }
        }
        return !propagate;
    }

    pub fn processMouseScrollEvent(self: *Module, e: platform.MouseScrollEvent) void {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);
        if (self.root_node) |node| {
            _ = self.processMouseScrollEventRecurse(node, xf, yf, e);
        }
    }

    fn processMouseScrollEventRecurse(self: *Module, node: *ui.Node, xf: f32, yf: f32, e: platform.MouseScrollEvent) bool {
        if (node.abs_bounds.containsPt(xf, yf)) {
            var cur = node.mouse_scroll_list;
            while (cur != NullId) {
                const sub = self.common.mouse_scroll_event_subs.getNoCheck(cur);
                sub.handleEvent(&self.event_ctx, e);
                cur = self.common.mouse_scroll_event_subs.getNextNoCheck(cur);
            }
            const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
            for (event_children) |child| {
                if (self.processMouseScrollEventRecurse(child, xf, yf, e)) {
                    break;
                }
            }
            return true;
        } else return false;
    }

    pub fn processMouseMoveEvent(self: *Module, e: platform.MouseMoveEvent) void {
        // Process global mouse move events.
        for (self.common.global_mouse_move_list.items) |node| {
            const sub = self.common.node_global_mousemove_map.get(node).?;
            if (!sub.to_remove) {
                sub.handleEvent(&self.event_ctx, e);
            }
        }

        // Process events related to mouse move.
        self.common.cur_mouse_x = e.x;
        self.common.cur_mouse_y = e.y;
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);
        if (self.root_node) |node| {
            self.processMouseMoveEventRecurse(node, xf, yf, e);
        }

        // Check to reset hovered nodes.
        var i = @intCast(u32, self.common.hovered_nodes.items.len);
        while (i > 0) {
            i -= 1;
            const node =  self.common.hovered_nodes.items[i];
            const sub = self.common.node_hoverchange_map.get(node).?;
            if (sub.to_remove) {
                continue;
            }
            if (sub.hit_test) |hit_test| {
                if (hit_test.call(.{ e.x, e.y })) {
                    continue;
                }
            } else {
                if (node.abs_bounds.containsPt(xf, yf)) {
                    continue;
                }
            }
            node.clearStateMask(ui.NodeStateMasks.hovered);
            sub.handleEvent(node, .{
                .ctx = &self.event_ctx,
                .x = e.x,
                .y = e.y,
                .hovered = false,
            });
            _ = self.common.hovered_nodes.swapRemove(i);
        }
    }

    fn processMouseMoveEventRecurse(self: *Module, node: *ui.Node, xf: f32, yf: f32, e: platform.MouseMoveEvent) void {
        if (node.hasHandler(ui.EventHandlerMasks.hoverchange)) {
            // Check if this node is already in hovered state.
            if (!node.hasState(ui.NodeStateMasks.hovered)) {
                const sub = self.common.node_hoverchange_map.get(node).?;
                if (sub.hit_test) |hit_test| {
                    if (!hit_test.call(.{ @floatToInt(i16, xf), @floatToInt(i16, yf) })) {
                        return;
                    }
                } else {
                    if (!node.abs_bounds.containsPt(xf, yf)) {
                        return;
                    }
                }

                self.common.hovered_nodes.append(self.alloc, node) catch fatal();
                node.setStateMask(ui.NodeStateMasks.hovered);

                sub.handleEvent(node, .{
                    .ctx = &self.event_ctx,
                    .hovered = true,
                    .x = e.x,
                    .y = e.y,
                });
            }
        }
        const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
        for (event_children) |child| {
            self.processMouseMoveEventRecurse(child, xf, yf, e);
        }
    }

    pub fn processKeyDownEvent(self: *Module, e: platform.KeyDownEvent) void {
        // Only the focused widget receives input.
        if (self.common.focused_widget) |focused_widget| {
            var cur = focused_widget.key_down_list;
            while (cur != NullId) {
                const sub = self.common.key_down_event_subs.getNoCheck(cur);
                sub.handleEvent(&self.event_ctx, e);
                cur = self.common.key_down_event_subs.getNextNoCheck(cur);
            }
        }
    }

    pub fn processKeyUpEvent(self: *Module, e: platform.KeyUpEvent) void {
        // Only the focused widget receives input.
        if (self.common.focused_widget) |focused_widget| {
            var cur = focused_widget.key_up_list;
            while (cur != NullId) {
                const sub = self.common.key_up_event_subs.getNoCheck(cur);
                sub.handleEvent(&self.event_ctx, e);
                cur = self.common.key_up_event_subs.getNextNoCheck(cur);
            }
        }
    }

    fn updateRoot(self: *Module, root_id: ui.FrameId) !void {
        if (root_id != NullFrameId) {
            const root = self.build_ctx.getFrame(root_id);
            if (self.root_node) |root_node| {
                if (root_node.vtable == root.vtable) {
                    try self.updateExistingNode(null, root_id, root_node);
                } else {
                    self.removeNode(root_node);
                    // Create the node first so getRoot() works in `init` and `postInit` callbacks.
                    var new_node = self.alloc.create(ui.Node) catch unreachable;
                    self.root_node = new_node;
                    errdefer self.root_node = null;
                    _ = try self.initNode(null, root_id, 0, new_node);
                }
            } else {
                var new_node = self.alloc.create(ui.Node) catch unreachable;
                self.root_node = new_node;
                errdefer self.root_node = null;
                _ = try self.initNode(null, root_id, 0, new_node);
            }
        } else {
            if (self.root_node) |root_node| {
                // Remove existing root.
                self.removeNode(root_node);
                self.root_node = null;
            }
        }
    }

    /// Assumes input events were processed so callbacks can make changes to widget states before layouts are computed.
    /// 1. Run timers/intervals/animations.
    /// 2. Remove marked handlers and nodes.
    /// 3. Build frames. Diff tree and create/update nodes from frames.
    /// 4. Compute layout.
    /// 5. Run next post layout cbs.
    pub fn preUpdate(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FrameId, layout_size: LayoutSize) UpdateError!void {
        self.common.updateIntervals(delta_ms, &self.event_ctx);

        // Remove event handlers marked for removal. This should happen before removing and invalidating nodes.
        self.common.removeHandlers();

        // Remove nodes marked for removal.
        self.common.removeNodes();

        // TODO: check if we have to update

        // Reset the builder buffer before we call any Component.build
        self.build_ctx.resetBuffer();
        self.common.arena_allocator.deinit();
        self.common.arena_allocator.state = .{};

        // Update global build context for idiomatic widget declarations.
        gbuild_ctx = &self.build_ctx;

        // TODO: Provide a different context for the bootstrap function since it doesn't have a frame or node. Currently uses the BuildContext.
        self.build_ctx.prepareCall(undefined, undefined);
        const user_root_id = bootstrap_fn(bootstrap_ctx, &self.build_ctx);
        if (user_root_id != NullFrameId) {
            const user_root = self.build_ctx.getFrame(user_root_id);
            if (user_root.vtable == FragmentVTable) {
                return error.UserRootCantBeFragment;
            }
        }

        // The user root widget is wrapped by the Root widget to facilitate things like modals and popovers.
        const root_id = self.build_ctx.build(ui.widgets.Root, .{ .user_root = user_root_id });

        // Since the aim is to do layout in linear time, the tree should be built first.
        // Traverse to see which nodes need to be created/deleted.
        try self.updateRoot(root_id);

        // Before computing layout, perform batched measure text.
        // Widgets can still explicitly measure text so the purpose of this is to act as a placeholder for future work to speed up text measurements.
        self.text_measure_batch_buf.clearRetainingCapacity();
        var iter = self.common.text_measures.iterator();
        while (iter.nextPtr()) |measure| {
            self.text_measure_batch_buf.append(&measure.measure) catch unreachable;
        }
        self.common.g.measureTextBatch(self.text_measure_batch_buf.items);

        // Compute layout only after all widgets/nodes exist since
        // only the Widget knows how to compute it's layout and that could depend on state and nested child nodes.
        // The goal here is to perform layout in linear time, more specifically pre and post visits to each node.
        if (self.root_node != null) {
            const size = self.layout_ctx.computeLayout(self.root_node.?, 0, 0, layout_size.width, layout_size.height);
            self.layout_ctx.setLayout(self.root_node.?, Layout.init(0, 0, size.width, size.height));
        }

        // Run logic that needs to happen after layout.
        for (self.common.next_post_layout_cbs.items) |*it| {
            it.call(.{});
            it.deinit(self.alloc);
        }
        self.common.next_post_layout_cbs.clearRetainingCapacity();
    }

    pub fn postUpdate(self: *Module) void {
        _ = self;
        // TODO: defer destroying widgets so that callbacks don't reference stale data.
    }

    /// Update a full app frame. Parts of the update are split up to facilitate testing.
    /// A bootstrap fn is needed to tell the module how to build the root frame.
    /// A width and height is needed to specify the root container size in which subsequent widgets will use for layout.
    pub fn updateAndRender(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FrameId, width: f32, height: f32) !void {
        const layout_size = LayoutSize.init(width, height);
        try self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
        self.render(delta_ms);
        self.postUpdate();
    }

    /// Just do an update without rendering.
    pub fn update(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FrameId, width: f32, height: f32) !void {
        const layout_size = LayoutSize.init(width, height);
        try self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
        self.postUpdate();
    }

    pub fn render(self: *Module, delta_ms: f32) void {
        self.render_ctx.delta_ms = delta_ms;
        ui_render.render(self);
    }

    /// Assumes the widget and the frame represent the same instance,
    /// so the widget is updated with the frame's props.
    /// Recursively update children.
    /// This assumes the frame's key is equal to the node's key.
    fn updateExistingNode(self: *Module, parent: ?*ui.Node, frame_id: ui.FrameId, node: *ui.Node) UpdateError!void {
        _ = parent;
        // Update frame and props.
        const frame = self.build_ctx.getFrame(frame_id);

        // if (parent) |pn| {
        //     node.transform = pn.transform;
        // }
        const widget_vtable = frame.vtable;
        if (frame.props.len > 0) {
            const props_ptr = self.build_ctx.frame_props.getBytesPtr(frame.props);
            widget_vtable.updateProps(node.widget, props_ptr);
        }

        defer {
            if (widget_vtable.has_post_update) {
                widget_vtable.postUpdate(node);
            }
        }

        const child_frame_id = self.buildChildFrame(frame_id, node, widget_vtable);
        if (child_frame_id == NullId) {
            if (node.children.items.len > 0) {
                for (node.children.items) |it| {
                    self.removeNode(it);
                }
            }
            node.children.items.len = 0;
            return;
        }
        const child_frame = self.build_ctx.getFrame(child_frame_id);
        if (child_frame.vtable == FragmentVTable) {
            // Fragment frame, diff it's children instead.

            const child_frames = child_frame.fragment_children;
            // Start by doing fast array iteration to update nodes with the same key/idx.
            // Once there is a discrepancy, switch to the slower method of key map checks.
            var child_idx: u32 = 0;
            while (child_idx < child_frames.len) : (child_idx += 1) {
                const child_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                const child_frame_ = self.build_ctx.getFrame(child_id);
                if (child_frame_.vtable == FragmentVTable) {
                    return error.NestedFragment;
                }
                if (node.children.items.len <= child_idx) {
                    // TODO: Create nodes for the rest of the frames instead.
                    try self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                    return;
                }
                const child_node = node.children.items[child_idx];
                if (child_node.vtable != child_frame_.vtable) {
                    try self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                    return;
                }
                const frame_key = child_frame_.key orelse ui.WidgetKey{.ListIdx = child_idx};
                if (!std.meta.eql(child_node.key, frame_key)) {
                    try self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                    return;
                }
                try self.updateExistingNode(node, child_id, child_node);
            }
            // Remove left over children.
            if (child_idx < node.children.items.len) {
                for (node.children.items[child_idx..]) |it| {
                    self.removeNode(it);
                }
                node.children.items.len = child_frames.len;
            }
        } else {
            // One child frame.
            if (node.children.items.len == 0) {
                const new_child = try self.createAndInitNode(node, child_frame_id, 0);
                node.children.append(new_child) catch unreachable;
                return;
            }
            const child_node = node.children.items[0];
            if (child_node.vtable != child_frame.vtable) {
                self.removeNode(child_node);
                const new_child = try self.createAndInitNode(node, child_frame_id, 0);
                node.children.items[0] = new_child;
                if (node.children.items.len > 1) {
                    for (node.children.items[1..]) |it| {
                        self.removeNode(it);
                    }
                }
                return;
            }
            const frame_key = if (child_frame.key != null) child_frame.key.? else ui.WidgetKey{.ListIdx = 0};
            if (!std.meta.eql(child_node.key, frame_key)) {
                self.removeNode(child_node);
                const new_child = try self.createAndInitNode(node, child_frame_id, 0);
                node.children.items[0] = new_child;
                if (node.children.items.len > 1) {
                    for (node.children.items[1..]) |it| {
                        self.removeNode(it);
                    }
                }
                return;
            }
            // Same child.
            try self.updateExistingNode(node, child_frame_id, child_node);
        }
    }

    /// Slightly slower method to update with frame children that utilizes a key map.
    fn updateChildFramesWithKeyMap(self: *Module, parent: *ui.Node, start_idx: u32, child_frames: ui.FrameListPtr) UpdateError!void {
        var child_idx: u32 = start_idx;
        while (child_idx < child_frames.len): (child_idx += 1) {
            const frame_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
            const frame = self.build_ctx.getFrame(frame_id);

            if (frame.vtable == FragmentVTable) {
                return error.NestedFragment;
            }
            const frame_key = frame.key orelse ui.WidgetKey{.ListIdx = child_idx};

            // Look for an existing child by key.
            const existing_node = parent.key_to_child.get(frame_key); 
            if (existing_node != null and existing_node.?.vtable == frame.vtable) {
                try self.updateExistingNode(parent, frame_id, existing_node.?);

                // Update the children list as we iterate.
                if (parent.children.items[child_idx] != existing_node.?) {
                    // Move the unmatched node at the current idx to the end. It can be matched later or removed at the end.
                    parent.children.append(parent.children.items[child_idx]) catch unreachable;
                    parent.children.items[child_idx] = existing_node.?;
                    // Mark this node as used so it doesn't get removed later.
                    existing_node.?.setStateMask(ui.NodeStateMasks.diff_used);
                }
            } else {
                if (parent.children.items.len == child_idx) {
                    // Exceeded the size of the existing children list. Insert the rest from child frames.
                    const new_child = try self.createAndInitNode(parent, frame_id, child_idx);
                    parent.children.append(new_child) catch unreachable;
                    child_idx += 1;
                    while (child_idx < child_frames.len) : (child_idx += 1) {
                        const frame_id_ = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                        const new_child_ = try self.createAndInitNode(parent, frame_id_, child_idx);
                        parent.children.append(new_child_) catch unreachable;
                    }
                    break;
                }
                if (parent.children.items.len > child_idx) {
                    // Move the child at the same idx to the end.
                    parent.children.append(parent.children.items[child_idx]) catch unreachable;
                }

                // Create a new child instance to correspond with child frame.
                const new_child = try self.createAndInitNode(parent, frame_id, child_idx);

                parent.children.items[child_idx] = new_child;
            }
        }

        // All the unused children were moved to the end so we can delete them all.
        // TODO: deal with different instances with the same key.
        for (parent.children.items[child_idx..]) |it| {
            if (!it.hasState(ui.NodeStateMasks.diff_used)) {
                // Only nodes that weren't matched during diff are removed.
                self.removeNode(it);
            } else {
                // Clear the state flag for next update diff.
                it.clearStateMask(ui.NodeStateMasks.diff_used);
            }
        }

        // Truncate existing children list to frame children list.
        if (parent.children.items.len > child_frames.len) {
            parent.children.shrinkRetainingCapacity(child_frames.len);
        }
    }

    /// Removes the node and performs deinit but does not unlink from the parent.children array since it's expensive.
    /// Assumes the caller has delt with it.
    fn removeNode(self: *Module, node: *ui.Node) void {
        // Remove children first.
        for (node.children.items) |child| {
            self.removeNode(child);
        }

        if (node.parent != null) {
            _ = node.parent.?.key_to_child.remove(node.key);
        }
        self.destroyNode(node);
    }

    fn destroyNode(self: *Module, node: *ui.Node) void {
        if (node.has_widget_id) {
            if (self.common.id_map.get(node.id)) |val| {
                // Must check that this node currently maps to that id since node removal can happen after newly created node.
                if (val == node) {
                    _ = self.common.id_map.remove(node.id);
                }
            }
        }

        const widget_vtable = node.vtable;

        // Make sure event handlers are removed.
        var cur_id = node.key_up_list;
        while (cur_id != NullId) {
            const sub = self.common.key_up_event_subs.getNoCheck(cur_id);
            sub.deinit(self.alloc);
            self.common.key_up_event_subs.removeAssumeNoPrev(cur_id) catch unreachable;
            cur_id = self.common.key_up_event_subs.getNextNoCheck(cur_id);
        }

        cur_id = node.key_down_list;
        while (cur_id != NullId) {
            const sub = self.common.key_down_event_subs.getNoCheck(cur_id);
            sub.deinit(self.alloc);
            self.common.key_down_event_subs.removeAssumeNoPrev(cur_id) catch unreachable;
            cur_id = self.common.key_down_event_subs.getNextNoCheck(cur_id);
        }

        cur_id = node.mouse_down_list;
        while (cur_id != NullId) {
            const sub = self.common.mouse_down_event_subs.getNoCheck(cur_id);
            sub.deinit(self.alloc);
            self.common.mouse_down_event_subs.removeAssumeNoPrev(cur_id) catch unreachable;
            cur_id = self.common.mouse_down_event_subs.getNextNoCheck(cur_id);
        }

        if (node.hasHandler(ui.EventHandlerMasks.mouseup)) {
            self.common.ctx.clearMouseUpHandler(node);
        }

        if (node.hasHandler(ui.EventHandlerMasks.global_mouseup)) {
            self.common.ctx.clearGlobalMouseUpHandler(node);
        }

        if (node.hasHandler(ui.EventHandlerMasks.global_mousemove)) {
            self.common.ctx.clearGlobalMouseMoveHandler(node);
        }

        if (node.hasHandler(ui.EventHandlerMasks.hoverchange)) {
            self.common.ctx.clearHoverChangeHandler(node);
        }

        // TODO: Make faster.
        var iter = self.common.interval_sessions.iterator();
        while (iter.next()) |it| {
            if (it.node == node) {
                it.deinit(self.alloc);
                self.common.interval_sessions.remove(iter.cur_id);
            }
        }

        // Check that the focused widget is still valid.
        if (self.common.focused_widget) |focused| {
            if (focused == node) {
                self.common.focused_widget = null;
            }
        }

        // Destroy widget state/props after firing any cleanup events. eg. hover end event.
        widget_vtable.destroy(node, self.alloc);

        node.deinit();

        self.common.to_remove_nodes.append(self.alloc, node) catch fatal();
    }

    /// Builds the child frame for a given frame.
    fn buildChildFrame(self: *Module, frame_id: ui.FrameId, node: *ui.Node, widget_vtable: *const ui.WidgetVTable) ui.FrameId {
        self.build_ctx.prepareCall(frame_id, node);
        return widget_vtable.build(node.widget, &self.build_ctx);
    }

    inline fn createAndInitNode(self: *Module, parent: ?*ui.Node, frame_id: ui.FrameId, idx: u32) UpdateError!*ui.Node {
        const new_node = self.alloc.create(ui.Node) catch unreachable;
        return self.initNode(parent, frame_id, idx, new_node);
    }

    /// Allow passing in a new node so a ref can be obtained beforehand.
    fn initNode(self: *Module, parent: ?*ui.Node, frame_id: ui.FrameId, idx: u32, new_node: *ui.Node) UpdateError!*ui.Node {
        const frame = self.build_ctx.getFrame(frame_id);
        const widget_vtable = frame.vtable;

        errdefer {
            for (new_node.children.items) |child| {
                self.destroyNode(child);
            }
            self.destroyNode(new_node);
        }
        const props_ptr = if (frame.props.len > 0) self.build_ctx.frame_props.getBytesPtr(frame.props) else null;

        // Init instance.
        // log.warn("create node {}", .{frame.type_id});
        const key = if (frame.key != null) frame.key.? else ui.WidgetKey{.ListIdx = idx};
        new_node.init(self.alloc, frame.vtable, parent, key, undefined);
        if (frame.id) |id| {
            // Due to how diffing works, nodes are batched removed at the end so a new node could be created to replace an existing one and still run into an id collision.
            // For now, just overwrite the existing mapping and make sure node removal only removes the id mapping if the entry matches the node.
            self.common.id_map.put(id, new_node) catch @panic("error");
            new_node.id = id;
            new_node.has_widget_id = true;
        }
        new_node.bind = frame.widget_bind;

        if (builtin.mode == .Debug) {
            if (frame.debug) {
                new_node.debug = true;
            }
        }

        if (parent != null) {
            parent.?.key_to_child.put(key, new_node) catch unreachable;
        }

        self.init_ctx.prepareForNode(new_node);
        const new_widget = widget_vtable.create(self.alloc, new_node, &self.init_ctx, props_ptr);
        new_node.widget = new_widget;
        if (frame.node_binds != null) {
            var mb_cur = frame.node_binds;
            while (mb_cur) |cur| {
                cur.node_ref.* = ui.NodeRef.init(new_node);
                mb_cur = cur.next;
            }
        }

        //log.warn("created: {}", .{frame.type_id});

        // Build child frames and create child nodes from them.
        const child_frame_id = self.buildChildFrame(frame_id, new_node, widget_vtable);
        if (child_frame_id != NullId) {
            const child_frame = self.build_ctx.getFrame(child_frame_id);
            if (child_frame.vtable == FragmentVTable) {
                // Fragment frame.
                const child_frames = child_frame.fragment_children;

                // Iterate using a counter since the frame list buffer is dynamic.
                var child_idx: u32 = 0;
                while (child_idx < child_frames.len) : (child_idx += 1) {
                    const child_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                    const child_frame_ = self.build_ctx.getFrame(child_id);
                    if (child_frame_.vtable == FragmentVTable) {
                        return error.NestedFragment;
                    }
                    const child_node = try self.createAndInitNode(new_node, child_id, child_idx);
                    new_node.children.append(child_node) catch unreachable;
                }
            } else {
                // Single child frame.
                const child_node = try self.createAndInitNode(new_node, child_frame_id, 0);
                new_node.children.append(child_node) catch unreachable;
            }
        }
        // log.debug("after {s}", .{getWidgetName(frame.type_id)});

        self.init_ctx.prepareForNode(new_node);
        widget_vtable.postInit(new_widget, &self.init_ctx);
        return new_node;
    }

    pub fn dumpTree(self: Module) void {
        if (self.root_node) |root| {
            dumpTreeR(self, 0, root);
        }
    }

    fn dumpTreeR(self: Module, depth: u32, node: *ui.Node) void {
        var foo: [100]u8 = undefined;
        std.mem.set(u8, foo[0..depth*2], ' ');
        log.debug("{s}{s}", .{ foo[0..depth*2], node.vtable.name });
        for (node.children.items) |child| {
            self.dumpTreeR(depth + 1, child);
        }
    }
};

pub const RenderContext = struct {
    common: *CommonContext,
    gctx: *graphics.Graphics,

    /// Elapsed time since the last render.
    delta_ms: f32,

    // Current node.
    node: *ui.Node,

    fn init(common: *CommonContext, gctx: *graphics.Graphics) RenderContext {
        return .{
            .gctx = gctx,
            .common = common,
            .node = undefined,
            .delta_ms = 0,
        };
    }

    pub inline fn drawBBox(self: *RenderContext, bounds: stdx.math.BBox) void {
        self.gctx.drawRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);
    }

    pub inline fn fillBBox(self: *RenderContext, bounds: stdx.math.BBox) void {
        self.gctx.fillRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);
    }

    pub inline fn fillRoundBBox(self: *RenderContext, bounds: stdx.math.BBox, radius: f32) void {
        self.gctx.fillRoundRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y, radius);
    }

    pub inline fn drawRoundBBox(self: *RenderContext, bounds: stdx.math.BBox, radius: f32) void {
        self.gctx.drawRoundRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y, radius);
    }

    pub inline fn clipBBox(self: *RenderContext, bounds: stdx.math.BBox) void {
        self.gctx.clipRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);
    }

    /// Note that this will update the current RenderContext.
    /// If you need RenderContext.node afterwards, that should be stored in a local variable first.
    /// To help prevent the user from forgetting this, an explicit parent_node is required.
    pub inline fn renderChildNode(self: *RenderContext, parent: *ui.Node, node: *ui.Node) void {
        node.vtable.render(node, self, parent.abs_bounds.min_x, parent.abs_bounds.min_y);
    }

    /// Renders the children in order.
    pub inline fn renderChildren(self: *RenderContext) void {
        const parent = self.node;
        for (self.node.children.items) |child| {
            child.vtable.render(child, self, parent.abs_bounds.min_x, parent.abs_bounds.min_y);
        }
    }

    pub inline fn getAbsBounds(self: *RenderContext) stdx.math.BBox {
        return self.node.getAbsBounds();
    }

    pub inline fn getGraphics(self: *RenderContext) *graphics.Graphics {
        return self.gctx;
    }

    pub usingnamespace MixinContextNodeReadOps(RenderContext);
    // pub usingnamespace MixinContextReadOps(RenderContext);
};

/// Requires Context.common.
pub fn MixinContextEventOps(comptime Context: type) type {
    return struct {

        pub inline fn resetInterval(self: *Context, id: IntervalId) void {
            self.common.resetInterval(id);
        }

        pub inline fn removeInterval(self: *Context, id: IntervalId) void {
            self.common.removeInterval(id);
        }
    };
}

/// Requires Context.common.
pub fn MixinContextSharedOps(comptime Context: type) type {
    return struct {
        pub inline fn getContext(self: Context, key: u32) ?*anyopaque {
            return self.common.common.context_provider(key);
        }

        pub inline fn getGraphics(self: Context) *graphics.Graphics {
            return self.common.getGraphics();
        }

        pub inline fn getRoot(self: Context) *ui.widgets.Root {
            return self.common.common.mod.root_node.?.getWidget(ui.widgets.Root);
        }

        pub inline fn getRootLayoutSize(self: Context) LayoutSize {
            const layout = self.common.common.mod.root_node.?.layout;
            return LayoutSize.init(layout.width, layout.height);
        }
    };
}

/// Requires Context.common.
pub fn MixinContextFontOps(comptime Context: type) type {
    return struct {

        pub inline fn getFontVMetrics(self: Context, font_id: graphics.FontId, font_size: f32) graphics.VMetrics {
            return self.common.getFontVMetrics(font_id, font_size);
        }

        pub inline fn getPrimaryFontVMetrics(self: Context, font_gid: graphics.FontGroupId, font_size: f32) graphics.VMetrics {
            return self.common.getPrimaryFontVMetrics(font_gid, font_size);
        }

        pub inline fn getTextMeasure(self: Context, id: TextMeasureId) *TextMeasure {
            return self.common.getTextMeasure(id);
        }

        pub inline fn measureText(self: *Context, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8) graphics.TextMetrics {
            return self.common.measureText(font_gid, font_size, str);
        }

        pub inline fn textGlyphIter(self: *Context, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8) graphics.TextGlyphIterator {
            return self.common.textGlyphIter(font_gid, font_size, str);
        }

        pub inline fn textLayout(self: *Context, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8, max_width: f32, buf: *graphics.TextLayout) void {
            return self.common.textLayout(font_gid, font_size, str, max_width, buf);
        }

        pub inline fn getFontGroupBySingleFontName(self: Context, name: []const u8) graphics.FontGroupId {
            return self.common.getFontGroupBySingleFontName(name);
        }

        pub inline fn getFontGroupByFamily(self: Context, family: graphics.FontFamily) graphics.FontGroupId {
            return self.common.getFontGroupByFamily(family);
        }

        pub inline fn getFontGroupForSingleFont(self: Context, font_id: graphics.FontId) graphics.FontGroupId {
            return self.common.getFontGroupForSingleFont(font_id);
        }

        pub inline fn getFontGroupForSingleFontOrDefault(self: Context, font_id: graphics.FontId) graphics.FontGroupId {
            if (font_id == NullId) {
                return self.getDefaultFontGroup();
            } else {
                return self.common.getFontGroupForSingleFont(font_id);
            }
        }

        pub inline fn getDefaultFontGroup(self: Context) graphics.FontGroupId {
            return self.common.getDefaultFontGroup();
        }

        pub inline fn createTextMeasure(self: *Context, font_gid: graphics.FontGroupId, font_size: f32) TextMeasureId {
            return self.common.createTextMeasure(font_gid, font_size);
        }
    };
}

const BlurHandler = fn (node: *ui.Node, ctx: *CommonContext) void;

/// Ops that need an attached node.
/// Requires Context.node and Context.common.
pub fn MixinContextNodeOps(comptime Context: type) type {
    return struct {
        pub inline fn getNode(self: *Context) *ui.Node {
            return self.node;
        }

        pub inline fn requestFocus(self: *Context, on_blur: BlurHandler) void {
            self.common.requestFocus(self.node, on_blur);
        }

        pub inline fn requestCaptureMouse(self: *Context, capture: bool) void {
            self.common.requestCaptureMouse(capture);
        }

        pub inline fn addInterval(self: *Context, dur: Duration, ctx: anytype, cb: events.IntervalHandler(@TypeOf(ctx))) IntervalId {
            return self.common.addInterval(self.node, dur, ctx, cb);
        }

        pub inline fn setMouseUpHandler(self: *Context, ctx: anytype, cb: events.MouseUpHandler(@TypeOf(ctx))) void {
            self.common.setMouseUpHandler(self.node, ctx, cb);
        }

        pub inline fn setGlobalMouseUpHandler(self: *Context, ctx: anytype, cb: events.MouseUpHandler(@TypeOf(ctx))) void {
            self.common.setGlobalMouseUpHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseDownHandler(self: Context, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
            self.common.addMouseDownHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseScrollHandler(self: Context, ctx: anytype, cb: events.MouseScrollHandler(@TypeOf(ctx))) void {
            self.common.addMouseScrollHandler(self.node, ctx, cb);
        }

        pub inline fn addKeyDownHandler(self: *Context, ctx: anytype, cb: events.KeyDownHandler(@TypeOf(ctx))) void {
            self.common.addKeyDownHandler(self.node, ctx, cb);
        }

        pub inline fn addKeyUpHandler(self: *Context, ctx: anytype, cb: events.KeyUpHandler(@TypeOf(ctx))) void {
            self.common.addKeyUpHandler(self.node, ctx, cb);
        }

        pub inline fn setGlobalMouseMoveHandler(self: *Context, ctx: anytype, cb: events.MouseMoveHandler(@TypeOf(ctx))) void {
            self.common.setGlobalMouseMoveHandler(self.node, ctx, cb);
        }

        pub inline fn clearGlobalMouseUpHandler(self: *Context) void {
            self.common.clearGlobalMouseUpHandler(self.node);
        }

        pub inline fn clearMouseUpHandler(self: *Context) void {
            self.common.clearMouseUpHandler(self.node);
        }

        pub inline fn clearGlobalMouseMoveHandler(self: *Context) void {
            self.common.clearGlobalMouseMoveHandler(self.node);
        }

        pub inline fn setHoverChangeHandler(self: *Context, ctx: anytype, func: events.HoverChangeHandler(@TypeOf(ctx))) void {
            self.common.setHoverChangeHandler(self.node, ctx, func, null);
        }

        /// Has custom user hit test.
        pub inline fn setHoverChangeHandler2(self: *Context, ctx: anytype, func: events.HoverChangeHandler(@TypeOf(ctx)), hitTest: fn (@TypeOf(ctx), i16, i16) bool) void {
            self.common.setHoverChangeHandler(self.node, ctx, func, hitTest);
        }
    };
}

/// Requires Context.node and Context.common.
pub fn MixinContextNodeReadOps(comptime Context: type) type {
    return struct {

        pub inline fn isFocused(self: *Context) bool {
            return self.common.isFocused(self.node);
        }
    };
}

/// Requires Context.common.
pub fn MixinContextInputOps(comptime Context: type) type {
    return struct {

        pub inline fn removeKeyUpHandler(self: *Context, comptime Ctx: type, func: events.KeyUpHandler(Ctx)) void {
            self.common.removeKeyUpHandler(Ctx, func);
        }
    };
}

/// Contains the min/max space for a child widget to occupy.
/// When min_width == max_width or min_height == max_height, the parent is forcing a tight size on the child.
pub const SizeConstraints = struct {
    min_width: f32,
    min_height: f32,
    max_width: f32,
    max_height: f32,

    pub inline fn getMaxLayoutSize(self: SizeConstraints) ui.LayoutSize {
        return ui.LayoutSize.init(self.max_width, self.max_height);
    }

    pub inline fn getMinLayoutSize(self: SizeConstraints) ui.LayoutSize {
        return ui.LayoutSize.init(self.min_width, self.min_height);
    }
};

pub const LayoutContext = struct {
    mod: *Module,
    common: *CommonContext,
    g: *graphics.Graphics,

    /// Size constraints are set by the parent, and consumed by child widget's `layout`.
    cstr: SizeConstraints,
    node: *ui.Node,

    fn init(mod: *Module, g: *graphics.Graphics) LayoutContext {
        return .{
            .mod = mod,
            .common = &mod.common.ctx,
            .g = g,
            .cstr = undefined,
            .node = undefined,
        };
    }

    pub inline fn getSizeConstraints(self: LayoutContext) SizeConstraints {
        return self.cstr;
    }

    /// Computes the layout for a node with a maximum size.
    pub fn computeLayoutWithMax(self: *LayoutContext, node: *ui.Node, max_width: f32, max_height: f32) LayoutSize {
        // Creates another context on the stack so the caller can continue to use their context.
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common = &self.mod.common.ctx,
            .g = self.g,
            .cstr = .{
                .min_width = 0,
                .min_height = 0,
                .max_width = max_width,
                .max_height = max_height,
            },
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    /// Computes the layout for a node that prefers an exact size.
    pub fn computeLayoutExact(self: *LayoutContext, node: *ui.Node, width: f32, height: f32) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common = &self.mod.common.ctx,
            .g = self.g,
            .cstr = .{
                .min_width = width,
                .min_height = height,
                .max_width = width,
                .max_height = height,
            },
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    /// Computes the layout for a node with given size constraints.
    pub fn computeLayout(self: *LayoutContext, node: *ui.Node, min_width: f32, min_height: f32, max_width: f32, max_height: f32) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .g = self.g,
            .cstr = .{
                .min_width = min_width,
                .min_height = min_height,
                .max_width = max_width,
                .max_height = max_height,
            },
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    /// Computes the layout for a node with given size constraints.
    pub fn computeLayout2(self: *LayoutContext, node: *ui.Node, cstr: SizeConstraints) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .g = self.g,
            .cstr = cstr,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn computeLayoutInherit(self: *LayoutContext, node: *ui.Node) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .g = self.g,
            .cstr = self.cstr,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn setLayout(self: *LayoutContext, node: *ui.Node, layout: Layout) void {
        _ = self;
        node.layout = layout;
    }

    pub fn setLayoutPos(self: *LayoutContext, node: *ui.Node, x: f32, y: f32) void {
        _ = self;
        node.layout.x = x;
        node.layout.y = y;
    }

    pub inline fn getLayout(self: *LayoutContext, node: *ui.Node) Layout {
        _ = self;
        return node.layout;
    }

    pub usingnamespace MixinContextNodeOps(LayoutContext);
    pub usingnamespace MixinContextFontOps(LayoutContext);
};

/// Access to common utilities.
pub const CommonContext = struct {
    common: *ModuleCommon,
    alloc: std.mem.Allocator,

    pub inline fn getFontVMetrics(self: CommonContext, font_gid: graphics.FontGroupId, font_size: f32) graphics.VMetrics {
        return self.common.g.getFontVMetrics(font_gid, font_size);
    }

    pub inline fn getPrimaryFontVMetrics(self: CommonContext, font_gid: graphics.FontGroupId, font_size: f32) graphics.VMetrics {
        return self.common.g.getPrimaryFontVMetrics(font_gid, font_size);
    }

    pub inline fn createTextMeasure(self: *CommonContext, font_gid: graphics.FontGroupId, font_size: f32) TextMeasureId {
        return self.common.createTextMeasure(font_gid, font_size);
    }

    pub inline fn destroyTextMeasure(self: *CommonContext, id: TextMeasureId) void {
        self.mod.destroyTextMeasure(id);
    }

    pub fn getTextMeasure(self: CommonContext, id: TextMeasureId) *TextMeasure {
        return self.common.getTextMeasure(id);
    }

    pub fn measureText(self: *CommonContext, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8) graphics.TextMetrics {
        var res: graphics.TextMetrics = undefined;
        self.common.g.measureFontText(font_gid, font_size, str, &res);
        return res;
    }

    pub inline fn textGlyphIter(self: *CommonContext, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8) graphics.TextGlyphIterator {
        return self.common.g.textGlyphIter(font_gid, font_size, str);
    }

    pub inline fn textLayout(self: *CommonContext, font_gid: graphics.FontGroupId, font_size: f32, str: []const u8, max_width: f32, buf: *graphics.TextLayout) void {
        self.common.g.textLayout(font_gid, font_size, str, max_width, buf);
    }

    pub inline fn getFontGroupForSingleFont(self: CommonContext, font_id: graphics.FontId) graphics.FontGroupId {
        return self.common.g.getFontGroupForSingleFont(font_id);
    }

    pub inline fn getFontGroupForSingleFontOrDefault(self: CommonContext, font_id: graphics.FontId) graphics.FontGroupId {
        if (font_id == NullId) {
            return self.getDefaultFontGroup();
        } else {
            return self.getFontGroupForSingleFont(font_id);
        }
    }

    pub inline fn getFontGroupBySingleFontName(self: CommonContext, name: []const u8) graphics.FontGroupId {
        return self.common.g.getFontGroupBySingleFontName(name);
    }

    pub inline fn getFontGroupByFamily(self: CommonContext, family: graphics.FontFamily) graphics.FontGroupId {
        return self.common.g.getFontGroupByFamily(family);
    }

    pub inline fn getGraphics(self: CommonContext) *graphics.Graphics {
        return self.common.g;
    }

    pub fn getDefaultFontGroup(self: CommonContext) graphics.FontGroupId {
        return self.common.default_font_gid;
    }

    pub fn addInterval(self: *CommonContext, node: *ui.Node, dur: Duration, ctx: anytype, cb: events.IntervalHandler(@TypeOf(ctx))) IntervalId {
        const closure = Closure(@TypeOf(ctx), fn (ui.IntervalEvent) void).init(self.alloc, ctx, cb).iface();
        const s = IntervalSession.init(dur, node, closure);
        return self.common.interval_sessions.add(s) catch unreachable;
    }

    pub fn resetInterval(self: *CommonContext, id: IntervalId) void {
        self.common.interval_sessions.getPtrNoCheck(id).progress_ms = 0;
    }

    pub fn removeInterval(self: *CommonContext, id: IntervalId) void {
        self.common.interval_sessions.getNoCheck(id).deinit(self.alloc);
        self.common.interval_sessions.remove(id);
    }

    /// Receive mouse move events outside of the window. Useful for dragging operations.
    pub fn requestCaptureMouse(_: *CommonContext, capture: bool) void {
        platform.captureMouse(capture);
    }

    pub fn requestFocus(self: *CommonContext, node: *ui.Node, on_blur: BlurHandler) void {
        if (self.common.focused_widget) |focused_widget| {
            if (focused_widget != node) {
                // Trigger blur for the current focused widget.
                self.common.focused_onblur(focused_widget, self);
            }
        }
        self.common.focused_widget = node;
        self.common.focused_onblur = on_blur;
    }

    pub fn isFocused(self: *CommonContext, node: *ui.Node) bool {
        if (self.common.focused_widget) |focused_widget| {
            return focused_widget == node;
        } else return false;
    }

    pub fn setMouseUpHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.MouseUpEvent){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_mouseup_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.mouseup);
        }
    }

    pub fn setGlobalMouseUpHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.MouseUpEvent){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_global_mouseup_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            // Insert into global list.
            self.common.global_mouse_up_list.append(self.alloc, node) catch fatal();
            node.setHandlerMask(ui.EventHandlerMasks.global_mouseup);
        }
    }

    pub fn clearGlobalMouseMoveHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_global_mousemove_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.global_mousemove);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_type = .global_mousemove,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn clearGlobalMouseUpHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_global_mouseup_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.global_mouseup);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_type = .global_mouseup,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn clearMouseUpHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_mouseup_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.mouseup);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_type = .mouseup,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn clearHoverChangeHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_hoverchange_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.hoverchange);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_type = .hoverchange,
                    .node = node,
                }) catch fatal();

                if (node.hasState(ui.NodeStateMasks.hovered)) {
                    // Trigger hover end so users can rely on it for teardown logic.
                    sub.handleEvent(node, .{
                        .ctx = &self.common.mod.event_ctx,
                        .hovered = false,
                        .x = self.common.cur_mouse_x,
                        .y = self.common.cur_mouse_y,
                    });
                }
            }
        }
    }

    pub fn addMouseDownHandler(self: CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseDownEvent) ui.EventResult).init(self.alloc, ctx, cb).iface();
        const sub = SubscriberRet(platform.MouseDownEvent, ui.EventResult){
            .closure = closure,
            .node = node,
        };
        if (self.common.mouse_down_event_subs.getLast(node.mouse_down_list)) |last_id| {
            _ = self.common.mouse_down_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            node.mouse_down_list = self.common.mouse_down_event_subs.add(sub) catch unreachable;
        }
    }

    pub fn removeMouseDownHandler(self: *CommonContext, node: *ui.Node, comptime Context: type, func: events.MouseDownHandler(Context)) void {
        var cur = node.mouse_down_list;
        var prev = NullId;
        while (cur != NullId) {
            const sub = self.common.mouse_down_event_subs.getNoCheck(cur);
            if (sub.closure.user_fn == @ptrCast(*const anyopaque, func)) {
                sub.deinit(self.alloc);
                if (prev == NullId) {
                    node.mouse_down_list = self.common.mouse_down_event_subs.getNextNoCheck(cur);
                    self.common.mouse_down_event_subs.removeAssumeNoPrev(cur) catch unreachable;
                } else {
                    self.common.mouse_down_event_subs.removeAfter(prev) catch unreachable;
                }
                // Continue scanning for duplicates.
            }
            prev = cur;
            cur = self.common.mouse_down_event_subs.getNextNoCheck(cur);
        }
    }

    pub fn addMouseScrollHandler(self: CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseScrollHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseScrollEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.MouseScrollEvent){
            .closure = closure,
            .node = node,
        };
        if (self.common.mouse_scroll_event_subs.getLast(node.mouse_scroll_list)) |last_id| {
            _ = self.common.mouse_scroll_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            node.mouse_scroll_list = self.common.mouse_scroll_event_subs.add(sub) catch unreachable;
        }
    }

    pub fn removeMouseScrollHandler(self: *CommonContext, node: *ui.Node, comptime Context: type, func: events.MouseScrollHandler(Context)) void {
        var cur = node.mouse_scroll_list;
        var prev = NullId;
        while (cur != NullId) {
            const sub = self.common.mouse_scroll_event_subs.getNoCheck(cur);
            if (sub.closure.user_fn == @ptrCast(*const anyopaque, func)) {
                sub.deinit(self.alloc);
                if (prev == NullId) {
                    node.mouse_scroll_list = self.common.mouse_scroll_event_subs.getNextNoCheck(cur);
                    self.common.mouse_scroll_event_subs.removeAssumeNoPrev(cur) catch unreachable;
                } else {
                    self.common.mouse_scroll_event_subs.removeAfter(prev) catch unreachable;
                }
                // Continue scanning for duplicates.
            }
            prev = cur;
            cur = self.common.mouse_scroll_event_subs.getNextNoCheck(cur);
        }
    }

    pub fn setGlobalMouseMoveHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseMoveHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseMoveEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.MouseMoveEvent){
            .closure = closure,
            .node = node,
        };

        const res = self.common.node_global_mousemove_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            // Insert into global list.
            self.common.global_mouse_move_list.append(self.alloc, node) catch fatal();
            node.setHandlerMask(ui.EventHandlerMasks.global_mousemove);
        }
        self.common.has_mouse_move_subs = true;
    }

    pub fn setHoverChangeHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, func: events.HoverChangeHandler(@TypeOf(ctx)), hitTest: ?fn (@TypeOf(ctx), i16, i16) bool) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.HoverChangeEvent) void).init(self.alloc, ctx, func).iface();
        var sub = HoverChangeSubscriber{
            .closure = closure,
            .hit_test = null,
        };
        if (hitTest) |hit_test| {
            sub.hit_test = Closure(@TypeOf(ctx), fn (i16, i16) bool).init(self.alloc, ctx, hit_test).iface();
        }

        const res = self.common.node_hoverchange_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.hoverchange);
        }
    }

    pub fn addKeyUpHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.KeyUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.KeyUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.KeyUpEvent){
            .closure = closure,
            .node = node,
        };
        if (self.common.key_up_event_subs.getLast(node.key_up_list)) |last_id| {
            _ = self.common.key_up_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            node.key_up_list = self.common.key_up_event_subs.add(sub) catch unreachable;
        }
    }

    /// Remove a handler from a node based on the function ptr.
    pub fn removeKeyUpHandler(self: *CommonContext, node: *ui.Node, func: *const anyopaque) void {
        var cur = node.key_up_list;
        var prev = NullId;
        while (cur != NullId) {
            const sub = self.common.key_up_event_subs.getNoCheck(cur);
            if (sub.closure.iface.getUserFunctionPtr() == func) {
                sub.deinit();
                self.common.key_up_event_subs.removeAfter(prev);
                // Continue scanning for duplicates.
            }
            prev = cur;
            cur = self.common.key_up_event_subs.getNextNoCheck(cur) catch unreachable;
        }
    }

    pub fn addKeyDownHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.KeyDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.KeyDownEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.KeyDownEvent){
            .closure = closure,
            .node = node,
        };
        if (self.common.key_down_event_subs.getLast(node.key_down_list)) |last_id| {
            _ = self.common.key_down_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            node.key_down_list = self.common.key_down_event_subs.add(sub) catch unreachable;
        }
    }

    pub fn removeKeyDownHandler(self: *CommonContext, node: *ui.Node, comptime Context: type, func: events.KeyDownHandler(Context)) void {
        var cur = node.key_down_list;
        var prev = NullId;
        while (cur != NullId) {
            const sub = self.common.key_down_event_subs.getNoCheck(cur);
            if (sub.closure.iface.getUserFunctionPtr() == @ptrCast(*const anyopaque, func)) {
                sub.deinit();
                self.common.key_down_event_subs.removeAfter(prev);
                // Continue scanning for duplicates.
            }
            prev = cur;
            cur = self.common.key_down_event_subs.getNextNoCheck(cur) catch unreachable;
        }
    }

    pub fn nextPostLayout(self: *CommonContext, ctx: anytype, cb: fn(@TypeOf(ctx)) void) void {
        return self.common.nextPostLayout(ctx, cb);
    }
};

// TODO: Refactor similar ops to their own struct. 
pub const ModuleCommon = struct {
    alloc: std.mem.Allocator,
    mod: *Module,

    /// Arena allocator that gets freed after each update cycle.
    arena_allocator: std.heap.ArenaAllocator,
    arena_alloc: std.mem.Allocator,

    g: *graphics.Graphics,
    text_measures: stdx.ds.PooledHandleList(TextMeasureId, TextMeasure),
    interval_sessions: stdx.ds.PooledHandleList(u32, IntervalSession),

    // TODO: Use one buffer for all the handlers.
    /// Keyboard handlers.
    key_up_event_subs: stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.KeyUpEvent)),
    key_down_event_subs: stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.KeyDownEvent)),

    /// Mouse handlers.
    global_mouse_up_list: std.ArrayListUnmanaged(*ui.Node),
    mouse_down_event_subs: stdx.ds.PooledHandleSLLBuffer(u32, SubscriberRet(platform.MouseDownEvent, ui.EventResult)),
    mouse_scroll_event_subs: stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.MouseScrollEvent)),
    node_global_mousemove_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseMoveEvent)),
    /// Mouse move events fire far more frequently so iteration should be fast.
    global_mouse_move_list: std.ArrayListUnmanaged(*ui.Node),
    has_mouse_move_subs: bool,

    node_mouseup_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseUpEvent)),
    node_global_mouseup_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseUpEvent)),

    /// Hover change event is more reliable than MouseEnter and MouseExit.
    /// Once the hovered state is triggered, another event is guaranteed to fire once the element is no longer hovered.
    /// This is done by tracking the current hovered items and checking their bounds against mouse move events.
    node_hoverchange_map: std.AutoHashMapUnmanaged(*ui.Node, HoverChangeSubscriber),
    hovered_nodes: std.ArrayListUnmanaged(*ui.Node),

    /// Currently focused widget.
    focused_widget: ?*ui.Node,
    focused_onblur: BlurHandler,
    /// Scratch vars to track the last focused widget.
    last_focused_widget: ?*ui.Node,
    hit_last_focused: bool,
    widget_hit_flag: bool,

    /// It's useful to have latest mouse position.
    cur_mouse_x: i16,
    cur_mouse_y: i16,

    next_post_layout_cbs: std.ArrayList(ClosureIface(fn () void)),

    // next_post_render_cbs: std.ArrayList(*ui.Node),

    // TODO: design themes.
    default_font_gid: graphics.FontGroupId,

    /// Keys are assumed to be static memory so they don't need to be freed.
    id_map: std.AutoHashMap(ui.WidgetUserId, *ui.Node),

    ctx: CommonContext,

    /// Event handlers are marked for removal and removed at the end of the process events step.
    /// This prevents a user handler from removing handlers in a list currently being iterated on.
    to_remove_handlers: std.ArrayListUnmanaged(EventHandlerRef),

    to_remove_nodes: std.ArrayListUnmanaged(*ui.Node),

    context_provider: fn (key: u32) ?*anyopaque,

    fn init(self: *ModuleCommon, alloc: std.mem.Allocator, mod: *Module, g: *graphics.Graphics) void {
        const S = struct {
            fn defaultContextProvider(key: u32) ?*anyopaque {
                _ = key;
                return null;
            }
        };
        self.* = .{
            .alloc = alloc,
            .mod = mod,
            .arena_allocator = std.heap.ArenaAllocator.init(alloc),
            .arena_alloc = undefined,

            .g = g,
            .text_measures = stdx.ds.PooledHandleList(TextMeasureId, TextMeasure).init(alloc),
            // .default_font_gid = g.getFontGroupBySingleFontName("Nunito Sans"),
            .default_font_gid = g.getDefaultFontGroupId(),
            .interval_sessions = stdx.ds.PooledHandleList(u32, IntervalSession).init(alloc),

            .key_up_event_subs = stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.KeyUpEvent)).init(alloc),
            .key_down_event_subs = stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.KeyDownEvent)).init(alloc),
            .node_mouseup_map = .{},
            .node_global_mouseup_map = .{},
            .node_global_mousemove_map = .{},
            .global_mouse_up_list = .{},
            .global_mouse_move_list = .{},
            .mouse_down_event_subs = stdx.ds.PooledHandleSLLBuffer(u32, SubscriberRet(platform.MouseDownEvent, ui.EventResult)).init(alloc),
            .mouse_scroll_event_subs = stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.MouseScrollEvent)).init(alloc),
            .has_mouse_move_subs = false,
            .node_hoverchange_map = .{},
            .hovered_nodes = .{},

            .next_post_layout_cbs = std.ArrayList(ClosureIface(fn () void)).init(alloc),
            // .next_post_render_cbs = std.ArrayList(*ui.Node).init(alloc),

            .focused_widget = null,
            .focused_onblur = undefined,
            .last_focused_widget = null,
            .hit_last_focused = false,
            .widget_hit_flag = false,
            .cur_mouse_x = 0,
            .cur_mouse_y = 0,

            .ctx = .{
                .common = self,
                .alloc = alloc, 
            },
            .context_provider = S.defaultContextProvider,
            .id_map = std.AutoHashMap(ui.WidgetUserId, *ui.Node).init(alloc),
            .to_remove_handlers = .{},
            .to_remove_nodes = .{},
        };
        self.arena_alloc = self.arena_allocator.allocator();
    }

    fn deinit(self: *ModuleCommon) void {
        self.id_map.deinit();
        self.text_measures.deinit();

        self.next_post_layout_cbs.deinit();
        // self.next_post_render_cbs.deinit();

        {
            var iter = self.interval_sessions.iterator();
            while (iter.next()) |it| {
                it.deinit(self.alloc);
            }
            self.interval_sessions.deinit();
        }

        {
            var iter = self.key_up_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.deinit(self.alloc);
            }
            self.key_up_event_subs.deinit();
        }

        {
            var iter = self.key_down_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.deinit(self.alloc);
            }
            self.key_down_event_subs.deinit();
        }

        {
            var iter = self.mouse_down_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.deinit(self.alloc);
            }
            self.mouse_down_event_subs.deinit();
        }

        {
            var iter = self.mouse_scroll_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.deinit(self.alloc);
            }
            self.mouse_scroll_event_subs.deinit();
        }

        self.removeHandlers();
        self.removeNodes();

        self.to_remove_handlers.deinit(self.alloc);
        self.to_remove_nodes.deinit(self.alloc);

        self.node_hoverchange_map.deinit(self.alloc);
        self.hovered_nodes.deinit(self.alloc);

        self.node_global_mousemove_map.deinit(self.alloc);
        self.global_mouse_move_list.deinit(self.alloc);
        self.node_global_mouseup_map.deinit(self.alloc);
        self.global_mouse_up_list.deinit(self.alloc);
        self.node_mouseup_map.deinit(self.alloc);

        self.arena_allocator.deinit();
    }

    /// Removing handlers should only free memory and remove items from lists/maps.
    /// Firing events or accessing widget prop callbacks is undefined since the widget state/props could already be freed.
    fn removeHandlers(self: *ModuleCommon) void {
        for (self.to_remove_handlers.items) |ref| {
            switch (ref.event_type) {
                .hoverchange => {
                    const sub = self.node_hoverchange_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_hoverchange_map.remove(ref.node);
                    for (self.hovered_nodes.items) |node, i| {
                        if (node == ref.node) {
                            _ = self.hovered_nodes.orderedRemove(i);
                            break;
                        }
                    }
                },
                .mouseup => {
                    const sub = self.node_mouseup_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_mouseup_map.remove(ref.node);
                },
                .global_mouseup => {
                    const sub = self.node_global_mouseup_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_global_mouseup_map.remove(ref.node);
                    for (self.global_mouse_up_list.items) |node, i| {
                        if (node == ref.node) {
                            _ = self.global_mouse_up_list.orderedRemove(i);
                            break;
                        }
                    }
                },
                .global_mousemove => {
                    const sub = self.node_global_mousemove_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_global_mousemove_map.remove(ref.node);
                    for (self.global_mouse_move_list.items) |node, i| {
                        if (node == ref.node) {
                            _ = self.global_mouse_move_list.orderedRemove(i);
                            break;
                        }
                    }
                    if (self.global_mouse_move_list.items.len == 0) {
                        self.has_mouse_move_subs = false;
                    }
                },
            }
        }
        self.to_remove_handlers.clearRetainingCapacity();
    }

    fn removeNodes(self: *ModuleCommon) void {
        for (self.to_remove_nodes.items) |node| {
            self.alloc.destroy(node);
        } 
        self.to_remove_nodes.clearRetainingCapacity();
    }

    fn createTextMeasure(self: *ModuleCommon, font_gid: graphics.FontGroupId, font_size: f32) TextMeasureId {
        return self.text_measures.add(TextMeasure.init(&.{}, font_gid, font_size)) catch unreachable;
    }

    fn getTextMeasure(self: *ModuleCommon, id: TextMeasureId) *TextMeasure {
        return self.text_measures.getPtrNoCheck(id);
    }

    pub fn destroyTextMeasure(self: *ModuleCommon, id: TextMeasureId) void {
        self.text_measures.remove(id);
    }

    fn updateIntervals(self: *ModuleCommon, delta_ms: f32, event_ctx: *ui.EventContext) void {
        var iter = self.interval_sessions.iterator();
        while (iter.nextPtr()) |it| {
            it.progress_ms += delta_ms;
            if (it.progress_ms > @intToFloat(f32, it.dur.toMillis())) {
                it.call(event_ctx);
                it.progress_ms = 0;
            }
        }
    }

    fn nextPostLayout(self: *ModuleCommon, ctx: anytype, cb: fn (@TypeOf(ctx)) void) void {
        const closure = Closure(@TypeOf(ctx), fn () void).init(self.alloc, ctx, cb).iface();
        self.next_post_layout_cbs.append(closure) catch unreachable;
    }

    /// Given id as an enum literal tag, return the node.
    pub fn getNodeByTag(self: ModuleCommon, comptime lit: @Type(.EnumLiteral)) ?*ui.Node {
        const id = stdx.meta.enumLiteralId(lit);
        return self.id_map.get(id);
    }
};

pub const ModuleContext = struct {
    mod: *Module,

    fn init(mod: *Module) ModuleContext {
        return .{
            .mod = mod,
        };
    }
};

pub const InitContext = struct {
    mod: *Module,
    alloc: std.mem.Allocator,
    common: *CommonContext,
    node: *ui.Node,

    fn init(mod: *Module) InitContext {
        return .{
            .mod = mod,
            .alloc = mod.alloc,
            .common = &mod.common.ctx,
            .node = undefined,
        };
    }

    fn prepareForNode(self: *InitContext, node: *ui.Node) void {
        self.node = node;
    }

    pub fn getModuleContext(self: *InitContext) *ModuleContext {
        return &self.mod.mod_ctx;
    }

    // TODO: findChildrenByTag
    // TODO: findChildByKey
    pub fn findChildWidgetByType(self: *InitContext, comptime Widget: type) ?ui.WidgetRef(Widget) {
        const needle = getWidgetIdByType(Widget);
        const walker = stdx.algo.recursive.ChildArrayListSearchWalker(*ui.Node);
        const S = struct {
            fn pred(type_id: ui.WidgetTypeId, node: *ui.Node) bool {
                return @ptrToInt(node.vtable) == type_id;
            }
        };
        const res = stdx.algo.recursive.searchPreMany(ui.WidgetTypeId, needle, *ui.Node, self.node.children.items, walker, S.pred);
        if (res != null) {
            return ui.WidgetRef(Widget).init(res.?);
        } else {
            return null;
        }
    }

    pub usingnamespace MixinContextInputOps(InitContext);
    pub usingnamespace MixinContextEventOps(InitContext);
    pub usingnamespace MixinContextNodeOps(InitContext);
    pub usingnamespace MixinContextFontOps(InitContext);
    pub usingnamespace MixinContextSharedOps(InitContext);
};

fn SubscriberRet(comptime T: type, comptime Return: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (ui.Event(T)) Return),
        node: *ui.Node,

        fn handleEvent(self: Self, ctx: *ui.EventContext, e: T) Return {
            ctx.node = self.node;
            return self.closure.call(.{
                ui.Event(T){
                    .ctx = ctx,
                    .val = e,
                },
            });
        }

        fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.closure.deinit(alloc);
        }
    };
}

const HoverChangeSubscriber = struct {
    closure: ClosureIface(fn (ui.HoverChangeEvent) void),
    hit_test: ?ClosureIface(fn (i16, i16) bool),
    to_remove: bool = false,

    fn handleEvent(self: HoverChangeSubscriber, node: *ui.Node, e: ui.HoverChangeEvent) void {
        e.ctx.node = node;
        self.closure.call(.{ e });
    }

    fn deinit(self: HoverChangeSubscriber, alloc: std.mem.Allocator) void {
        self.closure.deinit(alloc);
        if (self.hit_test) |hit_test| {
            hit_test.deinit(alloc);
        }
    }
};

fn Subscriber2(comptime T: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (T) void),

        /// Indicates this subscriber should be removed by the engine.
        to_remove: bool = false,

        fn handleEvent(self: Self, node: *ui.Node, e: T) void {
            e.ctx.node = node;
            self.closure.call(.{ e });
        }

        fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.closure.deinit(alloc);
        }
    };
}

fn Subscriber(comptime T: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (ui.Event(T)) void),
        node: *ui.Node,

        /// Indicates this subscriber should be removed by the engine.
        to_remove: bool = false,

        fn handleEvent(self: Self, ctx: *ui.EventContext, e: T) void {
            ctx.node = self.node;
            self.closure.call(.{
                ui.Event(T){
                    .ctx = ctx,
                    .val = e,
                },
            });
        }

        fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.closure.deinit(alloc);
        }
    };
}

const TestModule = struct {
    g: graphics.Graphics,
    mod: ui.Module,
    size: ui.LayoutSize,

    pub fn init(self: *TestModule) void {
        self.g.init(t.alloc, 1) catch fatal();
        self.mod.init(t.alloc, &self.g);
        self.size = LayoutSize.init(800, 600);
    }

    pub fn deinit(self: *TestModule) void {
        self.mod.deinit();
        self.g.deinit();
    }

    pub fn preUpdate(self: *TestModule, ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(ctx), *BuildContext) ui.FrameId) !void {
        try self.mod.preUpdate(0, ctx, bootstrap_fn, self.size);
    }

    pub fn getRoot(self: TestModule) ?*ui.Node {
        return self.mod.root_node;
    }

    pub fn getNodeByTag(self: TestModule, comptime lit: @Type(.EnumLiteral)) ?*ui.Node {
        return self.mod.common.getNodeByTag(lit);
    }
};

test "Node removal also removes the children." {
    const A = struct {
        props: struct {
            child: ui.FrameId,
        },
        fn build(self: *@This(), _: *BuildContext) ui.FrameId {
            return self.props.child;
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(delete: bool, c: *BuildContext) ui.FrameId {
            var child: ui.FrameId = NullFrameId;
            if (!delete) {
                child = c.build(A, .{ 
                    .child = c.build(B, .{}),
                });
            }
            return c.build(A, .{
                .id = .root,
                .child = child,
            });
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try mod.preUpdate(false, S.bootstrap);
    const root = mod.getNodeByTag(.root).?;
    try t.eq(root.numChildrenR(), 2);
    try mod.preUpdate(true, S.bootstrap);
    try t.eq(root.numChildrenR(), 0);
}

test "User root should not allow fragment frame." {
    const A = struct {
    };
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FrameId {
            const list = c.list(.{
                c.build(A, .{}),
                c.build(A, .{}),
            });
            return c.fragment(list);
        }
    };
    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try t.expectError(mod.preUpdate({}, S.bootstrap), error.UserRootCantBeFragment);
}

test "BuildContext.list() will skip over a NullFrameId item." {
    const B = struct {};
    const A = struct {
        fn build(_: *@This(), c: *BuildContext) ui.FrameId {
            return c.fragment(c.list(.{
                NullFrameId,
                c.build(B, .{}),
            }));
        }
    };
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FrameId {
            return c.build(A, .{
                .id = .root,
            });
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try mod.preUpdate({}, S.bootstrap);
    const root = mod.getNodeByTag(.root);
    try t.eq(root.?.vtable, GenWidgetVTable(A));
    try t.eq(root.?.children.items.len, 1);
    try t.eq(root.?.children.items[0].vtable, GenWidgetVTable(B));
}

test "Don't allow nested fragment frames." {
    const A = struct {
        props: struct { child: ui.FrameId },
        fn build(self: *@This(), _: *BuildContext) ui.FrameId {
            return self.props.child;
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(_: void, c: *ui.BuildContext) ui.FrameId {
            const nested_list = c.list(.{
                c.build(B, .{}),
            });
            const list = c.list(.{
                c.build(B, .{}),
                c.fragment(nested_list),
            });
            return c.build(A, .{
                .child = c.fragment(list),
            });
        }
    };
    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try t.expectError(mod.preUpdate({}, S.bootstrap), error.NestedFragment);
}

test "BuildContext.range" {
    const A = struct {
        props: struct {
            children: ui.FrameListPtr,
        },
        fn build(self: *@This(), c: *BuildContext) ui.FrameId {
            return c.fragment(self.props.children);
        }
    };
    const B = struct {};
    // Test case where a child widget uses BuildContext.list. Check if this causes problems with BuildContext.range.
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FrameId {
            return c.build(A, .{
                .id = .root,
                .children = c.range(1, {}, buildChild),
            });
        }
        fn buildChild(_: void, c: *BuildContext, _: u32) ui.FrameId {
            const list = c.list(.{
                c.build(B, .{}),
            });
            return c.build(A, .{ .children = list });
        }
    };
    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try mod.preUpdate({}, S.bootstrap);
    const root = mod.getNodeByTag(.root);
    try t.eq(root.?.vtable, GenWidgetVTable(A));
    try t.eq(root.?.children.items[0].vtable, GenWidgetVTable(A));
    try t.eq(root.?.children.items[0].children.items[0].vtable, GenWidgetVTable(B));
}

test "Widget instance lifecycle." {
    const A = struct {
        pub fn init(_: *@This(), c: *InitContext) void {
            c.addKeyUpHandler({}, onKeyUp);
            c.addKeyDownHandler({}, onKeyDown);
            c.addMouseDownHandler({}, onMouseDown);
            c.setMouseUpHandler({}, onMouseUp);
            c.setGlobalMouseMoveHandler(@as(u32, 1), onMouseMove);
            _ = c.addInterval(Duration.initSecsF(1), {}, onInterval);
            c.requestFocus(onBlur);
        }
        fn onInterval(_: void, _: ui.IntervalEvent) void {}
        fn onBlur(_: *ui.Node, _: *ui.CommonContext) void {}
        fn onKeyUp(_: void, _: ui.KeyUpEvent) void {}
        fn onKeyDown(_: void, _: ui.KeyDownEvent) void {}
        fn onMouseDown(_: void, _: ui.MouseDownEvent) ui.EventResult {
            return .default;
        }
        fn onMouseUp(_: void, _: ui.MouseUpEvent) void {}
        fn onMouseMove(_: u32, _: ui.MouseMoveEvent) void {}
    };
    const S = struct {
        fn bootstrap(build: bool, c: *BuildContext) ui.FrameId {
            if (build) {
                return c.build(A, .{
                    .id = .root,
                });
            } else {
                return NullFrameId;
            }
        }
    };

    var tmod: TestModule = undefined;
    tmod.init();
    defer tmod.deinit();
    const mod = &tmod.mod;

    try tmod.preUpdate(true, S.bootstrap);

    // Widget instance should exist with event handlers.
    var root = tmod.getNodeByTag(.root);
    try t.eq(root.?.vtable, GenWidgetVTable(A));
    try t.eq(mod.common.focused_widget.?, root.?);

    try t.eq(mod.common.key_up_event_subs.size(), 1);
    const keyup_sub = mod.common.key_up_event_subs.iterFirstValueNoCheck();
    try t.eq(keyup_sub.node, root.?);
    try t.eq(keyup_sub.closure.user_fn, A.onKeyUp);

    try t.eq(mod.common.key_down_event_subs.size(), 1);
    const keydown_sub = mod.common.key_down_event_subs.iterFirstValueNoCheck();
    try t.eq(keydown_sub.node, root.?);
    try t.eq(keydown_sub.closure.user_fn, A.onKeyDown);

    try t.eq(mod.common.mouse_down_event_subs.size(), 1);
    const mousedown_sub = mod.common.mouse_down_event_subs.iterFirstValueNoCheck();
    try t.eq(mousedown_sub.node, root.?);
    try t.eq(mousedown_sub.closure.user_fn, A.onMouseDown);

    try t.eq(mod.common.node_mouseup_map.size, 1);
    const mouseup_sub = mod.common.node_mouseup_map.get(root.?).?;
    try t.eq(mouseup_sub.closure.user_fn, A.onMouseUp);

    try t.eq(mod.common.node_global_mousemove_map.size, 1);
    const mousemove_sub = mod.common.node_global_mousemove_map.get(root.?).?;
    try t.eq(mousemove_sub.closure.user_fn, A.onMouseMove);

    try t.eq(mod.common.interval_sessions.size(), 1);
    var iter = mod.common.interval_sessions.iterator();
    const interval_sub = iter.next().?;
    try t.eq(interval_sub.node, root.?);
    try t.eq(interval_sub.closure.user_fn, A.onInterval);

    try tmod.preUpdate(false, S.bootstrap);
    // Run preupdate again to remove marked event handlers.
    try tmod.preUpdate(false, S.bootstrap);

    // Widget instance should be removed and handlers should have been cleaned up.
    root = tmod.getNodeByTag(.root);
    try t.eq(root, null);
    try t.eq(mod.common.focused_widget, null);
    try t.eq(mod.common.key_up_event_subs.size(), 0);
    try t.eq(mod.common.key_down_event_subs.size(), 0);
    try t.eq(mod.common.mouse_down_event_subs.size(), 0);
    try t.eq(mod.common.node_mouseup_map.size, 0);
    try t.eq(mod.common.node_global_mouseup_map.size, 0);
    try t.eq(mod.common.node_global_mousemove_map.size, 0);
    try t.eq(mod.common.interval_sessions.size(), 0);
}

test "Module.update creates or updates existing node" {
    const Foo = struct {
    };

    const Bar = struct {
    };

    const Root = struct {
        flag: bool,

        pub fn init(self: *@This(), _: *InitContext) void {
            self.* = .{
                .flag = true,
            };
        }

        fn build(self: *@This(), c: *BuildContext) ui.FrameId {
            if (self.flag) {
                return c.build(Foo, .{});
            } else {
                return c.build(Bar, .{});
            }
        }
    };

    {
        // Different root frame type creates new node.
        const S2 = struct {
            fn bootstrap(flag: bool, c: *BuildContext) ui.FrameId {
                if (flag) {
                    return c.build(Foo, .{
                        .id = .root,
                    });
                } else {
                    return c.build(Bar, .{
                        .id = .root,
                    });
                }
            }
        };
        var mod: TestModule = undefined;
        mod.init();
        defer mod.deinit();
        try mod.preUpdate(true, S2.bootstrap);
        var root = mod.getNodeByTag(.root);
        try t.eq(root.?.vtable, GenWidgetVTable(Foo));
        try mod.preUpdate(false, S2.bootstrap);
        root = mod.getNodeByTag(.root);
        try t.eq(root.?.vtable, GenWidgetVTable(Bar));
    }

    {
        // Different child frame type creates new node.
        const S2 = struct {
            fn bootstrap(_: void, c: *BuildContext) ui.FrameId {
                return c.build(Root, .{
                    .id = .root,
                });
            }
        };
        var tmod: TestModule = undefined;
        tmod.init();
        defer tmod.deinit();
        try tmod.preUpdate({}, S2.bootstrap);
        var root = tmod.getNodeByTag(.root);
        try t.eq(root.?.numChildren(), 1);
        try t.eq(root.?.getChild(0).vtable, GenWidgetVTable(Foo));
        root.?.getWidget(Root).flag = false;
        try tmod.preUpdate({}, S2.bootstrap);
        root = tmod.getNodeByTag(.root);
        try t.eq(root.?.numChildren(), 1);
        try t.eq(root.?.getChild(0).vtable, GenWidgetVTable(Bar));
    }
}

test "Diff matches child with key." {
    const C = struct {};
    const B = struct {};
    const A = struct {
        props: struct {
            children: ui.FrameListPtr = ui.FrameListPtr.init(0, 0),
        },
        fn build(self: *@This(), c: *BuildContext) ui.FrameId {
            return c.fragment(self.props.children);
        }
    };
    {
        const S = struct {
            fn bootstrap(step: bool, c: *BuildContext) ui.FrameId {
                var b = ui.NullFrameId;
                if (!step) {
                    b = c.build(B, .{});
                }
                return c.build(A, .{
                    .id = .root,
                    .children = c.list(.{
                        b,
                        c.build(C, .{ .key = ui.WidgetKeyId(1) }),
                    }),
                });
            }
        };
        // Removing unrelated child preserves existing child with key.
        var mod: TestModule = undefined;
        mod.init();
        defer mod.deinit();

        try mod.preUpdate(false, S.bootstrap);
        var root = mod.getNodeByTag(.root).?;
        try t.eq(root.numChildren(), 2);

        const c = root.getChild(1);
        try t.eq(c.vtable, GenWidgetVTable(C));

        try mod.preUpdate(true, S.bootstrap);
        root = mod.getNodeByTag(.root).?;
        try t.eq(root.numChildren(), 1);

        // Keyed widget is the same instance.
        try t.eq(c, root.getChild(0));
    }
}

// test "BuildContext.build disallows using a prop that's not declared in Widget.props" {
//     const Foo = struct {
//         props: struct {
//             bar: usize,
//         };
//     };
//     var mod: Module = undefined;
//     Module.init(&mod, t.alloc, &g, LayoutSize.init(800, 600), undefined);
//     defer mod.deinit();
//     _ = mod.build_ctx.new(.Foo, .{ .text = "foo" });
// }

pub const LayoutConstraints = struct {
    min_width: f32,
    max_width: f32,
    min_height: f32,
    max_height: f32,
};

pub const Layout = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Layout {
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn initWithSize(x: f32, y: f32, size: LayoutSize) Layout {
        return .{
            .x = x,
            .y = y,
            .width = size.width,
            .height = size.height,
        };
    }

    pub inline fn contains(self: Layout, x: f32, y: f32) bool {
        return x >= self.x and x <= self.x + self.width and y >= self.y and y <= self.y + self.height;
    }
};

const IntervalSession = struct {
    dur: Duration,
    progress_ms: f32,
    node: *ui.Node,
    closure: ClosureIface(fn (ui.IntervalEvent) void),

    fn init(dur: Duration, node: *ui.Node, closure: ClosureIface(fn (ui.IntervalEvent) void)) IntervalSession {
        return .{
            .dur = dur,
            .progress_ms = 0,
            .node = node,
            .closure = closure,
        };
    }

    fn deinit(self: IntervalSession, alloc: std.mem.Allocator) void {
        self.closure.deinit(alloc);
    }

    fn call(self: *IntervalSession, ctx: *ui.EventContext) void {
        ctx.node = self.node;
        self.closure.call(.{
            ui.IntervalEvent{
                .progress_ms = self.progress_ms,
                .ctx = ctx,
            },
        });
    }
};

pub fn WidgetHasProps(comptime Widget: type) bool {
    if (!@hasField(Widget, "props")) {
        return false;
    }
    const PropsField = std.meta.fieldInfo(Widget, .props);
    return @typeInfo(PropsField.field_type) == .Struct;
}

pub fn WidgetProps(comptime Widget: type) type {
    if (WidgetHasProps(Widget)) {
        return std.meta.fieldInfo(Widget, .props).field_type;
    } else {
        return void;
        // @compileError(@typeName(Widget) ++ " doesn't have props field.");
    }
}

const UpdateError = error {
    NestedFragment,
    UserRootCantBeFragment,
};