const std = @import("std");
const stdx = @import("../stdx.zig");
const PooledHandleList = stdx.ds.PooledHandleList;
const t = stdx.testing;
const ds = stdx.ds;
const log = stdx.log.scoped(.compact);

// TODO: Rename to PooledHandleSLList
/// Buffer is a PooledHandleList.
pub fn CompactSinglyLinkedList(comptime Id: type, comptime T: type) type {
    const Null = CompactNull(Id);
    const Node = CompactSinglyLinkedListNode(Id, T);
    return struct {
        const Self = @This();

        first: Id,
        nodes: PooledHandleList(Id, Node),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .first = Null,
                .nodes = PooledHandleList(Id, Node).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
        }

        pub fn insertAfter(self: *Self, id: Id, data: T) !Id {
            if (self.nodes.has(id)) {
                const new = try self.nodes.add(.{
                    .next = self.nodes.getNoCheck(id).next,
                    .data = data,
                });
                self.nodes.getPtrNoCheck(id).next = new;
                return new;
            } else return error.NoElement;
        }

        pub fn removeNext(self: *Self, id: Id) !bool {
            if (self.nodes.has(id)) {
                const at = self.nodes.getPtrNoCheck(id);
                if (at.next != Null) {
                    const next = at.next;
                    at.next = self.nodes.getNoCheck(next).next;
                    self.nodes.remove(next);
                    return true;
                } else return false;
            } else return error.NoElement;
        }

        pub fn getNode(self: *const Self, id: Id) ?Node {
            return self.nodes.get(id);
        }

        pub fn getNodeAssumeExists(self: *const Self, id: Id) Node {
            return self.nodes.getNoCheck(id);
        }

        pub fn get(self: *const Self, id: Id) ?T {
            if (self.nodes.has(id)) {
                return self.nodes.getNoCheck(id).data;
            } else return null;
        }

        pub fn getNoCheck(self: *const Self, id: Id) T {
            return self.nodes.getNoCheck(id).data;
        }

        pub fn getAt(self: *const Self, idx: usize) Id {
            var i: u32 = 0;
            var cur = self.first.?;
            while (i != idx) : (i += 1) {
                cur = self.getNext(cur).?;
            }
            return cur;
        }

        pub fn getFirst(self: *const Self) Id {
            return self.first;
        }

        pub fn getNext(self: Self, id: Id) ?Id {
            if (self.nodes.has(id)) {
                return self.nodes.getNoCheck(id).next;
            } else return null;
        }

        pub fn prepend(self: *Self, data: T) !Id {
            const node = Node{
                .next = self.first,
                .data = data,
            };
            self.first = try self.nodes.add(node);
            return self.first;
        }

        pub fn removeFirst(self: *Self) bool {
            if (self.first != Null) {
                const next = self.getNodeAssumeExists(self.first).next;
                self.nodes.remove(self.first);
                self.first = next;
                return true;
            } else return false;
        }
    };
}

test "CompactSinglyLinkedList" {
    const Null = CompactNull(u32);
    {
        // General test.
        var list = CompactSinglyLinkedList(u32, u8).init(t.alloc);
        defer list.deinit();

        const first = try list.prepend(1);
        var last = first;
        last = try list.insertAfter(last, 2);
        last = try list.insertAfter(last, 3);
        // Test remove next.
        _ = try list.removeNext(first);
        // Test remove first.
        _ = list.removeFirst();

        var id = list.getFirst();
        try t.eq(list.get(id), 3);
        id = list.getNext(id).?;
        try t.eq(id, Null);
    }
    {
        // Empty test.
        var list = CompactSinglyLinkedList(u32, u8).init(t.alloc);
        defer list.deinit();
        try t.eq(list.getFirst(), Null);
    }
}

// TODO: Rename to PooledHandleSLListNode
/// Id should be an unsigned integer type.
/// Max value of Id is used to indicate null. (An optional would increase the struct size.)
pub fn CompactSinglyLinkedListNode(comptime Id: type, comptime T: type) type {
    return struct {
        next: Id,
        // TODO: Rename to val.
        data: T,
    };
}

pub fn CompactNull(comptime Id: type) Id {
    return comptime std.math.maxInt(Id);
}

