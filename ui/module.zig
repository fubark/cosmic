const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const ds = stdx.ds;
const Closure = stdx.Closure;
const ClosureIface = stdx.ClosureIface;
const Function = stdx.Function;
const Duration = stdx.time.Duration;
const string = stdx.string;
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const FontGroupId = graphics.font.FontGroupId;
const platform = @import("platform");
const KeyUpEvent = platform.KeyUpEvent;
const KeyDownEvent = platform.KeyDownEvent;
const MouseUpEvent = platform.MouseUpEvent;
const MouseDownEvent = platform.MouseDownEvent;
const MouseScrollEvent = platform.MouseScrollEvent;
const MouseMoveEvent = platform.MouseMoveEvent;
const EventDispatcher = platform.EventDispatcher;

const ui = @import("ui.zig");
const Config = ui.Config;
const Import = ui.Import;
const Node = ui.Node;
const Frame = ui.Frame;
const FrameListPtr = ui.FrameListPtr;
const FramePropsPtr = ui.FramePropsPtr;
const FrameId = ui.FrameId;
const ui_render = @import("render.zig");
const WidgetTypeId = ui.WidgetTypeId;
const WidgetKey = ui.WidgetKey;
const WidgetRef = ui.WidgetRef;
const WidgetVTable = ui.WidgetVTable;
const LayoutSize = ui.LayoutSize;
const NullId = ds.CompactNull(u32);
const NullFrameId = NullId;
const TextMeasure = ui.TextMeasure;
pub const TextMeasureId = usize;
pub const IntervalId = u32;
const log = stdx.log.scoped(.module);

/// Contains static info about a widget type.
const WidgetTypeInfo = struct {
    vtable: *const WidgetVTable,
    // Whether this widget has a postRender function.
    has_post_render: bool,
};

