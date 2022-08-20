const stdx = @import("stdx");

const ui = @import("ui.zig");
const Module = ui.Module;
const Config = ui.Config;
const Node = ui.Node;
const log = stdx.log.scoped(.render);

/// Renders the widgets from the root.
pub fn render(mod: *Module) void {
    // TODO: Implement render tree to speed up redraws.
    // TODO: Implement draw lists.
    mod.root_node.?.vtable.render(mod.root_node.?, &mod.render_ctx, 0, 0);
}

pub inline fn defaultRenderChildren(node: *Node, ctx: *ui.RenderContext) void {
    for (node.children.items) |it| {
        it.vtable.render(it, ctx, node.abs_bounds.min_x, node.abs_bounds.min_y);
    }
}