const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

pub fn SinglyLinkedList(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        head: ?*Node,
        len: usize,

        pub const Node = struct {
            next: ?*Node,
            data: T,
        };

        pub const FindResult = struct {
            prev: ?*Node,
            node: *Node,
        };

        const SinglyLinkedListT = @This();

        pub fn init(alloc: std.mem.Allocator) SinglyLinkedListT {
            return .{
                .alloc = alloc,
                .head = null,
                .len = 0,
            };
        }

        pub fn deinit(self: *SinglyLinkedListT) void {
            var cur = self.head;
            while (cur) |node| {
                cur = node.next;
                self.alloc.destroy(node);
            }
        }

        pub fn removeHead(self: *SinglyLinkedListT) ?*Node {
            const mb_head = self.head;
            if (mb_head) |head| {
                self.head = head.next;
                self.alloc.destroy(head);
                self.len -= 1;
            }
            return mb_head;
        }

        pub fn removeAfter(self: *SinglyLinkedListT, node: *Node) ?*Node {
            const mb_next = node.next;
            if (mb_next) |next| {
                node.next = next.next;
                self.alloc.destroy(next);
                self.len -= 1;
            }
            return mb_next;
        }

        pub fn find(self: *SinglyLinkedListT, item: T) ?FindResult {
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

        pub fn findCustom(self: *SinglyLinkedListT, ctx: anytype, pred: fn (@TypeOf(ctx), *Node) bool) ?*Node {
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

        pub fn insertHead(self: *SinglyLinkedListT, item: T) !*Node {
            const new = try self.alloc.create(Node);
            new.next = self.head;
            new.data = item;
            self.head = new;
            self.len += 1;
            return new;
        }

        pub fn insertAfter(self: *SinglyLinkedListT, node: *Node, item: T) !*Node {
            const new = try self.alloc.create(Node);
            new.next = node.next;
            new.data = item;
            node.next = new;
            self.len += 1;
            return new;
        }

        pub fn getHead(self: *SinglyLinkedListT) ?*Node {
            return self.head;
        }
    };
}

test "SinglyLinkedList" {
    var list = SinglyLinkedList(u32).init(t.alloc);
    defer list.deinit();

    const first = try list.insertHead(1);
    const second = try list.insertHead(2);
    try t.eq(list.len, 2);

    try t.eq(list.find(0), null);
    try t.eq(list.find(1).?, .{ .prev = second, .node = first});
    try t.eq(list.find(2).?, .{ .prev = null, .node = second });

    _ = list.removeAfter(second);
    try t.eq(list.len, 1);
    try t.eq(list.getHead().?, second);
    try t.eq(list.getHead().?.next, null);

    _ = list.removeHead();
    try t.eq(list.len, 0);
    try t.eq(list.getHead(), null);
}