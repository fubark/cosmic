const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const t = stdx.testing;
const ds = stdx.ds;
const Closure = stdx.Closure;
const ClosureIface = stdx.ClosureIface;
const Function = stdx.Function;
const Duration = stdx.time.Duration;
const string = stdx.string;
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const FontGroupId = graphics.FontGroupId;
const FontId = graphics.FontId;
const platform = @import("platform");
const EventDispatcher = platform.EventDispatcher;

const ui = @import("ui.zig");
const Config = ui.Config;
const Import = ui.Import;
const Node = ui.Node;
const Frame = ui.Frame;
const BindNode = @import("frame.zig").BindNode;
const FrameListPtr = ui.FrameListPtr;
const FramePropsPtr = ui.FramePropsPtr;
const FrameId = ui.FrameId;
const ui_render = @import("render.zig");
const WidgetTypeId = ui.WidgetTypeId;
const WidgetKey = ui.WidgetKey;
const WidgetRef = ui.WidgetRef;
const NodeRef = ui.NodeRef;
const WidgetVTable = ui.WidgetVTable;
const LayoutSize = ui.LayoutSize;
const NullId = ds.CompactNull(u32);
const NullFrameId = NullId;
const TextMeasure = ui.TextMeasure;
pub const TextMeasureId = usize;
pub const IntervalId = u32;
const log = stdx.log.scoped(.module);

pub fn getWidgetIdByType(comptime Widget: type) WidgetTypeId {
    return @ptrToInt(GenWidgetVTable(Widget));
}

/// Generates the vtable for a Widget.
pub fn GenWidgetVTable(comptime Widget: type) *const WidgetVTable {
    const gen = struct {

        fn create(alloc: std.mem.Allocator, node: *Node, ctx_ptr: *anyopaque, props_ptr: ?[*]const u8) *anyopaque {
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
                stdx.mem.ptrCastAlign(*WidgetRef(Widget), bind).* = WidgetRef(Widget).init(node);
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

        fn postUpdate(node: *Node) void {
            if (@hasDecl(Widget, "postUpdate")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Node) void, @TypeOf(Widget.postUpdate))) {
                    @compileError("Invalid postUpdate function: " ++ @typeName(@TypeOf(Widget.postUpdate)) ++ " Widget: " ++ @typeName(Widget));
                }
                Widget.postUpdate(node);
            }
        }

        fn build(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) FrameId {
            const ctx = stdx.mem.ptrCastAlign(*BuildContext, ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);

            if (!@hasDecl(Widget, "build")) {
                // No build function. Return null child.
                return NullFrameId;
            } else {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *BuildContext) FrameId, @TypeOf(Widget.build))) {
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

        fn render(node: *Node, ctx: *RenderContext, parent_abs_x: f32, parent_abs_y: f32) void {
            // Attach node to ctx.
            ctx.node = node;
            // Update node's absolute position based on it's relative position and the parent.
            node.abs_pos = .{
                .x = parent_abs_x + node.layout.x,
                .y = parent_abs_y + node.layout.y,
            };
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

        /// The default layout behavior is to report the same size as it's children.
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
            return LayoutSize.init(max_width, max_height);
        }

        fn destroy(node: *Node, alloc: std.mem.Allocator) void {
            if (@sizeOf(Widget) > 0) {
                const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                if (@hasDecl(Widget, "deinit")) {
                    Widget.deinit(node, alloc);
                }
                alloc.destroy(widget);
            }
        }

        const vtable = WidgetVTable{
            .create = create,
            .postInit = postInit,
            .updateProps = updateProps,
            .postUpdate = postUpdate,
            .build = build,
            .render = render,
            .layout = layout,
            .destroy = destroy,
            .has_post_update = @hasDecl(Widget, "postUpdate"),
            .name = @typeName(Widget),
        };
    };

    return &gen.vtable;
}

pub fn Event(comptime EventType: type) type {
    return struct {
        ctx: *EventContext,
        val: EventType,
    };
}

const FragmentVTable = GenWidgetVTable(struct {});

