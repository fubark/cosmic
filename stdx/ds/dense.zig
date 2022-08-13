const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

/// Always keeps items packed for fast iteration and uses a hashmap to access items by handle id.
/// If Ordered is true, the items remain ordered at the cost of using an O(N) instead of O(1) item removal.
pub fn DenseHandleList(comptime Id: type, comptime T: type, comptime Ordered: bool) type {
    return struct {
        /// Packed data.
        id_list: std.ArrayListUnmanaged(Id),
        list: std.ArrayListUnmanaged(T),
        
        /// Id to index mapping.
        id_idx: std.AutoHashMapUnmanaged(Id, u32),

        alloc: std.mem.Allocator,
        next_id: Id,

        const DenseHandleListT = @This();

        pub fn init(alloc: std.mem.Allocator) DenseHandleListT {
            return .{
                .id_list = std.ArrayListUnmanaged(Id){},
                .list = std.ArrayListUnmanaged(T){},
                .id_idx = std.AutoHashMapUnmanaged(Id, u32){},
                .alloc = alloc,
                .next_id = 0,
            };
        }

        pub fn deinit(self: *DenseHandleListT) void {
            self.id_list.deinit(self.alloc);
            self.list.deinit(self.alloc);
            self.id_idx.deinit(self.alloc);
        }

        pub fn add(self: *DenseHandleListT, val: T) !Id {
            const new_id = self.next_id;
            try self.id_idx.put(self.alloc, new_id, @intCast(Id, self.list.items.len));
            try self.id_list.append(self.alloc, new_id);
            try self.list.append(self.alloc, val);
            self.next_id += 1;
            return new_id;
        }

        pub fn size(self: DenseHandleListT) u32 {
            return @intCast(u32, self.list.items.len);
        }

        pub fn has(self: DenseHandleListT, id: Id) bool {
            return self.id_idx.contains(id);
        }

        pub fn get(self: DenseHandleListT, id: Id) ?T {
            if (self.id_idx.get(id)) |idx| {
                return self.list.items[idx];
            } else return null;
        }

        pub fn getPtr(self: DenseHandleListT, id: Id) ?*T {
            if (self.id_idx.get(id)) |idx| {
                return &self.list.items[idx];
            } else return null;
        }

        pub fn remove(self: *DenseHandleListT, id: Id) void {
            const idx = self.id_idx.get(id).?;
            if (Ordered) {
                _ = self.list.orderedRemove(idx);
                _ = self.id_list.orderedRemove(idx);
                // Every item at or after the idx needs to update their mappings.
                var i = idx;
                while (i < self.list.items.len) : (i += 1) {
                    self.id_idx.putAssumeCapacity(self.id_list.items[i], i);
                }
            } else {
                _ = self.list.swapRemove(idx);
                _ = self.id_list.swapRemove(idx);
                if (idx != self.list.items.len) {
                    // Check if there was a swap and update swapped item's id -> idx mapping.
                    self.id_idx.putAssumeCapacity(self.id_list.items[idx], idx);
                }
            }
            _ = self.id_idx.remove(id);
        }

        pub fn items(self: DenseHandleListT) []T {
            return self.list.items;
        }

        pub fn ids(self: DenseHandleListT) []Id {
            return self.id_list.items;
        }
    };
}

test "DenseHandleList unordered" {
    var list = DenseHandleList(u32, u32, false).init(t.alloc);
    defer list.deinit();
    try t.eq(try list.add(10), 0);
    try t.eq(try list.add(20), 1);
    try t.eq(try list.add(30), 2);
    try t.eqSlice(u32, list.items(), &.{ 10, 20, 30 });
    list.remove(2);
    try t.eqSlice(u32, list.items(), &.{ 10, 20 });
    try t.eq(list.get(0).?, 10);
    try t.eq(list.get(1).?, 20);
    try t.eq(list.get(2), null);
    list.remove(0);
    try t.eqSlice(u32, list.items(), &.{ 20 });
    try t.eq(list.get(0), null);
    try t.eq(list.get(1).?, 20);
    try t.eq(list.get(2), null);
    list.getPtr(1).?.* = 100;
    try t.eq(list.get(1), 100);
}

test "DenseHandleList ordered" {
    var list = DenseHandleList(u32, u32, true).init(t.alloc);
    defer list.deinit();
    try t.eq(try list.add(10), 0);
    try t.eq(try list.add(20), 1);
    try t.eq(try list.add(30), 2);
    try t.eqSlice(u32, list.items(), &.{ 10, 20, 30 });
    list.remove(0);
    try t.eqSlice(u32, list.items(), &.{ 20, 30 });
    try t.eq(list.get(0), null);
    try t.eq(list.get(1).?, 20);
    try t.eq(list.get(2).?, 30);
}