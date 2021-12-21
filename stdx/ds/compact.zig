const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;
const ds = stdx.ds;

// Useful for keeping a list buffer together in memory when you're using a bunch of insert/delete, while keeping realloc to a minimum.
// Backed by std.ArrayList.
// Item ids are reused once removed.
// Items are assigned an id and have O(1) access time by id.
// TODO: Iterating can be just as fast as a dense array if CompactIdGenerator kept a sorted list of freed id ranges.
//       Although that also means delete ops would need to be O(logn).
pub fn CompactUnorderedList(comptime Id: type, comptime T: type) type {
    return struct {
        const Self = @This();
        const Iterator = struct {
            idx: Id,
            list: *const Self,

            fn init(list: *const Self) @This() {
                return .{
                    .idx = 0,
                    .list = list,
                };
            }

            pub fn reset(self: *@This()) void {
                self.idx = 0;
            }

            pub fn nextPtr(self: *@This()) ?*T {
                while (true) {
                    if (self.idx < self.list.data.items.len) {
                        if (!self.list.data_exists.isSet(self.idx)) {
                            self.idx += 1;
                            continue;
                        } else {
                            defer self.idx += 1;
                            return &self.list.data.items[self.idx];
                        }
                    } else {
                        return null;
                    }
                }
            }

            pub fn next(self: *@This()) ?T {
                while (true) {
                    if (self.idx < self.list.data.items.len) {
                        if (!self.list.data_exists.isSet(self.idx)) {
                            self.idx += 1;
                            continue;
                        } else {
                            defer self.idx += 1;
                            return self.list.data.items[self.idx];
                        }
                    } else {
                        return null;
                    }
                }
            }
        };

        id_gen: CompactIdGenerator(Id),
        data: std.ArrayList(T),

        // Keep track of whether an item exists at id in order to perform iteration.
        data_exists: ds.BitArrayList,

        pub fn init(alloc: std.mem.Allocator) @This() {
            const new = @This(){
                .id_gen = CompactIdGenerator(Id).init(alloc, 0),
                .data = std.ArrayList(T).init(alloc),
                .data_exists = ds.BitArrayList.init(alloc),
            };
            return new;
        }

        pub fn deinit(self: *Self) void {
            self.id_gen.deinit();
            self.data.deinit();
            self.data_exists.deinit();
        }

        pub fn iterator(self: *Self) Iterator {
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

        pub fn get(self: *const Self, id: Id) T {
            return self.data.items[id];
        }

        pub fn getPtr(self: *const Self, id: Id) *T {
            return &self.data.items[id];
        }

        pub fn hasItem(self: *const Self, id: Id) bool {
            return self.data_exists.isSet(id);
        }

        pub fn size(self: *const Self) usize {
            return self.data.items.len - self.id_gen.next_ids.count;
        }
    };
}

test "CompactUnorderedList" {
    {
        // General test.
        var arr = CompactUnorderedList(u32, u8).init(t.alloc);
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
        var arr = CompactUnorderedList(u32, u8).init(t.alloc);
        defer arr.deinit();
        var iter = arr.iterator();
        try t.eq(iter.next(), null);
        try t.eq(arr.size(), 0);
    }
}

// Buffer is a CompactUnorderedList.
pub fn CompactSinglyLinkedList(comptime Id: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const Item = struct {
            next: ?Id,
            data: T,
        };

        first: ?Id,
        items: CompactUnorderedList(Id, Item),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .first = null,
                .items = CompactUnorderedList(Id, Item).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn insertAfter(self: *Self, id: Id, data: T) !Id {
            const new = try self.items.add(.{
                .next = self.getNext(id),
                .data = data,
            });
            self.items.getPtr(id).next = new;
            return new;
        }

        pub fn removeNext(self: *Self, id: Id) void {
            const at = self.items.getPtr(id);
            if (at.next != null) {
                const next = at.next.?;
                const next_item = self.items.getPtr(next);
                at.next = next_item.next;
                self.items.remove(next);
            }
        }

        pub fn getItem(self: *const Self, id: Id) Item {
            return self.items.get(id);
        }

        pub fn get(self: *const Self, id: Id) T {
            return self.items.getPtr(id).data;
        }

        pub fn getAt(self: *const Self, idx: usize) Id {
            var i: u32 = 0;
            var cur = self.first.?;
            while (i != idx) : (i += 1) {
                cur = self.getNext(cur).?;
            }
            return cur;
        }

        pub fn getFirst(self: *const Self) ?Id {
            return self.first;
        }

        pub fn getNext(self: *const Self, id: Id) ?Id {
            return self.items.get(id).next;
        }

        pub fn prepend(self: *Self, data: T) !Id {
            const item = Item{
                .next = self.first,
                .data = data,
            };
            self.first = try self.items.add(item);
            return self.first.?;
        }

        pub fn removeFirst(self: *Self) bool {
            if (self.first == null) {
                return false;
            } else {
                const next = self.getNext(self.first.?);
                self.items.remove(self.first.?);
                self.first = next;
                return true;
            }
        }
    };
}

test "CompactSinglyLinkedList" {
    {
        // General test.
        var list = CompactSinglyLinkedList(u32, u8).init(t.alloc);
        defer list.deinit();

        const first = try list.prepend(1);
        var last = first;
        last = try list.insertAfter(last, 2);
        last = try list.insertAfter(last, 3);
        // Test remove next.
        list.removeNext(first);
        // Test remove first.
        _ = list.removeFirst();

        var id = list.getFirst();
        try t.eq(list.get(id.?), 3);
        id = list.getNext(id.?);
        try t.eq(id, null);
    }
    {
        // Empty test.
        var list = CompactSinglyLinkedList(u32, u8).init(t.alloc);
        defer list.deinit();
        try t.eq(list.getFirst(), null);
    }
}

