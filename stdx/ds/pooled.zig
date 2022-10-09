const std = @import("std");

const stdx = @import("../stdx.zig");
const fatal = stdx.fatal;
const t = stdx.testing;
const compact = @import("compact.zig");
const log = stdx.log.scoped(.pooled);

/// Keeps items closer together in memory without moving them due to a second list that tracks free slots for inserting new items.
/// Each handle id does not change and can be used to reference the same item.
/// Fast at accessing items by handle id since it's a direct array index.
/// Slower at iteration since items can have fragmentation after removals.
/// TODO: Iterating can be just as fast as a dense array if PoolIdGenerator kept a sorted list of freed id ranges. Then delete ops would be O(logn)
pub fn PooledHandleList(comptime Id: type, comptime T: type) type {
    return PooledHandleListExt(Id, T, false);
}
pub fn RcPooledHandleList(comptime Id: type, comptime T: type) type {
    return PooledHandleListExt(Id, T, true);
}
fn PooledHandleListExt(comptime Id: type, comptime T: type, comptime RC: bool) type {
    if (@typeInfo(Id).Int.signedness != .unsigned) {
        @compileError("Unsigned id type required.");
    }
    return struct {
        id_gen: PoolIdGenerator(Id),

        alloc: std.mem.Allocator,
        buf: std.ArrayListUnmanaged(T),

        // Keep track of whether an item exists at id in order to perform iteration.
        // TODO: Rename to exists.
        // TODO: Maybe the user should provide this if it's important. It would also simplify the api and remove optional return types. It also means iteration won't be possible.
        data_exists: stdx.ds.BitArrayList,

        ref_counts: if (RC) std.ArrayListUnmanaged(u32) else void,

        const PooledHandleListT = @This();
        pub const Iterator = struct {
            // The current id should reflect the id of the value returned from next or nextPtr.
            cur_id: Id,
            list: *const PooledHandleListT,

            fn init(list: *const PooledHandleListT) Iterator {
                return .{
                    .cur_id = std.math.maxInt(Id),
                    .list = list,
                };
            }

            pub fn reset(self: *Iterator) void {
                self.idx = std.math.maxInt(Id);
            }

            pub fn nextPtr(self: *Iterator) ?*T {
                self.cur_id +%= 1;
                while (true) {
                    if (self.cur_id < self.list.buf.items.len) {
                        if (!self.list.data_exists.isSet(self.cur_id)) {
                            self.cur_id += 1;
                            continue;
                        } else {
                            return &self.list.buf.items[self.cur_id];
                        }
                    } else {
                        return null;
                    }
                }
            }

            pub fn next(self: *@This()) ?T {
                self.cur_id +%= 1;
                while (true) {
                    if (self.cur_id < self.list.buf.items.len) {
                        if (!self.list.data_exists.isSet(self.cur_id)) {
                            self.cur_id += 1;
                            continue;
                        } else {
                            return self.list.buf.items[self.cur_id];
                        }
                    } else {
                        return null;
                    }
                }
            }
        };

        pub fn init(alloc: std.mem.Allocator) PooledHandleListT {
            const new = PooledHandleListT{
                .alloc = alloc,
                .id_gen = PoolIdGenerator(Id).init(alloc, 0),
                .buf = .{},
                .data_exists = stdx.ds.BitArrayList.init(alloc),
                .ref_counts = if (RC) .{} else {},
            };
            return new;
        }

        pub fn deinit(self: *PooledHandleListT) void {
            self.id_gen.deinit();
            self.buf.deinit(self.alloc);
            self.data_exists.deinit();
            if (RC) {
                self.ref_counts.deinit(self.alloc);
            }
        }

        pub fn iterator(self: *const PooledHandleListT) Iterator {
            return Iterator.init(self);
        }

        // Returns the id of the item.
        pub fn add(self: *PooledHandleListT, item: T) !Id {
            const new_id = self.id_gen.getNextId();

            if (new_id >= self.buf.items.len) {
                errdefer self.id_gen.deleteId(new_id);
                try self.buf.resize(self.alloc, new_id + 1);
                try self.data_exists.resize(new_id + 1);
                if (RC) {
                    try self.ref_counts.resize(self.alloc, new_id + 1);
                }
            }
            self.buf.items[new_id] = item;
            self.data_exists.set(new_id);
            if (RC) {
                self.ref_counts.items[new_id] = 1;
            }
            return new_id;
        }

        /// Add with specific id.
        pub fn addWithId(self: *PooledHandleListT, id: Id, item: T) !void {
            if (id < self.buf.items.len) {
                if (self.data_exists.isSet(id)) {
                    return error.AlreadyExists;
                }
                // Remove the free space entry.
                const free_buf = self.id_gen.next_ids.buf;
                const free_head = self.id_gen.next_ids.head;
                const free_len = self.id_gen.next_ids.count;
                const src = free_buf[free_head..free_head+free_len];
                for (src) |free_id, idx| {
                    if (free_id == id) {
                        if (idx == 0) {
                            self.id_gen.next_ids.discard(1);
                            self.id_gen.next_ids.head += 1;
                            self.id_gen.next_ids.count -= 1;
                        } else {
                            const abs_idx = free_head + idx;
                            std.mem.copy(Id, free_buf[abs_idx..free_head+free_len-1], free_buf[abs_idx+1..free_head+free_len]);
                            self.id_gen.next_ids.count -= 1;
                        }
                        break;
                    }
                }
            } else {
                const last_len = self.buf.items.len;
                try self.buf.resize(self.alloc, id + 1);
                try self.data_exists.resizeFillNew(id + 1, false);
                if (RC) {
                    try self.ref_counts.resize(self.alloc, id + 1);
                }
                var i = @intCast(Id, last_len);
                while (i < id) : (i += 1) {
                    self.id_gen.deleteId(i);
                }
                self.id_gen.next_default_id = @intCast(u32, self.buf.items.len);
            }
            self.buf.items[id] = item;
            self.data_exists.set(id);
            if (RC) {
                self.ref_counts[id] = 1;
            }
        }

        pub fn set(self: *PooledHandleListT, id: Id, item: T) void {
            self.buf.items[id] = item;
        }

        pub usingnamespace if (RC) struct {
            pub fn incRef(self: *PooledHandleListT, id: Id) void {
                self.ref_counts.items[id] += 1;
            }

            pub fn getRefCount(self: *PooledHandleListT, id: Id) u32 {
                return self.ref_counts.items[id];
            }
        } else struct {};

        pub fn remove(self: *PooledHandleListT, id: Id) void {
            if (RC) {
                self.ref_counts.items[id] -= 1;
                if (self.ref_counts.items[id] == 0) {
                    self.data_exists.unset(id);
                    self.id_gen.deleteId(id);
                }
            } else {
                self.data_exists.unset(id);
                self.id_gen.deleteId(id);
            }
        }

        pub fn ensureUnusedCapacity(self: *PooledHandleListT, cap: usize) !void {
            const num_free = self.id_gen.freeCount();
            if (num_free >= cap) {
                return;
            } else {
                const new_cap = cap - num_free; 
                try self.data_exists.ensureUnusedCapacity(new_cap);
                try self.buf.ensureUnusedCapacity(self.alloc, new_cap);
                if (RC) {
                    try self.ref_counts.ensureUnusedCapacity(self.alloc, new_cap);
                }
            }
        }

        pub fn clearRetainingCapacity(self: *PooledHandleListT) void {
            self.data_exists.clearRetainingCapacity();
            self.id_gen.clearRetainingCapacity();
            self.buf.clearRetainingCapacity();
            if (RC) {
                self.ref_counts.clearRetainingCapacity();
            }
        }

        pub fn get(self: PooledHandleListT, id: Id) ?T {
            if (self.has(id)) {
                return self.buf.items[id];
            } else return null;
        }

        pub fn getNoCheck(self: PooledHandleListT, id: Id) T {
            return self.buf.items[id];
        }

        pub fn getPtr(self: *const PooledHandleListT, id: Id) ?*T {
            if (self.has(id)) {
                return &self.buf.items[id];
            } else return null;
        }

        pub fn getPtrNoCheck(self: PooledHandleListT, id: Id) *T {
            return &self.buf.items[id];
        }

        pub fn has(self: PooledHandleListT, id: Id) bool {
            return self.data_exists.isSet(id);
        }

        pub fn size(self: PooledHandleListT) usize {
            return self.buf.items.len - self.id_gen.next_ids.count;
        }
    };
}

