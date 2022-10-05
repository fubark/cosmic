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
const u = ui.widgets;
const events = @import("events.zig");
const Frame = ui.Frame;
const BindNode = @import("frame.zig").BindNode;
const ui_render = @import("render.zig");
const LayoutSize = ui.LayoutSize;
const NullId = stdx.ds.CompactNull(u32);
const TextMeasure = ui.TextMeasure;
pub const TextMeasureId = usize;
pub const IntervalId = u32;
const log = stdx.log.scoped(.module);

const build_ = @import("ui_build.zig");
const BuildContext = build_.BuildContext;

/// Using a global BuildContext makes widget declarations more idiomatic.
pub var gbuild_ctx: *BuildContext = undefined;

pub fn getWidgetIdByType(comptime Widget: type) ui.WidgetTypeId {
    return @ptrToInt(GenWidgetVTable(Widget));
}

fn updateWidgetUserStyle(comptime Widget: type, mod: *Module, node: *ui.Node, frame: ui.Frame) ?*const WidgetUserStyle(Widget) {
    const UserStyle = WidgetUserStyle(Widget);
    if (frame.style) |style| {
        if (frame.style_is_owned) {
            const user_style = stdx.mem.ptrCastAlign(*const UserStyle, style);
            // Persist user style.
            if (!node.hasState(ui.NodeStateMasks.user_style)) {
                const new = mod.alloc.create(UserStyle) catch fatal();
                new.* = user_style.*;
                mod.common.node_user_styles.put(mod.alloc, node, .{
                    .ptr = .{
                        .owned = new,
                    },
                    .owned = true,
                }) catch fatal();
                node.setStateMask(ui.NodeStateMasks.user_style);
                return new;
            } else {
                const handle = mod.common.node_user_styles.getPtr(node).?;
                var existing: *UserStyle = undefined;
                if (!handle.owned) {
                    existing = mod.alloc.create(UserStyle) catch fatal();
                    handle.ptr = .{
                        .owned = existing,
                    };
                    handle.owned = true;
                } else {
                    existing = stdx.mem.ptrCastAlign(*UserStyle, handle.ptr.owned);
                }
                existing.* = user_style.*;
                return existing;
            }
        } else {
            const user_style = stdx.mem.ptrCastAlign(*const UserStyle, style);
            if (!node.hasState(ui.NodeStateMasks.user_style)) {
                mod.common.node_user_styles.put(mod.alloc, node, .{
                    .ptr = .{
                        .not_owned = style,
                    },
                    .owned = false,
                }) catch fatal();
                node.setStateMask(ui.NodeStateMasks.user_style);
            } else {
                const handle = mod.common.node_user_styles.getPtr(node).?;
                if (handle.owned) {
                    const existing = stdx.mem.ptrCastAlign(*UserStyle, handle.ptr.owned);
                    mod.alloc.destroy(existing);
                    handle.owned = false;
                }
                handle.ptr.not_owned = user_style;
            }
            return user_style;
        }
    } else {
        if (node.hasState(ui.NodeStateMasks.user_style)) {
            const handle = mod.common.node_user_styles.get(node).?;
            if (handle.owned) {
                const existing = stdx.mem.ptrCastAlign(*UserStyle, handle.ptr.owned);
                mod.alloc.destroy(existing);
            }
            _ = mod.common.node_user_styles.remove(node);
            node.clearStateMask(ui.NodeStateMasks.user_style);
        }
        return null;
    }
}

fn updateWidgetStyle(comptime Widget: type, mod: *Module, node: *ui.Node, frame: ui.Frame) void {
    const Style = WidgetComputedStyle(Widget);
    const StyleMods = WidgetStyleMods(Widget);
    if (StyleMods != void) {
        const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
        if (widget.mods.value > 0) {
            var computed = mod.common.getCurrentStyleDefault(Widget).*;
            if (updateWidgetUserStyle(Widget, mod, node, frame)) |user_style| {
                inline for (comptime std.meta.fieldNames(Style)) |name| {
                    if (@field(user_style, name)) |value| {
                        @field(computed, name) = value;
                    }
                }
            }
            mod.common.getCurrentStyleUpdateFuncDefault(Widget)(&computed, widget.mods);

            if (!node.hasState(ui.NodeStateMasks.computed_style)) {
                const new = mod.alloc.create(Style) catch fatal();
                new.* = computed;
                mod.common.node_computed_styles.put(mod.alloc, node, new) catch fatal();
                node.setStateMask(ui.NodeStateMasks.computed_style);
            } else {
                const existing = stdx.mem.ptrCastAlign(*Style, mod.common.node_computed_styles.get(node).?);
                existing.* = computed;
            }
            return;
        }
    }

    // Has user style.
    if (updateWidgetUserStyle(Widget, mod, node, frame)) |user_style| {
        var computed = mod.common.getCurrentStyleDefault(Widget).*;

        inline for (comptime std.meta.fieldNames(Style)) |name| {
            if (@field(user_style, name)) |value| {
                @field(computed, name) = value;
            }
        }

        if (!node.hasState(ui.NodeStateMasks.computed_style)) {
            const new = mod.alloc.create(Style) catch fatal();
            new.* = computed;
            mod.common.node_computed_styles.put(mod.alloc, node, new) catch fatal();
            node.setStateMask(ui.NodeStateMasks.computed_style);
        } else {
            const existing = stdx.mem.ptrCastAlign(*Style, mod.common.node_computed_styles.get(node).?);
            existing.* = computed;
        }
    } else {
        // Remove computed.
        if (node.hasState(ui.NodeStateMasks.computed_style)) {
            const existing = stdx.mem.ptrCastAlign(*Style, mod.common.node_computed_styles.get(node).?);
            mod.alloc.destroy(existing);
            _ = mod.common.node_computed_styles.remove(node);
            node.clearStateMask(ui.NodeStateMasks.computed_style);
        }
    }
}

