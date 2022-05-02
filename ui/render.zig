const stdx = @import("stdx");

const ui = @import("ui.zig");
const Module = ui.Module;
const Config = ui.Config;
const Node = ui.Node;
const log = stdx.log.scoped(.render);

/// Renders the widgets from the root.
pub fn render(comptime C: Config, mod: *Module(C)) void {
    // TODO: Implement render tree to speed up redraws.
    // TODO: Implement draw lists.
    renderNode(C, mod, mod.root_node.?, 0, 0);
}

fn renderNode(comptime C: Config, mod: *Module(C), node: *Node, abs_x: f32, abs_y: f32) void {
    // log.debug("render {}", .{node.type_id});
    node.abs_pos = .{
        .x = abs_x + node.layout.x,
        .y = abs_y + node.layout.y,
    };

    const info = Module(C).getWidgetInfo(node.type_id);

    mod.render_ctx.node = node;
    info.vtable.render(node.widget, &mod.render_ctx);

    for (node.children.items) |it| {
        renderNode(C, mod, it, node.abs_pos.x, node.abs_pos.y);
    }

    if (info.has_post_render) {
        mod.render_ctx.node = node;
        info.vtable.postRender(node.widget, &mod.render_ctx);
    }
}