test "RcPooledHandleList" {
    var list = RcPooledHandleList(u32, u8).init(t.alloc);
    defer list.deinit();

    var id = try list.add(1);
    list.remove(id);
    try t.eq(list.has(id), false);

    id = try list.add(1);
    list.incRef(id);
    list.remove(id);
    try t.eq(list.has(id), true);
    list.remove(id);
    try t.eq(list.has(id), false);
}

test "PooledHandleList" {
    {
        // General test.
        var list = PooledHandleList(u32, u8).init(t.alloc);
        defer list.deinit();

        _ = try list.add(1);
        const id = try list.add(2);
        _ = try list.add(3);
        list.remove(id);
        // Test adding to a removed slot.
        _ = try list.add(4);
        const id2 = try list.add(5);
        // Test iterator skips removed slot.
        list.remove(id2);

        var iter = list.iterator();
        try t.eq(iter.next(), 1);
        try t.eq(iter.next(), 4);
        try t.eq(iter.next(), 3);
        try t.eq(iter.next(), null);
        try t.eq(list.size(), 3);
    }
    {
        // Empty test.
        var list = PooledHandleList(u32, u8).init(t.alloc);
        defer list.deinit();
        var iter = list.iterator();
        try t.eq(iter.next(), null);
        try t.eq(list.size(), 0);
    }
    {
        // addWithId.
        var list = PooledHandleList(u32, u8).init(t.alloc);
        defer list.deinit();

        // Add that stretches the list capacity.
        try list.addWithId(3, 100);
        try t.eq(list.size(), 1);
        try t.eq(list.getNoCheck(3), 100);

        // Add in middle to make sure free id list is updated.
        try list.addWithId(1, 101);
        try t.eq(list.size(), 2);
        try t.eq(list.getNoCheck(1), 101);
        try t.eq(list.add(102), 0);
        try t.eq(list.add(103), 2);

        // After free list is used up, the next id should still be valid.
        try t.eq(list.add(104), 4);
    }
}

