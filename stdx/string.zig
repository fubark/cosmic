const std = @import("std");
const ds = @import("ds/ds.zig");
const Allocator = std.mem.Allocator;

// Wrapper around std. Might add support for UTF-8 in the future.

pub const StringHash = struct {
    len: u32,
    hash: u64,

    pub fn init(str: []const u8) StringHash {
        return .{
            .len = @intCast(u32, str.len),
            .hash = std.hash.Wyhash.hash(0, str),
        };
    }

    pub fn eqStringHash(self: StringHash, str: []const u8) bool {
        if (self.len != str.len) {
            return false;
        }
        return self.hash == std.hash.Wyhash.hash(0, str);
    }
};

pub const BoxString = ds.Box([]const u8);

pub inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub inline fn startsWith(str: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, str, prefix);
}

pub inline fn endsWith(str: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, str, suffix);
}

pub inline fn trimLeft(str: []const u8, to_remove: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, to_remove);
}

pub inline fn trimRight(str: []const u8, to_remove: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, to_remove);
}

pub fn dupe(alloc: Allocator, str: []const u8) ![]const u8 {
    return try alloc.dupe(u8, str);
}

pub fn dupeWrapped(alloc: Allocator, str: []const u8) !BoxString {
    const copy = try alloc.dupe(u8, str);
    return BoxString.init(alloc, copy);
}

pub fn concat(alloc: Allocator, slices: []const []const u8) ![]const u8 {
    return try std.mem.concat(alloc, u8, slices);
}

pub fn indexOfPos(str: []const u8, start_idx: usize, needle: u8) ?usize {
    return std.mem.indexOfScalarPos(u8, str, start_idx, needle);
}

pub fn indexOf(str: []const u8, needle: u8) ?usize {
    return std.mem.indexOfScalar(u8, str, needle);
}

pub fn findIndexOf(str: []const u8, cb: fn (u8) bool) ?usize {
    for (str, 0..) |ch, i| {
        if (cb(ch)) {
            return i;
        }
    }
    return null;
}

pub fn toLower(str: []const u8, dst: []u8) []const u8 {
    return std.ascii.lowerString(dst, str);
}

pub fn toLowerAlloc(alloc: Allocator, str: []const u8) ![]const u8 {
    return try std.ascii.allocLowerString(alloc, str);
}

pub fn splitLines(input: []const u8) std.mem.SplitIterator(u8) {
    return std.mem.split(u8, input, "\n");
}