// Stores multiple linked lists together in memory.
pub fn CompactManySinglyLinkedList(comptime ListId: type, comptime ItemId: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const Item = struct {
            next: ?ItemId,
            data: T,
        };

        const List = struct {
            head: ?ItemId,
        };

        items: CompactUnorderedList(ItemId, Item),
        lists: CompactUnorderedList(ListId, List),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .items = CompactUnorderedList(ItemId, Item).init(alloc),
                .lists = CompactUnorderedList(ListId, List).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
            self.lists.deinit();
        }

        // Returns detached item.
        pub fn detachAfter(self: *Self, id: ItemId) ?ItemId {
            const item = self.getItemPtr(id);
            const detached = item.next;
            item.next = null;
            return detached;
        }

        pub fn insertAfter(self: *Self, id: ItemId, data: T) !ItemId {
            const new = try self.items.add(.{
                .next = self.getNext(id),
                .data = data,
            });
            self.items.getPtr(id).next = new;
            return new;
        }

        pub fn setDetachedToEnd(self: *Self, id: ItemId, detached_id: ItemId) void {
            const item = self.items.getPtr(id);
            if (item.next != null) {
                unreachable;
            }
            item.next = detached_id;
        }

        pub fn addListWithDetachedHead(self: *Self, id: ItemId) !ListId {
            return self.lists.add(.{ .head = id });
        }

        pub fn addListWithHead(self: *Self, data: T) !ListId {
            const item_id = try self.addDetachedItem(data);
            return self.addListWithDetachedHead(item_id);
        }

        pub fn addEmptyList(self: *Self) !ListId {
            return self.lists.add(.{ .head = null });
        }

        pub fn addDetachedItem(self: *Self, data: T) !ItemId {
            return try self.items.add(.{
                .next = null,
                .data = data,
            });
        }

        pub fn prepend(self: *Self, list_id: ListId, data: T) !ItemId {
            const list = self.getList(list_id);
            const item = Item{
                .next = list.first,
                .data = data,
            };
            list.first = try self.items.add(item);
            return list.first.?;
        }

        pub fn removeFirst(self: *Self, list_id: ListId) bool {
            const list = self.getList(list_id);
            if (list.first == null) {
                return false;
            } else {
                const next = self.getNext(list.first.?);
                self.items.remove(list.first.?);
                list.first = next;
                return true;
            }
        }

        pub fn removeNext(self: *Self, id: ItemId) void {
            const at = self.items.getPtr(id);
            if (at.next != null) {
                const next = at.next.?;
                const next_item = self.items.getPtr(next);
                at.next = next_item.next;
                self.items.remove(next);
            }
        }

        pub fn removeDetached(self: *Self, id: ItemId) void {
            self.items.remove(id);
        }

        pub fn getListPtr(self: *const Self, id: ListId) *List {
            return self.lists.getPtr(id);
        }

        pub fn getListHead(self: *const Self, id: ListId) ?ItemId {
            return self.lists.getPtr(id).head;
        }

        pub fn getItem(self: *const Self, id: ItemId) Item {
            return self.items.get(id);
        }

        pub fn getItemPtr(self: *const Self, id: ItemId) *Item {
            return self.items.getPtr(id);
        }

        pub fn get(self: *const Self, id: ItemId) T {
            return self.items.getPtr(id).data;
        }

        pub fn getAt(self: *const Self, list_id: ListId, idx: usize) ItemId {
            var i: u32 = 0;
            var cur: ItemId = self.getListHead(list_id).?;
            while (i != idx) : (i += 1) {
                cur = self.getNext(cur).?;
            }
            return cur;
        }

        pub fn getPtr(self: *const Self, id: ItemId) *T {
            return &self.items.getPtr(id).data;
        }

        pub fn getNext(self: *const Self, id: ItemId) ?ItemId {
            return self.items.get(id).next;
        }

        pub fn getNextItem(self: *const Self, id: ItemId) ?Item {
            if (self.getNext(id)) |next| {
                return self.getItem(next);
            } else return null;
        }

        pub fn getNextData(self: *const Self, id: ItemId) ?T {
            if (self.getNext(id)) |next| {
                return self.get(next);
            } else return null;
        }
    };
}

test "CompactManySinglyLinkedList" {
    var lists = CompactManySinglyLinkedList(u32, u32, u32).init(t.alloc);
    defer lists.deinit();

    const list_id = try lists.addListWithHead(10);
    const head = lists.getListHead(list_id).?;

    // Test detachAfter.
    const after = try lists.insertAfter(head, 20);
    try t.eq(lists.getNext(head), after);
    try t.eq(lists.detachAfter(head), after);
    try t.eq(lists.getNext(head), null);
}

// Reuses deleted ids.
// Uses a fifo id buffer to get the next id if not empty, otherwise it uses the next id counter.
pub fn CompactIdGenerator(comptime T: type) type {
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

        pub fn deinit(self: *Self) void {
            self.next_ids.deinit();
        }
    };
}

test "CompactIdGenerator" {
    var gen = CompactIdGenerator(u16).init(t.alloc, 1);
    defer gen.deinit();
    try t.eq(gen.getNextId(), 1);
    try t.eq(gen.getNextId(), 2);
    gen.deleteId(1);
    try t.eq(gen.getNextId(), 1);
    try t.eq(gen.getNextId(), 3);
}
