const std = @import("std");
const t = std.testing;

// Test suite for the app.
test {
    _ = @import("../app/behavior_test.zig");
    _ = @import("../app/markdown.zig");
    _ = @import("../app/ui.zig");
}