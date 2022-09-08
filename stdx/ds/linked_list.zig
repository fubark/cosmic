const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

fn SLLNode(comptime T: type) type {
    return struct {
        next: ?*@This(),
        data: T,
    };
}

fn SLLFindResult(comptime T: type) type {
    return struct {
        prev: ?*SLLNode(T),
        node: *SLLNode(T),
    };
}

pub fn SLLUnmanaged(comptime T: type) type {
    return struct {
        head: ?*Node,
        len: usize,
            
        const SLLUnmanagedT = @This();
        const Node = SLLNode(T);
        const FindResult = SLLFindResult(T);

        pub fn init() SLLUnmanagedT {
            return .{
                .head = null,
                .len = 0,
            };
        }

        pub fn deinit(self: *SLLUnmanagedT, alloc: std.mem.Allocator) void {
            var cur = self.head;
            while (cur) |node| {
                cur = node.next;
                alloc.destroy(node);
            }
        }

        pub fn removeHead(self: *SLLUnmanagedT, alloc: std.mem.Allocator) ?*Node {
            const mb_head = self.head;
            if (mb_head) |head| {
                self.head = head.next;
                alloc.destroy(head);
                self.len -= 1;
            }
            return mb_head;
        }

        pub fn removeAfter(self: *SLLUnmanagedT, alloc: std.mem.Allocator, node: *Node) ?*Node {
            const mb_next = node.next;
            if (mb_next) |next| {
                node.next = next.next;
                alloc.destroy(next);
                self.len -= 1;
            }
            return mb_next;
        }

        pub fn find(self: *SLLUnmanagedT, item: T) ?FindResult {
            if (self.head == null) {
                return null;
            }
            if (std.meta.eql(self.head.?.data, item)) {
                return FindResult{
                    .prev = null,
                    .node = self.head.?,
                };
            }
            var prev = self.head.?;
            while (prev.next) |next| {
                if (std.meta.eql(next.data, item)) {
                    return FindResult{
                        .prev = prev,
                        .node = next,
                    };
                }
                prev = next;
            }
            return null;
        }

        pub fn findCustom(self: *SLLUnmanagedT, ctx: anytype, pred: fn (@TypeOf(ctx), *Node) bool) ?*Node {
            if (self.head == null) {
                return null;
            }
            if (pred(ctx, self.head.?)) {
                return FindResult{
                    .prev = null,
                    .node = self.head.?,
                };
            }
            var prev = self.head.?;
            while (prev.next) |next| {
                if (pred(ctx, next)) {
                    return FindResult{
                        .prev = prev,
                        .node = next,
                    };
                }
                prev = next;
            }
            return null;
        }

        pub fn insertHead(self: *SLLUnmanagedT, alloc: std.mem.Allocator, item: T) !*Node {
            const new = try alloc.create(Node);
            new.next = self.head;
            new.data = item;
            self.head = new;
            self.len += 1;
            return new;
        }

        pub fn insertAfter(self: *SLLUnmanagedT, alloc: std.mem.Allocator, node: *Node, item: T) !*Node {
            const new = try alloc.create(Node);
            new.next = node.next;
            new.data = item;
            node.next = new;
            self.len += 1;
            return new;
        }
    };
}

pub fn SinglyLinkedList(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        inner: SLLUnmanaged(T),

        const SinglyLinkedListT = @This();
        const Node = SLLNode(T);
        const FindResult = SLLFindResult(T);

        pub fn init(alloc: std.mem.Allocator) SinglyLinkedListT {
            return .{
                .alloc = alloc,
                .inner = SLLUnmanaged(T).init(),
            };
        }

        pub fn deinit(self: *SinglyLinkedListT) void {
            self.inner.deinit(self.alloc);
        }

        pub fn removeHead(self: *SinglyLinkedListT) ?*Node {
            return self.inner.removeHead(self.alloc);
        }

        pub fn removeAfter(self: *SinglyLinkedListT, node: *Node) ?*Node {
            return self.inner.removeAfter(self.alloc, node);
        }

        pub fn find(self: *SinglyLinkedListT, item: T) ?FindResult {
            return self.inner.find(item);
        }

        pub fn findCustom(self: *SinglyLinkedListT, ctx: anytype, pred: fn (@TypeOf(ctx), *Node) bool) ?*Node {
            return self.inner.find(ctx, pred);
        }

        pub fn insertHead(self: *SinglyLinkedListT, item: T) !*Node {
            return self.inner.insertHead(self.alloc, item);
        }

        pub fn insertAfter(self: *SinglyLinkedListT, node: *Node, item: T) !*Node {
            return self.inner.insertAfter(self.alloc, node, item);
        }

        pub fn getHead(self: *SinglyLinkedListT) ?*Node {
            return self.inner.head;
        }

        pub fn size(self: SinglyLinkedListT) usize {
            return self.inner.len;
        }
    };
}

test "SinglyLinkedList" {
    var list = SinglyLinkedList(u32).init(t.alloc);
    defer list.deinit();

    const first = try list.insertHead(1);
    const second = try list.insertHead(2);
    try t.eq(list.size(), 2);

    try t.eq(list.find(0), null);
    try t.eq(list.find(1).?, .{ .prev = second, .node = first});
    try t.eq(list.find(2).?, .{ .prev = null, .node = second });

    _ = list.removeAfter(second);
    try t.eq(list.size(), 1);
    try t.eq(list.getHead().?, second);
    try t.eq(list.getHead().?.next, null);

    _ = list.removeHead();
    try t.eq(list.size(), 0);
    try t.eq(list.getHead(), null);
}