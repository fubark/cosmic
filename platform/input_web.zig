const std = @import("std");
const platform = @import("platform.zig");
const KeyCode = platform.KeyCode;

const Map = b: {
    var map: [256]KeyCode = undefined;

    for (map, 0..) |*it, i| {
        @setEvalBranchQuota(100000);
        it.* = std.meta.intToEnum(KeyCode, i) catch .Unknown;
    }

    // Overrides.
    map[37] = .ArrowLeft;
    map[38] = .ArrowUp;

    break :b map;
};

pub inline fn toCanonicalKeyCode(web_code: u8) KeyCode {
    return Map[web_code];
}