/// Reuses deleted ids.
/// Uses a fifo id buffer to get the next id if not empty, otherwise it uses the next id counter.
pub fn PoolIdGenerator(comptime T: type) type {
    return struct {
        start_id: T,
        next_default_id: T,
        next_ids: std.fifo.LinearFifo(T, .Dynamic),

        const PoolIdGeneratorT = @This();

        pub fn init(alloc: std.mem.Allocator, start_id: T) PoolIdGeneratorT {
            return .{
                .start_id = start_id,
                .next_default_id = start_id,
                .next_ids = std.fifo.LinearFifo(T, .Dynamic).init(alloc),
            };
        }

        pub inline fn freeCount(self: PoolIdGeneratorT) usize {
            return self.next_ids.count;
        }

        pub fn peekNextId(self: PoolIdGeneratorT) T {
            if (self.next_ids.readableLength() == 0) {
                return self.next_default_id;
            } else {
                return self.next_ids.peekItem(0);
            }
        }

        pub fn getNextId(self: *PoolIdGeneratorT) T {
            if (self.next_ids.readableLength() == 0) {
                defer self.next_default_id += 1;
                return self.next_default_id;
            } else {
                return self.next_ids.readItem().?;
            }
        }

        pub fn clearRetainingCapacity(self: *PoolIdGeneratorT) void {
            self.next_default_id = self.start_id;
            self.next_ids.head = 0;
            self.next_ids.count = 0;
        }

        pub fn deleteId(self: *PoolIdGeneratorT, id: T) void {
            self.next_ids.writeItem(id) catch fatal();
        }

        pub fn deinit(self: PoolIdGeneratorT) void {
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

pub fn NullHandleId(comptime Id: type) Id {
    return std.math.maxInt(Id);
}

/// Holds linked lists of items in a compact buffer. Does not keep track of list heads.
pub fn PooledHandleSLLBuffer(comptime Id: type, comptime T: type) type {
    const Null = comptime NullHandleId(Id);
    const OptId = Id;
    return struct {
        nodes: PooledHandleList(Id, Node),

        pub const Node = compact.CompactSinglyLinkedListNode(Id, T);
        const PooledHandleSLLBufferT = @This();
        const ListIterator = struct {
            buf: *PooledHandleSLLBufferT,
            prev_id: Id,
            cur_id: Id,
            next_id: Id,

            fn init(buf: *PooledHandleSLLBufferT, head_id: Id) ListIterator {
                return .{
                    .buf = buf,
                    .prev_id = Null,
                    .cur_id = Null,
                    .next_id = head_id,
                };
            }

            pub fn next(self: *ListIterator) ?T {
                if (self.next_id != Null) {
                    const node = self.buf.nodes.getNoCheck(self.next_id);
                    self.prev_id = self.cur_id;
                    self.cur_id = self.next_id;
                    self.next_id = node.next;
                    return node.data;
                } else return null;
            }

            /// Returns the next node id that follows the removed node.
            pub fn remove(self: *ListIterator) !Id {
                if (self.cur_id != Null) {
                    if (self.prev_id != Null) {
                        try self.buf.removeAfter(self.prev_id);
                    } else {
                        try self.buf.removeAssumeNoPrev(self.cur_id);
                    }
                    self.cur_id = Null;
                    return self.next_id;
                } else return error.BadState;
            }
        };

        pub fn init(alloc: std.mem.Allocator) PooledHandleSLLBufferT {
            return .{
                .nodes = PooledHandleList(Id, Node).init(alloc),
            };
        }

        pub fn deinit(self: *PooledHandleSLLBufferT) void {
            self.nodes.deinit();
        }

        pub fn clearRetainingCapacity(self: *PooledHandleSLLBufferT) void {
            self.nodes.clearRetainingCapacity();
        }

        pub fn getNode(self: PooledHandleSLLBufferT, idx: Id) ?Node {
            return self.nodes.get(idx);
        }

        pub fn getNodeNoCheck(self: PooledHandleSLLBufferT, idx: Id) Node {
            return self.nodes.getNoCheck(idx);
        }

        pub fn getNodePtrNoCheck(self: PooledHandleSLLBufferT, idx: Id) *Node {
            return self.nodes.getPtrNoCheck(idx);
        }

        pub fn iterator(self: PooledHandleSLLBufferT) PooledHandleList(Id, Node).Iterator {
            return self.nodes.iterator();
        }

        pub fn listIterator(self: *PooledHandleSLLBufferT, head: Id) ListIterator {
            return ListIterator.init(self, head);
        }

        pub fn iterFirstNoCheck(self: PooledHandleSLLBufferT) Id {
            var iter = self.nodes.iterator();
            _ = iter.next();
            return iter.cur_id;
        }

        pub fn iterFirstValueNoCheck(self: PooledHandleSLLBufferT) T {
            var iter = self.nodes.iterator();
            return iter.next().?.data;
        }

        pub fn size(self: PooledHandleSLLBufferT) usize {
            return self.nodes.size();
        }

        pub fn getLast(self: PooledHandleSLLBufferT, id: Id) ?Id {
            if (id == Null) {
                return null;
            }
            if (self.nodes.has(id)) {
                var cur = id;
                while (cur != Null) {
                    const next = self.getNextNoCheck(cur);
                    if (next == Null) {
                        return cur;
                    }
                    cur = next;
                }
                unreachable;
            } else return null;
        }

        pub fn get(self: PooledHandleSLLBufferT, id: Id) ?T {
            if (self.nodes.has(id)) {
                return self.nodes.getNoCheck(id).data;
            } else return null;
        }

        pub fn getNoCheck(self: PooledHandleSLLBufferT, idx: Id) T {
            return self.nodes.getNoCheck(idx).data;
        }

        pub fn getPtrNoCheck(self: PooledHandleSLLBufferT, idx: Id) *T {
            return &self.nodes.getPtrNoCheck(idx).data;
        }

        pub fn getNextNoCheck(self: PooledHandleSLLBufferT, id: Id) OptId {
            return self.nodes.getNoCheck(id).next;
        }

        pub fn getNext(self: PooledHandleSLLBufferT, id: Id) ?OptId {
            if (self.nodes.has(id)) {
                return self.nodes.getNoCheck(id).next;
            } else return null;
        }

        /// Adds a new head node.
        pub fn add(self: *PooledHandleSLLBufferT, data: T) !Id {
            return try self.nodes.add(.{
                .next = Null,
                .data = data,
            });
        }

        pub fn insertBeforeHead(self: *PooledHandleSLLBufferT, head_id: Id, data: T) !Id {
            if (self.nodes.has(head_id)) {
                return try self.nodes.add(.{
                    .next = head_id,
                    .data = data,
                });
            } else return error.NoElement;
        }

        pub fn insertBeforeHeadNoCheck(self: *PooledHandleSLLBufferT, head_id: Id, data: T) !Id {
            return try self.nodes.add(.{
                .next = head_id,
                .data = data,
            });
        }

        pub fn insertAfter(self: *PooledHandleSLLBufferT, id: Id, data: T) !Id {
            if (self.nodes.has(id)) {
                const new = try self.nodes.add(.{
                    .next = self.nodes.getNoCheck(id).next,
                    .data = data,
                });
                self.nodes.getPtrNoCheck(id).next = new;
                return new;
            } else return error.NoElement;
        }

        pub fn appendToList(self: *PooledHandleSLLBufferT, head: Id, data: T) !Id {
            if (head != Null) {
                var iter = self.listIterator(head);
                while (iter.next()) |_| {}
                return self.insertAfter(iter.cur_id, data);
            } else {
                return self.add(data);
            }
        }

        pub fn removeFromList(self: *PooledHandleSLLBufferT, head: Id, id: Id) !void {
            var iter = self.listIterator(head);
            while (iter.next()) |_| {
                if (iter.cur_id == id) {
                    _ = try iter.remove();
                    break;
                }
            }
        }

        pub fn removeAfter(self: *PooledHandleSLLBufferT, id: Id) !void {
            if (self.nodes.has(id)) {
                const next = self.getNextNoCheck(id);
                if (next != Null) {
                    const next_next = self.getNextNoCheck(next);
                    self.nodes.getNoCheck(id).next = next_next;
                    self.nodes.remove(next);
                }
            } else return error.NoElement;
        }

        pub fn removeAssumeNoPrev(self: *PooledHandleSLLBufferT, id: Id) !void {
            if (self.nodes.has(id)) {
                self.nodes.remove(id);
            } else return error.NoElement;
        }
    };
}

test "PooledHandleSLLBuffer add, getters, insertAfter, removeAssumeNoPrev" {
    var buf = PooledHandleSLLBuffer(u32, u32).init(t.alloc);
    defer buf.deinit();

    const head = try buf.add(1);
    try t.eq(buf.get(head).?, 1);
    try t.eq(buf.getNoCheck(head), 1);
    try t.eq(buf.getNode(head).?.data, 1);
    try t.eq(buf.getNodeNoCheck(head).data, 1);

    const second = try buf.insertAfter(head, 2);
    try t.eq(buf.getNodeNoCheck(head).next, second);
    try t.eq(buf.getNoCheck(second), 2);

    try buf.removeAssumeNoPrev(head);
    try t.eq(buf.get(head), null);
}

test "PooledHandleSLLBuffer appendToList" {
    var buf = PooledHandleSLLBuffer(u32, u32).init(t.alloc);
    defer buf.deinit();

    const head = NullHandleId(u32);
    // Append to null head creates a new head.
    const id = try buf.appendToList(head, 1);
    try t.eq(id, 0);
    try t.eq(buf.get(id).?, 1);

    // Append value.
    const next = try buf.appendToList(id, 2);
    try t.eq(next, 1);
    try t.eq(buf.get(next).?, 2);
    try t.eq(buf.get(id).?, 1);
}