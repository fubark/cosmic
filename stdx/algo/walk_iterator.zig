const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;
const walk = @import("walk.zig");

// Iterator method is slightly slower than the callback method but is easier to use.

pub fn WalkIterator(comptime Node: type) type {
    return struct {
        const Self = @This();

        buf: std.ArrayList(Node),
        queuer: walk.ReverseAddToBuffer(Node),
        walker: *walk.WalkerIface(Node),

        pub fn initPre(self: *Self, alloc: std.mem.Allocator, root: Node, walker: *walk.WalkerIface(Node)) void {
            self.buf = std.ArrayList(Node).init(alloc);
            self.queuer = walk.ReverseAddToBuffer(Node){ .buf = &self.buf };
            self.walker = walker;
            walker.setQueuer(&self.queuer.iface);
            self.queuer.iface.addNodes(&.{root});
        }

        pub fn next(self: *Self) ?Node {
            const last = self.buf.popOrNull() orelse return null;
            self.walker.walk(last);
            return last;
        }

        pub fn deinit(self: *Self) void {
            self.buf.deinit();
        }
    };
}

test "WalkIterator.initPre" {
    var res = std.ArrayList(u32).init(t.alloc);
    defer res.deinit();

    var iter: WalkIterator(walk.TestNode) = undefined;
    iter.initPre(t.alloc, walk.TestGraph, walk.TestWalker.getIface());
    defer iter.deinit();

    while (iter.next()) |it| {
        try res.append(it.val);
    }

    try t.eqSlice(u32, res.items, &[_]u32{1, 2, 4, 3});
}