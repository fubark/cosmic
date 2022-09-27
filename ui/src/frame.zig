const stdx = @import("stdx");
const builtin = @import("builtin");

const NodeRef = @import("ui.zig").NodeRef;

const widget = @import("widget.zig");
const WidgetUserId = widget.WidgetUserId;
const WidgetTypeId = widget.WidgetTypeId;
const WidgetKey = widget.WidgetKey;
const WidgetVTable = widget.WidgetVTable;

pub const FrameId = u32;
pub const NullFrameId = stdx.ds.CompactNull(FrameId);

pub const FrameStyle = union {
    value: FramePropsPtr,
    ptr: *const anyopaque,
};

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
    props: FramePropsPtr,

    /// Type-erased pointer to the style data.
    style: FrameStyle,
    style_is_value: bool,
    has_style: bool,

    /// This is only used by the special Fragment frame which represents multiple frames.
    fragment_children: FrameListPtr,

    debug: if (builtin.mode == .Debug) bool else void,

    pub fn init(vtable: *const WidgetVTable, id: ?WidgetUserId, bind: ?*anyopaque, props: FramePropsPtr, style: FrameStyle, style_is_value: bool, fragment_children: FrameListPtr) Frame {
        return .{
            .vtable = vtable,
            .id = id,
            .widget_bind = bind,
            .node_binds = null,
            .is_bind_func = false,
            .props = props,
            .style = style,
            .style_is_value = style_is_value,
            .has_style = !style_is_value or style.value.len > 0,
            .fragment_children = fragment_children,
            .key = null,
            .tag = null,
            .debug = if (builtin.mode == .Debug) false else {},
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