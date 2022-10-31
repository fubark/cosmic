const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const Vec2 = stdx.math.Vec2;

const ui = @import("ui.zig");
const log = stdx.log.scoped(.widget);

/// Id can be an enum literal that is given a unique id at comptime.
pub const WidgetUserId = usize;

pub const WidgetTypeId = usize;

pub const WidgetKey = union(enum) {
    /// This is automatically given to a widget by default.
    ListIdx: usize,
    /// Key generated from enum literals using stdx.meta.enumLiteralId.
    EnumLiteral: usize,
    /// Custom id.
    Id: usize,
};

pub fn WidgetKeyId(id: usize) WidgetKey {
    return WidgetKey{
        .Id = id,
    };
}

/// If the user does not have the access to a widget's type, NodeRef still allows capturing the created Node.
/// Memory layout should match WidgetRef.
pub const NodeRef = struct {
    node: *Node = undefined,
    binded: bool = false,

    pub fn init(node: *Node) NodeRef {
        return .{
            .node = node,
            .binded = true,
        };
    }
};

pub const BindNodeFunc = struct {
    ctx: ?*anyopaque,
    func: fn (ctx: ?*anyopaque, node: *Node, bind: bool) void,
};

pub const NodeRefMap = struct {
    alloc: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(WidgetKey, *Node),
    bind: ui.BindNodeFunc,

    pub fn init(self: *NodeRefMap, alloc: std.mem.Allocator) void {
        self.* = .{
            .alloc = alloc,
            .map = .{},
            .bind = BindNodeFunc{
                .ctx = self,
                .func = bind,
            },
        };
    }

    pub fn deinit(self: *NodeRefMap) void {
        self.map.deinit(self.alloc);
    }

    fn bind(ptr: ?*anyopaque, node: *ui.Node, bind_: bool) void {
        const self = stdx.ptrCastAlign(*NodeRefMap, ptr);
        if (bind_) {
            self.map.put(self.alloc, node.key, node) catch fatal();
        } else {
            var iter = self.map.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.* == node) {
                    _ = self.map.remove(entry.key_ptr.*);
                    break;
                }
            }
        }
    }

    pub fn getNode(self: NodeRefMap, key: WidgetKey) ?*Node {
        return self.map.get(key);
    }

    pub fn getRef(self: NodeRefMap, key: WidgetKey) ?NodeRef {
        if (self.map.get(key)) |node| {
            return NodeRef.init(node);
        } else return null;
    }
};

/// Contains the widget and it's corresponding node in the layout tree.
/// Although the widget can be obtained from the node, this is more type safe and can provide convenience functions.
pub fn WidgetRef(comptime Widget: type) type {
    return struct {
        /// Use widget's *anyopaque pointer in node to avoid "depends on itself" when WidgetRef(Widget) is declared in Widget.
        node: *Node = undefined,

        binded: bool = false,

        const WidgetRefT = @This();

        pub fn init(node: *Node) WidgetRefT {
            return .{
                .node = node,
                .binded = true,
            };
        }

        pub const widget = getWidget;

        pub inline fn getWidget(self: WidgetRefT) *Widget {
            return stdx.ptrCastAlign(*Widget, self.node.widget);
        }

        pub inline fn key(self: WidgetRefT) WidgetKey {
            return self.node.key;
        }

        pub inline fn keyId(self: WidgetRefT) usize {
            return self.node.key.Id;
        }

        pub inline fn getAbsBounds(self: *WidgetRefT) stdx.math.BBox {
            return self.node.abs_bounds;
        }

        pub inline fn getHeight(self: WidgetRefT) f32 {
            return self.node.layout.height;
        }

        pub inline fn getWidth(self: WidgetRefT) f32 {
            return self.node.layout.width;
        }
    };
}

const NullId = stdx.ds.CompactNull(u32);

pub const NodeStateMasks = struct {
    /// Indicates the node is currently in a mouse hovered state.
    pub const hovered: u8 =   0b00000001;
    /// Indicates the node is already matched to a child index during tree diff.
    pub const diff_used: u8 = 0b00000010;
    /// Indicates the node's bind ptr is a *BindNodeFunc.
    pub const bind_func: u8 = 0b00000100;
    /// Node has a user style. If true, the erased UserStyle pointer can be accessed from the module map.
    pub const user_style: u8 = 0b00001000;
    /// Node has a computed style. If true, the erased Style pointer can be accessed from the module map.
    pub const computed_style: u8 = 0b00010000;
};

