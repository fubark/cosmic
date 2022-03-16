const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.scratch);

// Playground to test zig code.
// Run with: zig build test-file -Dpath="test/scratch_test.zig"

// To see what the code will compile to, check out godbolt.org.
// godbolt will compile in debug mode by default. Add "-O ReleaseSafe" if needed.

test {
    t.setLogLevel(.debug);
}