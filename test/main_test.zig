const std = @import("std");

// Main test suite.
test {
    // Nested imports are included for testing if they are used.

    // Separate imports for packages since they are not included implicitly.
    const stdx = @import("../stdx/stdx.zig");
    _ = std.meta.declarations(stdx);

    const parser = @import("../parser/parser.zig");
    _ = std.meta.declarations(parser);
    _ = @import("../parser/parser_simple.test.zig");
    _ = @import("../parser/incremental.test.zig");
}