pub const EventHandlerMasks = struct {
    pub const mousedown: u16 = 1 << 1;
    pub const enter_mousedown: u16 = 1 << 2;
    pub const mouseup: u16 = 1 << 3;
    pub const global_mouseup: u16 = 1 << 4;
    pub const global_mousemove: u16 = 1 << 5;
    pub const hoverchange: u16 = 1 << 6;
    pub const keyup: u16 = 1 << 7;
    pub const keydown: u16 = 1 << 8;
    pub const mousewheel: u16 = 1 << 9;
};

/// A Node contains the metadata for a widget instance and is initially created from a declared Frame.
pub const Node = struct {
    /// The vtable is also used to id the widget instance.
    vtable: *const WidgetVTable,

    key: WidgetKey,

    /// Having a chain of parents helps determine what top level group a source widget belongs to. (eg. Determine which overlay group to add to)
    /// It also helps compute the abs bounds for a widget before the render step. (eg. For popover placement.)
    parent: ?*Node,

    /// Pointer to the widget instance.
    widget: *anyopaque,

    /// If the Widget has props, the node owns a reference to the Frame that contains the props.
    frame: ui.FramePtr,

    /// Is only defined if has_widget_id = true.
    id: WidgetUserId,

    /// Binds the widget to a WidgetRef upon initialization. This is later used to unbind during the destroy step.
    bind: ?*anyopaque,

    /// The final layout is set by it's parent during the layout phase.
    /// x, y are relative to the parent's position.
    layout: ui.Layout,

    /// Absolute bounds of the node is computed when traversing the render tree.
    abs_bounds: stdx.math.BBox,

    // TODO: Use a shared buffer.
    /// The child nodes.
    children: std.ArrayList(*Node),

    /// Unmanaged slice of child event ordering. Only defined if has_child_event_ordering = true.
    child_event_ordering: []const *Node,

    /// TODO: Each node tracks it's own theme so that partially building widgets can get the theme easily.
    // theme_id: u32,

    /// Indicates which events this widget is currently listening for.
    event_handler_mask: u16,

    /// Various boolean states for the node.
    state_mask: u8,

    // TODO: Should use a shared hashmap from Module.
    key_to_child: std.AutoHashMap(WidgetKey, *Node),

    has_child_event_ordering: bool,

    has_widget_id: bool,

    debug: if (builtin.mode == .Debug) bool else void,

    pub fn init(self: *Node, alloc: std.mem.Allocator, vtable: *const WidgetVTable, parent: ?*Node, key: WidgetKey, widget: *anyopaque) void {
        self.* = .{
            .vtable = vtable,
            .key = key,
            .parent = parent,
            .widget = widget,
            .frame = .{},
            .bind = null,
            .children = std.ArrayList(*Node).init(alloc),
            .child_event_ordering = undefined,
            .layout = undefined,
            .abs_bounds = stdx.math.BBox.initZero(),
            .key_to_child = std.AutoHashMap(WidgetKey, *Node).init(alloc),
            // .theme_id = NullId,
            .state_mask = 0,
            .event_handler_mask = 0,
            .has_child_event_ordering = false,
            .id = undefined,
            .has_widget_id = false,
            .debug = if (builtin.mode == .Debug) false else {},
        };
    }

    /// Caller still owns ordering afterwards.
    pub fn setChildEventOrdering(self: *Node, ordering: []const *Node) void {
        self.child_event_ordering = ordering;
        self.has_child_event_ordering = true;
    }

    pub fn getWidget(self: Node, comptime Widget: type) *Widget {
        return stdx.ptrCastAlign(*Widget, self.widget);
    }

    pub fn deinit(self: *Node) void {
        self.children.deinit();
        self.key_to_child.deinit();
    }

    /// Returns the number of immediate children.
    pub fn numChildren(self: *Node) usize {
        return self.children.items.len;
    }

    /// Returns the total number of children recursively.
    pub fn numChildrenR(self: *Node) usize {
        var total = self.children.items.len;
        for (self.children.items) |child| {
            total += child.numChildrenR();
        }
        return total;
    }

    pub fn getChild(self: *Node, idx: usize) *Node {
        return self.children.items[idx];
    }

    /// Depth-first search of the first child that has the specified widget type.
    pub fn findChild(self: *Node, comptime Widget: type) ?WidgetRef(Widget) {
        if (findChildRec(self, ui.GenWidgetVTable(Widget))) |node| {
            return WidgetRef(Widget).init(node);
        } else return null;
    }

    fn findChildRec(cur: *Node, vtable: *const WidgetVTable) ?*Node {
        for (cur.children.items) |child| {
            if (child.vtable == vtable) {
                return child;
            }
            if (findChildRec(child, vtable)) |res| {
                return res;
            }
        }
        return null;
    }

    /// Compute the absolute position of the node by adding up it's ancestor positions.
    /// This is only accurate if the layout has been computed for this node and upwards.
    pub fn computeAbsPos(self: Node) Vec2 {
        if (self.parent) |parent| {
            return parent.computeAbsPos().add(Vec2.init(self.layout.x, self.layout.y));
        } else {
            return Vec2.init(self.layout.x, self.layout.y);
        }
    }

    pub fn computeAbsBounds(self: Node) stdx.math.BBox {
        const abs_pos = self.computeAbsPos();
        return stdx.math.BBox.init(abs_pos.x, abs_pos.y, abs_pos.x + self.layout.width, abs_pos.y + self.layout.height);
    }

    pub fn getAbsBounds(self: Node) stdx.math.BBox {
        return self.abs_bounds;
    }

    pub inline fn clearHandlerMask(self: *Node, mask: u16) void {
        self.event_handler_mask &= ~mask;
    }

    pub inline fn setHandlerMask(self: *Node, mask: u16) void {
        self.event_handler_mask |= mask;
    }

    pub inline fn hasHandler(self: Node, mask: u16) bool {
        return self.event_handler_mask & mask > 0;
    }

    pub inline fn clearStateMask(self: *Node, mask: u8) void {
        self.state_mask &= ~mask;
    }

    pub inline fn setStateMask(self: *Node, mask: u8) void {
        self.state_mask |= mask;
    }

    pub inline fn hasState(self: Node, mask: u8) bool {
        return self.state_mask & mask > 0;
    }

    pub fn dumpPath(self: Node) void {
        log.debug("{s} {}", .{self.vtable.name, self.children.items.len});
        if (self.parent) |parent| {
            parent.dumpPath();
        }
    }
};