pub const Module = struct {
    const Self = @This();

    // TODO: Provide widget id map at the root level.

    alloc: std.mem.Allocator,

    root_node: ?*Node,
    user_root: NodeRef,

    init_ctx: InitContext,
    build_ctx: BuildContext,
    layout_ctx: LayoutContext,
    render_ctx: RenderContext,
    event_ctx: EventContext,
    mod_ctx: ModuleContext,

    common: ModuleCommon,

    text_measure_batch_buf: std.ArrayList(*graphics.TextMeasure),

    pub fn init(
        self: *Self,
        alloc: std.mem.Allocator,
        g: *Graphics,
    ) void {
        self.* = .{
            .alloc = alloc,
            .root_node = null,
            .user_root = .{},
            .init_ctx = InitContext.init(self),
            .build_ctx = undefined,
            .layout_ctx = LayoutContext.init(self, g),
            .event_ctx = EventContext.init(self),
            .render_ctx = undefined,
            .mod_ctx = ModuleContext.init(self),
            .common = undefined,
            .text_measure_batch_buf = std.ArrayList(*graphics.TextMeasure).init(alloc),
        };
        self.common.init(alloc, self, g);
        self.build_ctx = BuildContext.init(alloc, self.common.arena_alloc, self);
        self.render_ctx = RenderContext.init(&self.common.ctx, g);
    }

    pub fn deinit(self: *Self) void {
        self.build_ctx.deinit();
        self.text_measure_batch_buf.deinit();

        // Destroy widget nodes.
        if (self.root_node != null) {
            const S = struct {
                fn visit(mod: *Self, node: *Node) void {
                    mod.destroyNode(node);
                }
            };
            const walker = stdx.algo.recursive.ChildArrayListWalker(*Node);
            stdx.algo.recursive.walkPost(*Self, self, *Node, self.root_node.?, walker, S.visit);
        }

        self.common.deinit();
    }

    pub fn setContextProvider(self: *Self, provider: fn (key: u32) ?*anyopaque) void {
        self.common.context_provider = provider;
    }

    /// Attaches handlers to the event dispatcher.
    pub fn addInputHandlers(self: *Self, dispatcher: *EventDispatcher) void {
        const S = struct {
            fn onKeyDown(ctx: ?*anyopaque, e: platform.KeyDownEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                self_.processKeyDownEvent(e);
            }
            fn onKeyUp(ctx: ?*anyopaque, e: platform.KeyUpEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                self_.processKeyUpEvent(e);
            }
            fn onMouseDown(ctx: ?*anyopaque, e: platform.MouseDownEvent) platform.EventResult {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                return self_.processMouseDownEvent(e);
            }
            fn onMouseUp(ctx: ?*anyopaque, e: platform.MouseUpEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                self_.processMouseUpEvent(e);
            }
            fn onMouseScroll(ctx: ?*anyopaque, e: platform.MouseScrollEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                self_.processMouseScrollEvent(e);
            }
            fn onMouseMove(ctx: ?*anyopaque, e: platform.MouseMoveEvent) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
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

    pub fn getUserRoot(self: Self, comptime Widget: type) ?*Widget {
        if (self.root_node != null) {
            const root = self.root_node.?.getWidget(ui.widgets.Root);
            if (root.user_root.binded) {
                return root.user_root.node.getWidget(Widget);
            } 
        }
        return null;
    }

    fn getWidget(self: *Self, comptime Widget: type, node: *Node) *Widget {
        _ = self;
        return stdx.mem.ptrCastAlign(*Widget, node.widget);
    }

    pub fn processMouseUpEvent(self: *Self, e: platform.MouseUpEvent) void {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);

        self.common.last_focused_widget = self.common.focused_widget;
        self.common.hit_last_focused = false;

        // Trigger global handlers first.
        for (self.common.global_mouse_up_list.items) |id| {
            const sub = self.common.mouse_up_event_subs.getNoCheck(id);
            const node = sub.sub.node;
            if (node == self.common.last_focused_widget) {
                self.common.hit_last_focused = true;
            }
            self.event_ctx.node = node;
            sub.sub.handleEvent(&self.event_ctx, e);
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

    fn processMouseUpEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: platform.MouseUpEvent) bool {
        const pos = node.abs_pos;
        if (xf >= pos.x and xf <= pos.x + node.layout.width and yf >= pos.y and yf <= pos.y + node.layout.height) {
            if (node == self.common.last_focused_widget) {
                self.common.hit_last_focused = true;
            }
            var cur = node.mouse_up_list;
            while (cur != NullId) {
                const sub = self.common.mouse_up_event_subs.getNoCheck(cur);
                if (!sub.is_global) {
                    sub.sub.handleEvent(&self.event_ctx, e);
                    cur = self.common.mouse_up_event_subs.getNextNoCheck(cur);
                }
            }
            const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
            for (event_children) |child| {
                if (self.processMouseUpEventRecurse(child, xf, yf, e)) {
                    break;
                }
            }
            return true;
        } else return false;
    }

    /// Start at the root node and propagate downwards on the first hit box.
    /// TODO: Handlers should be able to return Stop to prevent propagation.
    pub fn processMouseDownEvent(self: *Self, e: platform.MouseDownEvent) platform.EventResult {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);
        self.common.last_focused_widget = self.common.focused_widget;
        self.common.hit_last_focused = false;
        var hit_widget = false;
        if (self.root_node) |node| {
            _ = self.processMouseDownEventRecurse(node, xf, yf, e, &hit_widget);
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

    fn processMouseDownEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: platform.MouseDownEvent, hit_widget: *bool) bool {
        const pos = node.abs_pos;
        if (xf >= pos.x and xf <= pos.x + node.layout.width and yf >= pos.y and yf <= pos.y + node.layout.height) {
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
                if (sub.handleEvent(&self.event_ctx, e) == .Stop) {
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
            for (event_children) |child| {
                if (self.processMouseDownEventRecurse(child, xf, yf, e, hit_widget)) {
                    break;
                }
            }
            return true;
        } else return false;
    }

    pub fn processMouseScrollEvent(self: *Self, e: platform.MouseScrollEvent) void {
        const xf = @intToFloat(f32, e.x);
        const yf = @intToFloat(f32, e.y);
        if (self.root_node) |node| {
            _ = self.processMouseScrollEventRecurse(node, xf, yf, e);
        }
    }

    fn processMouseScrollEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: platform.MouseScrollEvent) bool {
        const pos = node.abs_pos;
        if (xf >= pos.x and xf <= pos.x + node.layout.width and yf >= pos.y and yf <= pos.y + node.layout.height) {
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

    pub fn processMouseMoveEvent(self: *Self, e: platform.MouseMoveEvent) void {
        for (self.common.mouse_move_event_subs.items) |*it| {
            it.handleEvent(&self.event_ctx, e);
        }
    }

    pub fn processKeyDownEvent(self: *Self, e: platform.KeyDownEvent) void {
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

    pub fn processKeyUpEvent(self: *Self, e: platform.KeyUpEvent) void {
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

    fn updateRoot(self: *Self, root_id: FrameId) !void {
        if (root_id != NullFrameId) {
            const root = self.build_ctx.getFrame(root_id);
            if (self.root_node) |root_node| {
                if (root_node.vtable == root.vtable) {
                    try self.updateExistingNode(null, root_id, root_node);
                } else {
                    self.removeNode(root_node);
                    // Create the node first so getRoot() works in `init` and `postInit` callbacks.
                    var new_node = self.alloc.create(Node) catch unreachable;
                    self.root_node = new_node;
                    errdefer self.root_node = null;
                    _ = try self.createAndUpdateNode2(null, root_id, 0, new_node);
                }
            } else {
                var new_node = self.alloc.create(Node) catch unreachable;
                self.root_node = new_node;
                errdefer self.root_node = null;
                _ = try self.createAndUpdateNode2(null, root_id, 0, new_node);
            }
        } else {
            if (self.root_node) |root_node| {
                // Remove existing root.
                self.removeNode(root_node);
                self.root_node = null;
            }
        }
    }

    // 1. Run timers/intervals/animations.
    // 2. Build frames. Diff tree and create/update nodes from frames.
    // 3. Compute layout.
    // 4. Run next post layout cbs.
    pub fn preUpdate(self: *Self, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) FrameId, layout_size: LayoutSize) UpdateError!void {
        self.common.updateIntervals(delta_ms, &self.event_ctx);

        // TODO: check if we have to update

        // Reset the builder buffer before we call any Component.build
        self.build_ctx.resetBuffer();
        self.common.arena_allocator.deinit();
        self.common.arena_allocator.state = .{};

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
        const root_id = self.build_ctx.decl(ui.widgets.Root, .{ .user_root = user_root_id });

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
            const size = self.layout_ctx.computeLayout(self.root_node.?, layout_size);
            self.layout_ctx.setLayout(self.root_node.?, Layout.init(0, 0, size.width, size.height));
        }

        // Run logic that needs to happen after layout.
        for (self.common.next_post_layout_cbs.items) |*it| {
            it.call(.{});
            it.deinit(self.alloc);
        }
        self.common.next_post_layout_cbs.clearRetainingCapacity();
    }

    pub fn postUpdate(self: *Self) void {
        _ = self;
        // TODO: defer destroying widgets so that callbacks don't reference stale data.
    }

    /// Update a full app frame. Parts of the update are split up to facilitate testing.
    /// A bootstrap fn is needed to tell the module how to build the root frame.
    /// A width and height is needed to specify the root container size in which subsequent widgets will use for layout.
    pub fn updateAndRender(self: *Self, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) FrameId, width: f32, height: f32) !void {
        const layout_size = LayoutSize.init(width, height);
        try self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
        self.render(delta_ms);
        self.postUpdate();
    }

    /// Just do an update without rendering.
    pub fn update(self: *Self, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) FrameId, width: f32, height: f32) !void {
        const layout_size = LayoutSize.init(width, height);
        try self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
        self.postUpdate();
    }

    pub fn render(self: *Self, delta_ms: f32) void {
        self.render_ctx.delta_ms = delta_ms;
        ui_render.render(self);
    }

    /// Assumes the widget and the frame represent the same instance,
    /// so the widget is updated with the frame's props.
    /// Recursively update children.
    /// This assumes the frame's key is equal to the node's key.
    fn updateExistingNode(self: *Self, parent: ?*Node, frame_id: FrameId, node: *Node) UpdateError!void {
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
                const frame_key = if (child_frame_.key != null) child_frame_.key.? else WidgetKey{.Idx = child_idx};
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
                const new_child = try self.createAndUpdateNode(node, child_frame_id, 0);
                node.children.append(new_child) catch unreachable;
                return;
            }
            const child_node = node.children.items[0];
            if (child_node.vtable != child_frame.vtable) {
                self.removeNode(child_node);
                const new_child = try self.createAndUpdateNode(node, child_frame_id, 0);
                node.children.items[0] = new_child;
                if (node.children.items.len > 1) {
                    for (node.children.items[1..]) |it| {
                        self.removeNode(it);
                    }
                }
                return;
            }
            const frame_key = if (child_frame.key != null) child_frame.key.? else WidgetKey{.Idx = 0};
            if (!std.meta.eql(child_node.key, frame_key)) {
                self.removeNode(child_node);
                const new_child = try self.createAndUpdateNode(node, child_frame_id, 0);
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
    fn updateChildFramesWithKeyMap(self: *Self, parent: *Node, start_idx: u32, child_frames: FrameListPtr) UpdateError!void {
        var child_idx: u32 = start_idx;
        while (child_idx < child_frames.len): (child_idx += 1) {
            const frame_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
            const frame = self.build_ctx.getFrame(frame_id);

            if (frame.vtable == FragmentVTable) {
                return error.NestedFragment;
            }
            const frame_key = if (frame.key != null) frame.key.? else WidgetKey{.Idx = child_idx};

            // Look for an existing child by key.
            const existing_node_q = parent.key_to_child.get(frame_key); 
            if (existing_node_q != null and existing_node_q.?.vtable == frame.vtable) {
                try self.updateExistingNode(parent, frame_id, existing_node_q.?);

                // Update the children list as we iterate.
                if (parent.children.items[child_idx] != existing_node_q.?) {
                    // Move the unused item to the end so we can delete them afterwards.
                    parent.children.append(parent.children.items[child_idx]) catch unreachable;
                }
                parent.children.items[child_idx] = existing_node_q.?;
            } else {
                if (parent.children.items.len == child_idx) {
                    // Exceeded the size of the existing children list. Insert the rest from child frames.
                    const new_child = try self.createAndUpdateNode(parent, frame_id, child_idx);
                    parent.children.append(new_child) catch unreachable;
                    child_idx += 1;
                    while (child_idx < child_frames.len) : (child_idx += 1) {
                        const frame_id_ = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                        const new_child_ = try self.createAndUpdateNode(parent, frame_id_, child_idx);
                        parent.children.append(new_child_) catch unreachable;
                    }
                    break;
                }
                if (parent.children.items.len > child_idx) {
                    // Move the child at the same idx to the end.
                    parent.children.append(parent.children.items[child_idx]) catch unreachable;
                }

                // Create a new child instance to correspond with child frame.
                const new_child = try self.createAndUpdateNode(parent, frame_id, child_idx);

                parent.children.items[child_idx] = new_child;
            }
        }

        // All the unused children were moved to the end so we can delete them all.
        // TODO: deal with different instances with the same key.
        for (parent.children.items[child_idx..]) |it| {
            self.removeNode(it);
        }

        // Truncate existing children list to frame children list.
        if (parent.children.items.len > child_frames.len) {
            parent.children.shrinkRetainingCapacity(child_frames.len);
        }
    }

    /// Removes the node and performs deinit but does not unlink from the parent.children array since it's expensive.
    /// Assumes the caller has delt with it.
    fn removeNode(self: *Self, node: *Node) void {
        // Remove children first.
        for (node.children.items) |child| {
            self.removeNode(child);
        }

        if (node.parent != null) {
            _ = node.parent.?.key_to_child.remove(node.key);
        }
        self.destroyNode(node);
    }

    fn destroyNode(self: *Self, node: *Node) void {
        if (node.has_widget_id) {
            if (self.common.id_map.get(node.id)) |val| {
                // Must check that this node currently maps to that id since node removal can happen after newly created node.
                if (val == node) {
                    _ = self.common.id_map.remove(node.id);
                }
            }
        }

        const widget_vtable = node.vtable;
        widget_vtable.destroy(node, self.alloc);

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

        cur_id = node.mouse_up_list;
        while (cur_id != NullId) {
            const sub = self.common.mouse_up_event_subs.getNoCheck(cur_id);
            sub.sub.deinit(self.alloc);
            self.common.mouse_up_event_subs.removeAssumeNoPrev(cur_id) catch unreachable;
            cur_id = self.common.mouse_up_event_subs.getNextNoCheck(cur_id);
        }

        var i = @intCast(u32, self.common.mouse_move_event_subs.items.len);
        // TODO: Make faster.
        while (i > 0) {
            i -= 1;
            if (self.common.mouse_move_event_subs.items[i].node == node) {
                self.common.mouse_move_event_subs.items[i].deinit(self.alloc);
                _ = self.common.mouse_move_event_subs.orderedRemove(i);
            }
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

        node.deinit();
        self.alloc.destroy(node);
    }

    /// Builds the child frame for a given frame.
    fn buildChildFrame(self: *Self, frame_id: FrameId, node: *Node, widget_vtable: *const WidgetVTable) FrameId {
        self.build_ctx.prepareCall(frame_id, node);
        return widget_vtable.build(node.widget, &self.build_ctx);
    }

    inline fn createAndUpdateNode(self: *Self, parent: ?*Node, frame_id: FrameId, idx: u32) UpdateError!*Node {
        const new_node = self.alloc.create(Node) catch unreachable;
        return self.createAndUpdateNode2(parent, frame_id, idx, new_node);
    }

    /// Allow passing in a new node so a ref can be obtained beforehand.
    fn createAndUpdateNode2(self: *Self, parent: ?*Node, frame_id: FrameId, idx: u32, new_node: *Node) UpdateError!*Node {
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
        const key = if (frame.key != null) frame.key.? else WidgetKey{.Idx = idx};
        new_node.init(self.alloc, frame.vtable, parent, key, undefined);
        if (frame.id) |id| {
            // Due to how diffing works, nodes are batched removed at the end so a new node could be created to replace an existing one and still run into an id collision.
            // For now, just overwrite the existing mapping and make sure node removal only removes the id mapping if the entry matches the node.
            self.common.id_map.put(id, new_node) catch @panic("error");
            new_node.id = id;
            new_node.has_widget_id = true;
        }
        new_node.bind = frame.widget_bind;

        if (parent != null) {
            parent.?.key_to_child.put(key, new_node) catch unreachable;
        }

        self.init_ctx.prepareForNode(new_node);
        const new_widget = widget_vtable.create(self.alloc, new_node, &self.init_ctx, props_ptr);
        new_node.widget = new_widget;
        if (frame.node_binds != null) {
            var mb_cur = frame.node_binds;
            while (mb_cur) |cur| {
                cur.node_ref.* = NodeRef.init(new_node);
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
                    const child_node = try self.createAndUpdateNode(new_node, child_id, child_idx);
                    new_node.children.append(child_node) catch unreachable;
                }
            } else {
                // Single child frame.
                const child_node = try self.createAndUpdateNode(new_node, child_frame_id, 0);
                new_node.children.append(child_node) catch unreachable;
            }
        }
        // log.debug("after {s}", .{getWidgetName(frame.type_id)});

        self.init_ctx.prepareForNode(new_node);
        widget_vtable.postInit(new_widget, &self.init_ctx);
        return new_node;
    }

    pub fn dumpTree(self: Self) void {
        if (self.root_node) |root| {
            dumpTreeR(self, 0, root);
        }
    }

    fn dumpTreeR(self: Self, depth: u32, node: *Node) void {
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
    g: *Graphics,

    /// Elapsed time since the last render.
    delta_ms: f32,

    // Current node.
    node: *Node,

    const Self = @This();

    fn init(common: *CommonContext, g: *Graphics) Self {
        return .{
            .g = g,
            .common = common,
            .node = undefined,
            .delta_ms = 0,
        };
    }

    /// Note that this will update the current RenderContext.
    /// If you need RenderContext.node afterwards, that should be stored in a local variable first.
    /// To help prevent the user from forgetting this, an explicit parent_node is required.
    pub inline fn renderChildNode(self: *Self, parent: *Node, node: *Node) void {
        node.vtable.render(node, self, parent.abs_pos.x, parent.abs_pos.y);
    }

    /// Renders the children in order.
    pub inline fn renderChildren(self: *Self) void {
        const parent = self.node;
        for (self.node.children.items) |child| {
            child.vtable.render(child, self, parent.abs_pos.x, parent.abs_pos.y);
        }
    }

    pub inline fn getAbsLayout(self: *Self) Layout {
        return self.node.getAbsLayout();
    }

    pub inline fn getGraphics(self: *Self) *Graphics {
        return self.g;
    }

    pub usingnamespace MixinContextNodeReadOps(Self);
    // pub usingnamespace MixinContextReadOps(Self);
};

fn IntervalHandler(comptime Context: type) type {
    return fn (Context, IntervalEvent) void;
}

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
    };
}

/// Requires Context.common.
pub fn MixinContextFontOps(comptime Context: type) type {
    return struct {

        pub inline fn getFontVMetrics(self: Context, font_id: FontId, font_size: f32) graphics.VMetrics {
            return self.common.getFontVMetrics(font_id, font_size);
        }

        pub inline fn getPrimaryFontVMetrics(self: Context, font_gid: FontGroupId, font_size: f32) graphics.VMetrics {
            return self.common.getPrimaryFontVMetrics(font_gid, font_size);
        }

        pub inline fn getTextMeasure(self: Context, id: TextMeasureId) *TextMeasure {
            return self.common.getTextMeasure(id);
        }

        pub inline fn measureText(self: *Context, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.TextMetrics {
            return self.common.measureText(font_gid, font_size, str);
        }

        pub inline fn textGlyphIter(self: *Context, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.TextGlyphIterator {
            return self.common.textGlyphIter(font_gid, font_size, str);
        }

        pub inline fn textLayout(self: *Context, font_gid: FontGroupId, font_size: f32, str: []const u8, max_width: f32, buf: *graphics.TextLayout) void {
            return self.common.textLayout(font_gid, font_size, str, max_width, buf);
        }

        pub inline fn getFontGroupBySingleFontName(self: Context, name: []const u8) FontGroupId {
            return self.common.getFontGroupBySingleFontName(name);
        }

        pub inline fn getFontGroupByFamily(self: Context, family: graphics.FontFamily) FontGroupId {
            return self.common.getFontGroupByFamily(family);
        }

        pub inline fn getFontGroupForSingleFont(self: Context, font_id: FontId) FontGroupId {
            return self.common.getFontGroupForSingleFont(font_id);
        }

        pub inline fn getFontGroupForSingleFontOrDefault(self: Context, font_id: FontId) FontGroupId {
            if (font_id == NullId) {
                return self.getDefaultFontGroup();
            } else {
                return self.common.getFontGroupForSingleFont(font_id);
            }
        }

        pub inline fn getDefaultFontGroup(self: Context) FontGroupId {
            return self.common.getDefaultFontGroup();
        }

        pub inline fn createTextMeasure(self: *Context, font_gid: FontGroupId, font_size: f32) TextMeasureId {
            return self.common.createTextMeasure(font_gid, font_size);
        }
    };
}

const BlurHandler = fn (node: *Node, ctx: *CommonContext) void;

/// Ops that make sense with an attached node.
/// Requires Context.node and Context.common.
pub fn MixinContextNodeOps(comptime Context: type) type {
    return struct {
        pub inline fn getNode(self: *Context) *Node {
            return self.node;
        }

        pub inline fn requestFocus(self: *Context, on_blur: BlurHandler) void {
            self.common.requestFocus(self.node, on_blur);
        }

        pub inline fn requestCaptureMouse(self: *Context, capture: bool) void {
            self.common.requestCaptureMouse(capture);
        }

        pub inline fn addInterval(self: *Context, dur: Duration, ctx: anytype, cb: IntervalHandler(@TypeOf(ctx))) IntervalId {
            return self.common.addInterval(self.node, dur, ctx, cb);
        }

        pub inline fn addMouseUpHandler(self: *Context, ctx: anytype, cb: MouseUpHandler(@TypeOf(ctx))) void {
            self.common.addMouseUpHandler(self.node, ctx, cb);
        }

        pub inline fn addGlobalMouseUpHandler(self: *Context, ctx: anytype, cb: MouseUpHandler(@TypeOf(ctx))) void {
            self.common.addGlobalMouseUpHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseDownHandler(self: Context, ctx: anytype, cb: MouseDownHandler(@TypeOf(ctx))) void {
            self.common.addMouseDownHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseScrollHandler(self: Context, ctx: anytype, cb: MouseScrollHandler(@TypeOf(ctx))) void {
            self.common.addMouseScrollHandler(self.node, ctx, cb);
        }

        pub inline fn addKeyDownHandler(self: *Context, ctx: anytype, cb: KeyDownHandler(@TypeOf(ctx))) void {
            self.common.addKeyDownHandler(self.node, ctx, cb);
        }

        pub inline fn addKeyUpHandler(self: *Context, ctx: anytype, cb: KeyUpHandler(@TypeOf(ctx))) void {
            self.common.addKeyUpHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseMoveHandler(self: *Context, ctx: anytype, cb: MouseMoveHandler(@TypeOf(ctx))) void {
            self.common.addMouseMoveHandler(self.node, ctx, cb);
        }

        pub inline fn removeMouseUpHandler(self: *Context, comptime Ctx: type, func: MouseUpHandler(Ctx)) void {
            self.common.removeMouseUpHandler(self.node, Ctx, func);
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

        pub inline fn removeKeyUpHandler(self: *Context, comptime Ctx: type, func: KeyUpHandler(Ctx)) void {
            self.common.removeKeyUpHandler(Ctx, func);
        }

        pub inline fn removeMouseMoveHandler(self: *Context, comptime Ctx: type, func: MouseMoveHandler(Ctx)) void {
            self.common.removeMouseMoveHandler(Ctx, func);
        }
    };
}

pub const LayoutContext = struct {
    mod: *Module,
    common: *CommonContext,
    g: *Graphics,

    /// Vars set by parent and consumed by Widget.layout
    cstr: LayoutSize,
    node: *Node,

    /// If this is false, prefer the layout size to not exceed the max layout size equal to cstr.
    /// If true, either the width, or height, or both prefer an exact value.
    prefer_exact_width_or_height: bool,
    prefer_exact_width: bool,
    prefer_exact_height: bool,

    const Self = @This();

    fn init(mod: *Module, g: *Graphics) Self {
        return .{
            .mod = mod,
            .common = &mod.common.ctx,
            .prefer_exact_width_or_height = false,
            .prefer_exact_width = false,
            .prefer_exact_height = false,
            .g = g,
            .cstr = undefined,
            .node = undefined,
        };
    }

    pub inline fn getSizeConstraint(self: Self) LayoutSize {
        return self.cstr;
    }

    /// Computes the layout for a node with a preferred max size.
    pub fn computeLayout(self: *Self, node: *Node, max_size: LayoutSize) LayoutSize {
        // Creates another context on the stack so the caller can continue to use their context.
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common = &self.mod.common.ctx,
            .g = self.g,
            .cstr = max_size,
            .prefer_exact_width_or_height = false,
            .prefer_exact_width = false,
            .prefer_exact_height = false,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    /// Computes the layout for a node with additional stretch preferences.
    pub fn computeLayoutStretch(self: *Self, node: *Node, cstr: LayoutSize, prefer_exact_width: bool, prefer_exact_height: bool) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .g = self.g,
            .cstr = cstr,
            .prefer_exact_width_or_height = prefer_exact_width or prefer_exact_height,
            .prefer_exact_width = prefer_exact_width,
            .prefer_exact_height = prefer_exact_height,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn computeLayoutInherit(self: *Self, node: *Node) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .g = self.g,
            .cstr = self.cstr,
            .prefer_exact_width_or_height = self.prefer_exact_width_or_height,
            .prefer_exact_width = self.prefer_exact_width,
            .prefer_exact_height = self.prefer_exact_height,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn setLayout(self: *Self, node: *Node, layout: Layout) void {
        _ = self;
        node.layout = layout;
    }

    pub fn setLayoutPos(self: *Self, node: *Node, x: f32, y: f32) void {
        _ = self;
        node.layout.x = x;
        node.layout.y = y;
    }

    pub inline fn getLayout(self: *Self, node: *Node) Layout {
        _ = self;
        return node.layout;
    }

    pub usingnamespace MixinContextNodeOps(Self);
    pub usingnamespace MixinContextFontOps(Self);
};

pub const EventContext = struct {
    alloc: std.mem.Allocator,
    common: *CommonContext,
    node: *Node,

    const Self = @This();

    fn init(mod: *Module) Self {
        return .{
            .common = &mod.common.ctx,
            .alloc = mod.alloc,
            .node = undefined,
        };
    }

    pub usingnamespace MixinContextInputOps(Self);
    pub usingnamespace MixinContextNodeOps(Self);
    pub usingnamespace MixinContextFontOps(Self);
    pub usingnamespace MixinContextEventOps(Self);
};

pub const KeyDownEvent = Event(platform.KeyDownEvent);
pub const KeyUpEvent = Event(platform.KeyUpEvent);
pub const MouseDownEvent = Event(platform.MouseDownEvent);
pub const MouseUpEvent = Event(platform.MouseUpEvent);
pub const MouseMoveEvent = Event(platform.MouseMoveEvent);
pub const MouseScrollEvent = Event(platform.MouseScrollEvent);

fn KeyDownHandler(comptime Context: type) type {
    return fn (Context, KeyDownEvent) void;
}

fn KeyUpHandler(comptime Context: type) type {
    return fn (Context, KeyUpEvent) void;
}

fn MouseMoveHandler(comptime Context: type) type {
    return fn (Context, MouseMoveEvent) void;
}

fn MouseDownHandler(comptime Context: type) type {
    return fn (Context, MouseDownEvent) ui.EventResult;
}

fn MouseUpHandler(comptime Context: type) type {
    return fn (Context, MouseUpEvent) void;
}

fn MouseScrollHandler(comptime Context: type) type {
    return fn (Context, MouseScrollEvent) void;
}

/// Does not depend on ModuleConfig so it can be embedded into Widget structs to access common utilities.
pub const CommonContext = struct {
    const Self = @This();

    common: *ModuleCommon,
    alloc: std.mem.Allocator,

    pub inline fn getFontVMetrics(self: Self, font_gid: FontGroupId, font_size: f32) graphics.VMetrics {
        return self.common.g.getFontVMetrics(font_gid, font_size);
    }

    pub inline fn getPrimaryFontVMetrics(self: Self, font_gid: FontGroupId, font_size: f32) graphics.VMetrics {
        return self.common.g.getPrimaryFontVMetrics(font_gid, font_size);
    }

    pub inline fn createTextMeasure(self: *Self, font_gid: FontGroupId, font_size: f32) TextMeasureId {
        return self.common.createTextMeasure(font_gid, font_size);
    }

    pub inline fn destroyTextMeasure(self: *Self, id: TextMeasureId) void {
        self.mod.destroyTextMeasure(id);
    }

    pub fn getTextMeasure(self: Self, id: TextMeasureId) *TextMeasure {
        return self.common.getTextMeasure(id);
    }

    pub fn measureText(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.TextMetrics {
        var res: graphics.TextMetrics = undefined;
        self.common.g.measureFontText(font_gid, font_size, str, &res);
        return res;
    }

    pub inline fn textGlyphIter(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.TextGlyphIterator {
        return self.common.g.textGlyphIter(font_gid, font_size, str);
    }

    pub inline fn textLayout(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8, max_width: f32, buf: *graphics.TextLayout) void {
        self.common.g.textLayout(font_gid, font_size, str, max_width, buf);
    }

    pub inline fn getFontGroupForSingleFont(self: Self, font_id: FontId) FontGroupId {
        return self.common.g.getFontGroupForSingleFont(font_id);
    }

    pub inline fn getFontGroupForSingleFontOrDefault(self: Self, font_id: FontId) FontGroupId {
        if (font_id == NullId) {
            return self.getDefaultFontGroup();
        } else {
            return self.getFontGroupForSingleFont(font_id);
        }
    }

    pub inline fn getFontGroupBySingleFontName(self: Self, name: []const u8) FontGroupId {
        return self.common.g.getFontGroupBySingleFontName(name);
    }

    pub inline fn getFontGroupByFamily(self: Self, family: graphics.FontFamily) FontGroupId {
        return self.common.g.getFontGroupByFamily(family);
    }

    pub inline fn getGraphics(self: Self) *graphics.Graphics {
        return self.common.g;
    }

    pub fn getDefaultFontGroup(self: Self) FontGroupId {
        return self.common.default_font_gid;
    }

    pub fn addInterval(self: *Self, node: *Node, dur: Duration, ctx: anytype, cb: IntervalHandler(@TypeOf(ctx))) IntervalId {
        const closure = Closure(@TypeOf(ctx), fn (IntervalEvent) void).init(self.alloc, ctx, cb).iface();
        const s = IntervalSession.init(dur, node, closure);
        return self.common.interval_sessions.add(s) catch unreachable;
    }

    pub fn resetInterval(self: *Self, id: IntervalId) void {
        self.common.interval_sessions.getPtrNoCheck(id).progress_ms = 0;
    }

    pub fn removeInterval(self: *Self, id: IntervalId) void {
        self.common.interval_sessions.getNoCheck(id).deinit(self.alloc);
        self.common.interval_sessions.remove(id);
    }

    /// Receive mouse move events outside of the window. Useful for dragging operations.
    pub fn requestCaptureMouse(_: *Self, capture: bool) void {
        platform.captureMouse(capture);
    }

    pub fn requestFocus(self: *Self, node: *Node, on_blur: BlurHandler) void {
        if (self.common.focused_widget) |focused_widget| {
            if (focused_widget != node) {
                // Trigger blur for the current focused widget.
                self.common.focused_onblur(focused_widget, self);
            }
        }
        self.common.focused_widget = node;
        self.common.focused_onblur = on_blur;
    }

    pub fn isFocused(self: *Self, node: *Node) bool {
        if (self.common.focused_widget) |focused_widget| {
            return focused_widget == node;
        } else return false;
    }

    pub fn removeMouseMoveHandler(self: *Self, comptime Context: type, func: MouseMoveHandler(Context)) void {
        for (self.common.mouse_move_event_subs.items) |*sub, i| {
            if (sub.closure.user_fn == @ptrCast(*const anyopaque, func)) {
                sub.deinit(self.alloc);
                _ = self.common.mouse_move_event_subs.orderedRemove(i);
                break;
            }
        }
        if (self.common.mouse_move_event_subs.items.len == 0) {
            self.common.has_mouse_move_subs = false;
        }
    }

    pub fn addMouseUpHandler(self: *Self, node: *Node, ctx: anytype, cb: MouseUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (MouseUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = GlobalSubscriber(platform.MouseUpEvent){
            .sub = Subscriber(platform.MouseUpEvent){
                .closure = closure,
                .node = node,
            },
            .is_global = false,
        };
        if (self.common.mouse_up_event_subs.getLast(node.mouse_up_list)) |last_id| {
            _ = self.common.mouse_up_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            node.mouse_up_list = self.common.mouse_up_event_subs.add(sub) catch unreachable;
        }
    }

    pub fn addGlobalMouseUpHandler(self: *Self, node: *Node, ctx: anytype, cb: MouseUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (MouseUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = GlobalSubscriber(platform.MouseUpEvent){
            .sub = Subscriber(platform.MouseUpEvent){
                .closure = closure,
                .node = node,
            },
            .is_global = true,
        };
        var new_id: u32 = undefined;
        if (self.common.mouse_up_event_subs.getLast(node.mouse_up_list)) |last_id| {
            new_id = self.common.mouse_up_event_subs.insertAfter(last_id, sub) catch unreachable;
        } else {
            new_id = self.common.mouse_up_event_subs.add(sub) catch unreachable;
            node.mouse_up_list = new_id;
        }
        // Insert into global list.
        self.common.global_mouse_up_list.append(new_id) catch unreachable;
    }

    pub fn removeMouseUpHandler(self: *Self, node: *Node, comptime Context: type, func: MouseUpHandler(Context)) void {
        var cur = node.mouse_up_list;
        var prev = NullId;
        while (cur != NullId) {
            const sub = self.common.mouse_up_event_subs.getNoCheck(cur);
            if (sub.sub.closure.user_fn == @ptrCast(*const anyopaque, func)) {
                sub.sub.deinit(self.alloc);
                if (prev == NullId) {
                    node.mouse_up_list = self.common.mouse_up_event_subs.getNextNoCheck(cur);
                    self.common.mouse_up_event_subs.removeAssumeNoPrev(cur) catch unreachable;
                } else {
                    self.common.mouse_up_event_subs.removeAfter(prev) catch unreachable;
                }
                if (sub.is_global) {
                    for (self.common.global_mouse_up_list.items) |id, i| {
                        if (id == cur) {
                            _ = self.common.global_mouse_up_list.orderedRemove(i);
                            break;
                        }
                    }
                }
                // Continue scanning for duplicates.
            }
            prev = cur;
            cur = self.common.mouse_up_event_subs.getNextNoCheck(cur);
        }
    }

    pub fn addMouseDownHandler(self: Self, node: *Node, ctx: anytype, cb: MouseDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (MouseDownEvent) ui.EventResult).init(self.alloc, ctx, cb).iface();
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

    pub fn removeMouseDownHandler(self: *Self, node: *Node, comptime Context: type, func: MouseDownHandler(Context)) void {
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

    pub fn addMouseScrollHandler(self: Self, node: *Node, ctx: anytype, cb: MouseScrollHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (MouseScrollEvent) void).init(self.alloc, ctx, cb).iface();
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

    pub fn removeMouseScrollHandler(self: *Self, node: *Node, comptime Context: type, func: MouseScrollHandler(Context)) void {
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

    pub fn addMouseMoveHandler(self: *Self, node: *Node, ctx: anytype, cb: MouseMoveHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (MouseMoveEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.MouseMoveEvent){
            .closure = closure,
            .node = node,
        };
        self.common.mouse_move_event_subs.append(sub) catch unreachable;
        self.common.has_mouse_move_subs = true;
    }

    pub fn addKeyUpHandler(self: *Self, node: *Node, ctx: anytype, cb: KeyUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (KeyUpEvent) void).init(self.alloc, ctx, cb).iface();
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
    pub fn removeKeyUpHandler(self: *Self, node: *Node, func: *const anyopaque) void {
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

    pub fn addKeyDownHandler(self: *Self, node: *Node, ctx: anytype, cb: KeyDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (KeyDownEvent) void).init(self.alloc, ctx, cb).iface();
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

    pub fn removeKeyDownHandler(self: *Self, node: *Node, comptime Context: type, func: KeyDownHandler(Context)) void {
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

    pub fn nextPostLayout(self: *Self, ctx: anytype, cb: fn(@TypeOf(ctx)) void) void {
        return self.common.nextPostLayout(ctx, cb);
    }
};

// TODO: Refactor similar ops to their own struct. 
pub const ModuleCommon = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    mod: *Module,

    /// Arena allocator that gets freed after each update cycle.
    arena_allocator: std.heap.ArenaAllocator,
    arena_alloc: std.mem.Allocator,

    g: *Graphics,
    text_measures: ds.CompactUnorderedList(TextMeasureId, TextMeasure),
    interval_sessions: ds.CompactUnorderedList(u32, IntervalSession),

    // TODO: Use one buffer for all the handlers.
    /// Keyboard handlers.
    key_up_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.KeyUpEvent)),
    key_down_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.KeyDownEvent)),

    /// Mouse handlers.
    mouse_up_event_subs: ds.CompactSinglyLinkedListBuffer(u32, GlobalSubscriber(platform.MouseUpEvent)),
    global_mouse_up_list: std.ArrayList(u32),
    mouse_down_event_subs: ds.CompactSinglyLinkedListBuffer(u32, SubscriberRet(platform.MouseDownEvent, ui.EventResult)),
    mouse_scroll_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.MouseScrollEvent)),
    /// Mouse move events fire far more frequently so it's better to just iterate a list and skip hit test.
    /// TODO: Implement a compact tree of nodes for mouse events.
    mouse_move_event_subs: std.ArrayList(Subscriber(platform.MouseMoveEvent)),
    has_mouse_move_subs: bool,

    /// Currently focused widget.
    focused_widget: ?*Node,
    focused_onblur: BlurHandler,
    /// Scratch vars to track the last focused widget.
    last_focused_widget: ?*Node,
    hit_last_focused: bool,
    widget_hit_flag: bool,

    next_post_layout_cbs: std.ArrayList(ClosureIface(fn () void)),

    // next_post_render_cbs: std.ArrayList(*Node),

    // TODO: design themes.
    default_font_gid: FontGroupId,

    /// Keys are assumed to be static memory so they don't need to be freed.
    id_map: std.AutoHashMap(ui.WidgetUserId, *Node),

    ctx: CommonContext,

    context_provider: fn (key: u32) ?*anyopaque,

    fn init(self: *Self, alloc: std.mem.Allocator, mod: *Module, g: *Graphics) void {
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
            .text_measures = ds.CompactUnorderedList(TextMeasureId, TextMeasure).init(alloc),
            // .default_font_gid = g.getFontGroupBySingleFontName("Nunito Sans"),
            .default_font_gid = g.getDefaultFontGroupId(),
            .interval_sessions = ds.CompactUnorderedList(u32, IntervalSession).init(alloc),

            .key_up_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.KeyUpEvent)).init(alloc),
            .key_down_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.KeyDownEvent)).init(alloc),
            .mouse_up_event_subs = ds.CompactSinglyLinkedListBuffer(u32, GlobalSubscriber(platform.MouseUpEvent)).init(alloc),
            .global_mouse_up_list = std.ArrayList(u32).init(alloc),
            .mouse_down_event_subs = ds.CompactSinglyLinkedListBuffer(u32, SubscriberRet(platform.MouseDownEvent, ui.EventResult)).init(alloc),
            .mouse_move_event_subs = std.ArrayList(Subscriber(platform.MouseMoveEvent)).init(alloc),
            .mouse_scroll_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(platform.MouseScrollEvent)).init(alloc),
            .has_mouse_move_subs = false,

            .next_post_layout_cbs = std.ArrayList(ClosureIface(fn () void)).init(alloc),
            // .next_post_render_cbs = std.ArrayList(*Node).init(alloc),

            .focused_widget = null,
            .focused_onblur = undefined,
            .last_focused_widget = null,
            .hit_last_focused = false,
            .widget_hit_flag = false,

            .ctx = .{
                .common = self,
                .alloc = alloc, 
            },
            .context_provider = S.defaultContextProvider,
            .id_map = std.AutoHashMap(ui.WidgetUserId, *Node).init(alloc),
        };
        self.arena_alloc = self.arena_allocator.allocator();
    }

    fn deinit(self: *Self) void {
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
            var iter = self.mouse_up_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.sub.deinit(self.alloc);
            }
            self.mouse_up_event_subs.deinit();
        }
        self.global_mouse_up_list.deinit();

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

        for (self.mouse_move_event_subs.items) |*it| {
            it.deinit(self.alloc);
        }
        self.mouse_move_event_subs.deinit();

        self.arena_allocator.deinit();
    }

    fn createTextMeasure(self: *Self, font_gid: FontGroupId, font_size: f32) TextMeasureId {
        return self.text_measures.add(TextMeasure.init(&.{}, font_gid, font_size)) catch unreachable;
    }

    fn getTextMeasure(self: *Self, id: TextMeasureId) *TextMeasure {
        return self.text_measures.getPtrNoCheck(id);
    }

    pub fn destroyTextMeasure(self: *Self, id: TextMeasureId) void {
        self.text_measures.remove(id);
    }

    fn updateIntervals(self: *Self, delta_ms: f32, event_ctx: *EventContext) void {
        var iter = self.interval_sessions.iterator();
        while (iter.nextPtr()) |it| {
            it.progress_ms += delta_ms;
            if (it.progress_ms > @intToFloat(f32, it.dur.toMillis())) {
                it.call(event_ctx);
                it.progress_ms = 0;
            }
        }
    }

    fn nextPostLayout(self: *Self, ctx: anytype, cb: fn (@TypeOf(ctx)) void) void {
        const closure = Closure(@TypeOf(ctx), fn () void).init(self.alloc, ctx, cb).iface();
        self.next_post_layout_cbs.append(closure) catch unreachable;
    }

    /// Given id as an enum literal tag, return the node.
    pub fn getNodeByTag(self: Self, comptime lit: @Type(.EnumLiteral)) ?*Node {
        const id = stdx.meta.enumLiteralId(lit);
        return self.id_map.get(id);
    }
};

pub const ModuleContext = struct {
    const Self = @This();

    mod: *Module,

    fn init(mod: *Module) Self {
        return .{
            .mod = mod,
        };
    }
};

pub const InitContext = struct {
    mod: *Module,
    alloc: std.mem.Allocator,
    common: *CommonContext,
    node: *Node,

    const Self = @This();

    fn init(mod: *Module) Self {
        return .{
            .mod = mod,
            .alloc = mod.alloc,
            .common = &mod.common.ctx,
            .node = undefined,
        };
    }

    fn prepareForNode(self: *Self, node: *Node) void {
        self.node = node;
    }

    pub fn getModuleContext(self: *Self) *ModuleContext {
        return &self.mod.mod_ctx;
    }

    // TODO: findChildrenByTag
    // TODO: findChildByKey
    pub fn findChildWidgetByType(self: *Self, comptime Widget: type) ?WidgetRef(Widget) {
        const needle = getWidgetIdByType(Widget);
        const walker = stdx.algo.recursive.ChildArrayListSearchWalker(*Node);
        const S = struct {
            fn pred(type_id: WidgetTypeId, node: *Node) bool {
                return @ptrToInt(node.vtable) == type_id;
            }
        };
        const res = stdx.algo.recursive.searchPreMany(WidgetTypeId, needle, *Node, self.node.children.items, walker, S.pred);
        if (res != null) {
            return WidgetRef(Widget).init(res.?);
        } else {
            return null;
        }
    }

    pub usingnamespace MixinContextInputOps(Self);
    pub usingnamespace MixinContextEventOps(Self);
    pub usingnamespace MixinContextNodeOps(Self);
    pub usingnamespace MixinContextFontOps(Self);
    pub usingnamespace MixinContextSharedOps(Self);
};

/// Contains an extra global flag.
fn GlobalSubscriber(comptime T: type) type {
    return struct {
        sub: Subscriber(T),
        is_global: bool,
    };
}

fn SubscriberRet(comptime T: type, comptime Return: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (Event(T)) Return),
        node: *Node,

        fn handleEvent(self: Self, ctx: *EventContext, e: T) Return {
            ctx.node = self.node;
            return self.closure.call(.{
                Event(T){
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

fn Subscriber(comptime T: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (Event(T)) void),
        node: *Node,

        fn handleEvent(self: Self, ctx: *EventContext, e: T) void {
            ctx.node = self.node;
            self.closure.call(.{
                Event(T){
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

pub const BuildContext = struct {
    alloc: std.mem.Allocator,
    arena_alloc: std.mem.Allocator,
    mod: *Module,

    // Temporary buffers used to build Frames in Widget's `build` function.
    // Cleared on the next update cycle. FrameIds generated are indexes to this buffer.
    frames: std.ArrayList(Frame),
    // One ArrayList is used to store multiple frame lists.
    // Appends a complete list and returns the start index and size as the key.
    frame_lists: std.ArrayList(FrameId),
    // Stores variable sized Widget props data. Appends props data and returns
    // the start index and size as the key.
    frame_props: ds.DynamicArrayList(u32, u8),

    u8_buf: std.ArrayList(u8),

    // Current node.
    node: *Node,

    // Current Frame used. Must use id since pointer could be invalidated.
    frame_id: FrameId,

    const Self = @This();

    fn init(alloc: std.mem.Allocator, arena_alloc: std.mem.Allocator, mod: *Module) Self {
        return .{
            .alloc = alloc,
            .arena_alloc = arena_alloc,
            .mod = mod,
            .frames = std.ArrayList(Frame).init(alloc),
            .frame_lists = std.ArrayList(FrameId).init(alloc),
            .frame_props = ds.DynamicArrayList(u32, u8).init(alloc),
            .u8_buf = std.ArrayList(u8).init(alloc),
            .node = undefined,
            .frame_id = undefined,
        };
    }

    fn deinit(self: *Self) void {
        self.frames.deinit();
        self.frame_lists.deinit();
        self.frame_props.deinit();
        self.u8_buf.deinit();
    }

    /// Creates a closure in arena buffer, and returns an iface.
    pub fn closure(self: *Self, ctx: anytype, user_fn: anytype) Function(stdx.meta.FnAfterFirstParam(@TypeOf(user_fn))) {
        const Params = comptime stdx.meta.FnParams(@TypeOf(user_fn));
        if (Params.len == 0) {
            @compileError("Expected first param to be: " ++ @typeName(@TypeOf(ctx)));
        }
        const InnerFn = stdx.meta.FnAfterFirstParam(@TypeOf(user_fn));
        const c = Closure(@TypeOf(ctx), InnerFn).init(self.mod.common.arena_alloc, ctx, user_fn).iface();
        return Function(InnerFn).initClosureIface(c);
    }

    /// Returns a wrapper over a free function.
    pub fn func(self: *Self, comptime user_fn: anytype) Function(@TypeOf(user_fn)) {
        _ = self;
        const Fn = @TypeOf(user_fn);
        stdx.meta.assertFunctionType(Fn);
        return Function(Fn).init(user_fn);
    }

    /// Returns a wrapper over a free function with a context pointer. This doesn't need any allocations.
    pub fn funcExt(self: *Self, ctx_ptr: anytype, comptime user_fn: anytype) Function(stdx.meta.FnAfterFirstParam(@TypeOf(user_fn))) {
        _ = self;
        const Params = comptime stdx.meta.FnParams(@TypeOf(user_fn));
        if (Params[0].arg_type.? != @TypeOf(ctx_ptr)) {
            @compileError("Expected first param to be: " ++ @typeName(@TypeOf(ctx_ptr)));
        }
        const InnerFn = stdx.meta.FnAfterFirstParam(@TypeOf(user_fn));
        return Function(InnerFn).initContext(ctx_ptr, user_fn);
    }

    pub fn range(self: *Self, count: usize, ctx: anytype, build_fn: fn (@TypeOf(ctx), *BuildContext, u32) FrameId) FrameListPtr {
        const start_idx = self.frame_lists.items.len;
        var i: u32 = 0;
        var buf_i: u32 = 0;
        // Preallocate the list so that the frame ids can be layed out contiguously. Otherwise, the frame_lists array runs the risk of being modified by the user build fn.
        // TODO: This is inefficient if the range is mostly a filter, leaving empty frame slots. One way to solve this is to use a separate stack buffer.
        self.frame_lists.resize(self.frame_lists.items.len + count) catch unreachable;
        while (i < count) : (i += 1) {
            const frame_id = build_fn(ctx, self, @intCast(u32, i));
            if (frame_id != NullFrameId) {
                self.frame_lists.items[start_idx + buf_i] = frame_id;
                buf_i += 1;
            }
        }
        return FrameListPtr.init(@intCast(u32, start_idx), buf_i);
    }

    fn resetBuffer(self: *Self) void {
        self.frames.clearRetainingCapacity();
        self.frame_lists.clearRetainingCapacity();
        self.frame_props.clearRetainingCapacity();
        self.u8_buf.clearRetainingCapacity();
    }

    fn prepareCall(self: *Self, frame_id: FrameId, node: *Node) void {
        self.frame_id = frame_id;
        self.node = node;
    }

    /// Appends formatted string to temporary buffer.
    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []const u8 {
        const start = self.u8_buf.items.len;
        std.fmt.format(self.u8_buf.writer(), format, args) catch unreachable;
        return self.u8_buf.items[start..];
    }

    /// Short-hand for createFrame.
    pub inline fn decl(self: *Self, comptime Widget: type, props: anytype) FrameId {
        return self.createFrame(Widget, props);
    }

    pub inline fn list(self: *Self, tuple_or_slice: anytype) FrameListPtr {
        const IsTuple = comptime std.meta.trait.isTuple(@TypeOf(tuple_or_slice));
        if (IsTuple) {
            // createFrameList doesn't support tuples right now because of tuples nested in anonymous struct is bugged,
            // so we convert it to an array.
            const arr: [stdx.meta.TupleLen(@TypeOf(tuple_or_slice))]FrameId = tuple_or_slice;
            return self.createFrameList(arr);
        } else {
            return self.createFrameList(tuple_or_slice);
        }
    }

    pub inline fn fragment(self: *Self, list_: FrameListPtr) FrameId {
        const frame = Frame.init(FragmentVTable, null, null, FramePropsPtr.init(0, 0), list_);
        const frame_id = @intCast(FrameId, @intCast(u32, self.frames.items.len));
        self.frames.append(frame) catch unreachable;
        return frame_id;
    }

    /// Allows caller to bind a FrameId to a NodeRef. One frame can be binded to many NodeRefs.
    pub fn bindFrame(self: *Self, frame_id: FrameId, ref: *ui.NodeRef) void {
        if (frame_id != NullFrameId) {
            const frame = &self.frames.items[frame_id];
            const node = self.arena_alloc.create(BindNode) catch fatal();
            node.node_ref = ref;
            node.next = frame.node_binds;
            frame.node_binds = node;
        }
    }

    fn createFrameList(self: *Self, frame_ids: anytype) FrameListPtr {
        const Type = @TypeOf(frame_ids);
        const IsSlice = comptime std.meta.trait.isSlice(Type) and @typeInfo(Type).Pointer.child == FrameId;
        const IsArray = @typeInfo(Type) == .Array;
        // const IsTuple = comptime std.meta.trait.isTuple(Type);
        comptime {
            // Currently disallow tuples due to https://github.com/ziglang/zig/issues/6043. 
            if (!IsSlice and !IsArray) {
                @compileError("unsupported  " ++ @typeName(Type));
            }
        }
        const start_idx = @intCast(u32, self.frame_lists.items.len);
        self.frame_lists.ensureUnusedCapacity(frame_ids.len) catch @panic("error");
        if (IsSlice or IsArray) {
            for (frame_ids) |id| {
                if (id != NullFrameId) {
                    self.frame_lists.appendAssumeCapacity(id);
                }
            }
        } else {
            stdx.debug.panic("unexpected");
            // inline for (std.meta.fields(Type)) |f| {
            //     const frame_id = @field(frame_ids, f.name);
            //     log.warn("appending {} {s} {}", .{frame_id, f.name, frame_ids});
            //     self.frame_lists.append(frame_id) catch unreachable;
            // }
        }
        return FrameListPtr.init(start_idx, @intCast(u32, self.frame_lists.items.len) - start_idx);
    }

    fn getFrame(self: Self, id: FrameId) Frame {
        return self.frames.items[id];
    }

    fn getFrameList(self: *Self, ptr: FrameListPtr) []const FrameId {
        const end_idx = ptr.id + ptr.len;
        return self.frame_lists.items[ptr.id..end_idx];
    }

    fn createFrame(self: *Self, comptime Widget: type, build_props: anytype) FrameId {
        // log.warn("createFrame {}", .{build_props});
        const BuildProps = @TypeOf(build_props);

        if (@hasField(BuildProps, "bind")) {
            if (stdx.meta.FieldType(BuildProps, .bind) != *WidgetRef(Widget)) {
                @compileError("Expected bind type to be: " ++ @typeName(*WidgetRef(Widget)));
            }
        }
        if (@hasField(BuildProps, "id")) {
            if (@typeInfo(stdx.meta.FieldType(BuildProps, .id)) != .EnumLiteral) {
                @compileError("Expected id type to be an enum literal.");
            }
        }
        if (@hasField(BuildProps, "spread")) {
            if (stdx.meta.FieldType(BuildProps, .spread) != WidgetProps(Widget)) {
                @compileError("Expected widget props type to spread.");
            }
        }
        const bind: ?*anyopaque = if (@hasField(BuildProps, "bind")) build_props.bind else null;
        const id = if (@hasField(BuildProps, "id")) stdx.meta.enumLiteralId(build_props.id) else null;

        const props_ptr = b: {
            const HasProps = comptime WidgetHasProps(Widget);

            // First use comptime to get a list of valid fields to be copied to props.
            const ValidFields = comptime b2: {
                var res: []const std.builtin.TypeInfo.StructField = &.{};
                for (std.meta.fields(BuildProps)) |f| {
                    // Skip special fields.
                    if (string.eq("id", f.name)) {
                        continue;
                    } else if (string.eq("bind", f.name)) {
                        continue;
                    } else if (string.eq("spread", f.name)) {
                        continue;
                    } else if (!HasProps) {
                        @compileError("No Props type declared in " ++ @typeName(Widget) ++ " for " ++ f.name);
                    } else if (@hasField(WidgetProps(Widget), f.name)) {
                        res = res ++ &[_]std.builtin.TypeInfo.StructField{f};
                    } else {
                        @compileError(f.name ++ " isn't declared in " ++ @typeName(Widget) ++ ".Props");
                    }
                }
                break :b2 res;
            };
            _ = ValidFields;

            if (HasProps) {
                var props: WidgetProps(Widget) = undefined;

                if (@hasField(BuildProps, "spread")) {
                    props = build_props.spread;
                    // When spreading provided props, don't overwrite with default values.
                    inline for (std.meta.fields(WidgetProps(Widget))) |Field| {
                        if (@hasField(BuildProps, Field.name)) {
                            @field(props, Field.name) = @field(build_props, Field.name);
                        }
                    }
                } else {
                    inline for (std.meta.fields(WidgetProps(Widget))) |Field| {
                        if (@hasField(BuildProps, Field.name)) {
                            @field(props, Field.name) = @field(build_props, Field.name);
                        } else {
                            if (Field.default_value) |def| {
                                // Set default value.
                                @field(props, Field.name) = @ptrCast(*const Field.field_type, def).*;
                            } else {
                                @compileError("Required field " ++ Field.name ++ " in " ++ @typeName(Widget));
                            }
                        }
                    }
                }

                // Then inline the copy statements.
                // inline for (ValidFields) |f| {
                //     @field(props, f.name) = @field(build_props, f.name);
                // }
                // log.warn("set frame props", .{});
                break :b self.frame_props.append(props) catch unreachable;
            } else {
                break :b FramePropsPtr.init(0, 0);
            }
        };
        const vtable = GenWidgetVTable(Widget);
        const frame = Frame.init(vtable, id, bind, props_ptr, FrameListPtr.init(0, 0));
        const frame_id = @intCast(FrameId, @intCast(u32, self.frames.items.len));
        self.frames.append(frame) catch unreachable;

        // log.warn("created frame {}", .{frame_id});
        return frame_id;
    }
};

const TestModule = struct {
    g: graphics.Graphics,
    mod: ui.Module,
    size: ui.LayoutSize,

    const Self = @This();

    pub fn init(self: *Self) void {
        self.g.init(t.alloc, 1);
        self.mod.init(t.alloc, &self.g);
        self.size = LayoutSize.init(800, 600);
    }

    pub fn deinit(self: *Self) void {
        self.mod.deinit();
        self.g.deinit();
    }

    pub fn preUpdate(self: *Self, ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(ctx), *BuildContext) FrameId) !void {
        try self.mod.preUpdate(0, ctx, bootstrap_fn, self.size);
    }

    pub fn getRoot(self: Self) ?*Node {
        return self.mod.root_node;
    }

    pub fn getNodeByTag(self: Self, comptime lit: @Type(.EnumLiteral)) ?*Node {
        return self.mod.common.getNodeByTag(lit);
    }
};

test "Node removal also removes the children." {
    const A = struct {
        props: struct {
            child: FrameId,
        },
        fn build(self: *@This(), _: *BuildContext) FrameId {
            return self.props.child;
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(delete: bool, c: *BuildContext) FrameId {
            var child: FrameId = NullFrameId;
            if (!delete) {
                child = c.decl(A, .{ 
                    .child = c.decl(B, .{}),
                });
            }
            return c.decl(A, .{
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
        fn bootstrap(_: void, c: *BuildContext) FrameId {
            const list = c.list(.{
                c.decl(A, .{}),
                c.decl(A, .{}),
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
        fn build(_: *@This(), c: *BuildContext) FrameId {
            return c.fragment(c.list(.{
                NullFrameId,
                c.decl(B, .{}),
            }));
        }
    };
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) FrameId {
            return c.decl(A, .{
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
        props: struct { child: FrameId },
        fn build(self: *@This(), _: *BuildContext) FrameId {
            return self.props.child;
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(_: void, c: *ui.BuildContext) FrameId {
            const nested_list = c.list(.{
                c.decl(B, .{}),
            });
            const list = c.list(.{
                c.decl(B, .{}),
                c.fragment(nested_list),
            });
            return c.decl(A, .{
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
        fn build(self: *@This(), c: *BuildContext) FrameId {
            return c.fragment(self.props.children);
        }
    };
    const B = struct {};
    // Test case where a child widget uses BuildContext.list. Check if this causes problems with BuildContext.range.
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) FrameId {
            return c.decl(A, .{
                .id = .root,
                .children = c.range(1, {}, buildChild),
            });
        }
        fn buildChild(_: void, c: *BuildContext, _: u32) FrameId {
            const list = c.list(.{
                c.decl(B, .{}),
            });
            return c.decl(A, .{ .children = list });
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
            c.addMouseUpHandler({}, onMouseUp);
            c.addMouseMoveHandler(@as(u32, 1), onMouseMove);
            _ = c.addInterval(Duration.initSecsF(1), {}, onInterval);
            c.requestFocus(onBlur);
        }
        fn onInterval(_: void, _: ui.IntervalEvent) void {}
        fn onBlur(_: *ui.Node, _: *ui.CommonContext) void {}
        fn onKeyUp(_: void, _: KeyUpEvent) void {}
        fn onKeyDown(_: void, _: KeyDownEvent) void {}
        fn onMouseDown(_: void, _: MouseDownEvent) ui.EventResult {
            return .Continue;
        }
        fn onMouseUp(_: void, _: MouseUpEvent) void {}
        fn onMouseMove(_: u32, _: MouseMoveEvent) void {}
    };
    const S = struct {
        fn bootstrap(decl: bool, c: *BuildContext) FrameId {
            if (decl) {
                return c.decl(A, .{
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

    try t.eq(mod.common.mouse_up_event_subs.size(), 1);
    const mouseup_sub = mod.common.mouse_up_event_subs.iterFirstValueNoCheck();
    try t.eq(mouseup_sub.is_global, false);
    try t.eq(mouseup_sub.sub.node, root.?);
    try t.eq(mouseup_sub.sub.closure.user_fn, A.onMouseUp);

    try t.eq(mod.common.mouse_move_event_subs.items.len, 1);
    const mousemove_sub = mod.common.mouse_move_event_subs.items[0];
    try t.eq(mousemove_sub.node, root.?);
    try t.eq(mousemove_sub.closure.user_fn, A.onMouseMove);

    try t.eq(mod.common.interval_sessions.size(), 1);
    var iter = mod.common.interval_sessions.iterator();
    const interval_sub = iter.next().?;
    try t.eq(interval_sub.node, root.?);
    try t.eq(interval_sub.closure.user_fn, A.onInterval);

    try tmod.preUpdate(false, S.bootstrap);

    // Widget instance should be removed and handlers should have been cleaned up.
    root = tmod.getNodeByTag(.root);
    try t.eq(root, null);
    try t.eq(mod.common.focused_widget, null);
    try t.eq(mod.common.key_up_event_subs.size(), 0);
    try t.eq(mod.common.key_down_event_subs.size(), 0);
    try t.eq(mod.common.mouse_down_event_subs.size(), 0);
    try t.eq(mod.common.mouse_up_event_subs.size(), 0);
    try t.eq(mod.common.mouse_move_event_subs.items.len, 0);
    try t.eq(mod.common.interval_sessions.size(), 0);
}

test "Module.update creates or updates existing node" {
    var g: graphics.Graphics = undefined;
    g.init(t.alloc, 1);
    defer g.deinit();

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

        fn build(self: *@This(), c: *BuildContext) FrameId {
            if (self.flag) {
                return c.decl(Foo, .{});
            } else {
                return c.decl(Bar, .{});
            }
        }
    };

    {
        // Different root frame type creates new node.
        const S2 = struct {
            fn bootstrap(flag: bool, c: *BuildContext) FrameId {
                if (flag) {
                    return c.decl(Foo, .{
                        .id = .root,
                    });
                } else {
                    return c.decl(Bar, .{
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
            fn bootstrap(_: void, c: *BuildContext) FrameId {
                return c.decl(Root, .{
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

// test "BuildContext.new disallows using a prop that's not declared in Component.Props" {
//     const Foo = struct {
//         const Props = struct {
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

    const Self = @This();

    pub fn init(x: f32, y: f32, width: f32, height: f32) Self {
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn initWithSize(x: f32, y: f32, size: LayoutSize) Self {
        return .{
            .x = x,
            .y = y,
            .width = size.width,
            .height = size.height,
        };
    }

    pub fn contains(self: Self, x: f32, y: f32) bool {
        return x >= self.x and x <= self.x + self.width and y >= self.y and y <= self.y + self.height;
    }
};

const IntervalSession = struct {
    const Self = @This();
    dur: Duration,
    progress_ms: f32,
    node: *Node,
    closure: ClosureIface(fn (IntervalEvent) void),

    fn init(dur: Duration, node: *Node, closure: ClosureIface(fn (IntervalEvent) void)) Self {
        return .{
            .dur = dur,
            .progress_ms = 0,
            .node = node,
            .closure = closure,
        };
    }

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        self.closure.deinit(alloc);
    }

    fn call(self: *Self, ctx: *EventContext) void {
        ctx.node = self.node;
        self.closure.call(.{
            IntervalEvent{
                .progress_ms = self.progress_ms,
                .ctx = ctx,
            },
        });
    }
};

pub const IntervalEvent = struct {
    progress_ms: f32,
    ctx: *EventContext,
};

fn WidgetHasProps(comptime Widget: type) bool {
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
        @compileError(@typeName(Widget) ++ " doesn't have props field.");
    }
}

const UpdateError = error {
    NestedFragment,
    UserRootCantBeFragment,
};