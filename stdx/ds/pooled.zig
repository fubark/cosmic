const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

/// Keeps items closer together in memory without moving them due to a second list that tracks free slots for inserting new items.
/// Each handle id does not change and can be used to reference the same item.
/// Fast at accessing items by handle id since it's a direct array index.
/// Slower at iteration since items can have fragmentation after removals.
/// TODO: Iterating can be just as fast as a dense array if PoolIdGenerator kept a sorted list of freed id ranges. Then delete ops would be O(logn)
pub fn PooledHandleList(comptime Id: type, comptime T: type) type {
    if (@typeInfo(Id).Int.signedness != .unsigned) {
        @compileError("Unsigned id type required.");
    }
    return struct {
        id_gen: PoolIdGenerator(Id),

        // TODO: Rename to buf.
        data: std.ArrayList(T),

        // Keep track of whether an item exists at id in order to perform iteration.
        // TODO: Rename to exists.
        // TODO: Maybe the user should provide this if it's important. It would also simplify the api and remove optional return types. It also means iteration won't be possible.
        data_exists: stdx.ds.BitArrayList,

        const Self = @This();
        pub const Iterator = struct {
            // The current id should reflect the id of the value returned from next or nextPtr.
            cur_id: Id,
            list: *const Self,

            fn init(list: *const Self) @This() {
                return .{
                    .cur_id = std.math.maxInt(Id),
                    .list = list,
                };
            }

            pub fn reset(self: *@This()) void {
                self.idx = std.math.maxInt(Id);
            }

            pub fn nextPtr(self: *@This()) ?*T {
                self.cur_id +%= 1;
                while (true) {
                    if (self.cur_id < self.list.data.items.len) {
                        if (!self.list.data_exists.isSet(self.cur_id)) {
                            self.cur_id += 1;
                            continue;
                        } else {
                            return &self.list.data.items[self.cur_id];
                        }
                    } else {
                        return null;
                    }
                }
            }

            pub fn next(self: *@This()) ?T {
                self.cur_id +%= 1;
                while (true) {
                    if (self.cur_id < self.list.data.items.len) {
                        if (!self.list.data_exists.isSet(self.cur_id)) {
                            self.cur_id += 1;
                            continue;
                        } else {
                            return self.list.data.items[self.cur_id];
                        }
                    } else {
                        return null;
                    }
                }
            }
        };

        pub fn init(alloc: std.mem.Allocator) @This() {
            const new = @This(){
                .id_gen = PoolIdGenerator(Id).init(alloc, 0),
                .data = std.ArrayList(T).init(alloc),
                .data_exists = stdx.ds.BitArrayList.init(alloc),
            };
            return new;
        }

        pub fn deinit(self: Self) void {
            self.id_gen.deinit();
            self.data.deinit();
            self.data_exists.deinit();
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator.init(self);
        }

        // Returns the id of the item.
        pub fn add(self: *Self, item: T) !Id {
            const new_id = self.id_gen.getNextId();
            errdefer self.id_gen.deleteId(new_id);

            if (new_id >= self.data.items.len) {
                try self.data.resize(new_id + 1);
                try self.data_exists.resize(new_id + 1);
            }
            self.data.items[new_id] = item;
            self.data_exists.set(new_id);
            return new_id;
        }

        pub fn set(self: *Self, id: Id, item: T) void {
            self.data.items[id] = item;
        }

        pub fn remove(self: *Self, id: Id) void {
            self.data_exists.unset(id);
            self.id_gen.deleteId(id);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.data_exists.clearRetainingCapacity();
            self.id_gen.clearRetainingCapacity();
            self.data.clearRetainingCapacity();
        }

        pub fn get(self: Self, id: Id) ?T {
            if (self.has(id)) {
                return self.data.items[id];
            } else return null;
        }

        pub fn getNoCheck(self: Self, id: Id) T {
            return self.data.items[id];
        }

        pub fn getPtr(self: *const Self, id: Id) ?*T {
            if (self.has(id)) {
                return &self.data.items[id];
            } else return null;
        }

        pub fn getPtrNoCheck(self: Self, id: Id) *T {
            return &self.data.items[id];
        }

        pub fn has(self: Self, id: Id) bool {
            return self.data_exists.isSet(id);
        }

        pub fn size(self: Self) usize {
            return self.data.items.len - self.id_gen.next_ids.count;
        }
    };
}

test "PooledHandleList" {
    {
        // General test.
        var arr = PooledHandleList(u32, u8).init(t.alloc);
        defer arr.deinit();

        _ = try arr.add(1);
        const id = try arr.add(2);
        _ = try arr.add(3);
        arr.remove(id);
        // Test adding to a removed slot.
        _ = try arr.add(4);
        const id2 = try arr.add(5);
        // Test iterator skips removed slot.
        arr.remove(id2);

        var iter = arr.iterator();
        try t.eq(iter.next(), 1);
        try t.eq(iter.next(), 4);
        try t.eq(iter.next(), 3);
        try t.eq(iter.next(), null);
        try t.eq(arr.size(), 3);
    }
    {
        // Empty test.
        var arr = PooledHandleList(u32, u8).init(t.alloc);
        defer arr.deinit();
        var iter = arr.iterator();
        try t.eq(iter.next(), null);
        try t.eq(arr.size(), 0);
    }
}

/// Reuses deleted ids.
/// Uses a fifo id buffer to get the next id if not empty, otherwise it uses the next id counter.
pub fn PoolIdGenerator(comptime T: type) type {
    return struct {
        const Self = @This();

        start_id: T,
        next_default_id: T,
        next_ids: std.fifo.LinearFifo(T, .Dynamic),

        pub fn init(alloc: std.mem.Allocator, start_id: T) Self {
            return .{
                .start_id = start_id,
                .next_default_id = start_id,
                .next_ids = std.fifo.LinearFifo(T, .Dynamic).init(alloc),
            };
        }

        pub fn peekNextId(self: Self) T {
            if (self.next_ids.readableLength() == 0) {
                return self.next_default_id;
            } else {
                return self.next_ids.peekItem(0);
            }
        }

        pub fn getNextId(self: *Self) T {
            if (self.next_ids.readableLength() == 0) {
                defer self.next_default_id += 1;
                return self.next_default_id;
            } else {
                return self.next_ids.readItem().?;
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.next_default_id = self.start_id;
            self.next_ids.head = 0;
            self.next_ids.count = 0;
        }

        pub fn deleteId(self: *Self, id: T) void {
            self.next_ids.writeItem(id) catch unreachable;
        }

        pub fn deinit(self: Self) void {
            self.next_ids.deinit();
        }
    };
}

test "PoolIdGenerator" {
    var gen = PoolIdGenerator(u16).init(t.alloc, 1);
    defer gen.deinit();
    try t.eq(gen.getNextId(), 1);
    try t.eq(gen.getNextId(), 2);
    gen.deleteId(1);
    try t.eq(gen.getNextId(), 1);
    try t.eq(gen.getNextId(), 3);
}
