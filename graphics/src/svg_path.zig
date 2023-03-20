const std = @import("std");
const stdx = @import("stdx");

const graphics = @import("graphics.zig");
const svg = graphics.svg;
const SubQuadBez = graphics.curve.SubQuadBez;
const CubicBez = graphics.curve.CubicBez;
const vec2 = stdx.math.Vec2.init;

const log = stdx.log.scoped(.svg_path);

const FlattenBuffer = struct {
    vec2: *std.ArrayListUnmanaged(stdx.math.Vec2),
    vec2_slice: *std.ArrayListUnmanaged(stdx.IndexSlice(u32)),
    qbez: *std.ArrayListUnmanaged(SubQuadBez),
};

pub fn flattenSvgPathStroke(alloc: std.mem.Allocator, buf: FlattenBuffer, path: svg.SvgPath) !void {
    _ = alloc;
    _ = buf;
    _ = path;
    return error.Todo;
}

pub fn flattenSvgPathFill(alloc: std.mem.Allocator, buf: FlattenBuffer, path: svg.SvgPath) !void {
    // log.debug("flattenSvgPathFill {}", .{path.cmds.len});

    // _ = x;
    // _ = y;

    // Accumulate polygons.
    var last_cmd_was_curveto = false;
    var last_control_pt = vec2(0, 0);
    var cur_data_idx: u32 = 0;
    var cur_pt = vec2(0, 0);
    var cur_poly_start: u32 = 0;

    for (path.cmds) |cmd| {
        var cmd_is_curveto = false;
        switch (cmd) {
            .MoveTo => {
                if (buf.vec2.items.len > cur_poly_start + 1) {
                    try buf.vec2_slice.append(alloc, .{
                        .start = cur_poly_start,
                        .end = @intCast(u32, buf.vec2.items.len),
                    });
                } else if (buf.vec2.items.len == cur_poly_start + 1) {
                    // Only one unused point. Remove it.
                    _ = buf.vec2.pop();
                }
                const data = path.getData(.MoveTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.MoveTo)) / 4;
                cur_pt = .{
                    .x = data.x,
                    .y = data.y,
                };
                cur_poly_start = @intCast(u32, buf.vec2.items.len);
                try buf.vec2.append(alloc, cur_pt);
            },
            .MoveToRel => {
                if (buf.vec2.items.len > cur_poly_start + 1) {
                    try buf.vec2_slice.append(alloc, .{
                        .start = cur_poly_start,
                        .end = @intCast(u32, buf.vec2.items.len),
                    });
                } else if (buf.vec2.items.len == cur_poly_start + 1) {
                    // Only one unused point. Remove it.
                    _ = buf.vec2.pop();
                }
                const data = path.getData(.MoveToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.MoveToRel)) / 4;
                cur_pt = .{
                    .x = cur_pt.x + data.x,
                    .y = cur_pt.y + data.y,
                };
                cur_poly_start = @intCast(u32, buf.vec2.items.len);
                try buf.vec2.append(alloc, cur_pt);
            },
            .CurveTo => {
                const data = path.getData(.CurveTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.CurveTo)) / 4;

                const prev_pt = cur_pt;
                cur_pt = .{
                    .x = data.x,
                    .y = data.y,
                };
                last_control_pt = .{
                    .x = data.cb_x,
                    .y = data.cb_y,
                };
                const c_bez = CubicBez{
                    .x0 = prev_pt.x,
                    .y0 = prev_pt.y,
                    .cx0 = data.ca_x,
                    .cy0 = data.ca_y,
                    .cx1 = last_control_pt.x,
                    .cy1 = last_control_pt.y,
                    .x1 = cur_pt.x,
                    .y1 = cur_pt.y,
                };
                c_bez.flatten(0.5, alloc, buf.vec2, buf.qbez);
                cmd_is_curveto = true;
            },
            .CurveToRel => {
                const data = path.getData(.CurveToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.CurveToRel)) / 4;

                last_control_pt = .{
                    .x = cur_pt.x + data.cb_x,
                    .y = cur_pt.y + data.cb_y,
                };
                const prev_pt = cur_pt;
                cur_pt = .{
                    .x = cur_pt.x + data.x,
                    .y = cur_pt.y + data.y,
                };
                const c_bez = CubicBez{
                    .x0 = prev_pt.x,
                    .y0 = prev_pt.y,
                    .cx0 = prev_pt.x + data.ca_x,
                    .cy0 = prev_pt.y + data.ca_y,
                    .cx1 = last_control_pt.x,
                    .cy1 = last_control_pt.y,
                    .x1 = cur_pt.x,
                    .y1 = cur_pt.y,
                };
                c_bez.flatten(0.5, alloc, buf.vec2, buf.qbez);
                cmd_is_curveto = true;
            },
            .LineTo => {
                const data = path.getData(.LineTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.LineTo)) / 4;

                cur_pt = .{
                    .x = data.x,
                    .y = data.y,
                };
                try buf.vec2.append(alloc, cur_pt);
            },
            .LineToRel => {
                const data = path.getData(.LineToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.LineToRel)) / 4;

                cur_pt = .{
                    .x = cur_pt.x + data.x,
                    .y = cur_pt.y + data.y,
                };
                try buf.vec2.append(alloc, cur_pt);
            },
            .EllipticArc => {
                const data = path.getData(.EllipticArcRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.EllipticArc)) / 4;
                // TODO.
                _ = data;
            },
            .EllipticArcRel => {
                const data = path.getData(.EllipticArcRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.EllipticArcRel)) / 4;
                // TODO.
                _ = data;
            },
            .SmoothCurveTo => {
                const data = path.getData(.SmoothCurveTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveTo)) / 4;

                var cx0: f32 = undefined;
                var cy0: f32 = undefined;
                if (last_cmd_was_curveto) {
                    // Reflection of last control point over current pos.
                    cx0 = cur_pt.x + (cur_pt.x - last_control_pt.x);
                    cy0 = cur_pt.y + (cur_pt.y - last_control_pt.y);
                } else {
                    cx0 = cur_pt.x;
                    cy0 = cur_pt.y;
                }
                const prev_pt = cur_pt;
                cur_pt = .{
                    .x = data.x,
                    .y = data.y,
                };
                last_control_pt = .{
                    .x = data.c2_x,
                    .y = data.c2_y,
                };
                const c_bez = CubicBez{
                    .x0 = prev_pt.x,
                    .y0 = prev_pt.y,
                    .cx0 = cx0,
                    .cy0 = cy0,
                    .cx1 = last_control_pt.x,
                    .cy1 = last_control_pt.y,
                    .x1 = cur_pt.x,
                    .y1 = cur_pt.y,
                };
                c_bez.flatten(0.5, alloc, buf.vec2, buf.qbez);
                cmd_is_curveto = true;
            },
            .SmoothCurveToRel => {
                const data = path.getData(.SmoothCurveToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveToRel)) / 4;

                var cx0: f32 = undefined;
                var cy0: f32 = undefined;
                if (last_cmd_was_curveto) {
                    // Reflection of last control point over current pos.
                    cx0 = cur_pt.x + (cur_pt.x - last_control_pt.x);
                    cy0 = cur_pt.y + (cur_pt.y - last_control_pt.y);
                } else {
                    cx0 = cur_pt.x;
                    cy0 = cur_pt.y;
                }
                last_control_pt = .{
                    .x = cur_pt.x + data.c2_x,
                    .y = cur_pt.y + data.c2_y,
                };
                const prev_pt = cur_pt;
                cur_pt = .{
                    .x = cur_pt.x + data.x,
                    .y = cur_pt.y + data.y,
                };
                const c_bez = CubicBez{
                    .x0 = prev_pt.x,
                    .y0 = prev_pt.y,
                    .cx0 = cx0,
                    .cy0 = cy0,
                    .cx1 = last_control_pt.x,
                    .cy1 = last_control_pt.y,
                    .x1 = cur_pt.x,
                    .y1 = cur_pt.y,
                };
                c_bez.flatten(0.5, alloc, buf.vec2, buf.qbez);
                cmd_is_curveto = true;
            },
            .HorzLineToRel => {
                const data = path.getData(.HorzLineToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.HorzLineToRel)) / 4;
                cur_pt.x += data.x;
                try buf.vec2.append(alloc, cur_pt);
            },
            .HorzLineTo => {
                const data = path.getData(.HorzLineTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.HorzLineTo)) / 4;
                cur_pt.x = data.x;
                try buf.vec2.append(alloc, cur_pt);
            },
            .VertLineToRel => {
                const data = path.getData(.VertLineToRel, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineToRel)) / 4;
                cur_pt.y += data.y;
                try buf.vec2.append(alloc, cur_pt);
            },
            .VertLineTo => {
                const data = path.getData(.VertLineTo, cur_data_idx);
                cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineTo)) / 4;
                cur_pt.y = data.y;
                try buf.vec2.append(alloc, cur_pt);
            },
            .ClosePath => {
                // For fills, this is a no-op.
                // For strokes, this would form a seamless connection to the first point.
            },
            else => {
                log.debug("unsupported: {}", .{cmd});
                return error.Unsupported;
            },
        }
        last_cmd_was_curveto = cmd_is_curveto;
    }

    if (buf.vec2.items.len > cur_poly_start + 1) {
        // Push the current polygon.
        try buf.vec2_slice.append(alloc, .{
            .start = cur_poly_start,
            .end = @intCast(u32, buf.vec2.items.len),
        });
    }
}