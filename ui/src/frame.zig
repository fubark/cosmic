const stdx = @import("stdx");

const NodeRef = @import("ui.zig").NodeRef;

const widget = @import("widget.zig");
const WidgetUserId = widget.WidgetUserId;
const WidgetTypeId = widget.WidgetTypeId;
const WidgetKey = widget.WidgetKey;
const WidgetVTable = widget.WidgetVTable;

pub const FrameId = u32;
pub const NullFrameId = stdx.ds.CompactNull(FrameId);

/// A frame represents a declaration of a widget instance and is created in each Widget's `build` function.
/// Before the ui engine performs layout, these frames are used to diff against an existing node tree to determine whether a new
/// widget instance is created or updated.
pub const Frame = struct {
    const Self = @This();

    vtable: *const WidgetVTable,

    // TODO: Allow this to be a u32 as well.
    /// Used to map a unique id to the created node.
    id: ?WidgetUserId,

    /// Binds to WidgetRef upon initializing Widget instance.
    widget_bind: ?*anyopaque,

    /// Binds to NodeRefs upon initializing Widget instance.
    node_binds: ?*BindNode,

    /// Used to find an existing node under the same parent.
    /// Should only be of type WidgetKey.EnumLiteral.
    /// WidgetKey.Idx keys are created during the diff op and used as a default key.
    key: ?WidgetKey,

    /// Used to map a common tag to the created node.
    tag: ?[]const u8,

    /// Pointer to the props data.
    props: FramePropsPtr,

    /// This is only used by the special Fragment frame which represents multiple frames.
    fragment_children: FrameListPtr,

    pub fn init(vtable: *const WidgetVTable, id: ?WidgetUserId, bind: ?*anyopaque, props: FramePropsPtr, fragment_children: FrameListPtr) Self {
        return .{
            .vtable = vtable,
            .id = id,
            .widget_bind = bind,
            .node_binds = null,
            .props = props,
            .fragment_children = fragment_children,
            .key = null,
            .tag = null,
        };
    }
};

/// Sized pointer to props data.
pub const FramePropsPtr = stdx.ds.DynamicArrayList(u32, u8).SizedPtr;

/// Represent a list of frames as a slice since the buffer could have been reallocated.
pub const FrameListPtr = struct {
    id: FrameId,
    len: u32,

    pub fn init(id: FrameId, len: u32) @This() {
        return .{ .id = id, .len = len };
    }
};

/// Allows more than one builder to bind to a frame.
pub const BindNode = struct {
    node_ref: *NodeRef,
    next: ?*BindNode,
};