// TODO: Can PooledHandleSLListBuffer replace CompactManySinglyLinkedList?
/// Stores multiple linked lists together in memory.
pub fn CompactManySinglyLinkedList(comptime ListId: type, comptime Index: type, comptime T: type) type {
    const Node = CompactSinglyLinkedListNode(Index, T);
    const Null = CompactNull(Index);
    return struct {
        const Self = @This();

        const List = struct {
            head: ?Index,
        };

        nodes: PooledHandleList(Index, Node),
        lists: PooledHandleList(ListId, List),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .nodes = PooledHandleList(Index, Node).init(alloc),
                .lists = PooledHandleList(ListId, List).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
            self.lists.deinit();
        }

        // Returns detached item.
        pub fn detachAfter(self: *Self, id: Index) !Index {
            if (self.nodes.has(id)) {
                const item = self.getNodePtrAssumeExists(id);
                const detached = item.next;
                item.next = Null;
                return detached;
            } else return error.NoElement;
        }

        pub fn insertAfter(self: *Self, id: Index, data: T) !Index {
            if (self.nodes.has(id)) {
                const new = try self.nodes.add(.{
                    .next = self.nodes.getNoCheck(id).next,
                    .data = data,
                });
                self.nodes.getPtrNoCheck(id).next = new;
                return new;
            } else return error.NoElement;
        }

        pub fn setDetachedToEnd(self: *Self, id: Index, detached_id: Index) void {
            const item = self.nodes.getPtr(id).?;
            item.next = detached_id;
        }

        pub fn addListWithDetachedHead(self: *Self, id: Index) !ListId {
            return self.lists.add(.{ .head = id });
        }

        pub fn addListWithHead(self: *Self, data: T) !ListId {
            const item_id = try self.addDetachedItem(data);
            return self.addListWithDetachedHead(item_id);
        }

        pub fn addEmptyList(self: *Self) !ListId {
            return self.lists.add(.{ .head = Null });
        }

        pub fn addDetachedItem(self: *Self, data: T) !Index {
            return try self.nodes.add(.{
                .next = Null,
                .data = data,
            });
        }

        pub fn prepend(self: *Self, list_id: ListId, data: T) !Index {
            const list = self.getList(list_id);
            const item = Node{
                .next = list.first,
                .data = data,
            };
            list.first = try self.nodes.add(item);
            return list.first.?;
        }

        pub fn removeFirst(self: *Self, list_id: ListId) bool {
            const list = self.getList(list_id);
            if (list.first == null) {
                return false;
            } else {
                const next = self.getNext(list.first.?);
                self.nodes.remove(list.first.?);
                list.first = next;
                return true;
            }
        }

        pub fn removeNext(self: *Self, id: Index) !bool {
            if (self.nodes.has(id)) {
                const at = self.nodes.getPtrNoCheck(id);
                if (at.next != Null) {
                    const next = at.next;
                    at.next = self.nodes.getNoCheck(next).next;
                    self.nodes.remove(next);
                    return true;
                } else return false;
            } else return error.NoElement;
        }

        pub fn removeDetached(self: *Self, id: Index) void {
            self.nodes.remove(id);
        }

        pub fn getListPtr(self: *const Self, id: ListId) *List {
            return self.lists.getPtr(id);
        }

        pub fn getListHead(self: *const Self, id: ListId) ?Index {
            if (self.lists.has(id)) {
                return self.lists.getNoCheck(id).head;
            } else return null;
        }

        pub fn findInList(self: Self, list_id: ListId, ctx: anytype, pred: fn (ctx: @TypeOf(ctx), buf: Self, item_id: Index) bool) ?Index {
            var id = self.getListHead(list_id) orelse return null;
            while (id != Null) {
                if (pred(ctx, self, id)) {
                    return id;
                }
                id = self.getNextIdNoCheck(id);
            }
            return null;
        }

        pub fn has(self: Self, id: Index) bool {
            return self.nodes.has(id);
        }

        pub fn getNode(self: Self, id: Index) ?Node {
            return self.nodes.get(id);
        }

        pub fn getNodeAssumeExists(self: Self, id: Index) Node {
            return self.nodes.getNoCheck(id);
        }

        pub fn getNodePtr(self: Self, id: Index) ?*Node {
            return self.nodes.getPtr(id);
        }

        pub fn getNodePtrAssumeExists(self: Self, id: Index) *Node {
            return self.nodes.getPtrNoCheck(id);
        }

        pub fn get(self: Self, id: Index) ?T {
            if (self.nodes.has(id)) {
                return self.nodes.getNoCheck(id).data;
            } else return null;
        }

        pub fn getNoCheck(self: Self, id: Index) T {
            return self.nodes.getNoCheck(id).data;
        }

        pub fn getIdAt(self: Self, list_id: ListId, idx: usize) Index {
            var i: u32 = 0;
            var cur: Index = self.getListHead(list_id).?;
            while (i != idx) : (i += 1) {
                cur = self.getNextId(cur).?;
            }
            return cur;
        }

        pub fn getPtr(self: Self, id: Index) ?*T {
            if (self.nodes.has(id)) {
                return &self.nodes.getPtrNoCheck(id).data;
            } else return null;
        }

        pub fn getPtrNoCheck(self: Self, id: Index) *T {
            return &self.nodes.getPtrNoCheck(id).data;
        }

        pub fn getNextId(self: Self, id: Index) ?Index {
            if (self.nodes.get(id)) |node| {
                return node.next;
            } else return null;
        }

        pub fn getNextIdNoCheck(self: Self, id: Index) Index {
            return self.nodes.getNoCheck(id).next;
        }

        pub fn getNextNode(self: Self, id: Index) ?Node {
            if (self.getNext(id)) |next| {
                return self.getNode(next);
            } else return null;
        }

        pub fn getNextData(self: *const Self, id: Index) ?T {
            if (self.getNext(id)) |next| {
                return self.get(next);
            } else return null;
        }
    };
}

test "CompactManySinglyLinkedList" {
    const Null = CompactNull(u32);
    var lists = CompactManySinglyLinkedList(u32, u32, u32).init(t.alloc);
    defer lists.deinit();

    const list_id = try lists.addListWithHead(10);
    const head = lists.getListHead(list_id).?;

    // Test detachAfter.
    const after = try lists.insertAfter(head, 20);
    try t.eq(lists.getNextIdNoCheck(head), after);
    try t.eq(lists.detachAfter(head), after);
    try t.eq(lists.getNextIdNoCheck(head), Null);
}