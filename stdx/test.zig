const std = @import("std");
const t = std.testing;

test {
    const stdx = @import("stdx.zig");
    t.refAllDecls(stdx);
    t.refAllDecls(stdx.ds);
}