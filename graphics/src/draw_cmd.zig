const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics.zig");
const log = stdx.log.scoped(.draw_cmd);

// Draw calls serialized into data.
// This is useful for parsing svg files into draw calls.
// In the future, it might be useful for a library consumer to cache draw calls.

pub const DrawCommandList = struct {
    alloc: ?std.mem.Allocator,
    extra_data: []const f32,
    cmd_data: []const f32,
    cmds: []DrawCommandPtr,

    // For commands that have sub commands like SVG path.
    sub_cmds: []const u8,

    pub fn deinit(self: DrawCommandList) void {
        if (self.alloc) |alloc| {
            alloc.free(self.cmd_data);
            alloc.free(self.cmds);
            alloc.free(self.extra_data);
            alloc.free(self.sub_cmds);
        }
    }

    pub fn getCommand(self: DrawCommandList, comptime Tag: DrawCommand, ptr: DrawCommandPtr) DrawCommandData(Tag) {
        return @ptrCast(*const DrawCommandData(Tag), self.cmd_data[ptr.id..][0 .. @sizeOf(DrawCommandData(Tag)) / 4]).*;
    }

    pub fn getExtraData(self: DrawCommandList, start_id: u32, len: u32) []const f32 {
        return self.extra_data[start_id .. start_id + len];
    }
};

pub fn dump(list: DrawCommandList) void {
    log.debug("DrawCommandList: {} cmds", .{list.cmds.len});
    for (list.cmds) |ptr| {
        switch (ptr.tag) {
            .FillColor => {
                const cmd = list.getCommand(.FillColor, ptr);
                const color = graphics.Color.fromU32(cmd.rgba);
                log.debug("fillColor {}, {}, {}, {}", .{color.channels.r, color.channels.g, color.channels.b, color.channels.a});
            },
            .FillPolygon => {
                const cmd = list.getCommand(.FillPolygon, ptr);
                const slice = list.getExtraData(cmd.start_vertex_id, cmd.num_vertices * 2);
                const poly = @ptrCast([*]const stdx.math.Vec2, slice.ptr)[0..cmd.num_vertices];
                log.debug("fillPolygon {any}", .{poly});
            },
            .FillPath => {
                const cmd = list.getCommand(.FillPath, ptr);
                var end = cmd.start_path_cmd_id + cmd.num_cmds;
                log.debug("fillSvgPath", .{});
                dumpSvgPath(.{
                    .alloc = null,
                    .data = list.extra_data[cmd.start_data_id..],
                    .cmds = std.mem.bytesAsSlice(graphics.svg.PathCommand, list.sub_cmds)[cmd.start_path_cmd_id..end],
                });
            },
            .FillRect => {
                const cmd = list.getCommand(.FillRect, ptr);
                log.debug("fillRect {} {} {} {}", .{cmd.x, cmd.y, cmd.width, cmd.height});
            },
        }
    }
}

pub fn dumpSvgPath(path: graphics.svg.SvgPath) void {
    for (path.cmds) |cmd| {
        switch (cmd) {
            else => {
                log.debug("{}", .{cmd});
            },
        }
    }
}

fn DrawCommandData(comptime Tag: DrawCommand) type {
    return switch (Tag) {
        .FillColor => FillColorCommand,
        .FillPolygon => FillPolygonCommand,
        .FillPath => FillPathCommand,
        .FillRect => FillRectCommand,
    };
}

pub const DrawCommandPtr = struct {
    id: u32,
    tag: DrawCommand,
};

// TODO: We'll add more as we need them.
const DrawCommand = enum {
    FillColor,
    FillPolygon,
    FillPath,
    FillRect,
};

pub const FillColorCommand = struct {
    rgba: u32,
};

pub const FillPolygonCommand = struct {
    num_vertices: u32,
    start_vertex_id: u32,
};

pub const FillPathCommand = struct {
    num_cmds: u32,
    start_path_cmd_id: u32,
    start_data_id: u32,
};

pub const FillRectCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
