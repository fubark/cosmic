const std = @import("std");
const t = std.testing;

// Test suite for app and cscript.
test {
    const cscript = @import("../cscript/cscript.zig");
    t.refAllDecls(cscript);
    _ = @import("../cscript/behavior_test.zig");
}