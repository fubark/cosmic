const std = @import("std");
const t = std.testing;

// Main test suite.
test {
    // Nested imports are included for testing if they are used.

    // Separate imports for packages since they are not included implicitly.
    const stdx = @import("../stdx/stdx.zig");
    t.refAllDecls(stdx);
    t.refAllDecls(stdx.ds);

    const parser = @import("../parser/parser.zig");
    t.refAllDecls(parser);
    _ = @import("../parser/parser_simple.test.zig");
    _ = @import("../parser/incremental.test.zig");

    const graphics = @import("../graphics/src/graphics.zig");
    t.refAllDecls(graphics);

    const gl_graphics = @import("../graphics/src/backend/gl/graphics.zig");
    t.refAllDecls(gl_graphics);

    const input = @import("../input/input.zig");
    t.refAllDecls(input);

    const main = @import("../runtime/main.zig");
    t.refAllDecls(main);
}
