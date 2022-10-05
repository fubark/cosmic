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
            
        const SLLUnmanagedT = @This();
        pub const Node = SLLNode(T);
        const FindResult = SLLFindResult(T);

        pub fn init() SLLUnmanagedT {
            return .{
                .head = null,
            };
        }

        pub fn deinit(self: *SLLUnmanagedT, alloc: std.mem.Allocator) void {
            var cur = self.head;
            while (cur) |node| {
                cur = node.next;
                alloc.destroy(node);
            }
            self.head = null;
        }

        pub fn size(self: SLLUnmanagedT) u32 {
            var i: u32 = 0;
            var cur = self.head;
            while (cur) |node| {
                i += 1;
                cur = node.next;
            }
            return i;
        }

        pub fn removeHead(self: *SLLUnmanagedT, alloc: std.mem.Allocator) ?T {
            const mb_head = self.head;
            if (mb_head) |head| {
                const data = head.data;
                self.head = head.next;
                alloc.destroy(head);
                return data;
            } else return null;
        }

        pub fn removeAfter(self: *SLLUnmanagedT, alloc: std.mem.Allocator, node: *Node) ?T {
            _ = self;
            const mb_next = node.next;
            if (mb_next) |next| {
                const data = next.data;
                node.next = next.next;
                alloc.destroy(next);
                return data;
            } else return null;
        }

        pub fn removeAfterOrHead(self: *SLLUnmanagedT, alloc: std.mem.Allocator, mb_node: ?*Node) ?T {
            if (mb_node) |node| {
                return self.removeAfter(alloc, node);
            } else {
                return self.removeHead(alloc);
            }
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

        pub fn findCustom(self: *SLLUnmanagedT, ctx: anytype, pred: fn (@TypeOf(ctx), T) bool) ?FindResult {
            if (self.head == null) {
                return null;
            }
            if (pred(ctx, self.head.?.data)) {
                return FindResult{
                    .prev = null,
                    .node = self.head.?,
                };
            }
            var prev = self.head.?;
            while (prev.next) |next| {
                if (pred(ctx, next.data)) {
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
            new.* = .{
                .next = self.head,
                .data = item,
            };
            self.head = new;
            return new;
        }

        pub fn insertAfter(self: *SLLUnmanagedT, alloc: std.mem.Allocator, node: *Node, item: T) !*Node {
            _ = self;
            const new = try alloc.create(Node);
            new.* = .{
                .next = node.next,
                .data = item,
            };
            node.next = new;
            return new;
        }

        pub fn insertAfterOrHead(self: *SLLUnmanagedT, alloc: std.mem.Allocator, mb_node: ?*Node, item: T) !*Node {
            if (mb_node) |node| {
                return self.insertAfter(alloc, node, item);
            } else {
                return self.insertHead(alloc, item);
            }
        }
    };
}

pub fn SinglyLinkedList(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        inner: SLLUnmanaged(T),

        const SinglyLinkedListT = @This();
        pub const Node = SLLNode(T);
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

        pub fn removeHead(self: *SinglyLinkedListT) ?T {
            return self.inner.removeHead(self.alloc);
        }

        pub fn removeAfter(self: *SinglyLinkedListT, node: *Node) ?T {
            return self.inner.removeAfter(self.alloc, node);
        }
            
        pub fn removeAfterOrHead(self: *SinglyLinkedListT, mb_node: ?*Node) ?T {
            return self.inner.removeAfterOrHead(self.alloc, mb_node);
        }

        pub fn find(self: *SinglyLinkedListT, item: T) ?FindResult {
            return self.inner.find(item);
        }

        pub fn findCustom(self: *SinglyLinkedListT, ctx: anytype, pred: fn (@TypeOf(ctx), T) bool) ?FindResult {
            return self.inner.find(ctx, pred);
        }

        pub fn insertHead(self: *SinglyLinkedListT, item: T) !*Node {
            return self.inner.insertHead(self.alloc, item);
        }

        pub fn insertAfter(self: *SinglyLinkedListT, node: *Node, item: T) !*Node {
            return self.inner.insertAfter(self.alloc, node, item);
        }

        pub fn insertAfterOrHead(self: *SinglyLinkedListT, mb_node: ?*Node, item: T) !*Node {
            return self.inner.insertAfterOrHead(self.alloc, mb_node, item);
        }

        pub fn isEmpty(self: SinglyLinkedListT) bool {
            return self.inner.head == null;
        }

        pub fn head(self: *SinglyLinkedListT) ?*Node {
            return self.inner.head;
        }

        pub fn size(self: SinglyLinkedListT) usize {
            return self.inner.size();
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

    var removed = list.removeAfter(second);
    try t.eq(removed, 1);
    try t.eq(list.size(), 1);
    try t.eq(list.head().?, second);
    try t.eq(list.head().?.next, null);

    removed = list.removeHead();
    try t.eq(removed, 2);
    try t.eq(list.size(), 0);
    try t.eq(list.head(), null);
}