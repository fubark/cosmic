const std = @import("std");
const stdx = @import("../stdx.zig");
const string = stdx.string;
const t = stdx.testing;

const compact = @import("compact.zig");
pub const CompactUnorderedList = compact.CompactUnorderedList;
pub const CompactSinglyLinkedList = compact.CompactSinglyLinkedList;
pub const CompactManySinglyLinkedList = compact.CompactManySinglyLinkedList;
const complete_tree = @import("complete_tree.zig");
pub const CompleteTreeArray = complete_tree.CompleteTreeArray;
pub const DynamicArrayList = @import("dynamic_array_list.zig").DynamicArrayList;
pub const BitArrayList = @import("bit_array_list.zig").BitArrayList;

// Shared opaque type.
pub const Opaque = opaque{

    pub fn fromPtr(comptime T: type, ptr: T) *Opaque {
        return @ptrCast(*Opaque, ptr);
    }

    pub fn toPtr(comptime T: type, ptr: *Opaque) T {
        return @intToPtr(T, @ptrToInt(ptr));
    }
};

// TODO: Rename to IndexSlice
// Relative slice. Use to reference slice in a growing memory buffer.
pub fn RelSlice(comptime T: type) type {
    return struct {
        start: T,
        end: T,

        pub fn len(self: *const @This()) T {
            return self.end - self.start;
        }
    };
}

// std.StringHashMap except key is duped and managed.
pub fn OwnedKeyStringHashMap(comptime T: type) type {
    return struct {
        const Self = @This();
        alloc: *std.mem.Allocator,
        map: std.StringHashMap(T),

        pub fn init(alloc: *std.mem.Allocator) @This() {
            return .{
                .alloc = alloc,
                .map = std.StringHashMap(T).init(alloc),
            };
        }

        pub fn get(self: *const Self, key: []const u8) ?T {
            return self.map.get(key);
        }

        pub fn keyIterator(self: *Self) std.StringHashMap(T).KeyIterator {
            return self.map.keyIterator();
        }

        pub fn getEntry(self: @This(), key: []const u8) ?std.StringHashMap(T).Entry {
            return self.map.getEntry(key);
        }

        pub fn count(self: @This()) std.StringHashMap(T).Size {
            return self.map.count();
        }

        pub fn getOrPut(self: *@This(), key: []const u8) !std.StringHashMap(T).GetOrPutResult {
            const res = try self.map.getOrPut(key);
            if (!res.found_existing) {
                res.key_ptr.* = string.dupe(self.alloc, key) catch unreachable;
            }
            return res;
        }

        // Use with care, doesn't free existing key.
        pub fn put(self: *@This(), key: []const u8, val: T) !void {
            const key_dupe = try stdx.string.dupe(self.alloc, key);
            errdefer self.alloc.free(key_dupe);
            try self.map.put(key_dupe, val);
        }

        pub fn iterator(self: *const @This()) std.StringHashMap(T).Iterator {
            return self.map.iterator();
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.map.iterator();
            while (iter.next()) |it| {
                self.alloc.free(it.key_ptr.*);
            }
            self.map.deinit();
        }
    };
}

// TODO: Might want a better interface for a hash set. https://github.com/ziglang/zig/issues/6919
pub fn AutoHashSet(comptime Key: type) type {
    return std.AutoHashMap(Key, void);
}