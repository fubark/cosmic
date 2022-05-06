const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

// For tracking existing zig bugs.

// This should crash. Currently it passes.
// test "@alignCast triggers runtime check when taking a comptime expression." {
//     var aligned_addr: usize = 1;
//     const ptr = @intToPtr(*align(1) u32, aligned_addr);
//     const alignment = @typeInfo(*u32).Pointer.alignment;
//     try t.eq(alignment, 4);
//     const unaligned_ptr = @alignCast(alignment, ptr);
//     try t.eq(std.mem.isAligned(@ptrToInt(unaligned_ptr), alignment), false);
// }