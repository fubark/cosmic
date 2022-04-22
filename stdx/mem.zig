const std = @import("std");
const ds = @import("ds/ds.zig");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.mem);

pub fn ptrCastTo(ptr_to_ptr: anytype, from: anytype) void {
    const Ptr = std.meta.Child(@TypeOf(ptr_to_ptr));
    ptr_to_ptr.* = @ptrCast(Ptr, from);
}

/// @alignCast seems to be broken (does not insert runtime checks) when passed a comptime int from an expression like @typeInfo(Ptr).Pointer.alignment (for cases where Ptr has a custom alignment, eg. *align(1) u32).
/// Current fix is to branch to common alignments.
pub fn ptrCastAlign(comptime Ptr: type, ptr: anytype) Ptr {
    const alignment = @typeInfo(Ptr).Pointer.alignment;
    switch (alignment) {
        0 => return @ptrCast(Ptr, ptr),
        1 => return @ptrCast(Ptr, @alignCast(1, ptr)),
        2 => return @ptrCast(Ptr, @alignCast(2, ptr)),
        4 => return @ptrCast(Ptr, @alignCast(4, ptr)),
        8 => return @ptrCast(Ptr, @alignCast(8, ptr)),
        else => unreachable,
    }
}

// Same as std.mem.replace except we write to an ArrayList.
pub fn replaceIntoList(comptime T: type, input: []const T, needle: []const T, replacement: []const T, output: *std.ArrayList(T)) usize {
    // Clear the array list.
    output.clearRetainingCapacity();
    var i: usize = 0;
    var slide: usize = 0;
    var replacements: usize = 0;
    while (slide < input.len) {
        if (std.mem.indexOf(T, input[slide..], needle) == @as(usize, 0)) {
            output.appendSlice(replacement) catch unreachable;
            i += replacement.len;
            slide += needle.len;
            replacements += 1;
        } else {
            output.append(input[slide]) catch unreachable;
            i += 1;
            slide += 1;
        }
    }
    return replacements;
}

// Copy to dest, truncates if overflows buffer.
pub fn copyTrunc(src: []const u8, dst: []u8) void {
    const len = std.math.min(dst.len, src.len);
    std.mem.copy(dst[0..len], src[0..len]);
}

pub fn readFloat32Little(ptr: *[4]u8) f32 {
    return @bitCast(f32, std.mem.readIntLittle(u32, ptr));
}

pub fn freeOpaqueWithSize(alloc: std.mem.Allocator, ptr: *ds.Opaque, size: usize) void {
    alloc.free(@ptrCast([*]u8, ptr)[0..size]);
}

pub fn indexOfNth(comptime T: type, haystack: []const T, needle: []const T, n: u32) ?usize {
    var pos: usize = 0;
    var i: u32 = 0;
    while (i <= n) : (i += 1) {
        pos = if (std.mem.indexOfPos(T, haystack, pos, needle)) |new_pos| new_pos + 1 else return null;
    }
    return pos - 1;
}

test "indexOfNth" {
    const s = "\nfoo\nfoo\n";
    try t.eq(indexOfNth(u8, s, "\n", 0), 0);
    try t.eq(indexOfNth(u8, s, "\n", 1), 4);
    try t.eq(indexOfNth(u8, s, "\n", 2), 8);
    try t.eq(indexOfNth(u8, s, "\n", 3), null);
}

pub fn lastIndexOfNth(comptime T: type, haystack: []const T, needle: []const T, n: u32) ?usize {
    var pos: usize = haystack.len - needle.len;
    var i: u32 = 0;
    while (i <= n) : (i += 1) {
        if (lastIndexOfPos(T, haystack, pos, needle)) |new_pos| pos = new_pos +% @bitCast(usize, @intCast(i64, -1)) else return null;
    }
    return pos +% 1;
}

test "lastIndexOfNth" {
    const s = "\nfoo\nfoo\n";
    try t.eq(lastIndexOfNth(u8, s, "\n", 0), 8);
    try t.eq(lastIndexOfNth(u8, s, "\n", 1), 4);
    try t.eq(lastIndexOfNth(u8, s, "\n", 2), 0);
    try t.eq(lastIndexOfNth(u8, s, "\n", 3), null);
}

pub fn lastIndexOfPos(comptime T: type, haystack: []const T, start: usize, needle: []const T) ?usize {
    var i: usize = start;
    if (start > haystack.len - needle.len) {
        return null;
    }
    while (i > 0) : (i -= 1) {
        if (std.mem.eql(T, haystack[i .. i + needle.len], needle)) return i;
    }
    if (std.mem.eql(T, haystack[0..needle.len], needle)) return i else return null;
}
