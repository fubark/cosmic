const std = @import("std");
const t = std.testing;

test {
    const graphics = @import("src/graphics.zig");
    t.refAllDecls(graphics);
    t.refAllDecls(graphics.gl);
}