/// Generates the vtable for a Widget given a module config.
fn genWidgetVTable(comptime C: Config, comptime Widget: type) *const WidgetVTable {
    const gen = struct {

        fn create(alloc: std.mem.Allocator, node: *Node, ctx_ptr: *anyopaque, props_ptr: ?[*]const u8) *anyopaque {
            const ctx = stdx.mem.ptrCastAlign(*C.Init(), ctx_ptr);

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
                // Call widget's init to set state.
                new.init(C, ctx);
            }
            // Set bind.
            if (node.bind) |bind| {
                stdx.mem.ptrCastAlign(*WidgetRef(Widget), bind).* = WidgetRef(Widget).init(new, node);
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
            const ctx = stdx.mem.ptrCastAlign(*C.Init(), ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "postInit")) {
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.postInit(C, ctx);
                } else {
                    widget.postInit(C, ctx);
                }
            }
        }

        fn updateProps(widget_ptr: *anyopaque, props_ptr: [*]const u8) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (comptime WidgetHasProps(Widget)) {
                const Props = WidgetProps(Widget);
                widget.props = std.mem.bytesToValue(Props, props_ptr[0..@sizeOf(Props)]);
            }
            if (@hasDecl(Widget, "postUpdate")) {
                widget.postUpdate();
            }
        }

        fn build(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) FrameId {
            const ctx = stdx.mem.ptrCastAlign(*C.Build(), ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);

            if (!@hasDecl(Widget, "build")) {
                // No build function. Return null child.
                return NullFrameId;
            }
            if (@sizeOf(Widget) == 0) {
                const empty: *Widget = undefined;
                return empty.build(C, ctx);
            } else {
                return widget.build(C, ctx);
            }
        }

        fn render(widget_ptr: *anyopaque, ctx: *RenderContext) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "render")) {
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.render(ctx);
                } else {
                    widget.render(ctx);
                }
            }
        }

        fn postRender(widget_ptr: *anyopaque, ctx: *RenderContext) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "postRender")) {
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    empty.postRender(ctx);
                } else {
                    widget.postRender(ctx);
                }
            }
        }

        fn layout(widget_ptr: *anyopaque, ctx_ptr: *anyopaque) LayoutSize {
            const ctx = stdx.mem.ptrCastAlign(*C.Layout(), ctx_ptr);
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "layout")) {
                if (@sizeOf(Widget) == 0) {
                    const empty: *Widget = undefined;
                    return empty.layout(C, ctx);
                } else {
                    return widget.layout(C, ctx);
                }
            } else {
                return defaultLayout(ctx);
            }
        }

        /// The default layout behavior is to report the same size as it's children.
        /// Multiple children are stacked over each other like a ZStack.
        fn defaultLayout(c: *C.Layout()) LayoutSize {
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
            .build = build,
            .render = render,
            .postRender = postRender,
            .layout = layout,
            .destroy = destroy,
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

pub fn Module(comptime C: Config) type {

    return struct {
        const Self = @This();

        const WidgetInfos = b: {
            var arr: []const WidgetTypeInfo = &.{};
            for (C.Imports) |import| {
                const Widget = WidgetType(import);
                const vtable = genWidgetVTable(C, Widget);
                const has_post_render = @hasDecl(Widget, "postRender");
                const info = WidgetTypeInfo{
                    .vtable = vtable,
                    .has_post_render = has_post_render,
                };
                arr = arr ++ &[_]WidgetTypeInfo{info};
            }
            break :b arr;
        };

        pub inline fn getWidgetInfo(id: u32) WidgetTypeInfo {
            return WidgetInfos[id];
        }

        pub inline fn getWidgetVTable(id: u32) *const WidgetVTable {
            return WidgetInfos[id].vtable;
        }

        /// The last id is allocated for the Fragment widget.
        const FragmentWidgetId: u32 = @intCast(u32, WidgetInfos.len);

        fn WidgetById(comptime id: WidgetTypeId) type {
            return C.Imports[id];
        }

        fn WidgetType(comptime I: Import) type {
            if (I.tag == .Template) {
                return I.create_type_fn.?(C);
            } else if (I.tag == .ContainerTemplate) {
                return @field(I.container_type.?, I.container_fn_name.?)(C);
            } else {
                if (I.widget_type != null) {
                    return I.widget_type.?;
                } else {
                    return @field(I.container_type.?, I.container_fn_name.?)(C);
                }
            }
        }

        pub fn WidgetIdByType(comptime Widget: type) WidgetTypeId {
            return comptime b: {
                for (C.Imports) |import, idx| {
                    switch (import.tag) {
                        .Type => {
                            if (import.widget_type.? == Widget) {
                                break :b idx;
                            }
                        },
                        .ContainerTemplate => {
                            if (@field(import.container_type.?, import.container_fn_name.?)(C) == Widget) {
                                break :b idx;
                            }
                        },
                        else => unreachable,
                    }
                }
                @compileError("Widget not found in Module: " ++ @typeName(Widget));
            };
        }

        pub fn getWidgetName(id: WidgetTypeId) []const u8 {
            inline for (C.Imports) |import, idx| {
                if (id == idx) {
                    return @typeName(import.widget_type.?);
                }
            }
            unreachable;
        }

        // TODO: Provide widget id map at the root level.

        alloc: std.mem.Allocator,

        /// Arena allocator that gets freed after each update cycle.
        arena_allocator: std.heap.ArenaAllocator,
        arena_alloc: std.mem.Allocator,

        root_node: ?*Node,

        init_ctx: InitContext(C),
        build_ctx: BuildContext(C),
        layout_ctx: LayoutContext(C),
        render_ctx: RenderContext,
        event_ctx: EventContext,
        mod_ctx: ModuleContext(C),

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
                .init_ctx = InitContext(C).init(self),
                .build_ctx = BuildContext(C).init(alloc, self),
                .arena_allocator = std.heap.ArenaAllocator.init(alloc),
                .arena_alloc = undefined,
                .layout_ctx = LayoutContext(C).init(self, g),
                .event_ctx = EventContext.init(C, self),
                .render_ctx = undefined,
                .mod_ctx = ModuleContext(C).init(self),
                .common = undefined,
                .text_measure_batch_buf = std.ArrayList(*graphics.TextMeasure).init(alloc),
            };
            self.arena_alloc = self.arena_allocator.allocator();
            self.common.init(alloc, g);
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
            self.arena_allocator.deinit();
        }

        /// Attaches handlers to the event dispatcher.
        pub fn addInputHandlers(self: *Self, dispatcher: *EventDispatcher) void {
            const S = struct {
                fn onKeyDown(ctx: ?*anyopaque, e: KeyDownEvent) void {
                    const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                    self_.processKeyDownEvent(e);
                }
                fn onKeyUp(ctx: ?*anyopaque, e: KeyUpEvent) void {
                    const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                    self_.processKeyUpEvent(e);
                }
                fn onMouseDown(ctx: ?*anyopaque, e: MouseDownEvent) void {
                    const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                    self_.processMouseDownEvent(e);
                }
                fn onMouseUp(ctx: ?*anyopaque, e: MouseUpEvent) void {
                    const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                    self_.processMouseUpEvent(e);
                }
                fn onMouseScroll(ctx: ?*anyopaque, e: MouseScrollEvent) void {
                    const self_ = stdx.mem.ptrCastAlign(*Self, ctx);
                    self_.processMouseScrollEvent(e);
                }
                fn onMouseMove(ctx: ?*anyopaque, e: MouseMoveEvent) void {
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

        fn getWidget(self: *Self, comptime Widget: type, node: *Node) *Widget {
            _ = self;
            return stdx.mem.ptrCastAlign(*Widget, node.widget);
        }

        pub fn processMouseUpEvent(self: *Self, e: MouseUpEvent) void {
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

        fn processMouseUpEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: MouseUpEvent) bool {
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
                for (node.children.items) |child| {
                    if (self.processMouseUpEventRecurse(child, xf, yf, e)) {
                        break;
                    }
                }
                return true;
            } else return false;
        }

        /// Start at the root node and propagate downwards on the first hit box.
        /// TODO: Handlers should be able to return Stop to prevent propagation.
        pub fn processMouseDownEvent(self: *Self, e: MouseDownEvent) void {
            const xf = @intToFloat(f32, e.x);
            const yf = @intToFloat(f32, e.y);
            self.common.last_focused_widget = self.common.focused_widget;
            self.common.hit_last_focused = false;
            if (self.root_node) |node| {
                _ = self.processMouseDownEventRecurse(node, xf, yf, e);
            }
            // If the existing focused widget wasn't hit and no other widget requested focus, trigger blur.
            if (self.common.last_focused_widget != null and self.common.last_focused_widget == self.common.focused_widget and !self.common.hit_last_focused) {
                self.common.focused_onblur(self.common.focused_widget.?, &self.common.ctx);
                self.common.focused_widget = null;
                self.common.focused_onblur = undefined;
            }
        }

        fn processMouseDownEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: MouseDownEvent) bool {
            const pos = node.abs_pos;
            if (xf >= pos.x and xf <= pos.x + node.layout.width and yf >= pos.y and yf <= pos.y + node.layout.height) {
                if (node == self.common.last_focused_widget) {
                    self.common.hit_last_focused = true;
                }
                var cur = node.mouse_down_list;
                while (cur != NullId) {
                    const sub = self.common.mouse_down_event_subs.getNoCheck(cur);
                    sub.handleEvent(&self.event_ctx, e);
                    cur = self.common.mouse_down_event_subs.getNextNoCheck(cur);
                }
                for (node.children.items) |child| {
                    if (self.processMouseDownEventRecurse(child, xf, yf, e)) {
                        break;
                    }
                }
                return true;
            } else return false;
        }

        pub fn processMouseScrollEvent(self: *Self, e: MouseScrollEvent) void {
            const xf = @intToFloat(f32, e.x);
            const yf = @intToFloat(f32, e.y);
            if (self.root_node) |node| {
                _ = self.processMouseScrollEventRecurse(node, xf, yf, e);
            }
        }

        fn processMouseScrollEventRecurse(self: *Self, node: *Node, xf: f32, yf: f32, e: MouseScrollEvent) bool {
            const pos = node.abs_pos;
            if (xf >= pos.x and xf <= pos.x + node.layout.width and yf >= pos.y and yf <= pos.y + node.layout.height) {
                var cur = node.mouse_scroll_list;
                while (cur != NullId) {
                    const sub = self.common.mouse_scroll_event_subs.getNoCheck(cur);
                    sub.handleEvent(&self.event_ctx, e);
                    cur = self.common.mouse_scroll_event_subs.getNextNoCheck(cur);
                }
                for (node.children.items) |child| {
                    if (self.processMouseScrollEventRecurse(child, xf, yf, e)) {
                        break;
                    }
                }
                return true;
            } else return false;
        }

        pub fn processMouseMoveEvent(self: *Self, e: MouseMoveEvent) void {
            for (self.common.mouse_move_event_subs.items) |*it| {
                it.handleEvent(&self.event_ctx, e);
            }
        }

        pub fn processKeyDownEvent(self: *Self, e: KeyDownEvent) void {
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

        pub fn processKeyUpEvent(self: *Self, e: KeyUpEvent) void {
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

        // 1. Run timers/intervals/animations.
        // 2. Build frames. Diff tree and create/update nodes from frames.
        // 3. Compute layout.
        // 4. Run next post layout cbs.
        pub fn preUpdate(self: *Self, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *C.Build()) FrameId, layout_size: LayoutSize) void {
            self.common.updateIntervals(delta_ms);

            // TODO: check if we have to update

            // Reset the builder buffer before we call any Component.build
            self.build_ctx.resetBuffer();
            self.arena_allocator.deinit();
            self.arena_allocator.state = .{};

            // TODO: Provide a different context for the bootstrap function since it doesn't have a frame or node. Currently uses the BuildContext.
            self.build_ctx.prepareCall(undefined, undefined);
            const root_id = bootstrap_fn(bootstrap_ctx, &self.build_ctx);
            const root = self.build_ctx.getFrame(root_id);

            // Since the aim is to do layout in linear time, the tree should be built first.
            // Traverse to see which nodes need to be created/deleted.
            if (self.root_node) |root_node| {
                if (root_node.type_id == root.type_id) {
                        self.updateExistingNode(null, root_id, root_node);
                } else {
                    self.removeNode(root_node);
                    self.root_node = self.createAndUpdateNode(null, root_id, 0);
                }
            } else {
                self.root_node = self.createAndUpdateNode(null, root_id, 0);
            }

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
            const size = self.layout_ctx.computeLayout(self.root_node.?, layout_size);
            self.layout_ctx.setLayout(self.root_node.?, Layout.init(0, 0, size.width, size.height));

            // Run logic that needs to happen after layout.
            for (self.common.next_post_layout_cbs.items) |*it| {
                it.call({});
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
        pub fn updateAndRender(self: *Self, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *C.Build()) FrameId, width: f32, height: f32) void {
            const layout_size = LayoutSize.init(width, height);
            self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
            self.render();
            self.postUpdate();
        }

        pub fn render(self: *Self) void {
            ui_render.render(C, self);
        }

        /// Assumes the widget and the frame represent the same instance,
        /// so the widget is updated with the frame's props.
        /// Recursively update children.
        /// This assumes the frame's key is equal to the node's key.
        fn updateExistingNode(self: *Self, parent: ?*Node, frame_id: FrameId, node: *Node) void {
            _ = parent;
            // Update frame and props.
            const frame = self.build_ctx.getFrame(frame_id);

            // if (parent) |pn| {
            //     node.transform = pn.transform;
            // }
            const widget_vtable = getWidgetVTable(frame.type_id);
            if (frame.props.len > 0) {
                const props_ptr = self.build_ctx.frame_props.getBytesPtr(frame.props);
                widget_vtable.updateProps(node.widget, props_ptr);
            }
            const child_frame_id = self.buildChildFrame(frame_id, node, widget_vtable);
            if (child_frame_id == NullId) {
                if (node.children.items.len > 0) {
                    for (node.children.items) |it| {
                        self.removeNode(it);
                    }
                }
                return;
            }
            const child_frame = self.build_ctx.getFrame(child_frame_id);
            if (child_frame.type_id == FragmentWidgetId) {
                // Fragment frame, diff it's children instead.

                const child_frames = child_frame.fragment_children;
                // Start by doing fast array iteration to update nodes with the same key/idx.
                // Once there is a discrepancy, switch to the slower method of key map checks.
                var child_idx: u32 = 0;
                while (child_idx < child_frames.len) : (child_idx += 1) {
                    const child_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                    const child_frame_ = self.build_ctx.getFrame(child_id);
                    if (node.children.items.len <= child_idx) {
                        // TODO: Create nodes for the rest of the frames instead.
                        self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                        return;
                    }
                    const child_node = node.children.items[child_idx];
                    if (child_node.type_id != child_frame_.type_id) {
                        self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                        return;
                    }
                    const frame_key = if (child_frame_.key != null) child_frame_.key.? else WidgetKey{.Idx = child_idx};
                    if (!std.meta.eql(child_node.key, frame_key)) {
                        self.updateChildFramesWithKeyMap(node, child_idx, child_frames);
                        return;
                    }
                    self.updateExistingNode(node, child_id, child_node);
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
                    const new_child = self.createAndUpdateNode(node, child_frame_id, 0);
                    node.children.append(new_child) catch unreachable;
                    return;
                }
                const child_node = node.children.items[0];
                if (child_node.type_id != child_frame.type_id) {
                    self.removeNode(child_node);
                    const new_child = self.createAndUpdateNode(node, child_frame_id, 0);
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
                    const new_child = self.createAndUpdateNode(node, child_frame_id, 0);
                    node.children.items[0] = new_child;
                    if (node.children.items.len > 1) {
                        for (node.children.items[1..]) |it| {
                            self.removeNode(it);
                        }
                    }
                    return;
                }
                // Same child.
                self.updateExistingNode(node, child_frame_id, child_node);
            }
        }
    
        /// Slightly slower method to update with frame children that utilizes a key map.
        fn updateChildFramesWithKeyMap(self: *Self, parent: *Node, start_idx: u32, child_frames: FrameListPtr) void {
            var child_idx: u32 = start_idx;
            while (child_idx < child_frames.len): (child_idx += 1) {
                const frame_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                const frame = self.build_ctx.getFrame(frame_id);

                const frame_key = if (frame.key != null) frame.key.? else WidgetKey{.Idx = child_idx};

                // Look for an existing child by key.
                const existing_node_q = parent.key_to_child.get(frame_key); 
                if (existing_node_q != null and existing_node_q.?.type_id == frame.type_id) {
                    self.updateExistingNode(parent, frame_id, existing_node_q.?);

                    // Update the children list as we iterate.
                    if (parent.children.items[child_idx] != existing_node_q.?) {
                        // Move the unused item to the end so we can delete them afterwards.
                        parent.children.append(parent.children.items[child_idx]) catch unreachable;
                    }
                    parent.children.items[child_idx] = existing_node_q.?;
                } else {
                    if (parent.children.items.len == child_idx) {
                        // Exceeded the size of the existing children list. Insert the rest from child frames.
                        const new_child = self.createAndUpdateNode(parent, frame_id, child_idx);
                        parent.children.append(new_child) catch unreachable;
                        child_idx += 1;
                        while (child_idx < child_frames.len) : (child_idx += 1) {
                            const frame_id_ = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                            const new_child_ = self.createAndUpdateNode(parent, frame_id_, child_idx);
                            parent.children.append(new_child_) catch unreachable;
                        }
                        break;
                    }
                    if (parent.children.items.len > child_idx) {
                        // Move the child at the same idx to the end.
                        parent.children.append(parent.children.items[child_idx]) catch unreachable;
                    }

                    // Create a new child instance to correspond with child frame.
                    const new_child = self.createAndUpdateNode(parent, frame_id, child_idx);

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

        // Note: Does not remove from parent.children since it's expensive, relies on the caller to deal with it.
        fn removeNode(self: *Self, node: *Node) void {
            if (node.parent != null) {
                _ = node.parent.?.key_to_child.remove(node.key);
            }
            self.destroyNode(node);
        }

        fn destroyNode(self: *Self, node: *Node) void {
            const widget_vtable = getWidgetVTable(node.type_id);
            widget_vtable.destroy(node, self.alloc);
            node.deinit();
            self.alloc.destroy(node);
        }

        /// Builds the child frame for a given frame.
        fn buildChildFrame(self: *Self, frame_id: FrameId, node: *Node, widget_vtable: *const WidgetVTable) FrameId {
            self.build_ctx.prepareCall(frame_id, node);
            return widget_vtable.build(node.widget, &self.build_ctx);
        }

        fn createAndUpdateNode(self: *Self, parent: ?*Node, frame_id: FrameId, idx: u32) *Node {
            const frame = self.build_ctx.getFrame(frame_id);
            const widget_vtable = getWidgetVTable(frame.type_id);

            const new_node = self.alloc.create(Node) catch unreachable;
            const props_ptr = if (frame.props.len > 0) self.build_ctx.frame_props.getBytesPtr(frame.props) else null;

            // Init instance.
            // log.warn("create node {}", .{frame.type_id});
            const key = if (frame.key != null) frame.key.? else WidgetKey{.Idx = idx};
            new_node.init(self.alloc, frame.type_id, parent, key, undefined);
            new_node.bind = frame.bind;

            if (parent != null) {
                parent.?.key_to_child.put(key, new_node) catch unreachable;
            }

            self.init_ctx.prepareForNode(new_node);
            const new_widget = widget_vtable.create(self.alloc, new_node, &self.init_ctx, props_ptr);
            new_node.widget = new_widget;

            //log.warn("created: {}", .{frame.type_id});

            // Build child frames and create child nodes from them.
            const child_frame_id = self.buildChildFrame(frame_id, new_node, widget_vtable);
            if (child_frame_id != NullId) {
                const child_frame = self.build_ctx.getFrame(child_frame_id);
                if (child_frame.type_id == FragmentWidgetId) {
                    // Fragment frame.
                    const child_frames = child_frame.fragment_children;

                    // Iterate using a counter since the frame list buffer is dynamic.
                    var child_idx: u32 = 0;
                    while (child_idx < child_frames.len) : (child_idx += 1) {
                        const child_id = self.build_ctx.frame_lists.items[child_frames.id + child_idx];
                        const child_node = self.createAndUpdateNode(new_node, child_id, child_idx);
                        new_node.children.append(child_node) catch unreachable;
                    }
                } else {
                    // Single child frame.
                    const child_node = self.createAndUpdateNode(new_node, child_frame_id, 0);
                    new_node.children.append(child_node) catch unreachable;
                }
            }
            // log.debug("after {s}", .{getWidgetName(frame.type_id)});

            self.init_ctx.prepareForNode(new_node);
            widget_vtable.postInit(new_widget, &self.init_ctx);
            return new_node;
        }
    };
}

pub const RenderContext = struct {
    const Self = @This();

    common: *CommonContext,
    g: *Graphics,

    // Current node.
    node: *Node,

    fn init(common: *CommonContext, g: *Graphics) Self {
        return .{
            .g = g,
            .common = common,
            .node = undefined,
        };
    }

    pub fn getAbsLayout(self: *Self) Layout {
        return .{
            .x = self.node.abs_pos.x,
            .y = self.node.abs_pos.y,
            .width = self.node.layout.width,
            .height = self.node.layout.height,
        };
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

        pub inline fn addInterval(self: *Context, dur: Duration, ctx: anytype, cb: IntervalHandler(@TypeOf(ctx))) IntervalId {
            return self.common.addInterval(dur, ctx, cb);
        }

        pub inline fn resetInterval(self: *Context, id: IntervalId) void {
            self.common.resetInterval(id);
        }

        pub inline fn removeInterval(self: *Context, id: IntervalId) void {
            self.common.removeInterval(id);
        }
    };
}

/// Requires Context.common.
pub fn MixinContextFontOps(comptime Context: type) type {
    return struct {

        pub inline fn getPrimaryFontVMetrics(self: Context, font_gid: FontGroupId, font_size: f32) graphics.font.VMetrics {
            return self.common.getPrimaryFontVMetrics(font_gid, font_size);
        }

        pub inline fn measureText(self: *Context, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.TextMetrics {
            return self.common.measureText(font_gid, font_size, str);
        }

        pub inline fn measureTextIter(self: *Context, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.MeasureTextIterator {
            return self.common.measureTextIter(font_gid, font_size, str);
        }

        pub inline fn getFontGroupBySingleFontName(self: Context, name: []const u8) FontGroupId {
            return self.common.getFontGroupBySingleFontName(name);
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

        pub inline fn addKeyUpHandler(self: *Context, ctx: anytype, cb: KeyUpHandler(@TypeOf(ctx))) void {
            self.common.addKeyUpHandler(ctx, cb);
        }

        pub inline fn removeKeyUpHandler(self: *Context, comptime Ctx: type, func: KeyUpHandler(Ctx)) void {
            self.common.removeKeyUpHandler(Ctx, func);
        }

        pub inline fn removeMouseMoveHandler(self: *Context, comptime Ctx: type, func: MouseMoveHandler(Ctx)) void {
            self.common.removeMouseMoveHandler(Ctx, func);
        }
    };
}

pub fn LayoutContext(comptime C: Config) type {
    return struct {
        const Self = @This();

        mod: *Module(C),
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

        fn init(mod: *Module(C), g: *Graphics) Self {
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
            var child_ctx = LayoutContext(C){
                .mod = self.mod,
                .common = &self.mod.common.ctx,
                .g = self.g,
                .cstr = max_size,
                .prefer_exact_width_or_height = false,
                .prefer_exact_width = false,
                .prefer_exact_height = false,
                .node = node,
            };
            return Module(C).getWidgetVTable(node.type_id).layout(node.widget, &child_ctx);
        }

        /// Computes the layout for a node with additional stretch preferences.
        pub fn computeLayoutStretch(self: *Self, node: *Node, cstr: LayoutSize, prefer_exact_width: bool, prefer_exact_height: bool) LayoutSize {
            var child_ctx = C.Layout(){
                .mod = self.mod,
                .common  = &self.mod.common.ctx,
                .g = self.g,
                .cstr = cstr,
                .prefer_exact_width_or_height = prefer_exact_width or prefer_exact_height,
                .prefer_exact_width = prefer_exact_width,
                .prefer_exact_height = prefer_exact_height,
                .node = node,
            };
            return Module(C).getWidgetVTable(node.type_id).layout(node.widget, &child_ctx);
        }

        pub fn computeLayoutInherit(self: *Self, node: *Node) LayoutSize {
            var child_ctx = C.Layout(){
                .mod = self.mod,
                .common  = &self.mod.common.ctx,
                .g = self.g,
                .cstr = self.cstr,
                .prefer_exact_width_or_height = self.prefer_exact_width_or_height,
                .prefer_exact_width = self.prefer_exact_width,
                .prefer_exact_height = self.prefer_exact_height,
                .node = node,
            };
            return Module(C).getWidgetVTable(node.type_id).layout(node.widget, &child_ctx);
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
}

pub const EventContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    common: *CommonContext,
    node: *Node,

    fn init(comptime C: Config, mod: *Module(C)) Self {
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

fn KeyDownHandler(comptime Context: type) type {
    return fn (Context, Event(KeyDownEvent)) void;
}

fn KeyUpHandler(comptime Context: type) type {
    return fn (Context, Event(KeyUpEvent)) void;
}

fn MouseMoveHandler(comptime Context: type) type {
    return fn (Context, Event(MouseMoveEvent)) void;
}

fn MouseDownHandler(comptime Context: type) type {
    return fn (Context, Event(MouseDownEvent)) void;
}

fn MouseUpHandler(comptime Context: type) type {
    return fn (Context, Event(MouseUpEvent)) void;
}

fn MouseScrollHandler(comptime Context: type) type {
    return fn (Context, Event(MouseScrollEvent)) void;
}

/// Does not depend on ModuleConfig so it can be embedded into Widget structs to access common utilities.
pub const CommonContext = struct {
    const Self = @This();

    common: *ModuleCommon,
    alloc: std.mem.Allocator,

    pub inline fn getPrimaryFontVMetrics(self: Self, font_gid: FontGroupId, font_size: f32) graphics.font.VMetrics {
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

    pub inline fn measureTextIter(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8) graphics.MeasureTextIterator {
        return self.common.g.measureFontTextIter(font_gid, font_size, str);
    }

    pub fn getFontGroupBySingleFontName(self: Self, name: []const u8) FontGroupId {
        return self.common.g.getFontGroupBySingleFontName(name);
    }

    pub fn getDefaultFontGroup(self: Self) FontGroupId {
        return self.common.default_font_gid;
    }

    pub fn addInterval(self: *Self, dur: Duration, ctx: anytype, cb: IntervalHandler(@TypeOf(ctx))) IntervalId {
        const closure = Closure(@TypeOf(ctx), IntervalEvent).init(self.alloc, ctx, cb).iface();
        const s = IntervalSession.init(dur, closure);
        return self.common.interval_sessions.add(s) catch unreachable;
    }

    pub fn resetInterval(self: *Self, id: IntervalId) void {
        self.common.interval_sessions.getPtrNoCheck(id).progress_ms = 0;
    }

    pub fn removeInterval(self: *Self, id: IntervalId) void {
        self.common.interval_sessions.getNoCheck(id).deinit(self.alloc);
        self.common.interval_sessions.remove(id);
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
        const closure = Closure(@TypeOf(ctx), Event(MouseUpEvent)).init(self.alloc, ctx, cb).iface();
        const sub = GlobalSubscriber(MouseUpEvent){
            .sub = Subscriber(MouseUpEvent){
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
        const closure = Closure(@TypeOf(ctx), Event(MouseUpEvent)).init(self.alloc, ctx, cb).iface();
        const sub = GlobalSubscriber(MouseUpEvent){
            .sub = Subscriber(MouseUpEvent){
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
        const closure = Closure(@TypeOf(ctx), Event(MouseDownEvent)).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(MouseDownEvent){
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
        const closure = Closure(@TypeOf(ctx), Event(MouseScrollEvent)).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(MouseScrollEvent){
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
        const closure = Closure(@TypeOf(ctx), Event(MouseMoveEvent)).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(MouseMoveEvent){
            .closure = closure,
            .node = node,
        };
        self.common.mouse_move_event_subs.append(sub) catch unreachable;
        self.common.has_mouse_move_subs = true;
    }

    pub fn addKeyUpHandler(self: *Self, ctx: anytype, cb: KeyUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), Event(KeyUpEvent)).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(KeyUpEvent){
            .closure = closure,
        };
        self.common.key_up_event_subs.append(sub) catch unreachable;
    }

    pub fn removeKeyUpHandler(self: *Self, comptime Context: type, func: KeyUpHandler(Context)) void {
        for (self.common.key_up_event_subs.items) |*sub, i| {
            if (sub.closure.iface.getUserFunctionPtr() == @ptrCast(*const anyopaque, func)) {
                sub.deinit();
                _ = self.mod.key_up_event_subs.orderedRemove(i);
                break;
            }
        }
    }

    pub fn addKeyDownHandler(self: *Self, node: *Node, ctx: anytype, cb: KeyDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), Event(KeyDownEvent)).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(KeyDownEvent){
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

/// Contains data and logic that does not depend on ModuleConfig.
pub const ModuleCommon = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    g: *Graphics,
    text_measures: ds.CompactUnorderedList(TextMeasureId, TextMeasure),
    interval_sessions: ds.CompactUnorderedList(u32, IntervalSession),

    // TODO: Use one buffer for all the handlers.
    /// Keyboard handlers.
    key_up_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(KeyUpEvent)),
    key_down_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(KeyDownEvent)),

    /// Mouse handlers.
    mouse_up_event_subs: ds.CompactSinglyLinkedListBuffer(u32, GlobalSubscriber(MouseUpEvent)),
    global_mouse_up_list: std.ArrayList(u32),
    mouse_down_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(MouseDownEvent)),
    mouse_scroll_event_subs: ds.CompactSinglyLinkedListBuffer(u32, Subscriber(MouseScrollEvent)),
    /// Mouse move events fire far more frequently so it's better to just iterate a list and skip hit test.
    /// TODO: Implement a compact tree of nodes for mouse events.
    mouse_move_event_subs: std.ArrayList(Subscriber(MouseMoveEvent)),
    has_mouse_move_subs: bool,

    /// Currently focused widget.
    focused_widget: ?*Node,
    focused_onblur: BlurHandler,
    /// Scratch vars to track the last focused widget.
    last_focused_widget: ?*Node,
    hit_last_focused: bool,

    next_post_layout_cbs: std.ArrayList(ClosureIface(void)),

    // next_post_render_cbs: std.ArrayList(*Node),

    // TODO: design themes.
    default_font_gid: FontGroupId,

    ctx: CommonContext,

    fn init(self: *Self, alloc: std.mem.Allocator, g: *Graphics) void {
        self.* = .{
            .alloc = alloc,
            .g = g,
            .text_measures = ds.CompactUnorderedList(TextMeasureId, TextMeasure).init(alloc),
            // .default_font_gid = g.getFontGroupBySingleFontName("Nunito Sans"),
            .default_font_gid = g.getDefaultFontGroupId(),
            .interval_sessions = ds.CompactUnorderedList(u32, IntervalSession).init(alloc),

            .key_up_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(KeyUpEvent)).init(alloc),
            .key_down_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(KeyDownEvent)).init(alloc),
            .mouse_up_event_subs = ds.CompactSinglyLinkedListBuffer(u32, GlobalSubscriber(MouseUpEvent)).init(alloc),
            .global_mouse_up_list = std.ArrayList(u32).init(alloc),
            .mouse_down_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(MouseDownEvent)).init(alloc),
            .mouse_move_event_subs = std.ArrayList(Subscriber(MouseMoveEvent)).init(alloc),
            .mouse_scroll_event_subs = ds.CompactSinglyLinkedListBuffer(u32, Subscriber(MouseScrollEvent)).init(alloc),
            .has_mouse_move_subs = false,

            .next_post_layout_cbs = std.ArrayList(ClosureIface(void)).init(alloc),
            // .next_post_render_cbs = std.ArrayList(*Node).init(alloc),

            .focused_widget = null,
            .focused_onblur = undefined,
            .last_focused_widget = null,
            .hit_last_focused = false,

            .ctx = .{
                .common = self,
                .alloc = alloc, 
            },
        };
    }

    fn deinit(self: *Self) void {
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

    fn updateIntervals(self: *Self, delta_ms: f32) void {
        var iter = self.interval_sessions.iterator();
        while (iter.nextPtr()) |it| {
            it.progress_ms += delta_ms;
            if (it.progress_ms > @intToFloat(f32, it.dur.toMillis())) {
                it.call(&self.ctx);
                it.progress_ms = 0;
            }
        }
    }

    fn nextPostLayout(self: *Self, ctx: anytype, cb: fn(@TypeOf(ctx)) void) void {
        const closure = Closure(@TypeOf(ctx), void).init(self.alloc, ctx, cb).iface();
        self.next_post_layout_cbs.append(closure) catch unreachable;
    }
};

pub fn ModuleContext(comptime C: Config) type {
    return struct {
        const Self = @This();

        mod: *Module(C),

        fn init(mod: *Module(C)) Self {
            return .{
                .mod = mod,
            };
        }
    };
}

pub fn InitContext(comptime C: Config) type {
    return struct {
        const Self = @This();

        mod: *Module(C),
        alloc: std.mem.Allocator,
        common: *CommonContext,
        node: *Node,

        fn init(mod: *Module(C)) Self {
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

        pub fn getModuleContext(self: *Self) *ModuleContext(C) {
            return &self.mod.mod_ctx;
        }

        // TODO: findChildrenByTag
        // TODO: findChildByKey
        pub fn findChildWidgetByType(self: *Self, comptime Widget: type) ?WidgetRef(Widget) {
            const ct_typeid = Module(C).WidgetIdByType(Widget);
            const walker = stdx.algo.recursive.ChildArrayListSearchWalker(*Node);
            const S = struct {
                fn pred(type_id: WidgetTypeId, node: *Node) bool {
                    return node.type_id == type_id;
                }
            };
            const res = stdx.algo.recursive.searchPreMany(WidgetTypeId, ct_typeid, *Node, self.node.children.items, walker, S.pred);
            if (res != null) {
                const state = self.mod.getWidget(Widget, res.?);
                return WidgetRef(Widget).init(state, res.?);
            } else {
                return null;
            }
        }

        pub usingnamespace MixinContextInputOps(Self);
        pub usingnamespace MixinContextEventOps(Self);
        pub usingnamespace MixinContextNodeOps(Self);
        pub usingnamespace MixinContextFontOps(Self);
    };
}

/// Contains an extra global flag.
fn GlobalSubscriber(comptime T: type) type {
    return struct {
        sub: Subscriber(T),
        is_global: bool,
    };
}

fn Subscriber(comptime T: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(Event(T)),
        node: *Node,

        fn handleEvent(self: Self, ctx: *EventContext, e: T) void {
            ctx.node = self.node;
            self.closure.call(.{ .ctx = ctx, .val = e });
        }

        fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.closure.deinit(alloc);
        }
    };
}

pub fn BuildContext(comptime C: Config) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        mod: *Module(C),

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

        fn init(alloc: std.mem.Allocator, mod: *Module(C)) Self {
            return .{
                .alloc = alloc,
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
        pub fn closure(self: *Self, comptime Context: type, ctx: Context, comptime Param: type, user_fn: fn (Context, Param) void) Function(Param) {
            const c = Closure(Context, Param).init(self.mod.arena_alloc, ctx, user_fn).iface();
            return Function(Param).initClosureIface(c);
        }

        /// Returns a wrapper over a free function.
        pub fn func(self: *Self, comptime Param: type, comptime user_fn: fn (Param) void) Function(Param) {
            _ = self;
            return Function(Param).init(user_fn);
        }

        /// Returns a wrapper over a free function with a context pointer. This doesn't need any allocations.
        pub fn funcExt(self: *Self, ctx_ptr: anytype, comptime Param: type, comptime user_fn: fn (@TypeOf(ctx_ptr), Param) void) Function(Param) {
            _ = self;
            return Function(Param).initContext(ctx_ptr, user_fn);
        }

        pub fn range(self: *Self, count: usize, ctx: anytype, build_fn: fn (@TypeOf(ctx), *C.Build(), u32) FrameId) FrameListPtr {
            const start_idx = self.frame_lists.items.len;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                const frame_id = build_fn(ctx, self, @intCast(u32, i));
                if (frame_id != NullFrameId) {
                    self.frame_lists.append(frame_id) catch unreachable;
                }
            }
            return FrameListPtr.init(@intCast(u32, start_idx), @intCast(u32, self.frame_lists.items.len-start_idx));
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
            const frame = Frame.init(Module(C).FragmentWidgetId, null, null, FramePropsPtr.init(0, 0), list_);
            const frame_id = @intCast(FrameId, @intCast(u32, self.frames.items.len));
            self.frames.append(frame) catch unreachable;
            return frame_id;
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
            if (IsSlice or IsArray) {
                for (frame_ids) |it| {
                    self.frame_lists.append(it) catch unreachable;
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

            const type_id = comptime Module(C).WidgetIdByType(Widget);
            const id = if (@hasField(BuildProps, "id")) stdx.meta.enumLiteralId(build_props.id) else null;
            if (@hasField(BuildProps, "bind")) {
                if (stdx.meta.FieldType(BuildProps, .bind) != *WidgetRef(Widget)) {
                    @compileError("Expected bind type to be: " ++ @typeName(*WidgetRef(Widget)));
                }
            }
            const bind: ?*anyopaque = if (@hasField(BuildProps, "bind")) build_props.bind else null;

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
            const frame = Frame.init(type_id, id, bind, props_ptr, FrameListPtr.init(0, 0));
            const frame_id = @intCast(FrameId, @intCast(u32, self.frames.items.len));
            self.frames.append(frame) catch unreachable;

            // log.warn("created frame {}", .{frame_id});
            return frame_id;
        }
    };
}

test "Module.update creates or updates existing node" {
    var g: graphics.Graphics = undefined;
    g.init(t.alloc);
    defer g.deinit();

    const Foo = struct {
        fn render(self: *@This(), c: *RenderContext) void {
            _ = self;
            _ = c;
        }
    };

    const Bar = struct {
        fn render(self: *@This(), c: *RenderContext) void {
            _ = self;
            _ = c;
        }
    };

    const Root = struct {
        flag: bool,

        pub fn init(self: *@This(), comptime C: Config, _: *C.Init()) void {
            self.* = .{
                .flag = true,
            };
        }

        fn build(self: *@This(), comptime C: Config, c: *C.Build()) FrameId {
            if (self.flag) {
                return c.decl(Foo, .{});
            } else {
                return c.decl(Bar, .{});
            }
        }
        fn render(self: *@This(), c: *RenderContext) void {
            _ = self;
            _ = c;
        }
    };

    {
        // Different root frame type creates new node.
        const TestConfig = comptime Config{
            .Imports = &.{
                Import.init(Foo),
                Import.init(Bar),
            },
        };
        const S2 = struct {
            fn bootstrap(flag: bool, c: *BuildContext(TestConfig)) FrameId {
                if (flag) {
                    return c.decl(Foo, .{});
                } else {
                    return c.decl(Bar, .{});
                }
            }
        };
        var mod: Module(TestConfig) = undefined;
        Module(TestConfig).init(&mod, t.alloc, &g);
        defer mod.deinit();
        const layout_size = LayoutSize.init(800, 600);
        mod.preUpdate(0, true, S2.bootstrap, layout_size);
        try t.eq(mod.root_node.?.type_id, Module(TestConfig).WidgetIdByType(Foo));
        mod.preUpdate(0, false, S2.bootstrap, layout_size);
        try t.eq(mod.root_node.?.type_id, Module(TestConfig).WidgetIdByType(Bar));
    }

    {
        // Different child frame type creates new node.
        const TestConfig = comptime Config{
            .Imports = &.{
                Import.init(Foo),
                Import.init(Bar),
                Import.init(Root),
            },
        };
        const S2 = struct {
            fn bootstrap(_: void, c: *BuildContext(TestConfig)) FrameId {
                return c.decl(Root, .{});
            }
        };
        var mod: Module(TestConfig) = undefined;
        Module(TestConfig).init(&mod, t.alloc, &g);
        defer mod.deinit();
        const layout_size = LayoutSize.init(800, 600);
        mod.preUpdate(0, {}, S2.bootstrap, layout_size);
        try t.eq(mod.root_node.?.numChildren(), 1);
        try t.eq(mod.root_node.?.getChild(0).type_id, Module(TestConfig).WidgetIdByType(Foo));
        const root = mod.getWidget(Root, mod.root_node.?);
        root.flag = false;
        mod.preUpdate(0, {}, S2.bootstrap, layout_size);
        log.warn("{} {}", .{Module(TestConfig).WidgetIdByType(Foo), Module(TestConfig).WidgetIdByType(Bar)});
        try t.eq(mod.root_node.?.numChildren(), 1);
        try t.eq(mod.root_node.?.getChild(0).type_id, Module(TestConfig).WidgetIdByType(Bar));
    }
}

// test "BuildContext.new disallows using a prop that's not declared in Component.Props" {
//     const Foo = struct {
//         const Props = struct {
//             bar: usize,
//         };
//     };
//     const TestConfig = ModuleConfig{
//         .Components = WidgetImport.initMany(.{Foo}),
//     };

//     var mod: Module(TestConfig) = undefined;
//     Module(TestConfig).init(&mod, t.alloc, &g, LayoutSize.init(800, 600), undefined);
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

    pub fn init(x: f32, y: f32, width: f32, height: f32) @This() {
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn initWithSize(x: f32, y: f32, size: LayoutSize) @This() {
        return .{
            .x = x,
            .y = y,
            .width = size.width,
            .height = size.height,
        };
    }
};

const IntervalSession = struct {
    const Self = @This();
    dur: Duration,
    progress_ms: f32,
    closure: ClosureIface(IntervalEvent),

    fn init(dur: Duration, closure: ClosureIface(IntervalEvent)) Self {
        return .{
            .dur = dur,
            .progress_ms = 0,
            .closure = closure,
        };
    }

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        self.closure.deinit(alloc);
    }

    fn call(self: *Self, ctx: *CommonContext) void {
        self.closure.call(IntervalEvent{
            .progress_ms = self.progress_ms,
            .ctx = ctx,
        });
    }
};

pub const IntervalEvent = struct {
    progress_ms: f32,
    ctx: *CommonContext,
};

fn WidgetHasProps(comptime Widget: type) bool {
    if (!@hasField(Widget, "props")) {
        return false;
    }
    const PropsField = std.meta.fieldInfo(Widget, .props);
    return @typeInfo(PropsField.field_type) == .Struct;
}

fn WidgetProps(comptime Widget: type) type {
    if (WidgetHasProps(Widget)) {
        return std.meta.fieldInfo(Widget, .props).field_type;
    } else {
        @compileError(@typeName(Widget) ++ " doesn't have props field.");
    }
}