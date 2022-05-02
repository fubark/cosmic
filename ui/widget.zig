const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;

const ui = @import("ui.zig");
const Layout = ui.Layout;
const RenderContext = ui.RenderContext;
const FrameId = ui.FrameId;

pub const WidgetUserId = usize;
pub const WidgetTypeId = u32;

pub const WidgetKey = union(enum) {
    Idx: usize,
    EnumLiteral: usize,
};

/// Contains the widget and it's corresponding node in the layout tree.
/// Although the widget can be obtained from the node, this is more type safe and can provide convenience functions.
pub fn WidgetRef(comptime T: type) type {
    return struct {
        const Self = @This();

        widget: *T,
        node: *Node,

        pub fn init(widget: *T, node: *Node) Self {
            return .{
                .widget = widget,
                .node = node,
            };
        }

        pub fn getHeight(self: Self) f32 {
            return self.node.layout.height;
        }

        pub fn getWidth(self: Self) f32 {
            return self.node.layout.width;
        }
    };
}

const NullId = stdx.ds.CompactNull(u32);

/// A Node contains the metadata for a widget instance and is initially created from a declared Frame.
pub const Node = struct {
    const Self = @This();

    type_id: WidgetTypeId,

    key: WidgetKey,

    // TODO: Document why a parent reference is useful.
    parent: ?*Node,

    /// Pointer to the widget instance.
    widget: *anyopaque,

    // TODO: This was added to Node for convenience. Since binding is a one time operation, it shouldn't have to carry over from a Frame.
    /// Binds the widget to a WidgetRef upon initialization.
    bind: ?*anyopaque,

    /// The final layout is set by it's parent during the layout phase.
    /// x, y are relative to the parent's position.
    layout: Layout,

    /// Absolute position of the node is computed when traversing the render tree.
    abs_pos: Vec2,

    // TODO: Use a shared buffer.
    /// The child nodes.
    children: std.ArrayList(*Node),

    /// Singly linked lists of events attached to this node. Can be NullId.
    mouse_down_list: u32,
    mouse_up_list: u32,
    key_up_list: u32,
    key_down_list: u32,

    // TODO: Should use a shared hashmap from Module.
    key_to_child: std.AutoHashMap(WidgetKey, *Node),

    pub fn init(self: *Self, alloc: std.mem.Allocator, type_id: WidgetTypeId, parent: ?*Node, key: WidgetKey, widget: *anyopaque) void {
        self.* = .{
            .type_id = type_id,
            .key = key,
            .parent = parent,
            .widget = widget,
            .bind = null,
            .children = std.ArrayList(*Node).init(alloc),
            .layout = undefined,
            .abs_pos = undefined,
            .key_to_child = std.AutoHashMap(WidgetKey, *Node).init(alloc),
            .mouse_down_list = NullId,
            .mouse_up_list = NullId,
            .key_up_list = NullId,
            .key_down_list = NullId,
        };
    }

    pub fn getWidget(self: Self, comptime Widget: type) *Widget {
        return stdx.mem.ptrCastAlign(*Widget, self.widget);
    }

    pub fn deinit(self: *Self) void {
        self.children.deinit();
        self.key_to_child.deinit();
    }

    pub fn numChildren(self: *Self) usize {
        return self.children.items.len;
    }

    pub fn getChild(self: *Self, idx: usize) *Node {
        return self.children.items[idx];
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

    /// Generates the frame for an existing Widget.
    build: fn (widget_ptr: *anyopaque, build_ctx: *anyopaque) FrameId,

    /// Renders an existing Widget.
    render: fn (widget_ptr: *anyopaque, render_ctx: *RenderContext) void,

    /// Render step in post order when traversing the render tree.
    postRender: fn (widget_ptr: *anyopaque, render_ctx: *RenderContext) void,

    /// Computes the layout size for an existing Widget and sets the relative positioning for it's child nodes.
    layout: fn (widget_ptr: *anyopaque, layout_ctx: *anyopaque) LayoutSize,

    /// Destroys an existing Widget.
    destroy: fn (node: *Node, alloc: std.mem.Allocator) void,
};

pub const LayoutSize = struct {
    const Self = @This();

    width: f32,
    height: f32,

    pub fn init(width: f32, height: f32) @This() {
        return .{
            .width = width,
            .height = height,
        };
    }

    pub fn cropTo(self: *Self, max_size: LayoutSize) void {
        if (self.width > max_size.width) {
            self.width = max_size.width;
        }
        if (self.height > max_size.height) {
            self.height = max_size.height;
        }
    }

    pub fn cropToWidth(self: *Self, width: f32) void {
        if (self.width > width) {
            self.width = width;
        }
    }

    pub fn cropToHeight(self: *Self, height: f32) void {
        if (self.height > height) {
            self.height = height;
        }
    }

    pub fn toIncSize(self: Self, inc_width: f32, inc_height: f32) LayoutSize {
        return .{
            .width = self.width + inc_width,
            .height = self.height + inc_height,
        };
    }
};