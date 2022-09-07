const std = @import("std");
const stdx = @import("../stdx.zig");
const string = stdx.string;
const t = stdx.testing;

const dense = @import("dense.zig");
pub const DenseHandleList = dense.DenseHandleList;
const pooled = @import("pooled.zig");
pub const PooledHandleList = pooled.PooledHandleList;
pub const PooledHandleSLLBuffer = pooled.PooledHandleSLLBuffer;
pub const PoolIdGenerator = pooled.PoolIdGenerator;
const compact = @import("compact.zig");
pub const CompactSinglyLinkedListNode = compact.CompactSinglyLinkedListNode;
pub const CompactNull = compact.CompactNull;
pub const CompactSinglyLinkedList = compact.CompactSinglyLinkedList;
pub const CompactManySinglyLinkedList = compact.CompactManySinglyLinkedList;
const complete_tree = @import("complete_tree.zig");
pub const CompleteTreeArray = complete_tree.CompleteTreeArray;
pub const DynamicArrayList = @import("dynamic_array_list.zig").DynamicArrayList;
pub const BitArrayList = @import("bit_array_list.zig").BitArrayList;
const box = @import("box.zig");
pub const Box = box.Box;
pub const SizedBox = box.SizedBox;
pub const RbTree = @import("rb_tree.zig").RbTree;
pub const Queue = @import("queue.zig").Queue;
pub const SinglyLinkedList = @import("linked_list.zig").SinglyLinkedList;

// Shared opaque type.
pub const Opaque = opaque {
    pub fn fromPtr(comptime T: type, ptr: T) *Opaque {
        return @ptrCast(*Opaque, ptr);
    }

    pub fn toPtr(comptime T: type, ptr: *Opaque) T {
        return @intToPtr(T, @ptrToInt(ptr));
    }
};

/// Slice that holds indexes instead of pointers. Use to reference slice in a growing memory buffer.
pub fn IndexSlice(comptime T: type) type {
    return struct {
        start: T,
        end: T,

        pub fn init(start: T, end: T) @This() {
            return .{
                .start = start,
                .end = end,
            };
        }

        pub fn len(self: *const @This()) T {
            return self.end - self.start;
        }
    };
}

// std.StringHashMap except key is duped and managed.
pub fn OwnedKeyStringHashMap(comptime T: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        map: std.StringHashMap(T),

        pub fn init(alloc: std.mem.Allocator) @This() {
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

        pub fn getEntry(self: Self, key: []const u8) ?std.StringHashMap(T).Entry {
            return self.map.getEntry(key);
        }

        pub fn count(self: Self) std.StringHashMap(T).Size {
            return self.map.count();
        }

        pub fn getOrPut(self: *Self, key: []const u8) !std.StringHashMap(T).GetOrPutResult {
            const res = try self.map.getOrPut(key);
            if (!res.found_existing) {
                res.key_ptr.* = string.dupe(self.alloc, key) catch unreachable;
            }
            return res;
        }

        pub fn put(self: *Self, key: []const u8, val: T) !void {
            const res = try self.map.getOrPut(key);
            if (res.found_existing) {
                res.value_ptr.* = val;
            } else {
                const key_dupe = try self.alloc.dupe(u8, key);
                errdefer self.alloc.free(key_dupe);
                res.key_ptr.* = key_dupe;
                res.value_ptr.* = val;
            }
        }

        pub fn iterator(self: *const Self) std.StringHashMap(T).Iterator {
            return self.map.iterator();
        }

        pub fn deinit(self: *Self) void {
            var iter = self.map.iterator();
            while (iter.next()) |it| {
                self.alloc.free(it.key_ptr.*);
            }
            self.map.deinit();
        }
    };
}

test "OwnedKeyStringHashMap.put doesn't dupe an existing key" {
    var map = OwnedKeyStringHashMap(u32).init(t.alloc);
    defer map.deinit();
    try map.put("foo", 123);
    try map.put("foo", 234);
    // Test should end without memory leak.
}

// TODO: Might want a better interface for a hash set. https://github.com/ziglang/zig/issues/6919
pub fn AutoHashSet(comptime Key: type) type {
    return std.AutoHashMap(Key, void);
}

pub const SizedPtr = struct {
    const Self = @This();

    ptr: *Opaque,
    size: u32,

    pub fn init(ptr: anytype) Self {
        const Ptr = @TypeOf(ptr);
        return .{
            .ptr = Opaque.fromPtr(Ptr, ptr),
            .size = @sizeOf(@typeInfo(Ptr).Pointer.child),
        };
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        const slice = Opaque.toPtr([*]u8, self.ptr)[0..self.size];
        alloc.free(slice);
    }
};

/// The ptr or slice inside should be freed depending on the flag.
/// Use case: Sometimes a branching condition returns heap or non-heap memory. The deinit logic can just skip non-heap memory.
pub fn MaybeOwned(comptime PtrOrSlice: type) type {
    return struct {
        inner: PtrOrSlice,
        owned: bool,

        pub fn initOwned(inner: PtrOrSlice) @This() {
            return .{
                .inner = inner,
                .owned = true,
            };
        }

        pub fn initUnowned(inner: PtrOrSlice) @This() {
            return .{
                .inner = inner,
                .owned = false,
            };
        }

        pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
            if (self.owned) {
                if (@typeInfo(PtrOrSlice) == .Pointer and @typeInfo(PtrOrSlice).Pointer.size == .Slice) {
                    alloc.free(self.inner);
                } else {
                    alloc.destroy(self.inner);
                }
            }
        }
    };
}