/// VTable for a Widget.
pub const WidgetVTable = struct {

    /// Creates a new Widget on the heap and returns the pointer.
    create: fn (mod: *ui.Module, node: *Node, framePtr: ui.FramePtr, frame: ui.Frame) *anyopaque,

    /// Runs post init on an existing Widget.
    postInit: fn (widget_ptr: *anyopaque, init_ctx: *ui.InitContext) void,

    /// Updates the props on an existing Widget.
    updateProps: fn (mod: *ui.Module, node: *Node, framePtr: ui.FramePtr, frame: ui.Frame, ctx: *ui.UpdateContext) void,

    /// Runs post update.
    postUpdate: fn (node: *Node, ctx: *ui.UpdateContext) void,

    /// Generates the frame for an existing Widget.
    build: fn (widget_ptr: *anyopaque, build_ctx: *ui.BuildContext) ui.FramePtr,

    /// Renders an existing Widget.
    render: fn (node: *Node, render_ctx: *ui.RenderContext, parent_abs_x: f32, parent_abs_y: f32) void,

    /// Computes the layout size for an existing Widget and sets the relative positioning for it's child nodes.
    layout: fn (widget_ptr: *anyopaque, ctx: *ui.LayoutContext) ui.LayoutSize,

    /// Destroys an existing Widget.
    destroy: fn (mod: *ui.Module, node: *Node) void,

    deinitFrame: fn (mod: *ui.Module, frame: ui.Frame) void,

    name: []const u8,

    has_post_update: bool,

    /// Whether the children of this widget can have overlapping bounds. eg. ZStack.
    /// If no children can overlap, mouse events propagate down the widget tree on the first child hit.
    /// If children can overlap, mouse events continue to check silbing hits until `stop` is returned from a handler.
    children_can_overlap: bool,
};