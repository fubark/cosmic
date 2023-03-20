const stdx = @import("stdx");
const builtin = @import("builtin");

const NodeRef = @import("ui.zig").NodeRef;
const module = @import("module.zig");

const widget = @import("widget.zig");
const WidgetUserId = widget.WidgetUserId;
const WidgetTypeId = widget.WidgetTypeId;
const WidgetKey = widget.WidgetKey;
const WidgetVTable = widget.WidgetVTable;

pub const FrameId = u32;
const NullFrameId = stdx.ds.CompactNull(FrameId);

/// A frame represents a declaration of a widget instance and is created in each Widget's `build` function.
/// Before the ui engine performs layout, these frames are used to diff against an existing node tree to determine whether a new
/// widget instance is created or updated.
pub const Frame = struct {
    vtable: *const WidgetVTable,

    // TODO: Allow this to be a u32 as well.
    /// Used to map a unique id to the created node.
    id: ?WidgetUserId,

    /// Binds to WidgetRef upon initializing Widget instance.
    widget_bind: ?*anyopaque,
    is_bind_func: bool,

    /// Binds to NodeRefs upon initializing Widget instance.
    node_binds: ?*BindNode,

    /// Used to find an existing node under the same parent.
    /// Should only be of type WidgetKey.EnumLiteral.
    /// WidgetKey.Idx keys are created during the diff op and used as a default key.
    key: ?WidgetKey,

    /// Used to map a common tag to the created node.
    tag: ?[]const u8,

    /// Type-erased pointer to the props data.
    props: ?*anyopaque,

    /// Type-erased pointer to the style data.
    style: ?*const anyopaque,
    style_is_owned: bool,

    /// This is only used by the special Fragment frame which represents multiple frames.
    fragment_children: FrameListPtr,

    debug: if (builtin.mode == .Debug) bool else void,

    pub fn init(vtable: *const WidgetVTable, id: ?WidgetUserId, bind: ?*anyopaque, props: ?*anyopaque, style: ?*const anyopaque, style_is_owned: bool, fragment_children: FrameListPtr) Frame {
        return .{
            .vtable = vtable,
            .id = id,
            .widget_bind = bind,
            .node_binds = null,
            .is_bind_func = false,
            .props = props,
            .style = style,
            .style_is_owned = style_is_owned,
            .fragment_children = fragment_children,
            .key = null,
            .tag = null,
            .debug = if (builtin.mode == .Debug) false else {},
        };
    }
};

pub const FramePtr = struct {
    id: FrameId = NullFrameId,

    pub fn init(id: FrameId) FramePtr {
        return .{ .id = id };
    }

    pub fn destroy(self: FramePtr) void {
        if (self.id != NullFrameId) {
            module.gbuild_ctx.releaseFrame(self.id);
        }
    }

    pub fn get(self: FramePtr) Frame {
        return module.gbuild_ctx.frames.getNoCheck(self.id);
    }

    pub fn getPtr(self: FramePtr) *Frame {
        return module.gbuild_ctx.frames.getPtrNoCheck(self.id);
    }

    pub inline fn isNull(self: FramePtr) bool {
        return self.id == NullFrameId;
    }

    pub inline fn isPresent(self: FramePtr) bool {
        return self.id != NullFrameId;
    }

    pub fn dupe(self: FramePtr) FramePtr {
        if (self.id == NullFrameId) {
            return .{};
        } else {
            module.gbuild_ctx.frames.incRef(self.id);
            return self;
        }
    }
};

pub const FrameListId = u32;
const NullFrameListId = stdx.ds.CompactNull(FrameListId);

pub const FrameListPtr = struct {
    id: FrameListId = NullFrameListId,

    pub fn init(id: FrameListId) FrameListPtr {
        return .{ .id = id };
    }

    pub fn destroy(self: FrameListPtr) void {
        if (self.id != NullFrameListId) {
            module.gbuild_ctx.releaseFrameList(self.id);
        }
    }

    pub fn get(self: FrameListPtr) stdx.ds.SLLUnmanaged(FramePtr) {
        return module.gbuild_ctx.frame_lists.getNoCheck(self.id);
    }

    pub fn getPtr(self: FrameListPtr) *stdx.ds.SLLUnmanaged(FramePtr) {
        return module.gbuild_ctx.frame_lists.getPtrNoCheck(self.id);
    }

    pub inline fn isNull(self: FrameListPtr) bool {
        return self.id == NullFrameListId;
    }

    pub inline fn isPresent(self: FrameListPtr) bool {
        return self.id != NullFrameListId;
    }

    pub fn size(self: FrameListPtr) usize {
        if (self.id == NullFrameListId) {
            return 0;
        } else {
            return module.gbuild_ctx.getFrameList(self.id).size();
        }
    }

    pub fn dupe(self: FrameListPtr) FrameListPtr {
        if (self.id == NullFrameListId) {
            return .{};
        } else {
            module.gbuild_ctx.frame_lists.incRef(self.id);
            return self;
        }
    }
};

/// Allows more than one builder to bind to a frame.
pub const BindNode = struct {
    node_ref: *NodeRef,
    next: ?*BindNode,
};