/// Generates the vtable for a Widget.
pub fn GenWidgetVTable(comptime Widget: type) *const ui.WidgetVTable {
    const gen = struct {

        fn create(mod: *Module, node: *ui.Node, frame: ui.Frame) *anyopaque {
            const ctx = &mod.init_ctx;

            const new: *Widget = if (@sizeOf(Widget) > 0) b: {
                const res = mod.alloc.create(Widget) catch unreachable;
                node.widget = res;
                break :b res;
            } else undefined;

            if (@sizeOf(Widget) > 0) {
                if (comptime WidgetHasProps(Widget)) {
                    if (frame.props) |ptr| {
                        const Props = WidgetProps(Widget);
                        const props = stdx.mem.ptrCastAlign(*const Props, ptr);
                        new.props = props.*;

                        if (@hasField(Widget, "props")) {
                            // "child" or "children" are duped into widget props.
                            if (@hasField(stdx.meta.FieldType(Widget, .props), "child")) {
                                if (props.child.isPresent()) {
                                    mod.build_ctx.frames.incRef(props.child.id);
                                }
                            }
                            if (@hasField(stdx.meta.FieldType(Widget, .props), "children")) {
                                if (props.children.isPresent()) {
                                    mod.build_ctx.frame_lists.incRef(props.children.id);
                                }
                            }
                        }
                    }
                }
            }

            // Styles are computed just before Widget.init so they can be accessed.
            // eg. TextStyle.fontSize needs to be cached in Text widget to skip recomputing the layout.
            // This also means that any modifiers need to be inited on Widget struct init with default values.
            const Style = WidgetComputedStyle(Widget);
            if (Style != void) {
                updateWidgetStyle(Widget, mod, node, frame);
            }

            if (@hasDecl(Widget, "init")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *InitContext) void, @TypeOf(Widget.init))) {
                    @compileError("Invalid init function: " ++ @typeName(@TypeOf(Widget.init)) ++ " Widget: " ++ @typeName(Widget));
                }
                // Call widget's init to set state.
                new.init(ctx);
            }

            return node.widget;
        }

        fn postInit(widget_ptr: *anyopaque, ctx: *InitContext) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);
            if (@hasDecl(Widget, "postInit")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *InitContext) void, @TypeOf(Widget.postInit))) {
                    @compileError("Invalid postInit function: " ++ @typeName(@TypeOf(Widget.postInit)) ++ " Widget: " ++ @typeName(Widget));
                }
                widget.postInit(ctx);
            }
        }

        fn updateProps(mod: *Module, node: *ui.Node, frame: ui.Frame, ctx: *UpdateContext) void {
            const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
            if (comptime WidgetHasProps(Widget)) {
                if (frame.props) |ptr| {
                    const Props = WidgetProps(Widget);
                    const props = stdx.mem.ptrCastAlign(*const Props, ptr);

                    if (@hasField(Widget, "props")) {
                        if (@hasField(stdx.meta.FieldType(Widget, .props), "child")) {
                            if (widget.props.child.id != props.child.id) {
                                if (widget.props.child.isPresent()) {
                                    widget.props.child.destroy();
                                }
                                if (props.child.isPresent()) {
                                    mod.build_ctx.frames.incRef(props.child.id);
                                }
                            }
                        }
                        if (@hasField(stdx.meta.FieldType(Widget, .props), "children")) {
                            if (widget.props.children.id != props.children.id) {
                                if (widget.props.children.isPresent()) {
                                    widget.props.children.destroy();
                                }
                                if (props.children.isPresent()) {
                                    mod.build_ctx.frame_lists.incRef(props.children.id);
                                }
                            }
                        }
                    }

                    if (@hasDecl(Widget, "prePropsUpdate")) {
                        if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *UpdateContext, *const Props) void, @TypeOf(Widget.prePropsUpdate))) {
                            @compileError("Invalid prePropsUpdate function: " ++ @typeName(@TypeOf(Widget.prePropsUpdate)) ++ " Widget: " ++ @typeName(Widget));
                        }
                        widget.prePropsUpdate(ctx, props);
                    }

                    widget.props = props.*;
                }
            }

            const Style = WidgetComputedStyle(Widget);
            if (Style != void) {
                updateWidgetStyle(Widget, mod, node, frame);
            }

            if (@hasDecl(Widget, "postPropsUpdate")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *UpdateContext) void, @TypeOf(Widget.postPropsUpdate))) {
                    @compileError("Invalid postPropsUpdate function: " ++ @typeName(@TypeOf(Widget.postPropsUpdate)) ++ " Widget: " ++ @typeName(Widget));
                }
                widget.postPropsUpdate(ctx);
            }
        }

        fn postUpdate(node: *ui.Node, ctx: *UpdateContext) void {
            if (@hasDecl(Widget, "postUpdate")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *UpdateContext) void, @TypeOf(Widget.postUpdate))) {
                    @compileError("Invalid postUpdate function: " ++ @typeName(@TypeOf(Widget.postUpdate)) ++ " Widget: " ++ @typeName(Widget));
                }
                const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                widget.postUpdate(ctx);
            }
        }

        fn build(widget_ptr: *anyopaque, ctx: *BuildContext) ui.FramePtr {
            const widget = stdx.mem.ptrCastAlign(*Widget, widget_ptr);

            if (!@hasDecl(Widget, "build")) {
                // No build function. Return null child.
                return .{};
            } else {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *BuildContext) ui.FramePtr, @TypeOf(Widget.build))) {
                    @compileError("Invalid build function: " ++ @typeName(@TypeOf(Widget.build)) ++ " Widget: " ++ @typeName(Widget));
                }
            }
            return widget.build(ctx);
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
                const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                widget.renderCustom(ctx);
            } else {
                if (@hasDecl(Widget, "render")) {
                    if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *RenderContext) void, @TypeOf(Widget.render))) {
                        @compileError("Invalid render function: " ++ @typeName(@TypeOf(Widget.render)) ++ " Widget: " ++ @typeName(Widget));
                    }
                    const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                    widget.render(ctx);
                }
                if (@hasDecl(Widget, "postRender")) {
                    if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *RenderContext) void, @TypeOf(Widget.postRender))) {
                        @compileError("Invalid postRender function: " ++ @typeName(@TypeOf(Widget.render)) ++ " Widget: " ++ @typeName(Widget));
                    }
                    const temp = ctx.node;
                    ui_render.defaultRenderChildren(node, ctx);
                    const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
                    ctx.node = temp;
                    widget.postRender(ctx);
                } else {
                    ui_render.defaultRenderChildren(node, ctx);
                }
            }
        }

        fn layout(widget_ptr: *anyopaque, ctx: *LayoutContext) LayoutSize {
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
                return widget.layout(ctx);
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

        fn destroy(mod: *Module, node: *ui.Node) void {
            if (node.bind) |bind| {
                // Unbind.
                if (node.hasState(ui.NodeStateMasks.bind_func)) {
                    const bind_func = stdx.mem.ptrCastAlign(*ui.BindNodeFunc, bind);
                    bind_func.func(bind_func.ctx, node, false);
                } else {
                    const ref = stdx.mem.ptrCastAlign(*ui.WidgetRef(Widget), bind);
                    ref.binded = false;
                }
            }
            const widget = stdx.mem.ptrCastAlign(*Widget, node.widget);
            if (@hasDecl(Widget, "deinit")) {
                if (comptime !stdx.meta.hasFunctionSignature(fn (*Widget, *DeinitContext) void, @TypeOf(Widget.deinit))) {
                    @compileError("Invalid deinit function: " ++ @typeName(@TypeOf(Widget.deinit)) ++ " Widget: " ++ @typeName(Widget));
                }
                widget.deinit(&mod.deinit_ctx);
            }

            // "child" and "children" are automatically freed.
            if (@hasField(Widget, "props")) {
                if (@hasField(stdx.meta.FieldType(Widget, .props), "child")) {
                    if (widget.props.child.isPresent()) {
                        widget.props.child.destroy();
                    }
                }
                if (@hasField(stdx.meta.FieldType(Widget, .props), "children")) {
                    if (widget.props.children.isPresent()) {
                        widget.props.children.destroy();
                    }
                }
            }

            const Style = WidgetComputedStyle(Widget);
            if (Style != void) {
                const UserStyle = WidgetUserStyle(Widget);
                if (node.hasState(ui.NodeStateMasks.user_style)) {
                    const handle = mod.common.node_user_styles.get(node).?;
                    if (handle.owned) {
                        const style = stdx.mem.ptrCastAlign(*UserStyle, handle.ptr.owned);
                        mod.alloc.destroy(style);
                    }
                    _ = mod.common.node_user_styles.remove(node);
                }
                if (node.hasState(ui.NodeStateMasks.computed_style)) {
                    const style = stdx.mem.ptrCastAlign(*Style, mod.common.node_computed_styles.get(node).?);
                    mod.alloc.destroy(style);
                    _ = mod.common.node_computed_styles.remove(node);
                }
            }
            mod.alloc.destroy(widget);
        }

        fn deinitFrame(mod: *Module, frame: ui.Frame) void {
            if (@hasDecl(Widget, "deinitFrame")) {
                Widget.deinitFrame(frame, &mod.deinit_ctx);
            }

            const UserStyle = WidgetUserStyle(Widget);
            if (UserStyle != void) {
                if (frame.style) |ptr| {
                    if (frame.style_is_owned) {
                        const style = stdx.mem.ptrCastAlign(*const UserStyle, ptr);
                        mod.build_ctx.dynamic_alloc.destroy(style);
                    }
                }
            }

            const Props = WidgetProps(Widget);
            if (Props != void) {
                if (frame.props) |ptr| {
                    const props = stdx.mem.ptrCastAlign(*Props, ptr);
                    if (@hasField(Widget, "props")) {
                        if (@hasField(stdx.meta.FieldType(Widget, .props), "child")) {
                            if (props.child.isPresent()) {
                                props.child.destroy();
                            }
                        }
                        if (@hasField(stdx.meta.FieldType(Widget, .props), "children")) {
                            if (props.children.isPresent()) {
                                props.children.destroy();
                            }
                        }
                    }
                    mod.build_ctx.dynamic_alloc.destroy(props);
                }
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
            .deinitFrame = deinitFrame,
            .has_post_update = @hasDecl(Widget, "postUpdate"),
            .children_can_overlap = @hasDecl(Widget, "ChildrenCanOverlap") and Widget.ChildrenCanOverlap,
            .name = @typeName(Widget),
        };
    };

    return &gen.vtable;
}

const Fragment = struct {};
pub const FragmentVTable = GenWidgetVTable(Fragment);

const EventType = enum(u3) {
    mouseup,
    mousedown,
    enter_mousedown,
    global_mouseup,
    global_mousemove,
    hoverchange,
    keyup,
    keydown,
};

const EventHandlerRef = struct {
    event_t: EventType,
    node: *ui.Node,
};

