const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const walk = @import("walk.zig");
const walk_iterator = @import("walk_iterator.zig");

pub const walkPre = walk.walkPre;
pub const walkPost = walk.walkPost;
pub const walkPreAlloc = walk.walkPreAlloc;
pub const walkPrePost = walk.walkPrePost;
pub const Walker = walk.Walker;
pub const WalkerContext = walk.WalkerContext;
pub const VisitContext = walk.VisitContext;

pub const WalkIterator = walk_iterator.WalkIterator;

const Range = struct {
    start: usize,
    end: usize,
};

// compare function should return .lt if the target idx is before the current idx.
pub fn binarySearchByIndex(len: usize, target: anytype, ctx: anytype, compare: fn (@TypeOf(ctx), @TypeOf(target), usize) std.math.Order) ?usize {
    var rng = Range{ .start = 0, .end = len };
    while (rng.start < rng.end) {
        const mid = rng.start + (rng.end - rng.start) / 2;
        switch (compare(ctx, target, mid)) {
            .eq => return mid,
            .gt => rng.start = mid + 1,
            .lt => rng.end = mid,
        }
    }
    return null;
}

// Used to find insert index in sorted list.
// Finds an index where inserting preserves the sorted list. value at index is <= given value. value at index-1 is >= given value.
pub fn binarySearchInsertIdx(comptime T: type, items: []const T, value: T, ctx: anytype, less: fn (@TypeOf(ctx), T, T) bool) usize {
    if (items.len == 0) {
        return 0;
    }
    // range end is inclusive.
    var rng = Range{ .start = 0, .end = items.len };
    // one less than the rng length.
    var rng_len_m1 = rng.end - rng.start;
    while (rng_len_m1 > 0) {
        // Mid should land on the upper half in an even len so it doesn't revisit the same rng.end idx when rng_len = 2
        const mid_idx = rng.start + rng_len_m1 / 2;
        if (less(ctx, value, items[mid_idx])) {
            rng.end = mid_idx;
        } else {
            rng.start = mid_idx + 1;
        }
        rng_len_m1 = rng.end - rng.start;
    }
    return rng.start;
}

test "binarySearchInsertIdx" {
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{}, 1, {}, std.sort.asc(u32)), 0);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 2, 3, 4, 5 }, 1, {}, std.sort.asc(u32)), 1);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 2, 3, 4, 5 }, 2, {}, std.sort.asc(u32)), 2);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 2, 3, 4, 5 }, 3, {}, std.sort.asc(u32)), 3);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 2, 3, 4, 5 }, 4, {}, std.sort.asc(u32)), 4);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 2, 3, 4, 5 }, 5, {}, std.sort.asc(u32)), 5);
}
