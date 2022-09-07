const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

pub fn Queue(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        buf: []T,
        head: usize,
        len: usize,

        const QueueT = @This();

        pub fn init(alloc: std.mem.Allocator) QueueT {
            return .{
                .alloc = alloc,
                .buf = &.{},
                .head = 0,
                .len = 0,
            };
        }

        pub fn deinit(self: *QueueT) void {
            self.alloc.free(self.buf);
            self.head = 0;
            self.len = 0;
        }

        pub fn removeHead(self: *QueueT) ?T {
            if (self.len > 0) {
                defer {
                    self.head += 1;
                    if (self.head == self.buf.len) {
                        self.head = 0;
                    }
                    self.len -= 1;
                }
                return self.buf[self.head];
            } else return null;
        }

        pub fn insertHead(self: *QueueT, item: T) !void {
            try self.ensureTotalCapacity(self.len + 1);
            if (self.head == 0) {
                self.head = self.buf.len - 1;
            } else {
                self.head -= 1;
            }
            self.buf[self.head] = item;
            self.len += 1;
        }

        pub fn insertTail(self: *QueueT, item: T) !void {
            try self.ensureTotalCapacity(self.len + 1);
            const logical_end = self.head + self.len;
            if (logical_end < self.buf.len) {
                self.buf[logical_end] = item;
            } else {
                self.buf[logical_end - self.buf.len] = item;
            }
            self.len += 1;
        }

        fn ensureTotalCapacity(self: *QueueT, new_cap: usize) !void {
            var better_cap = self.buf.len;
            if (better_cap >= new_cap) {
                return;
            }
            while (true) {
                better_cap += better_cap / 2 + 8;
                if (better_cap >= new_cap) {
                    break;
                }
            }
            const prev_cap = self.buf.len;
            self.buf = try self.alloc.reallocAtLeast(self.buf, better_cap);
            if (self.head + self.len >= prev_cap) {
                // List currently touches the end of prev capacity. Need to copy to new capacity.
                const head_to_end = prev_cap - self.head;
                std.mem.copyBackwards(T, self.buf[self.buf.len-head_to_end..], self.buf[self.head..prev_cap]);
                self.head = self.buf.len - head_to_end;
            }
        }
    };
}

test "Queue" {
    var queue = Queue(u32).init(t.alloc);
    defer queue.deinit();

    // insertHead
    try queue.insertHead(1);
    try queue.insertHead(2);
    try queue.insertHead(3);
    try t.eq(queue.len, 3);
    try t.eq(queue.removeHead().?, 3);
    try t.eq(queue.removeHead().?, 2);
    try t.eq(queue.removeHead().?, 1);
    try t.eq(queue.len, 0);

    // insertTail
    try queue.insertTail(4);
    try queue.insertTail(5);
    try queue.insertTail(6);
    try t.eq(queue.len, 3);
    try t.eq(queue.removeHead().?, 4);
    try t.eq(queue.removeHead().?, 5);
    try t.eq(queue.removeHead().?, 6);
    try t.eq(queue.len, 0);

    // resizing capacity preserves list.
    try queue.insertTail(1);
    try queue.insertTail(2);
    try queue.insertHead(3);
    try queue.insertHead(4);
    try queue.insertHead(5);
    try queue.insertHead(6);
    try queue.insertHead(7);
    try queue.insertHead(8);
    try t.eq(queue.buf.len, 8);
    try queue.insertHead(9);
    try t.eq(queue.buf.len, 20);
    try t.eq(queue.len, 9);
    try t.eq(queue.removeHead().?, 9);
    try t.eq(queue.removeHead().?, 8);
    try t.eq(queue.removeHead().?, 7);
    try t.eq(queue.removeHead().?, 6);
    try t.eq(queue.removeHead().?, 5);
    try t.eq(queue.removeHead().?, 4);
    try t.eq(queue.removeHead().?, 3);
    try t.eq(queue.removeHead().?, 1);
    try t.eq(queue.removeHead().?, 2);
    try t.eq(queue.len, 0);
}