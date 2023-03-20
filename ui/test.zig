const std = @import("std");
const t = std.testing;

test {
    const ui = @import("src/ui.zig");
    t.refAllDecls(ui);
}