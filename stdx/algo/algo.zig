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

// For binarySearch, use std.sort.binarySearch

// compare function should return .lt if the target idx is before the current idx.
pub fn binarySearchByIndex(len: usize, target: anytype, ctx: anytype, compare: fn (@TypeOf(ctx), @TypeOf(target), usize) std.math.Order) ?usize {
    var start: usize = 0;
    var end = len;
    while (start < end) {
        const mid = start + (end - start) / 2;
        switch (compare(ctx, target, mid)) {
            .eq => return mid,
            .gt => start = mid + 1,
            .lt => end = mid,
        }
    }
    return null;
}

/// Returns the in-order insert index that would preserve a sorted list for a given insert value.
/// insert value is the first arg in less.
pub fn binarySearchInsertIdx(comptime T: type, arr: []const T, value: T, ctx: anytype, less: fn (@TypeOf(ctx), T, T) bool) usize {
    if (arr.len == 0) {
        return 0;
    }
    var start: usize = 0;
    // end is exclusive.
    var end = arr.len;
    while (start < end) {
        const mid_idx = (start + end) / 2;
        if (less(ctx, value, arr[mid_idx])) {
            end = mid_idx;
        } else {
            start = mid_idx + 1;
        }
    }
    return start;
}

test "binarySearchInsertIdx" {
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{}, 1, {}, std.sort.asc(u32)), 0);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 0, {}, std.sort.asc(u32)), 0);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 1, {}, std.sort.asc(u32)), 1);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 2, {}, std.sort.asc(u32)), 1);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 3, {}, std.sort.asc(u32)), 2);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 4, {}, std.sort.asc(u32)), 2);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 5, {}, std.sort.asc(u32)), 3);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 6, {}, std.sort.asc(u32)), 3);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 7, {}, std.sort.asc(u32)), 4);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 8, {}, std.sort.asc(u32)), 4);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 9, {}, std.sort.asc(u32)), 5);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 1, 3, 5, 7, 9 }, 10, {}, std.sort.asc(u32)), 5);

    // Returns in-order idx.
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 10, 10, 10, 10 }, 10, {}, std.sort.asc(u32)), 4);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 10, 10, 10, 10 }, 9, {}, std.sort.asc(u32)), 0);
    try t.eqT(usize, binarySearchInsertIdx(u32, &[_]u32{ 10, 10, 10, 10 }, 11, {}, std.sort.asc(u32)), 4);
}
