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
    renderNode(mod, mod.root_node.?, 0, 0);
}

fn renderNode(mod: *Module, node: *Node, abs_x: f32, abs_y: f32) void {
    // log.debug("render {}", .{node.type_id});
    node.abs_pos = .{
        .x = abs_x + node.layout.x,
        .y = abs_y + node.layout.y,
    };

    const vtable = node.vtable;

    mod.render_ctx.node = node;
    vtable.render(node.widget, &mod.render_ctx);

    for (node.children.items) |it| {
        renderNode(mod, it, node.abs_pos.x, node.abs_pos.y);
    }

    if (vtable.has_post_render) {
        mod.render_ctx.node = node;
        vtable.postRender(node.widget, &mod.render_ctx);
    }
}