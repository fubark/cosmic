const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;

const ui = @import("ui.zig");
const Layout = ui.Layout;
const RenderContext = ui.RenderContext;
const FrameId = ui.FrameId;

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

/// If the user does not have the access to a widget's type, NodeRef still allows capturing the creating Node.
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
            return stdx.mem.ptrCastAlign(*Widget, self.node.widget);
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

/// A Node contains the metadata for a widget instance and is initially created from a declared Frame.
pub const Node = struct {
    /// The vtable is also used to id the widget instance.
    vtable: *const WidgetVTable,

    key: WidgetKey,

    // TODO: Document why a parent reference is useful.
    parent: ?*Node,

    /// Pointer to the widget instance.
    widget: *anyopaque,

    /// Is only defined if has_widget_id = true.
    id: WidgetUserId,

    // TODO: This was added to Node for convenience. Since binding is a one time operation, it shouldn't have to carry over from a Frame.
    /// Binds the widget to a WidgetRef upon initialization.
    bind: ?*anyopaque,

    /// The final layout is set by it's parent during the layout phase.
    /// x, y are relative to the parent's position.
    layout: Layout,

    /// Absolute bounds of the node is computed when traversing the render tree.
    abs_bounds: stdx.math.BBox,

    // TODO: Use a shared buffer.
    /// The child nodes.
    children: std.ArrayList(*Node),

    /// Unmanaged slice of child event ordering. Only defined if has_child_event_ordering = true.
    child_event_ordering: []const *Node,

    // TODO: It might be better to keep things simple and only allow one callback per event type per node. If the widget wants more they can multiplex in their implementation.
    /// Singly linked lists of events attached to this node. Can be NullId.
    mouse_down_list: u32,
    mouse_up_list: u32,
    mouse_scroll_list: u32,
    key_up_list: u32,
    key_down_list: u32,

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
            .bind = null,
            .children = std.ArrayList(*Node).init(alloc),
            .child_event_ordering = undefined,
            .layout = undefined,
            .abs_bounds = stdx.math.BBox.init(),
            .key_to_child = std.AutoHashMap(WidgetKey, *Node).init(alloc),
            .mouse_down_list = NullId,
            .mouse_up_list = NullId,
            .mouse_scroll_list = NullId,
            .key_up_list = NullId,
            .key_down_list = NullId,
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
        return stdx.mem.ptrCastAlign(*Widget, self.widget);
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

    /// Compute the absolute position of the node by adding up it's ancestor positions.
    /// This is only accurate if the layout has been computed for this node and upwards.
    pub fn computeCurrentAbsPos(self: Node) Vec2 {
        if (self.parent) |parent| {
            return parent.computeCurrentAbsPos().add(Vec2.init(self.layout.x, self.layout.y));
        } else {
            return Vec2.init(self.layout.x, self.layout.y);
        }
    }

    pub fn getAbsBounds(self: Node) stdx.math.BBox {
        return self.abs_bounds;
    }
};

/// VTable for a Widget.
pub const WidgetVTable = struct {

    /// Creates a new Widget on the heap and returns the pointer.
    create: fn (alloc: std.mem.Allocator, node: *Node, init_ctx: *anyopaque, props_ptr: ?[*]const u8) *anyopaque,

    /// Runs post init on an existing Widget.
    postInit: fn (widget_ptr: *anyopaque, init_ctx: *anyopaque) void,

    /// Updates the props on an existing Widget.
    updateProps: fn (widget_ptr: *anyopaque, props_ptr: [*]const u8) void,

    /// Runs post update.
    postUpdate: fn (node: *Node) void,

    /// Generates the frame for an existing Widget.
    build: fn (widget_ptr: *anyopaque, build_ctx: *anyopaque) FrameId,

    /// Renders an existing Widget.
    render: fn (node: *Node, render_ctx: *RenderContext, parent_abs_x: f32, parent_abs_y: f32) void,

    /// Computes the layout size for an existing Widget and sets the relative positioning for it's child nodes.
    layout: fn (widget_ptr: *anyopaque, layout_ctx: *anyopaque) LayoutSize,

    /// Destroys an existing Widget.
    destroy: fn (node: *Node, alloc: std.mem.Allocator) void,

    name: []const u8,

    has_post_update: bool,
};

pub const LayoutSize = struct {
    width: f32,
    height: f32,

    pub fn init(width: f32, height: f32) LayoutSize {
        return .{
            .width = width,
            .height = height,
        };
    }

    pub fn growToMin(self: *LayoutSize, cstr: ui.SizeConstraints) void {
        if (self.width < cstr.min_width) {
            self.width = cstr.min_width;
        }
        if (self.height < cstr.min_height) {
            self.height = cstr.min_height;
        }
    }

    pub fn growToWidth(self: *LayoutSize, width: f32) void {
        if (self.width < width) {
            self.width = width;
        }
    }

    pub fn growToHeight(self: *LayoutSize, height: f32) void {
        if (self.height < height) {
            self.height = height;
        }
    }

    pub fn limitToMinMax(self: *LayoutSize, cstr: ui.SizeConstraints) void {
        self.growToMin(cstr);
        self.cropToMax(cstr);
    }

    pub fn cropToMax(self: *LayoutSize, cstr: ui.SizeConstraints) void {
        if (self.width > cstr.max_width) {
            self.width = cstr.max_width;
        }
        if (self.height > cstr.max_height) {
            self.height = cstr.max_height;
        }
    }

    pub fn cropTo(self: *LayoutSize, max_size: LayoutSize) void {
        if (self.width > max_size.width) {
            self.width = max_size.width;
        }
        if (self.height > max_size.height) {
            self.height = max_size.height;
        }
    }

    pub fn cropToWidth(self: *LayoutSize, width: f32) void {
        if (self.width > width) {
            self.width = width;
        }
    }

    pub fn cropToHeight(self: *LayoutSize, height: f32) void {
        if (self.height > height) {
            self.height = height;
        }
    }

    pub fn toIncSize(self: LayoutSize, inc_width: f32, inc_height: f32) LayoutSize {
        return .{
            .width = self.width + inc_width,
            .height = self.height + inc_height,
        };
    }
};