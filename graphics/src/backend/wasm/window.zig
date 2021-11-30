const window = @import("../../window.zig");
const Config = window.Config;

extern "graphics" fn jsSetCanvasBuffer(width: u32, height: u32) void;

pub const Window = struct {
    const Self = @This();

    id: u32,
    width: u32,
    height: u32,

    pub fn init(config: Config) !Self {
        var res: Self = .{
            .id = undefined,
            .width = @intCast(u32, config.width),
            .height = @intCast(u32, config.height),
        };
        jsSetCanvasBuffer(config.width, config.height);
        return res;
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }
};