pub const Module = struct {
    // TODO: Provide widget id map at the root level.

    alloc: std.mem.Allocator,

    root_node: ?*ui.Node,
    user_root: ui.NodeRef,

    init_ctx: InitContext,
    deinit_ctx: DeinitContext,
    build_ctx: BuildContext,
    update_ctx: UpdateContext,
    layout_ctx: LayoutContext,
    render_ctx: RenderContext,
    event_ctx: ui.EventContext,
    mod_ctx: ModuleContext,

    common: ModuleCommon,

    text_measure_batch_buf: std.ArrayList(*graphics.TextMeasure),

    debug_dump_after_num_updates: if (builtin.mode == .Debug) ?u32 else void,
    trace: if (builtin.mode == .Debug) std.ArrayListUnmanaged(Trace) else void,

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
            .deinit_ctx = DeinitContext.init(self),
            .build_ctx = undefined,
            .layout_ctx = LayoutContext.init(self, g),
            .event_ctx = ui.EventContext.init(self),
            .render_ctx = undefined,
            .update_ctx = undefined,
            .mod_ctx = ModuleContext.init(self),
            .common = undefined,
            .text_measure_batch_buf = std.ArrayList(*graphics.TextMeasure).init(alloc),
            .debug_dump_after_num_updates = undefined,
            .trace = undefined,
        };
        self.common.init(alloc, self, g);
        self.build_ctx.init(alloc, self.common.arena_alloc, self);
        self.render_ctx = RenderContext.init(&self.common.ctx, g);
        self.update_ctx = .{
            .common = &self.common.ctx,
            .node = undefined,
        };
        if (builtin.mode == .Debug) {
            self.debug_dump_after_num_updates = null;
            self.trace = .{};
        }
    }

    pub fn deinit(self: *Module) void {
        self.text_measure_batch_buf.deinit();

        // Destroy widget nodes.
        if (self.root_node != null) {
            // Remove from prev update.
            self.common.removeHandlers();
            self.common.removeNodes();

            const S = struct {
                fn visit(mod: *Module, node: *ui.Node) void {
                    mod.destroyNode(node);
                }
            };
            const walker = stdx.algo.recursive.ChildArrayListWalker(*ui.Node);
            stdx.algo.recursive.walkPost(*Module, self, *ui.Node, self.root_node.?, walker, S.visit);
        }

        self.common.deinit();

        // Deinit frames after nodes have been removed to report any remaining ref counted frames.
        self.build_ctx.deinit();

        if (builtin.mode == .Debug) {
            self.trace.deinit(self.alloc);
        }
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

    /// The way to receive paste events from the browser.
    pub fn processPasteEvent(self: *Module, str: []const u8) void {
        if (self.common.focused_widget) |node| {
            if (self.common.focused_onpaste) |on_paste| {
                on_paste(node, &self.common.ctx, str);
            }
        }
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
            if (self.common.focused_onblur) |on_blur| {
                on_blur(self.common.focused_widget.?, &self.common.ctx);
            }
            self.common.focused_widget = null;
            self.common.focused_onblur = null;
            self.common.focused_onpaste = null;
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
    /// Once the bottom is reached, `mousedown` events are triggered in order back towards the root.
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
            if (self.common.focused_onblur) |on_blur| {
                on_blur(self.common.focused_widget.?, &self.common.ctx);
            }
            self.common.focused_widget = null;
            self.common.focused_onblur = null;
            self.common.focused_onpaste = null;
        }
        if (hit_widget) {
            return .Stop;
        } else {
            return .Continue;
        }
    }

    /// hit_widget only considers hits on the way back up the tree.
    /// Returns true to stop propagation.
    fn processMouseDownEventRecurse(self: *Module, node: *ui.Node, xf: f32, yf: f32, e: platform.MouseDownEvent, hit_widget: *bool) bool {
        // log.debug("mousedown enter {s}", .{node.vtable.name});

        // As long as the focused widget was hit from top-down, mark it as hit or the event could end at a child widget.
        // If a child widget requested focus it would still take away focus from the current focused widget.
        if (node == self.common.last_focused_widget) {
            self.common.hit_last_focused = true;
            hit_widget.* = true;
        }

        // Initial mousedown. From top to bottom.
        if (node.hasHandler(ui.EventHandlerMasks.enter_mousedown)) {
            const sub = self.common.node_enter_mousedown_map.get(node).?;
            if (sub.handleEvent(&self.event_ctx, e) == .stop) {
                return true;
            }
        }

        const event_children = if (!node.has_child_event_ordering) node.children.items else node.child_event_ordering;
        if (!node.vtable.children_can_overlap) {
            // Greedy hit check. Skips siblings.
            for (event_children) |child| {
                if (child.abs_bounds.containsPt(xf, yf)) {
                    if (self.processMouseDownEventRecurse(child, xf, yf, e, hit_widget)) {
                        return true;
                    }
                    break;
                }
            }
        } else {
            // Continues to hit check siblings until `stop` is received.
            for (event_children) |child| {
                if (child.abs_bounds.containsPt(xf, yf)) {
                    if (self.processMouseDownEventRecurse(child, xf, yf, e, hit_widget)) {
                        return true;
                    }
                }
            }
        }

        // Bubble up to root. The normal mousedown event is fired in order from bottom to top.

        var propagate = true;
        if (node.hasHandler(ui.EventHandlerMasks.mousedown)) {
            // If there is a handler, assume the event hits the widget.
            // If the widget performs clearMouseHitFlag() in any of the handlers, the flag is reset so it does not change hit_widget.
            self.common.widget_hit_flag = true;

            const sub = self.common.node_mousedown_map.get(node).?;
            if (sub.handleEvent(&self.event_ctx, e) == .stop) {
                propagate = false;
            }
        }

        if (self.common.widget_hit_flag) {
            hit_widget.* = true;
        }
        // if (!propagate) {
        //     log.debug("end at {s}", .{node.vtable.name});
        // }
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
            if (focused_widget.hasHandler(ui.EventHandlerMasks.keydown)) {
                const sub = self.common.node_keydown_map.get(focused_widget).?;
                sub.handleEvent(&self.event_ctx, e);
            }
        }
    }

    pub fn processKeyUpEvent(self: *Module, e: platform.KeyUpEvent) void {
        // Only the focused widget receives input.
        if (self.common.focused_widget) |focused_widget| {
            if (focused_widget.hasHandler(ui.EventHandlerMasks.keyup)) {
                const sub = self.common.node_keyup_map.get(focused_widget).?;
                sub.handleEvent(&self.event_ctx, e);
            }
        }
    }

    fn updateRoot(self: *Module, root_id: ui.FramePtr) !void {
        if (root_id.isPresent()) {
            const root = root_id.get();
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
    pub fn preUpdate(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FramePtr, layout_size: LayoutSize) UpdateError!void {
        self.common.updateIntervals(delta_ms, &self.event_ctx);

        // Remove event handlers marked for removal. This should happen before removing and invalidating nodes.
        self.common.removeHandlers();

        // Remove nodes marked for removal.
        self.common.removeNodes();

        // TODO: check if we have to update

        // Reset the builder buffer before we call any Component.build
        self.build_ctx.resetBuffer();
        if (self.common.use_first_arena) {
            self.common.arena_allocators[0].deinit();
            self.common.arena_allocators[0].state = .{};
            self.common.arena_alloc = self.common.arena_allocs[0];
        } else {
            self.common.arena_allocators[1].deinit();
            self.common.arena_allocators[1].state = .{};
            self.common.arena_alloc = self.common.arena_allocs[1];
        }
        self.build_ctx.arena_alloc = self.common.arena_alloc;
        self.common.use_first_arena = !self.common.use_first_arena;

        defer {
            for (self.common.build_owned_frames.items) |ptr| {
                ptr.destroy();
            }
            self.common.build_owned_frames.clearRetainingCapacity();
        }

        if (builtin.mode == .Debug) {
            self.trace.clearRetainingCapacity();
        }

        // Update global build context for idiomatic widget declarations.
        gbuild_ctx = &self.build_ctx;

        // TODO: Provide a different context for the bootstrap function since it doesn't have a frame or node. Currently uses the BuildContext.
        self.build_ctx.prepareCall(undefined, undefined);
        const user_root = bootstrap_fn(bootstrap_ctx, &self.build_ctx);
        if (user_root.isPresent()) {
            // user root frame isn't owned by the build step directly since it's a prop under the Root frame.
            const user_root_frame = self.build_ctx.getFrame(user_root.id);

            if (user_root_frame.vtable == FragmentVTable) {
                try self.common.build_owned_frames.append(self.alloc, user_root);
                return error.UserRootCantBeFragment;
            }
        }

        // The user root widget is wrapped by the Root widget to facilitate things like modals and popovers.
        const root_id = self.build_ctx.build(ui.widgets.Root, .{ .user_root = user_root });
        try self.common.build_owned_frames.append(self.alloc, root_id);

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
    pub fn updateAndRender(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FramePtr, width: f32, height: f32) !void {
        const layout_size = LayoutSize.init(width, height);
        try self.preUpdate(delta_ms, bootstrap_ctx, bootstrap_fn, layout_size);
        self.render(delta_ms);
        self.postUpdate();
        if (builtin.mode == .Debug) {
            if (self.debug_dump_after_num_updates) |num_updates| {
                if (num_updates == 0) {
                    self.debug_dump_after_num_updates = null;
                } else {
                    if (num_updates - 1 == 0) {
                        self.dumpTree();
                        self.debug_dump_after_num_updates = null;
                    } else {
                        self.debug_dump_after_num_updates = num_updates - 1;
                    }
                }
            }
        }
    }

    /// Just do an update without rendering.
    pub fn update(self: *Module, delta_ms: f32, bootstrap_ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(bootstrap_ctx), *BuildContext) ui.FramePtr, width: f32, height: f32) !void {
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
    fn updateExistingNode(self: *Module, parent: ?*ui.Node, frame_ptr: ui.FramePtr, node: *ui.Node) UpdateError!void {
        _ = parent;
        if (builtin.mode == .Debug) {
            try self.trace.append(self.alloc, .{ .node = node, .trace_t = .update });
        }

        // Update frame and props.
        const frame = frame_ptr.get();

        // if (parent) |pn| {
        //     node.transform = pn.transform;
        // }
        const widget_vtable = frame.vtable;

        if (frame.props != null or frame.style != null) {
            self.update_ctx.node = node;
            widget_vtable.updateProps(self, node, frame, &self.update_ctx);
        }

        defer {
            if (widget_vtable.has_post_update) {
                self.update_ctx.node = node;
                widget_vtable.postUpdate(node, &self.update_ctx);
            }
        }

        const child_frame_ptr = self.buildChildFrame(frame_ptr, node, widget_vtable);
        if (child_frame_ptr.isNull()) {
            if (node.children.items.len > 0) {
                for (node.children.items) |it| {
                    self.removeNode(it);
                }
            }
            node.children.items.len = 0;
            return;
        }
        try self.common.build_owned_frames.append(self.alloc, child_frame_ptr);
        const child_frame = child_frame_ptr.get();
        if (child_frame.vtable == FragmentVTable) {
            // Fragment frame, diff it's children instead.

            // Start by doing fast array iteration to update nodes with the same key/idx.
            // Once there is a discrepancy, switch to the slower method of key map checks.
            var child_idx: u32 = 0;

            if (child_frame.fragment_children.isPresent()) {
                var cur_child = child_frame.fragment_children.get().head;
                while (cur_child) |frame_node| {
                    const child_id = frame_node.data;
                    const child_frame_ = child_id.get();
                    if (child_frame_.vtable == FragmentVTable) {
                        return error.NestedFragment;
                    }
                    if (node.children.items.len <= child_idx) {
                        // TODO: Create nodes for the rest of the frames instead.
                        try self.updateChildFramesWithKeyMap(node, child_idx, cur_child);
                        return;
                    }
                    const child_node = node.children.items[child_idx];
                    if (child_node.vtable != child_frame_.vtable) {
                        try self.updateChildFramesWithKeyMap(node, child_idx, cur_child);
                        return;
                    }
                    const frame_key = child_frame_.key orelse ui.WidgetKey{.ListIdx = child_idx};
                    if (!std.meta.eql(child_node.key, frame_key)) {
                        try self.updateChildFramesWithKeyMap(node, child_idx, cur_child);
                        return;
                    }
                    try self.updateExistingNode(node, child_id, child_node);
                    child_idx += 1;
                    cur_child = frame_node.next;
                }
            }

            // Remove left over children.
            if (child_idx < node.children.items.len) {
                for (node.children.items[child_idx..]) |it| {
                    self.removeNode(it);
                }
                node.children.items.len = child_idx;
            }
        } else {
            // One child frame.
            if (node.children.items.len == 0) {
                const new_child = try self.createAndInitNode(node, child_frame_ptr, 0);
                node.children.append(new_child) catch unreachable;
                return;
            }
            const child_node = node.children.items[0];
            if (child_node.vtable != child_frame.vtable) {
                self.removeNode(child_node);
                const new_child = try self.createAndInitNode(node, child_frame_ptr, 0);
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
                const new_child = try self.createAndInitNode(node, child_frame_ptr, 0);
                node.children.items[0] = new_child;
                if (node.children.items.len > 1) {
                    for (node.children.items[1..]) |it| {
                        self.removeNode(it);
                    }
                }
                return;
            }
            // Same child.
            try self.updateExistingNode(node, child_frame_ptr, child_node);
        }
    }

    /// Slightly slower method to update with frame children that utilizes a key map.
    fn updateChildFramesWithKeyMap(self: *Module, parent: *ui.Node, start_idx: u32, start_child: ?*stdx.ds.SLLUnmanaged(ui.FramePtr).Node) UpdateError!void {
        var child_idx: u32 = start_idx;
        var cur_child = start_child;
        while (cur_child) |frame_node| {
            const frame_id = frame_node.data;
            const frame = frame_id.get();

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
                    cur_child = frame_node.next;
                    while (cur_child) |frame_node_| {
                        const frame_id_ = frame_node_.data;
                        const new_child_ = try self.createAndInitNode(parent, frame_id_, child_idx);
                        parent.children.append(new_child_) catch unreachable;
                        child_idx += 1;
                        cur_child = frame_node_.next;
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
            child_idx += 1;
            cur_child = frame_node.next;
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
        const num_child_frames = child_idx;
        if (parent.children.items.len > num_child_frames) {
            parent.children.shrinkRetainingCapacity(num_child_frames);
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
        if (node.hasHandler(ui.EventHandlerMasks.keyup)) {
            self.common.ctx.clearKeyUpHandler(node);
        }
        if (node.hasHandler(ui.EventHandlerMasks.keydown)) {
            self.common.ctx.clearKeyDownHandler(node);
        }
        if (node.hasHandler(ui.EventHandlerMasks.enter_mousedown)) {
            self.common.ctx.clearEnterMouseDownHandler(node);
        }
        if (node.hasHandler(ui.EventHandlerMasks.mousedown)) {
            self.common.ctx.clearMouseDownHandler(node);
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
        widget_vtable.destroy(self.mod_ctx.mod, node);

        node.deinit();

        self.common.to_remove_nodes.append(self.alloc, node) catch fatal();
    }

    /// Builds the child frame for a given frame.
    fn buildChildFrame(self: *Module, frame_ptr: ui.FramePtr, node: *ui.Node, widget_vtable: *const ui.WidgetVTable) ui.FramePtr {
        self.build_ctx.prepareCall(frame_ptr.id, node);
        return widget_vtable.build(node.widget, &self.build_ctx);
    }

    inline fn createAndInitNode(self: *Module, parent: ?*ui.Node, frame_ptr: ui.FramePtr, idx: u32) UpdateError!*ui.Node {
        const new_node = self.alloc.create(ui.Node) catch unreachable;
        return self.initNode(parent, frame_ptr, idx, new_node);
    }

    /// Allow passing in a new node so a ref can be obtained beforehand.
    fn initNode(self: *Module, parent: ?*ui.Node, frame_ptr: ui.FramePtr, idx: u32, new_node: *ui.Node) UpdateError!*ui.Node {
        const frame = frame_ptr.get();
        const widget_vtable = frame.vtable;

        errdefer {
            for (new_node.children.items) |child| {
                self.destroyNode(child);
            }
            self.destroyNode(new_node);
        }

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

        if (builtin.mode == .Debug) {
            if (frame.debug) {
                new_node.debug = true;
            }
        }

        if (parent != null) {
            parent.?.key_to_child.put(key, new_node) catch unreachable;
        }

        self.init_ctx.prepareForNode(new_node);
        const new_widget = widget_vtable.create(self, new_node, frame);

        // Bind to ref after initializing the widget.
        if (frame.widget_bind) |bind| {
            if (frame.is_bind_func) {
                const bind_func = stdx.mem.ptrCastAlign(*ui.BindNodeFunc, frame.widget_bind);
                bind_func.func(bind_func.ctx, new_node, true);
                new_node.setStateMask(ui.NodeStateMasks.bind_func);
            } else {
                stdx.mem.ptrCastAlign(*ui.NodeRef, bind).* = ui.NodeRef.init(new_node);
            }
            new_node.bind = bind;
        }
        if (frame.node_binds != null) {
            var mb_cur = frame.node_binds;
            while (mb_cur) |cur| {
                cur.node_ref.* = ui.NodeRef.init(new_node);
                mb_cur = cur.next;
            }
        }

        //log.warn("created: {}", .{frame.type_id});

        // Build child frames and create child nodes from them.
        const child_frame_ptr = self.buildChildFrame(frame_ptr, new_node, widget_vtable);
        if (child_frame_ptr.isPresent()) {
            try self.common.build_owned_frames.append(self.alloc, child_frame_ptr);
            const child_frame = child_frame_ptr.get();

            if (child_frame.vtable == FragmentVTable) {
                if (child_frame.fragment_children.isPresent()) {
                    // Fragment frame.
                    var cur_child = child_frame.fragment_children.get().head;
                    // Iterate using a counter since the frame list buffer is dynamic.
                    var child_idx: u32 = 0;
                    while (cur_child) |frame_node| {
                        const child_id = frame_node.data;
                        const child_frame_ = child_id.get();
                        if (child_frame_.vtable == FragmentVTable) {
                            return error.NestedFragment;
                        }
                        const child_node = try self.createAndInitNode(new_node, child_id, child_idx);
                        new_node.children.append(child_node) catch unreachable;
                        child_idx += 1;
                        cur_child = frame_node.next;
                    }
                }
            } else {
                // Single child frame.
                const child_node = try self.createAndInitNode(new_node, child_frame_ptr, 0);
                new_node.children.append(child_node) catch unreachable;
            }
        }
        // log.debug("after {s}", .{getWidgetName(frame.type_id)});

        self.init_ctx.prepareForNode(new_node);
        widget_vtable.postInit(new_widget, &self.init_ctx);
        return new_node;
    }

    pub fn dumpTrace(self: Module) void {
        for (self.trace.items) |trace| {
            log.debug("{s} {}", .{trace.node.vtable.name, trace.trace_t});
        }
    }

    pub fn dumpTreeById(self: Module, comptime lit: @Type(.EnumLiteral)) void {
        if (self.common.getNodeByTag(lit)) |node| {
            self.dumpTreeR(0, node);
        }
    }

    pub fn dumpTree(self: Module) void {
        if (self.root_node) |root| {
            self.dumpTreeR(0, root);
        }
    }

    fn dumpTreeR(self: Module, depth: u32, node: *ui.Node) void {
        const S = struct{
            pub var buf: [256]u8 = undefined;
        };
        if (node.vtable == GenWidgetVTable(u.TextT)) {
            const text = node.getWidget(u.TextT);
            const buf = std.fmt.bufPrint(&S.buf, "{[0]s: <[1]}{[2]s} \"{[3]s}\"", .{ "", depth * 2, node.vtable.name, text.props.text }) catch fatal();
            log.debug("{s}", .{buf});
        } else {
            const buf = std.fmt.bufPrint(&S.buf, "{[0]s: <[1]}{[2]s}", .{ "", depth * 2, node.vtable.name }) catch fatal();
            log.debug("{s}", .{buf});
        }
        const buf = std.fmt.bufPrint(&S.buf, "{[0]s: <[1]}{[2]}", .{ "", (depth + 1) * 2, node.getAbsBounds()}) catch fatal();
        log.debug("{s}", .{buf});
        for (node.children.items) |child| {
            self.dumpTreeR(depth + 1, child);
        }
    }
};

pub const UpdateContext = struct {
    common: *CommonContext,
    node: *ui.Node,

    pub inline fn getStyle(self: *UpdateContext, comptime Widget: type) *const WidgetComputedStyle(Widget) {
        return self.common.getNodeStyle(Widget, self.node);
    }

    pub usingnamespace MixinContextFrameOps(UpdateContext);
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

    pub inline fn strokeBBoxInward(self: *RenderContext, bounds: stdx.math.BBox) void {
        self.gctx.strokeRectBoundsInward(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);
    }

    pub inline fn fillBBox(self: *RenderContext, bounds: stdx.math.BBox) void {
        self.gctx.fillRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y);
    }

    pub inline fn fillRoundBBox(self: *RenderContext, bounds: stdx.math.BBox, radius: f32) void {
        self.gctx.fillRoundRectBounds(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y, radius);
    }

    pub inline fn strokeRoundBBoxInward(self: *RenderContext, bounds: stdx.math.BBox, radius: f32) void {
        self.gctx.strokeRoundRectBoundsInward(bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y, radius);
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

    pub inline fn getStyle(self: *RenderContext, comptime Widget: type) *const WidgetComputedStyle(Widget) {
        return self.common.getNodeStyle(Widget, self.node);
    }

    pub usingnamespace MixinContextNodeReadOps(RenderContext);
    pub usingnamespace MixinContextSharedOps(RenderContext);
    // pub usingnamespace MixinContextReadOps(RenderContext);
};

inline fn WidgetStyleMods(comptime Widget: type) type {
    return switch (Widget) {
        ui.widgets.ButtonT => ui.widgets.ButtonMods,
        else => void,
    };
}

pub inline fn WidgetComputedStyle(comptime Widget: type) type {
    if (@hasDecl(Widget, "ComputedStyle")) {
        return Widget.ComputedStyle;
    } else return void;
}

pub inline fn WidgetUserStyle(comptime Widget: type) type {
    if (@hasDecl(Widget, "Style")) {
        return Widget.Style;
    } else return void;
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

        pub inline fn nextPostLayout(self: *Context, ctx: anytype, cb: fn(@TypeOf(ctx)) void) void {
            self.common.nextPostLayout(ctx, cb);
        }
        
        pub inline fn getCurrentMouseX(self: *Context) i16 {
            return self.common.getCurrentMouseX();
        }

        pub inline fn getCurrentMouseY(self: *Context) i16 {
            return self.common.getCurrentMouseY();
        }
    };
}

pub fn MixinContextFrameOps(comptime Context: type) type {
    return struct {
        pub fn handleFrameUpdate(self: Context, old: ui.FramePtr, new: ui.FramePtr) void {
            if (old.id != new.id) {
                if (old.isPresent()) {
                    old.destroy();
                }
                if (new.isPresent()) {
                    self.incFrameRef(new);
                }
            }
        }

        pub fn removeFrame(self: Context, ptr: ui.FramePtr) void {
            if (ptr.isPresent()) {
                ptr.destroy();
            }
        }
            
        pub fn incFrameRef(self: Context, ptr: ui.FramePtr) void {
            if (ptr.isPresent()) {
                return self.common.common.mod.build_ctx.frames.incRef(ptr.id);
            }
        }
    };
}

/// Requires Context.common.
pub fn MixinContextSharedOps(comptime Context: type) type {
    return struct {
        pub inline fn getContext(self: Context, key: u32) ?*anyopaque {
            return self.common.common.context_provider(key);
        }

        pub inline fn getRoot(self: Context) *ui.widgets.Root {
            return self.common.common.mod.root_node.?.getWidget(ui.widgets.Root);
        }

        pub inline fn getUserRoot(self: Context, comptime Widget: type) ?*Widget {
            return self.common.common.mod.getUserRoot(Widget);
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
const PasteHandler = fn (node: *ui.Node, ctx: *CommonContext, str: []const u8) void;

/// Ops that need an attached node.
/// Requires Context.node and Context.common.
pub fn MixinContextNodeOps(comptime Context: type) type {
    return struct {
        pub inline fn getNode(self: *Context) *ui.Node {
            return self.node;
        }

        pub inline fn requestFocus(self: *Context, opts: RequestFocusOptions) void {
            self.common.requestFocus(self.node, opts);
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

        pub inline fn setEnterMouseDownHandler(self: *Context, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
            self.common.setEnterMouseDownHandler(self.node, ctx, cb);
        }

        pub inline fn setMouseDownHandler(self: *Context, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
            self.common.setMouseDownHandler(self.node, ctx, cb);
        }

        pub inline fn addMouseScrollHandler(self: Context, ctx: anytype, cb: events.MouseScrollHandler(@TypeOf(ctx))) void {
            self.common.addMouseScrollHandler(self.node, ctx, cb);
        }

        pub inline fn setKeyDownHandler(self: *Context, ctx: anytype, cb: events.KeyDownHandler(@TypeOf(ctx))) void {
            self.common.setKeyDownHandler(self.node, ctx, cb);
        }

        pub inline fn setKeyUpHandler(self: *Context, ctx: anytype, cb: events.KeyUpHandler(@TypeOf(ctx))) void {
            self.common.setKeyUpHandler(self.node, ctx, cb);
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

        pub inline fn clearKeyUpHandler(self: *Context, comptime Ctx: type, func: events.KeyUpHandler(Ctx)) void {
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
    gctx: *graphics.Graphics,

    /// Size constraints are set by the parent, and consumed by child widget's `layout`.
    cstr: SizeConstraints,
    node: *ui.Node,

    fn init(mod: *Module, gctx: *graphics.Graphics) LayoutContext {
        return .{
            .mod = mod,
            .common = &mod.common.ctx,
            .gctx = gctx,
            .cstr = undefined,
            .node = undefined,
        };
    }
        
    pub inline fn getStyle(self: *LayoutContext, comptime Widget: type) *const WidgetComputedStyle(Widget) {
        return self.common.getNodeStyle(Widget, self.node);
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
            .gctx = self.gctx,
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
            .gctx = self.gctx,
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
            .gctx = self.gctx,
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
            .gctx = self.gctx,
            .cstr = cstr,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn computeLayoutInherit(self: *LayoutContext, node: *ui.Node) LayoutSize {
        var child_ctx = LayoutContext{
            .mod = self.mod,
            .common  = &self.mod.common.ctx,
            .gctx = self.gctx,
            .cstr = self.cstr,
            .node = node,
        };
        return node.vtable.layout(node.widget, &child_ctx);
    }

    pub fn setLayout2(self: *LayoutContext, node: *ui.Node, x: f32, y: f32, width: f32, height: f32) void {
        _ = self;
        node.layout = Layout.init(x, y, width, height);
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

const RequestFocusOptions = struct {
    onBlur: ?BlurHandler = null,
    onPaste: ?PasteHandler = null,
};

/// Access to common utilities.
pub const CommonContext = struct {
    common: *ModuleCommon,
    alloc: std.mem.Allocator,

    pub inline fn getNodeStyle(self: CommonContext, comptime Widget: type, node: *ui.Node) *const WidgetComputedStyle(Widget) {
        const Style = WidgetComputedStyle(Widget);

        if (GenWidgetVTable(Widget) != node.vtable) {
            stdx.panic("Type assertion failed.");
        }
        if (!node.hasState(ui.NodeStateMasks.computed_style)) {
            return self.common.getCurrentStyleDefault(Widget);
        } else {
            return stdx.mem.ptrCastAlign(*Style, self.common.node_computed_styles.get(node).?);
        }
    }

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

    pub fn requestFocus(self: *CommonContext, node: *ui.Node, opts: RequestFocusOptions) void {
        if (self.common.focused_widget) |focused_widget| {
            if (focused_widget != node) {
                // Trigger blur for the current focused widget.
                if (self.common.focused_onblur) |on_blur| {
                    on_blur(focused_widget, self);
                }
            }
        }
        self.common.focused_widget = node;
        self.common.focused_onblur = opts.onBlur;
        self.common.focused_onpaste = opts.onPaste;
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
                    .event_t = .global_mousemove,
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
                    .event_t = .global_mouseup,
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
                    .event_t = .mouseup,
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
                    .event_t = .hoverchange,
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

    pub fn setEnterMouseDownHandler(self: CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseDownEvent) ui.EventResult).init(self.alloc, ctx, cb).iface();
        const sub = SubscriberRet(platform.MouseDownEvent, ui.EventResult){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_enter_mousedown_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.enter_mousedown);
        }
    }

    pub fn setMouseDownHandler(self: CommonContext, node: *ui.Node, ctx: anytype, cb: events.MouseDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.MouseDownEvent) ui.EventResult).init(self.alloc, ctx, cb).iface();
        const sub = SubscriberRet(platform.MouseDownEvent, ui.EventResult){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_mousedown_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.mousedown);
        }
    }

    pub fn clearEnterMouseDownHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_enter_mousedown_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.enter_mousedown);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_t = .enter_mousedown,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn clearMouseDownHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_mousedown_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.mousedown);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_t = .mousedown,
                    .node = node,
                }) catch fatal();
            }
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
            // Check to remove a previous clear handler task.
            if (res.value_ptr.to_remove) {
                self.common.cancelRemoveHandler(.global_mousemove, node);
            }
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

    pub fn setKeyUpHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.KeyUpHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.KeyUpEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.KeyUpEvent){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_keyup_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.keyup);
        }
    }

    pub fn clearKeyUpHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_keyup_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.keyup);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_t = .keyup,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn setKeyDownHandler(self: *CommonContext, node: *ui.Node, ctx: anytype, cb: events.KeyDownHandler(@TypeOf(ctx))) void {
        const closure = Closure(@TypeOf(ctx), fn (ui.KeyDownEvent) void).init(self.alloc, ctx, cb).iface();
        const sub = Subscriber(platform.KeyDownEvent){
            .closure = closure,
            .node = node,
        };
        const res = self.common.node_keydown_map.getOrPut(self.alloc, node) catch fatal();
        if (res.found_existing) {
            res.value_ptr.deinit(self.alloc);
            res.value_ptr.* = sub;
        } else {
            res.value_ptr.* = sub;
            node.setHandlerMask(ui.EventHandlerMasks.keydown);
        }
    }

    pub fn clearKeyDownHandler(self: *CommonContext, node: *ui.Node) void {
        if (self.common.node_keydown_map.getPtr(node)) |sub| {
            if (!sub.to_remove) {
                sub.to_remove = true;
                node.clearHandlerMask(ui.EventHandlerMasks.keydown);
                self.common.to_remove_handlers.append(self.alloc, .{
                    .event_t = .keydown,
                    .node = node,
                }) catch fatal();
            }
        }
    }

    pub fn nextPostLayout(self: *CommonContext, ctx: anytype, cb: fn(@TypeOf(ctx)) void) void {
        return self.common.nextPostLayout(ctx, cb);
    }

    pub fn getCurrentMouseX(self: *CommonContext) i16 {
        return self.common.cur_mouse_x;
    }

    pub fn getCurrentMouseY(self: *CommonContext) i16 {
        return self.common.cur_mouse_y;
    }
};

const UserStyleHandle = struct {
    ptr: union {
        owned: *anyopaque,
        not_owned: *const anyopaque,
    },
    owned: bool,
};

// TODO: Refactor similar ops to their own struct. 
pub const ModuleCommon = struct {
    alloc: std.mem.Allocator,
    mod: *Module,

    /// Arena allocators that get freed after two update cycles.
    /// Allocations should survive two update cycles so that nodes that have been discarded from tree diff still have valid props memory.
    /// Two are needed to alternate on each engine update.
    arena_allocators: [2]std.heap.ArenaAllocator,
    arena_allocs: [2]std.mem.Allocator,
    use_first_arena: bool,
    /// The current arena allocator.
    arena_alloc: std.mem.Allocator,

    build_owned_frames: std.ArrayListUnmanaged(ui.FramePtr),

    g: *graphics.Graphics,
    text_measures: stdx.ds.PooledHandleList(TextMeasureId, TextMeasure),
    interval_sessions: stdx.ds.PooledHandleList(u32, IntervalSession),

    /// Keyboard handlers.
    node_keyup_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.KeyUpEvent)),
    node_keydown_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.KeyDownEvent)),

    /// Mouse handlers.
    global_mouse_up_list: std.ArrayListUnmanaged(*ui.Node),
    mouse_scroll_event_subs: stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.MouseScrollEvent)),
    node_global_mousemove_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseMoveEvent)),
    /// Mouse move events fire far more frequently so iteration should be fast.
    global_mouse_move_list: std.ArrayListUnmanaged(*ui.Node),
    has_mouse_move_subs: bool,

    node_enter_mousedown_map: std.AutoHashMapUnmanaged(*ui.Node, SubscriberRet(platform.MouseDownEvent, ui.EventResult)),
    node_mousedown_map: std.AutoHashMapUnmanaged(*ui.Node, SubscriberRet(platform.MouseDownEvent, ui.EventResult)),
    node_mouseup_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseUpEvent)),
    node_global_mouseup_map: std.AutoHashMapUnmanaged(*ui.Node, Subscriber(platform.MouseUpEvent)),

    /// Hover change event is more reliable than MouseEnter and MouseExit.
    /// Once the hovered state is triggered, another event is guaranteed to fire once the element is no longer hovered.
    /// This is done by tracking the current hovered items and checking their bounds against mouse move events.
    node_hoverchange_map: std.AutoHashMapUnmanaged(*ui.Node, HoverChangeSubscriber),
    hovered_nodes: std.ArrayListUnmanaged(*ui.Node),

    /// Currently focused widget.
    focused_widget: ?*ui.Node,
    focused_onblur: ?BlurHandler,
    focused_onpaste: ?PasteHandler,
    /// Scratch vars to track the last focused widget.
    last_focused_widget: ?*ui.Node,
    hit_last_focused: bool,
    widget_hit_flag: bool,

    /// Maps node to custom style. The style type is erased and is determined by the Widget type.
    /// TODO: Currently styles are allocated on the heap, it might be better to have an arraylist per Style type and store indexes instead.
    node_user_styles: std.AutoHashMapUnmanaged(*ui.Node, UserStyleHandle),

    /// Nodes that have dynamic styles either because of per widget user styles or the widget has style modifiers,
    /// cache their computed styles in this map.
    /// When all style modifiers are false and there are no user style overrides,
    /// the computed style will be removed and the current theme style will be returned instead.
    /// TODO: Also reduce capacity if map is reduced by some threshold of current cap.
    node_computed_styles: std.AutoHashMapUnmanaged(*ui.Node, *anyopaque),

    /// Style defaults.
    default_button_style: u.ButtonT.ComputedStyle,
    default_update_button_style: fn (*u.ButtonT.ComputedStyle, u.ButtonMods) void,
    default_text_button_style: u.TextButtonT.ComputedStyle,
    default_icon_button_style: u.IconButtonT.ComputedStyle,
    default_text_style: u.TextT.ComputedStyle,
    default_text_area_style: u.TextAreaT.ComputedStyle,
    default_window_style: u.WindowT.ComputedStyle,
    default_scroll_view_style: u.ScrollViewT.ComputedStyle,
    default_tab_view_style: u.TabViewT.ComputedStyle,
    default_border_style: u.BorderT.ComputedStyle,

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
            .arena_allocators = .{ std.heap.ArenaAllocator.init(alloc), std.heap.ArenaAllocator.init(alloc) },
            .arena_allocs = undefined,
            .use_first_arena = true,
            .arena_alloc = undefined,
            .build_owned_frames = .{},

            .g = g,
            .text_measures = stdx.ds.PooledHandleList(TextMeasureId, TextMeasure).init(alloc),
            // .default_font_gid = g.getFontGroupBySingleFontName("Nunito Sans"),
            .default_font_gid = g.getDefaultFontGroupId(),
            .interval_sessions = stdx.ds.PooledHandleList(u32, IntervalSession).init(alloc),

            .node_keyup_map = .{},
            .node_keydown_map = .{},
            .node_enter_mousedown_map = .{},
            .node_mousedown_map = .{},
            .node_mouseup_map = .{},
            .node_global_mouseup_map = .{},
            .node_global_mousemove_map = .{},
            .global_mouse_up_list = .{},
            .global_mouse_move_list = .{},
            .mouse_scroll_event_subs = stdx.ds.PooledHandleSLLBuffer(u32, Subscriber(platform.MouseScrollEvent)).init(alloc),
            .has_mouse_move_subs = false,
            .node_hoverchange_map = .{},
            .hovered_nodes = .{},

            .next_post_layout_cbs = std.ArrayList(ClosureIface(fn () void)).init(alloc),
            // .next_post_render_cbs = std.ArrayList(*ui.Node).init(alloc),

            .focused_widget = null,
            .focused_onblur = null,
            .focused_onpaste = null,
            .last_focused_widget = null,
            .hit_last_focused = false,
            .widget_hit_flag = false,
            .cur_mouse_x = 0,
            .cur_mouse_y = 0,

            .node_user_styles = .{},
            .node_computed_styles = .{},
            .default_button_style = .{},
            .default_update_button_style = u.ButtonT.ComputedStyle.defaultUpdate,
            .default_text_button_style = .{},
            .default_icon_button_style = .{},
            .default_text_style = .{},
            .default_window_style = .{},
            .default_text_area_style = .{},
            .default_scroll_view_style = .{},
            .default_tab_view_style = .{},
            .default_border_style = .{},

            .ctx = .{
                .common = self,
                .alloc = alloc, 
            },
            .context_provider = S.defaultContextProvider,
            .id_map = std.AutoHashMap(ui.WidgetUserId, *ui.Node).init(alloc),
            .to_remove_handlers = .{},
            .to_remove_nodes = .{},
        };
        self.arena_allocs[0] = self.arena_allocators[0].allocator();
        self.arena_allocs[1] = self.arena_allocators[1].allocator();
        self.arena_alloc = self.arena_allocs[0];
    }

    fn deinit(self: *ModuleCommon) void {
        // Assumes all nodes have called destroyNode.

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
            var iter = self.mouse_scroll_event_subs.iterator();
            while (iter.next()) |it| {
                it.data.deinit(self.alloc);
            }
            self.mouse_scroll_event_subs.deinit();
        }

        self.removeHandlers();
        self.removeNodes();

        if (self.node_user_styles.size > 0) {
            stdx.panic("Unexpected num node user styles > 0");
        }
        self.node_user_styles.deinit(self.alloc);
        if (self.node_computed_styles.size > 0) {
            stdx.panicFmt("Unexpected num node computed styles {} > 0", .{self.node_computed_styles.size});
        }
        self.node_computed_styles.deinit(self.alloc);

        self.to_remove_handlers.deinit(self.alloc);
        self.to_remove_nodes.deinit(self.alloc);

        self.node_hoverchange_map.deinit(self.alloc);
        self.hovered_nodes.deinit(self.alloc);

        self.node_keydown_map.deinit(self.alloc);
        self.node_keyup_map.deinit(self.alloc);
        self.node_global_mousemove_map.deinit(self.alloc);
        self.global_mouse_move_list.deinit(self.alloc);
        self.node_global_mouseup_map.deinit(self.alloc);
        self.global_mouse_up_list.deinit(self.alloc);
        self.node_mouseup_map.deinit(self.alloc);
        self.node_enter_mousedown_map.deinit(self.alloc);
        self.node_mousedown_map.deinit(self.alloc);

        self.arena_allocators[0].deinit();
        self.arena_allocators[1].deinit();

        self.build_owned_frames.deinit(self.alloc);
    }

    pub inline fn getStylePropPtr(self: *ModuleCommon, style: anytype, comptime prop: []const u8) ?*const stdx.meta.ChildOrStruct(@TypeOf(@field(style, prop))) {
        _ = self;
        const Prop = @TypeOf(@field(style, prop));
        if (@typeInfo(Prop) == .Optional) {
            return if (@field(style, prop) != null) &@field(style, prop).? else null;
        } else {
            return &@field(style, prop);
        }
    }

    inline fn getCurrentStyleDefault(self: *ModuleCommon, comptime Widget: type) *const WidgetComputedStyle(Widget) {
        const Style = WidgetComputedStyle(Widget);
        return switch (Style) {
            u.ButtonT.ComputedStyle => &self.default_button_style,
            u.TextButtonT.ComputedStyle => &self.default_text_button_style,
            u.TextT.ComputedStyle => &self.default_text_style,
            u.WindowT.ComputedStyle => &self.default_window_style,
            u.TextAreaT.ComputedStyle => &self.default_text_area_style,
            u.IconButtonT.ComputedStyle => &self.default_icon_button_style,
            u.ScrollViewT.ComputedStyle => &self.default_scroll_view_style,
            u.TabViewT.ComputedStyle => &self.default_tab_view_style,
            u.BorderT.ComputedStyle => &self.default_border_style,
            else => @compileError("Unsupported style: " ++ @typeName(Widget)),
        };
    }

    inline fn getCurrentStyleUpdateFuncDefault(self: *ModuleCommon, comptime Widget: type) fn (*WidgetComputedStyle(Widget), WidgetStyleMods(Widget)) void {
        const Style = WidgetComputedStyle(Widget);
        return switch (Style) {
            u.ButtonT.ComputedStyle => self.default_update_button_style,
            else => @compileError("Unsupported style: " ++ @typeName(Widget)),
        };
    }

    fn cancelRemoveHandler(self: *ModuleCommon, event_t: EventType, node: *ui.Node) void {
        for (self.to_remove_handlers.items) |ref, i| {
            if (ref.node == node and ref.event_t == event_t) {
                _ = self.to_remove_handlers.swapRemove(i);
                break;
            }
        }
    }

    /// Removing handlers should only free memory and remove items from lists/maps.
    /// Firing events or accessing widget prop callbacks is undefined since the widget state/props could already be freed.
    fn removeHandlers(self: *ModuleCommon) void {
        for (self.to_remove_handlers.items) |ref| {
            switch (ref.event_t) {
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
                .keydown => {
                    const sub = self.node_keydown_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_keydown_map.remove(ref.node);
                },
                .keyup => {
                    const sub = self.node_keyup_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_keyup_map.remove(ref.node);
                },
                .enter_mousedown => {
                    const sub = self.node_enter_mousedown_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_enter_mousedown_map.remove(ref.node);
                },
                .mousedown => {
                    const sub = self.node_mousedown_map.get(ref.node).?;
                    sub.deinit(self.alloc);
                    _ = self.node_mousedown_map.remove(ref.node);
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

pub const DeinitContext = struct {
    mod: *Module,
    alloc: std.mem.Allocator,
    common: *CommonContext,

    fn init(mod: *Module) DeinitContext {
        return .{
            .mod = mod,
            .alloc = mod.alloc,
            .common = &mod.common.ctx,
        };
    }

    pub usingnamespace MixinContextFrameOps(DeinitContext);
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

    pub inline fn getStyle(self: *InitContext, comptime Widget: type) *const WidgetComputedStyle(Widget) {
        return self.common.getNodeStyle(Widget, self.node);
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

    /// Only available at widget initialization. Forces the node to be in the hovered state.
    pub fn forceHoveredState(self: *InitContext) void {
        self.common.common.hovered_nodes.append(self.alloc, self.node) catch fatal();
        self.node.setStateMask(ui.NodeStateMasks.hovered);
    }

    pub usingnamespace MixinContextInputOps(InitContext);
    pub usingnamespace MixinContextEventOps(InitContext);
    pub usingnamespace MixinContextNodeOps(InitContext);
    pub usingnamespace MixinContextFontOps(InitContext);
    pub usingnamespace MixinContextSharedOps(InitContext);
    pub usingnamespace MixinContextFrameOps(InitContext);
};

fn SubscriberRet(comptime T: type, comptime Return: type) type {
    return struct {
        const Self = @This();
        closure: ClosureIface(fn (ui.Event(T)) Return),
        node: *ui.Node,
        to_remove: bool = false,

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
        self.g.init(t.alloc, 1, undefined, undefined) catch fatal();
        self.mod.init(t.alloc, &self.g);
        self.size = LayoutSize.init(800, 600);
    }

    pub fn deinit(self: *TestModule) void {
        self.mod.deinit();
        self.g.deinit();
    }

    pub fn preUpdate(self: *TestModule, ctx: anytype, comptime bootstrap_fn: fn (@TypeOf(ctx), *BuildContext) ui.FramePtr) !void {
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
            child: ui.FramePtr,
        },
        fn build(self: *@This(), _: *BuildContext) ui.FramePtr {
            return self.props.child.dupe();
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(delete: bool, c: *BuildContext) ui.FramePtr {
            var child: ui.FramePtr = .{};
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
        fn bootstrap(_: void, c: *BuildContext) ui.FramePtr {
            const list = c.list(&.{
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

test "BuildContext.list() will skip over a null FramePtr item." {
    const B = struct {};
    const A = struct {
        fn build(_: *@This(), c: *BuildContext) ui.FramePtr {
            return c.fragment(c.list(&.{
                .{},
                c.build(B, .{}),
            }));
        }
    };
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FramePtr {
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
        props: struct { child: ui.FramePtr },
        fn build(self: *@This(), _: *BuildContext) ui.FramePtr {
            return self.props.child.dupe();
        }
    };
    const B = struct {};
    const S = struct {
        fn bootstrap(_: void, c: *ui.BuildContext) ui.FramePtr {
            const nested_list = c.list(&.{
                c.build(B, .{}),
            });
            const list = c.list(&.{
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
        fn build(self: *@This(), c: *BuildContext) ui.FramePtr {
            return c.fragment(self.props.children.dupe());
        }
    };
    const B = struct {};
    // Test case where a child widget uses BuildContext.list. Check if this causes problems with BuildContext.range.
    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FramePtr {
            return c.build(A, .{
                .id = .root,
                .children = c.range(1, {}, buildChild),
            });
        }
        fn buildChild(_: void, c: *BuildContext, _: u32) ui.FramePtr {
            const list = c.list(&.{
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
            c.setKeyUpHandler({}, onKeyUp);
            c.setKeyDownHandler({}, onKeyDown);
            c.setMouseDownHandler({}, onMouseDown);
            c.setEnterMouseDownHandler({}, onEnterMouseDown);
            c.setMouseUpHandler({}, onMouseUp);
            c.setGlobalMouseMoveHandler(@as(u32, 1), onMouseMove);
            _ = c.addInterval(Duration.initSecsF(1), {}, onInterval);
            c.requestFocus(.{ .onBlur = onBlur });
        }
        fn onInterval(_: void, _: ui.IntervalEvent) void {}
        fn onBlur(_: *ui.Node, _: *ui.CommonContext) void {}
        fn onKeyUp(_: void, _: ui.KeyUpEvent) void {}
        fn onKeyDown(_: void, _: ui.KeyDownEvent) void {}
        fn onMouseDown(_: void, _: ui.MouseDownEvent) ui.EventResult {
            return .default;
        }
        fn onEnterMouseDown(_: void, _: ui.MouseDownEvent) ui.EventResult {
            return .default;
        }
        fn onMouseUp(_: void, _: ui.MouseUpEvent) void {}
        fn onMouseMove(_: u32, _: ui.MouseMoveEvent) void {}
    };
    const S = struct {
        fn bootstrap(build: bool, c: *BuildContext) ui.FramePtr {
            if (build) {
                return c.build(A, .{
                    .id = .root,
                });
            } else {
                return .{};
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

    try t.eq(mod.common.node_keyup_map.size, 1);
    const keyup_sub = mod.common.node_keyup_map.get(root.?).?;
    try t.eq(keyup_sub.closure.user_fn, A.onKeyUp);

    try t.eq(mod.common.node_keydown_map.size, 1);
    const keydown_sub = mod.common.node_keydown_map.get(root.?).?;
    try t.eq(keydown_sub.closure.user_fn, A.onKeyDown);

    try t.eq(mod.common.node_mousedown_map.size, 1);
    const mousedown_sub = mod.common.node_mousedown_map.get(root.?).?;
    try t.eq(mousedown_sub.closure.user_fn, A.onMouseDown);

    try t.eq(mod.common.node_enter_mousedown_map.size, 1);
    const enter_mousedown_sub = mod.common.node_enter_mousedown_map.get(root.?).?;
    try t.eq(enter_mousedown_sub.closure.user_fn, A.onEnterMouseDown);

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
    try t.eq(mod.common.node_keyup_map.size, 0);
    try t.eq(mod.common.node_keydown_map.size, 0);
    try t.eq(mod.common.node_mousedown_map.size, 0);
    try t.eq(mod.common.node_enter_mousedown_map.size, 0);
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

        fn build(self: *@This(), c: *BuildContext) ui.FramePtr {
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
            fn bootstrap(flag: bool, c: *BuildContext) ui.FramePtr {
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
            fn bootstrap(_: void, c: *BuildContext) ui.FramePtr {
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
            children: ui.FrameListPtr = .{},
        },
        fn build(self: *@This(), c: *BuildContext) ui.FramePtr {
            return c.fragment(self.props.children.dupe());
        }
    };
    {
        const S = struct {
            fn bootstrap(step: bool, c: *BuildContext) ui.FramePtr {
                var b = ui.FramePtr{};
                if (!step) {
                    b = c.build(B, .{});
                }
                return c.build(A, .{
                    .id = .root,
                    .children = c.list(&.{
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

test "Props memory should still be valid at node destroy time." {
    // Arena allocations should survive for two update cycles. 
    // If not, a tree diff that destroys nodes will have invalidated props memory which is undesirable since
    // the engine may need to fire cleanup events and call the Widget's deinit function.
    // In both cases, it should be assumed that props data (eg. closures, strings) are still valid and usable.

    const Options = struct {
        buf: []u8,
        decl: bool
    };

    const A = struct {
        props: struct {
            str: []const u8,
            buf: []u8,
        },

        pub fn deinit(self: *@This(), _: *ui.DeinitContext) void {
            // str should still point to valid memory.
            std.mem.copy(u8, self.props.buf, self.props.str);
        }
    };

    const S = struct {
        fn bootstrap(opts: Options, c: *BuildContext) ui.FramePtr {
            if (opts.decl) {
                return c.build(A, .{
                    .id = .root,
                    .str = c.fmt("foo", .{}),
                    .buf = opts.buf,
                });
            } else {
                return .{};
            }
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    var buf: [10]u8 = undefined;

    try mod.preUpdate(Options{ .buf = &buf, .decl = true }, S.bootstrap);
    var root = mod.getNodeByTag(.root).?;
    try t.eq(root.vtable, GenWidgetVTable(A));
    const widget = root.getWidget(A);
    try t.eqStr(widget.props.str, "foo");

    try mod.preUpdate(Options{ .buf = &buf, .decl = false }, S.bootstrap);
    try t.eqStr(buf[0..3], "foo");
}

test "Setting and clearing an event handler in the same update cycle results in the last state being effective." {
    const A = struct {
        some_var: bool,

        pub fn init(self: *@This(), ctx: *InitContext) void {
            ctx.setGlobalMouseMoveHandler(self, onMouseMove);
            ctx.clearGlobalMouseMoveHandler();
            ctx.setGlobalMouseMoveHandler(self, onMouseMove);
            // Replacing an old handler shouldn't have memory leaks.
            ctx.setGlobalMouseMoveHandler(self, onMouseMove);
            ctx.clearGlobalMouseMoveHandler();
        }

        fn onMouseMove(_: *@This(), _: ui.MouseMoveEvent) void {
        }
    };

    const S = struct {
        fn bootstrap(_: void, c: *BuildContext) ui.FramePtr {
            return c.build(A, .{
                .id = .root,
            });
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    try mod.preUpdate({}, S.bootstrap);
    var root = mod.getNodeByTag(.root).?;
    try t.eq(root.vtable, GenWidgetVTable(A));
    try t.eq(root.hasHandler(ui.EventHandlerMasks.global_mousemove), false);
}

test "WidgetRef binding." {
    const A = struct {};
    const Options = struct {
        decl: bool,
        ref: *ui.WidgetRef(A),
    };
    const S = struct {
        fn bootstrap(opts: Options, c: *BuildContext) ui.FramePtr {
            var child = ui.FramePtr{};
            if (opts.decl) {
                child = c.build(A, .{ .bind = opts.ref });
            }
            return u.Container(.{ .id = .root }, child);
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    var ref: ui.WidgetRef(A) = undefined;
    try mod.preUpdate(Options{ .decl = true, .ref = &ref }, S.bootstrap);
    try t.eq(ref.binded, true);
    try t.eq(ref.node.vtable, GenWidgetVTable(A));
    try mod.preUpdate(Options{ .decl = false, .ref = &ref }, S.bootstrap);
    try t.eq(ref.binded, false);
}

test "NodeRefMap binding." {
    const A = struct {};
    const Options = struct {
        decl: bool,
        bind: *ui.BindNodeFunc,
    };
    const S = struct {
        fn bootstrap(opts: Options, c: *BuildContext) ui.FramePtr {
            var child = ui.FramePtr{};
            if (opts.decl) {
                child = c.build(A, .{ .bind = opts.bind, .key = ui.WidgetKeyId(10) });
            }
            return u.Container(.{ .id = .root }, child);
        }
    };

    var mod: TestModule = undefined;
    mod.init();
    defer mod.deinit();

    var map: ui.NodeRefMap = undefined;
    map.init(t.alloc);
    defer map.deinit();
    try mod.preUpdate(Options{ .decl = true, .bind = &map.bind }, S.bootstrap);
    const node = map.getNode(ui.WidgetKeyId(10)).?;
    try t.eq(node.vtable, GenWidgetVTable(A));
    try mod.preUpdate(Options{ .decl = false, .bind = &map.bind }, S.bootstrap);
    try t.eq(map.getRef(ui.WidgetKeyId(10)), null);
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
    OutOfMemory,
};

const TraceType = enum {
    update,
};

const Trace = struct {
    node: *ui.Node,
    trace_t: TraceType,
};