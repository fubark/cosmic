const std = @import("std");

const window = @import("window.zig");
const Config = window.Config;

extern "graphics" fn jsSetCanvasBuffer(width: u32, height: u32) void;
extern "graphics" fn jsBeginFrame() void;

pub const Window = struct {
    const Self = @This();

    id: u32,
    width: u32,
    height: u32,

    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        var res: Self = .{
            .id = undefined,
            .width = @intCast(u32, config.width),
            .height = @intCast(u32, config.height),
            .alloc = alloc,
        };
        jsSetCanvasBuffer(config.width, config.height);
        res.graphics.init(alloc);
        return res;
    }

    pub fn deinit(self: Self) void {
        self.graphics.deinit();
        self.alloc.destroy(self.graphics);
    }

    pub fn beginFrame(self: Self) void {
        _ = self;
        jsBeginFrame();
    }

    pub fn endFrame(self: Self) void {
        _ = self;
    }
};
