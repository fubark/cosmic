const std = @import("std");
const stdx = @import("stdx");
const Function = stdx.Function;
const fatal = stdx.fatal;
const builtin = @import("builtin");

const ui = @import("ui.zig");
const module = @import("module.zig");
const BindNode = @import("frame.zig").BindNode;
const log = stdx.log.scoped(.build);

pub const BuildContext = struct {
    alloc: std.mem.Allocator,
    arena_alloc: std.mem.Allocator,
    mod: *ui.Module,

    /// Buffer for refcounted frames created from Widget's `build` function.
    /// Currently, frames are pushed into `frames`, `frame_lists`, and `frame_props` in a depth first order from BuildContext.build.
    /// This may help keep related frames in a subtree together when partial updates is implemented. 
    frames: stdx.ds.RcPooledHandleList(ui.FrameId, ui.Frame),

    // Linked list nodes buffer with a list of refcounted list heads.
    frame_lists: stdx.ds.RcPooledHandleList(ui.FrameListId, stdx.ds.SLLUnmanaged(ui.FramePtr)),

    /// Allocator for dynamic data that aren't organized in an array list but should still be close together in memory.
    dynamic_alloc: std.mem.Allocator,

    /// Temporary frame id buffer.
    frameid_buf: std.ArrayListUnmanaged(ui.FramePtr),
    u8_buf: std.ArrayList(u8),

    // Current node.
    node: *ui.Node,

    // Current Frame used. Must use id since pointer could be invalidated.
    frame_id: ui.FrameId,

    pub fn init(self: *BuildContext, alloc: std.mem.Allocator, arena_alloc: std.mem.Allocator, mod: *ui.Module) void {
        self.* = .{
            .alloc = alloc,
            .dynamic_alloc = alloc,
            .arena_alloc = arena_alloc,
            .mod = mod,
            .frames = stdx.ds.RcPooledHandleList(ui.FrameId, ui.Frame).init(alloc),
            .frame_lists = stdx.ds.RcPooledHandleList(ui.FrameListId, stdx.ds.SLLUnmanaged(ui.FramePtr)).init(alloc),
            .u8_buf = std.ArrayList(u8).init(alloc),
            .frameid_buf = .{},
            .node = undefined,
            .frame_id = undefined,
        };
    }

    pub fn deinit(self: *BuildContext) void {
        if (builtin.mode == .Debug) {
            if (self.frames.size() > 0) {
                var iter = self.frames.iterator();
                while (iter.next()) |frame| {
                    log.debug("{s} {} rc: {}", .{frame.vtable.name, iter.cur_id, self.frames.getRefCount(iter.cur_id)});
                }
                stdx.panicFmt("{} remaining frames.", .{self.frames.size()});
            }
            if (self.frame_lists.size() > 0) {
                stdx.panicFmt("{} remaining frame lists.", .{self.frame_lists.size()});
            }
        }
        self.frames.deinit();
        self.frame_lists.deinit();
        self.frameid_buf.deinit(self.alloc);
        self.u8_buf.deinit();
    }

    /// Creates a closure in arena buffer, and returns an iface.
    pub fn closure(self: *BuildContext, ctx: anytype, user_fn: anytype) Function(stdx.meta.FnAfterFirstParam(@TypeOf(user_fn))) {
        const Params = comptime stdx.meta.FnParams(@TypeOf(user_fn));
        if (Params.len == 0) {
            @compileError("Expected first param to be: " ++ @typeName(@TypeOf(ctx)));
        }
        const InnerFn = stdx.meta.FnAfterFirstParam(@TypeOf(user_fn));
        const c = stdx.Closure(@TypeOf(ctx), InnerFn).init(self.mod.common.arena_alloc, ctx, user_fn).iface();
        return Function(InnerFn).initClosureIface(c);
    }

    /// Closure over a PtrId pair.
    pub fn closurePtrId(self: *BuildContext, ptr: ?*anyopaque, id: usize, user_fn: anytype) Function(stdx.meta.FnAfterFirstParam(@TypeOf(user_fn))) {
        return self.closure(PtrId.init(ptr, id), user_fn);
    }

    /// Returns a wrapper over a free function.
    pub fn func(self: *BuildContext, comptime user_fn: anytype) Function(@TypeOf(user_fn)) {
        _ = self;
        const Fn = @TypeOf(user_fn);
        stdx.meta.assertFunctionType(Fn);
        return Function(Fn).init(user_fn);
    }

    /// Returns a wrapper over a free function with a context pointer. This doesn't need any allocations.
    pub fn funcExt(self: *BuildContext, ctx_ptr: anytype, comptime user_fn: anytype) Function(stdx.meta.FnAfterFirstParam(@TypeOf(user_fn))) {
        _ = self;
        const Params = comptime stdx.meta.FnParams(@TypeOf(user_fn));
        if (Params[0].arg_type.? != @TypeOf(ctx_ptr)) {
            @compileError("Expected first param to be: " ++ @typeName(@TypeOf(ctx_ptr)));
        }
        const InnerFn = stdx.meta.FnAfterFirstParam(@TypeOf(user_fn));
        return Function(InnerFn).initContext(ctx_ptr, user_fn);
    }

    /// Returned slice should be used immediately. eg. Pass into a build widget function.
    pub fn tempRange(self: *BuildContext, count: usize, ctx: anytype, build_fn: fn(@TypeOf(ctx), *BuildContext, u32) ui.FramePtr) []const ui.FramePtr {
        self.frameid_buf.resize(self.alloc, count) catch fatal();
        var cur: u32 = 0;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const frame = build_fn(ctx, self, @intCast(u32, i));
            if (frame.isPresent()) {
                self.frameid_buf.items[cur] = frame;
                cur += 1;
            }
        }
        return self.frameid_buf.items[0..cur];
    }

    pub fn range(self: *BuildContext, count: usize, ctx: anytype, build_fn: fn (@TypeOf(ctx), *BuildContext, u32) ui.FramePtr) ui.FrameListPtr {
        var i: u32 = 0;
        var act_count: u32 = 0;
        self.frames.ensureUnusedCapacity(count) catch fatal();

        var slist = stdx.ds.SLLUnmanaged(ui.FramePtr).init();
        var last = slist.head;
        while (i < count) : (i += 1) {
            const frame_ptr = build_fn(ctx, self, @intCast(u32, i));
            if (frame_ptr.isPresent()) {
                last = slist.insertAfterOrHead(self.alloc, last, frame_ptr) catch fatal();
                act_count += 1;
            }
        }

        if (act_count > 0) {
            const id = self.frame_lists.add(slist) catch fatal();
            return ui.FrameListPtr.init(id);
        } else {
            return .{}; 
        }
    }

    pub fn resetBuffer(self: *BuildContext) void {
        self.u8_buf.clearRetainingCapacity();
    }

    pub fn prepareCall(self: *BuildContext, frame_id: ui.FrameId, node: *ui.Node) void {
        self.frame_id = frame_id;
        self.node = node;
    }

    /// Uses arena allocator to format text.
    pub fn fmt(self: *BuildContext, comptime format: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.arena_alloc, format, args) catch fatal();
    }

    /// Short-hand for createFrame.
    pub inline fn build(self: *BuildContext, comptime Widget: type, props: anytype) ui.FramePtr {
        const HasProps = comptime module.WidgetHasProps(Widget);
        if (HasProps) {
            var widget_props: ui.WidgetProps(Widget) = undefined;
            setWidgetProps(Widget, &widget_props, props);
            return self.createFrame(Widget, &widget_props, props);
        } else {
            return self.createFrame(Widget, {}, props);
        }
    }

    pub inline fn list(self: *BuildContext, slice: []const ui.FramePtr) ui.FrameListPtr {
        return self.createFrameList(slice);
    }

    pub fn removeFrame(self: *BuildContext, id: ui.FrameId) void {
        // log.debug("remove frame {s} {} rc:{}", .{self.getFrame(id).vtable.name, id, self.frames.getRefCount(id)});
        const ref_count = self.frames.getRefCount(id);
        if (ref_count == 1) {
            const frame = self.getFrame(id);
            if (frame.fragment_children.isPresent()) {
                frame.fragment_children.destroy();
            }
            frame.vtable.deinitFrame(self.mod, frame);
        }
        if (builtin.mode == .Debug) {
            if (ref_count == 0) {
                log.debug("Free frame with ref count = 0.", .{});
                self.mod.dumpTrace();
                stdx.panic("");
            }
        }
        self.frames.remove(id);
    }

    pub fn removeFrameList(self: *BuildContext, id: ui.FrameListId) void {
        // log.debug("remove list {}", .{self.frame_lists.getRefCount(id)});
        const ref_count = self.frame_lists.getRefCount(id);
        if (ref_count == 1) {
            const slist = self.frame_lists.getPtrNoCheck(id);
            while (slist.head) |node| {
                node.data.destroy();
                _ = slist.removeHead(self.dynamic_alloc);
            }
        }
        if (builtin.mode == .Debug) {
            if (ref_count == 0) {
                log.debug("Free frame list with ref count = 0", .{});
                self.mod.dumpTrace();
                stdx.panic("");
            }
        }
        self.frame_lists.remove(id);
    }

    /// Creates a fragment frame and owns the list.
    pub fn fragment(self: *BuildContext, list_: ui.FrameListPtr) ui.FramePtr {
        const frame = ui.Frame.init(module.FragmentVTable, null, null, null, null, true, list_);
        const frame_id = self.frames.add(frame) catch fatal();
        return ui.FramePtr.init(frame_id);
    }

    pub fn fragmentSlice(self: *BuildContext, frames: []const ui.FrameId) ui.FramePtr {
        const list_ptr = self.createFrameList(frames);
        return self.fragment(list_ptr);
    }

    /// Allows caller to bind a FrameId to a NodeRef. One frame can be binded to many NodeRefs.
    pub fn bindFrame(self: *BuildContext, frame_ptr: ui.FramePtr, ref: *ui.NodeRef) void {
        if (frame_ptr.isPresent()) {
            const frame = frame_ptr.getPtr();
            const node = self.arena_alloc.create(BindNode) catch fatal();
            node.node_ref = ref;
            node.next = frame.node_binds;
            frame.node_binds = node;
        }
    }

    fn createFrameList(self: *BuildContext, frame_ptrs: anytype) ui.FrameListPtr {
        const Type = @TypeOf(frame_ptrs);
        const IsSlice = comptime std.meta.trait.isSlice(Type) and @typeInfo(Type).Pointer.child == ui.FramePtr;
        const IsArray = @typeInfo(Type) == .Array;
        // const IsTuple = comptime std.meta.trait.isTuple(Type);
        comptime {
            // Currently disallow tuples due to https://github.com/ziglang/zig/issues/6043. 
            if (!IsSlice and !IsArray) {
                @compileError("unsupported  " ++ @typeName(Type));
            }
        }

        var slist = stdx.ds.SLLUnmanaged(ui.FramePtr).init();
        var last = slist.head;
        if (IsSlice or IsArray) {
            for (frame_ptrs) |ptr| {
                if (ptr.isPresent()) {
                    last = slist.insertAfterOrHead(self.dynamic_alloc, last, ptr) catch fatal();
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

        if (slist.head != null) {
            const id = self.frame_lists.add(slist) catch fatal();
            return ui.FrameListPtr.init(id);
        } else {
            return .{};
        }
    }

    pub inline fn getStyle(self: *BuildContext, comptime Widget: type) *const ui.WidgetComputedStyle(Widget) {
        return self.mod.common.ctx.getNodeStyle(Widget, self.node);
    }

    pub inline fn getStylePropPtr(self: *BuildContext, style: anytype, comptime prop: []const u8) ?*const stdx.meta.ChildOrStruct(@TypeOf(@field(style, prop))) {
        return self.mod.common.getStylePropPtr(style, prop);
    }

    pub fn getFrame(self: BuildContext, id: ui.FrameId) ui.Frame {
        return self.frames.getNoCheck(id);
    }

    pub fn getFrameList(self: *BuildContext, id: ui.FrameListId) stdx.ds.SLLUnmanaged(ui.FramePtr) {
        return self.frame_lists.getNoCheck(id);
    }

    pub fn createFrame(self: *BuildContext, comptime Widget: type, props: ?*ui.WidgetProps(Widget), build_props: anytype) ui.FramePtr {
        // log.warn("createFrame {}", .{build_props});
        const BuildProps = @TypeOf(build_props);

        const bind: ?*anyopaque = if (@hasField(BuildProps, "bind")) build_props.bind else null;
        const id = if (@hasField(BuildProps, "id")) stdx.meta.enumLiteralId(build_props.id) else null;

        var style: ?*const anyopaque = null;
        var style_is_owned = true;
        if (@hasField(BuildProps, "style")) {
            const UserStyle = ui.WidgetUserStyle(Widget);
            const PropsStyle = @TypeOf(build_props.style);
            if (PropsStyle == UserStyle) {
                const dupe = self.dynamic_alloc.create(UserStyle) catch fatal();
                dupe.* = build_props.style;
                style = dupe;
            } else if (PropsStyle == *UserStyle) {
                style = build_props.style;
                style_is_owned = false;
            } else if (PropsStyle == ?*const UserStyle) {
                if (build_props.style) |ptr| {
                    style = ptr;
                    style_is_owned = false;
                }
            }
        }

        const HasProps = comptime module.WidgetHasProps(Widget);
        var props_ptr: ?*anyopaque = if (HasProps) b: {
            const dupe = self.dynamic_alloc.create(ui.WidgetProps(Widget)) catch fatal();
            dupe.* = props.?.*;
            break :b dupe;
        } else null;

        const vtable = module.GenWidgetVTable(Widget);
        var frame = ui.Frame.init(vtable, id, bind, props_ptr, style, style_is_owned, .{});
        if (@hasField(BuildProps, "key")) {
            frame.key = build_props.key;
        }
        if (@hasField(BuildProps, "bind")) {
            if (@TypeOf(build_props.bind) == *ui.BindNodeFunc) {
                frame.is_bind_func = true;
            }
        }

        if (builtin.mode == .Debug) {
            if (@hasField(BuildProps, "debug")) {
                if (build_props.debug) {
                    frame.debug = true;
                }
            }
        }
        const frame_id = self.frames.add(frame) catch fatal();

        // log.warn("created frame {}", .{frame_id});
        return ui.FramePtr.init(frame_id);
    }

    pub fn validateBuildProps(comptime Widget: type, build_props: anytype) void {
        const BuildProps = @TypeOf(build_props);
        const HasProps = comptime module.WidgetHasProps(Widget);

        if (@hasField(BuildProps, "bind")) {
            comptime {
                const IsWidgetRef = stdx.meta.FieldType(BuildProps, .bind) == *ui.WidgetRef(Widget);
                const IsBindNodeFunction = stdx.meta.FieldType(BuildProps, .bind) == *ui.BindNodeFunc;
                if (!IsWidgetRef and !IsBindNodeFunction) {
                    @compileError("Expected bind type to be: " ++ @typeName(*ui.WidgetRef(Widget)) ++ " or *ui.BindNodeFunc");
                }
            }
        }
        if (@hasField(BuildProps, "id")) {
            if (@typeInfo(stdx.meta.FieldType(BuildProps, .id)) != .EnumLiteral) {
                @compileError("Expected id type to be an enum literal.");
            }
        }
        if (@hasField(BuildProps, "spread")) {
            if (stdx.meta.FieldType(BuildProps, .spread) != ui.WidgetProps(Widget)) {
                @compileError("Expected widget props type to spread.");
            }
        }

        comptime {
            // var res: []const std.builtin.Type.StructField = &.{};
            inline for (std.meta.fields(BuildProps)) |f| {
                // Skip special fields.
                if (stdx.string.eq("id", f.name)) {
                    continue;
                } else if (stdx.string.eq("bind", f.name)) {
                    continue;
                } else if (builtin.mode == .Debug and stdx.string.eq("debug", f.name)) {
                    continue;
                } else if (stdx.string.eq("spread", f.name)) {
                    continue;
                } else if (stdx.string.eq("key", f.name)) {
                    continue;
                } else if (stdx.string.eq("style", f.name)) {
                    const UserStyle = ui.WidgetUserStyle(Widget);
                    if (UserStyle == void) {
                        @compileError(@typeName(Widget) ++ " doesn't have styles.");
                    } else {
                        if (f.field_type != UserStyle and !(@typeInfo(f.field_type) == .Pointer and std.meta.Child(f.field_type) != UserStyle) and 
                            f.field_type != ?*const UserStyle) {
                            @compileError(@typeName(Widget) ++ " style must be of type " ++ @typeName(UserStyle) ++ " or a pointer to it. " ++ @typeName(f.field_type));
                        }
                    }
                    continue;
                } else if (!HasProps) {
                    @compileError("No Props type declared in " ++ @typeName(Widget) ++ " for " ++ f.name);
                } else if (@hasField(ui.WidgetProps(Widget), f.name)) {
                    // res = res ++ &[_]std.builtin.Type.StructField{f};
                } else {
                    @compileError(f.name ++ " isn't declared in " ++ @typeName(Widget) ++ ".Props");
                }
            }
            // return res;
        }
    }

    pub fn setWidgetProps(comptime Widget: type, props: *ui.WidgetProps(Widget), build_props: anytype) void {
        const BuildProps = @TypeOf(build_props);
        validateBuildProps(Widget, build_props);
        if (@hasField(BuildProps, "spread")) {
            props.* = build_props.spread;
            // When spreading provided props, don't overwrite with default values.
            inline for (std.meta.fields(ui.WidgetProps(Widget))) |Field| {
                if (@hasField(BuildProps, Field.name)) {
                    @field(props, Field.name) = @field(build_props, Field.name);
                }
            }
        } else {
            inline for (std.meta.fields(ui.WidgetProps(Widget))) |Field| {
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
    }
};

pub const PtrId = struct {
    ptr: ?*anyopaque,
    id: usize,

    pub fn init(ptr: ?*anyopaque, id: usize) PtrId {
        return .{
            .ptr = ptr,
            .id = id,
        };
    }

    pub fn castPtr(self: PtrId, comptime Ptr: type) Ptr {
        return stdx.mem.ptrCastAlign(Ptr, self.ptr);
    }
};