const std = @import("std");
const t = std.testing;

test {
    const platform = @import("platform.zig");
    t.refAllDecls(platform);
}