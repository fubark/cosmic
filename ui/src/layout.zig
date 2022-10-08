const graphics = @import("graphics");
const ui = @import("ui.zig");
const module = @import("module.zig");

pub const LayoutConstraints = struct {
    min_width: f32,
    max_width: f32,
    min_height: f32,
    max_height: f32,
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
    mod: *ui.Module,
    common: *ui.CommonContext,
    gctx: *graphics.Graphics,

    /// Size constraints are set by the parent, and consumed by child widget's `layout`.
    cstr: SizeConstraints,
    node: *ui.Node,

    pub fn init(mod: *ui.Module, gctx: *graphics.Graphics) LayoutContext {
        return .{
            .mod = mod,
            .common = &mod.common.ctx,
            .gctx = gctx,
            .cstr = undefined,
            .node = undefined,
        };
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

    pub usingnamespace module.MixinContextNodeOps(LayoutContext);
    pub usingnamespace module.MixinContextFontOps(LayoutContext);
    pub usingnamespace module.MixinContextStyleOps(LayoutContext);
};