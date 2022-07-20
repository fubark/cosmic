const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

/// Always keeps items packed for fast iteration and uses a hashmap to access items by handle id.
pub fn DenseHandleList(comptime Id: type, comptime T: type) type {
    return struct {
        id_list: std.ArrayListUnmanaged(Id),
        list: std.ArrayListUnmanaged(T),
        id_idx: std.AutoHashMapUnmanaged(Id, Id),
        alloc: std.mem.Allocator,
        next_id: Id,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .id_list = std.ArrayListUnmanaged(Id){},
                .list = std.ArrayListUnmanaged(T){},
                .id_idx = std.AutoHashMapUnmanaged(Id, Id){},
                .alloc = alloc,
                .next_id = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.id_list.deinit(self.alloc);
            self.list.deinit(self.alloc);
            self.id_idx.deinit(self.alloc);
        }

        pub fn add(self: *Self, val: T) !Id {
            const new_id = self.next_id;
            try self.id_idx.put(self.alloc, new_id, @intCast(Id, self.list.items.len));
            try self.id_list.append(self.alloc, new_id);
            try self.list.append(self.alloc, val);
            self.next_id += 1;
            return new_id;
        }

        pub fn get(self: Self, id: Id) ?T {
            if (self.id_idx.get(id)) |idx| {
                return self.list.items[idx];
            } else return null;
        }

        pub fn getPtr(self: Self, id: Id) ?*T {
            if (self.id_idx.get(id)) |idx| {
                return &self.list.items[idx];
            } else return null;
        }

        pub fn remove(self: *Self, id: Id) void {
            const idx = self.id_idx.get(id).?;
            _ = self.list.swapRemove(idx);
            _ = self.id_list.swapRemove(idx);
            if (idx != self.list.items.len) {
                // Check if there was a swap and update swapped item's id -> idx mapping.
                self.id_idx.putAssumeCapacity(self.id_list.items[idx], idx);
            }
            _ = self.id_idx.remove(id);
        }

        pub fn items(self: Self) []T {
            return self.list.items;
        }
    };
}

test "DenseHandleList" {
    var list = DenseHandleList(u32, u32).init(t.alloc);
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