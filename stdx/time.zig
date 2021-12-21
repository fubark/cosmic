const std = @import("std");
const builtin = @import("builtin");

const time_wasm = @import("time_wasm.zig");

pub usingnamespace switch (builtin.target.cpu.arch) {
    .wasm32 => struct {
        pub const Timer = time_wasm.Timer;
    },
    else => struct {
        pub const Timer = std.time.Timer;
    },
};

pub const Duration = struct {
    const Self = @This();

    ms: u32,

    pub fn initSecs(secs: f32) Self {
        return .{
            .ms = @floatToInt(u32, secs * 1000),
        };
    }
};
