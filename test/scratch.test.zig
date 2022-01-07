const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.scratch);

// Playground to test zig code.
// Run with "zig build test-file -Dpath=test/scratch.test.zig"

test {
    t.setLogLevel(.debug);
}
