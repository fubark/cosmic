const std = @import("std");
const stdx = @import("stdx");
const Function = stdx.Function;
const fatal = stdx.fatal;
const builtin = @import("builtin");

const ui = @import("ui.zig");
const module = @import("module.zig");
const BindNode = @import("frame.zig").BindNode;

pub const BuildContext = struct {
    alloc: std.mem.Allocator,
    arena_alloc: std.mem.Allocator,
    mod: *ui.Module,

    /// Temporary buffers used to build Frames in Widget's `build` function.
    /// Cleared on the next update cycle. FrameIds generated are indexes to this buffer.
    /// Currently, frames are pushed into `frames`, `frame_lists`, and `frame_props` in a depth first order from BuildContext.build.
    /// This may help keep related frames in a subtree together when partial updates is implemented. 
    frames: std.ArrayList(ui.Frame),
    // One ArrayList is used to store multiple frame lists.
    // Appends a complete list and returns the start index and size as the key.
    frame_lists: std.ArrayList(ui.FrameId),
    // Stores variable sized Widget props data. Appends props data and returns
    // the start index and size as the key.
    frame_props: stdx.ds.DynamicArrayList(u32, u8),

    /// Temporary frame id buffer.
    frameid_buf: std.ArrayListUnmanaged(ui.FrameId),
    u8_buf: std.ArrayList(u8),

    // Current node.
    node: *ui.Node,

    // Current Frame used. Must use id since pointer could be invalidated.
    frame_id: ui.FrameId,

    pub fn init(alloc: std.mem.Allocator, arena_alloc: std.mem.Allocator, mod: *ui.Module) BuildContext {
        return .{
            .alloc = alloc,
            .arena_alloc = arena_alloc,
            .mod = mod,
            .frames = std.ArrayList(ui.Frame).init(alloc),
            .frame_lists = std.ArrayList(ui.FrameId).init(alloc),
            .frame_props = stdx.ds.DynamicArrayList(u32, u8).init(alloc),
            .u8_buf = std.ArrayList(u8).init(alloc),
            .frameid_buf = .{},
            .node = undefined,
            .frame_id = undefined,
        };
    }

    pub fn deinit(self: *BuildContext) void {
        self.frames.deinit();
        self.frame_lists.deinit();
        self.frame_props.deinit();
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
    pub fn tempRange(self: *BuildContext, count: usize, ctx: anytype, build_fn: fn(@TypeOf(ctx), *BuildContext, u32) ui.FrameId) []const ui.FrameId {
        self.frameid_buf.resize(self.alloc, count) catch fatal();
        var cur: u32 = 0;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const frame_id = build_fn(ctx, self, @intCast(u32, i));
            if (frame_id != ui.NullFrameId) {
                self.frameid_buf.items[cur] = frame_id;
                cur += 1;
            }
        }
        return self.frameid_buf.items[0..cur];
    }

    pub fn range(self: *BuildContext, count: usize, ctx: anytype, build_fn: fn (@TypeOf(ctx), *BuildContext, u32) ui.FrameId) ui.FrameListPtr {
        const start_idx = self.frame_lists.items.len;
        var i: u32 = 0;
        var buf_i: u32 = 0;
        // Preallocate the list so that the frame ids can be layed out contiguously. Otherwise, the frame_lists array runs the risk of being modified by the user build fn.
        // TODO: This is inefficient if the range is mostly a filter, leaving empty frame slots. One way to solve this is to use a separate stack buffer.
        self.frame_lists.resize(self.frame_lists.items.len + count) catch unreachable;
        while (i < count) : (i += 1) {
            const frame_id = build_fn(ctx, self, @intCast(u32, i));
            if (frame_id != ui.NullFrameId) {
                self.frame_lists.items[start_idx + buf_i] = frame_id;
                buf_i += 1;
            }
        }
        return ui.FrameListPtr.init(@intCast(u32, start_idx), buf_i);
    }

    pub fn resetBuffer(self: *BuildContext) void {
        self.frames.clearRetainingCapacity();
        self.frame_lists.clearRetainingCapacity();
        self.frame_props.clearRetainingCapacity();
        self.u8_buf.clearRetainingCapacity();
    }

    pub fn prepareCall(self: *BuildContext, frame_id: ui.FrameId, node: *ui.Node) void {
        self.frame_id = frame_id;
        self.node = node;
    }

    /// Appends formatted string to temporary buffer.
    pub fn fmt(self: *BuildContext, comptime format: []const u8, args: anytype) []const u8 {
        const start = self.u8_buf.items.len;
        std.fmt.format(self.u8_buf.writer(), format, args) catch unreachable;
        return self.u8_buf.items[start..];
    }

    /// Short-hand for createFrame.
    pub inline fn build(self: *BuildContext, comptime Widget: type, props: anytype) ui.FrameId {
        const HasProps = comptime module.WidgetHasProps(Widget);
        if (HasProps) {
            var widget_props: ui.WidgetProps(Widget) = undefined;
            setWidgetProps(Widget, &widget_props, props);
            return self.createFrame(Widget, &widget_props, props);
        } else {
            return self.createFrame(Widget, {}, props);
        }
    }

    pub inline fn list(self: *BuildContext, tuple_or_slice: anytype) ui.FrameListPtr {
        const IsTuple = comptime std.meta.trait.isTuple(@TypeOf(tuple_or_slice));
        if (IsTuple) {
            // createFrameList doesn't support tuples right now because of tuples nested in anonymous struct is bugged,
            // so we convert it to an array.
            const arr: [stdx.meta.TupleLen(@TypeOf(tuple_or_slice))]ui.FrameId = tuple_or_slice;
            return self.createFrameList(arr);
        } else {
            return self.createFrameList(tuple_or_slice);
        }
    }

    pub inline fn fragment(self: *BuildContext, list_: ui.FrameListPtr) ui.FrameId {
        const frame = ui.Frame.init(module.FragmentVTable, null, null, ui.FramePropsPtr.init(0, 0), list_);
        const frame_id = @intCast(ui.FrameId, @intCast(u32, self.frames.items.len));
        self.frames.append(frame) catch unreachable;
        return frame_id;
    }

    pub inline fn fragmentSlice(self: *BuildContext, frames: []const ui.FrameId) ui.FrameId {
        const list_ptr = self.createFrameList(frames);
        return self.fragment(list_ptr);
    }

    /// Allows caller to bind a FrameId to a NodeRef. One frame can be binded to many NodeRefs.
    pub fn bindFrame(self: *BuildContext, frame_id: ui.FrameId, ref: *ui.NodeRef) void {
        if (frame_id != ui.NullFrameId) {
            const frame = &self.frames.items[frame_id];
            const node = self.arena_alloc.create(BindNode) catch fatal();
            node.node_ref = ref;
            node.next = frame.node_binds;
            frame.node_binds = node;
        }
    }

    fn createFrameList(self: *BuildContext, frame_ids: anytype) ui.FrameListPtr {
        const Type = @TypeOf(frame_ids);
        const IsSlice = comptime std.meta.trait.isSlice(Type) and @typeInfo(Type).Pointer.child == ui.FrameId;
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
                if (id != ui.NullFrameId) {
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
        return ui.FrameListPtr.init(start_idx, @intCast(u32, self.frame_lists.items.len) - start_idx);
    }

    pub fn getFrame(self: BuildContext, id: ui.FrameId) ui.Frame {
        return self.frames.items[id];
    }

    fn getFrameList(self: *BuildContext, ptr: ui.FrameListPtr) []const ui.FrameId {
        const end_idx = ptr.id + ptr.len;
        return self.frame_lists.items[ptr.id..end_idx];
    }

    pub fn createFrame(self: *BuildContext, comptime Widget: type, props: ?*ui.WidgetProps(Widget), build_props: anytype) ui.FrameId {
        // log.warn("createFrame {}", .{build_props});
        const BuildProps = @TypeOf(build_props);

        const bind: ?*anyopaque = if (@hasField(BuildProps, "bind")) build_props.bind else null;
        const id = if (@hasField(BuildProps, "id")) stdx.meta.enumLiteralId(build_props.id) else null;

        const props_ptr = b: {
            const HasProps = comptime module.WidgetHasProps(Widget);
            if (HasProps) {
                break :b self.frame_props.append(props.?.*) catch unreachable;
            } else {
                break :b ui.FramePropsPtr.init(0, 0);
            }
        };
        const vtable = module.GenWidgetVTable(Widget);
        var frame = ui.Frame.init(vtable, id, bind, props_ptr, ui.FrameListPtr.init(0, 0));
        if (@hasField(BuildProps, "key")) {
            frame.key = build_props.key;
        }
        if (builtin.mode == .Debug) {
            if (@hasField(BuildProps, "debug")) {
                if (build_props.debug) {
                    frame.debug = true;
                }
            }
        }
        const frame_id = @intCast(ui.FrameId, @intCast(u32, self.frames.items.len));
        self.frames.append(frame) catch unreachable;

        // log.warn("created frame {}", .{frame_id});
        return frame_id;
    }

    pub fn validateBuildProps(comptime Widget: type, build_props: anytype) void {
        const BuildProps = @TypeOf(build_props);
        const HasProps = comptime module.WidgetHasProps(Widget);

        if (@hasField(BuildProps, "bind")) {
            if (stdx.meta.FieldType(BuildProps, .bind) != *ui.WidgetRef(Widget)) {
                @compileError("Expected bind type to be: " ++ @typeName(*ui.WidgetRef(Widget)));
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
            // var res: []const std.builtin.TypeInfo.StructField = &.{};
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
                } else if (!HasProps) {
                    @compileError("No Props type declared in " ++ @typeName(Widget) ++ " for " ++ f.name);
                } else if (@hasField(ui.WidgetProps(Widget), f.name)) {
                    // res = res ++ &[_]std.builtin.TypeInfo.StructField{f};
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
