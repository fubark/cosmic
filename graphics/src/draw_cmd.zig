const std = @import("std");

// Draw calls serialized into data.
// This is useful for parsing svg files into draw calls.
// In the future, it might be useful for a library consumer to cache draw calls.

pub const DrawCommandList = struct {
    const Self = @This();

    alloc: ?std.mem.Allocator,
    extra_data: []const f32,
    cmd_data: []const f32,
    cmds: []DrawCommandPtr,

    // For commands that have sub commands like SVG path.
    sub_cmds: []const u8,

    pub fn deinit(self: Self) void {
        if (self.alloc) |alloc| {
            alloc.free(self.cmd_data);
            alloc.free(self.cmds);
            alloc.free(self.extra_data);
            alloc.free(self.sub_cmds);
        }
    }

    pub fn getCommand(self: Self, comptime Tag: DrawCommand, ptr: DrawCommandPtr) DrawCommandData(Tag) {
        return @ptrCast(*const DrawCommandData(Tag), self.cmd_data[ptr.id..][0 .. @sizeOf(DrawCommandData(Tag)) / 4]).*;
    }

    pub fn getExtraData(self: Self, start_id: u32, len: u32) []const f32 {
        return self.extra_data[start_id .. start_id + len];
    }
};

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
