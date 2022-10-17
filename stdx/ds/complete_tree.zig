const std = @import("std");
const stdx = @import("../stdx.zig");
const ds = stdx.ds;
const t = stdx.testing;

const log = stdx.log.scoped(.complete_tree);

// Like a BTree but doesn't do self balancing.
// Nodes can have at most BF (branching factor) children.
// Appending a node will insert into the next slot to preserve a complete tree.
// Stored in a dense array for fast access to all nodes.
pub fn CompleteTreeArray(comptime BF: u16, comptime T: type) type {
    return struct {
        const Self = @This();

        const NodeId = u32;

        nodes: std.ArrayList(T),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .nodes = std.ArrayList(T).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
        }

        pub fn getNodePtr(self: *Self, id: NodeId) *T {
            return &self.nodes.items[id];
        }

        pub fn getNode(self: *Self, id: NodeId) T {
            return self.nodes.items[id];
        }

        pub fn getParent(self: *Self, id: NodeId) ?NodeId {
            _ = self;
            if (id == 0) {
                return null;
            } else {
                return (id - 1) / BF;
            }
        }

        pub fn getParentNode(self: *Self, id: NodeId) ?T {
            const parent_id = self.getParent(id);
            return self.getNode(parent_id);
        }

        // Includes self.
        pub fn getSiblings(self: *Self, id: NodeId, buf: []NodeId) []const NodeId {
            if (id == 0) {
                buf[0] = 0;
                return buf[0..1];
            } else {
                const parent = self.getParent(id).?;
                return self.getChildren(parent, buf);
            }
        }

        pub fn getChildrenRange(self: *Self, id: NodeId) stdx.IndexSlice(NodeId) {
            const start = BF * id + 1;
            const end = std.math.min(start + BF, self.nodes.items.len);
            return .{ .start = start, .end = end };
        }

        pub fn getChildren(self: *Self, id: NodeId, buf: []NodeId) []const NodeId {
            var i: u32 = 0;
            const range = self.getChildrenRange(id);
            const len = if (range.end > range.start) range.end - range.start else 0;
            var cur = range.start;
            while (cur < range.end) : (cur += 1) {
                buf[i] = cur;
                i += 1;
            }
            return buf[0..len];
        }

        // Leaf node before in-order.
        // Since leaves can only be apart by one depth, this is a simple O(1) op.
        pub fn isLeafNodeBefore(self: *Self, node: NodeId, target: NodeId) bool {
            const node_d = self.getDepthAt(node);
            const target_d = self.getDepthAt(target);
            if (node_d > target_d) {
                return true;
            } else if (node_d < target_d) {
                return false;
            } else {
                return node < target;
            }
        }

        // First leaf in-order.
        pub fn getFirstLeaf(self: *Self) NodeId {
            const d = self.getDepth();
            return self.getFirstAtDepth(d);
        }

        // Last leaf in-order.
        pub fn getLastLeaf(self: *Self) NodeId {
            const d = self.getDepth();
            const max_nodes = self.getMaxNodesAtDepth(d);
            const _size = self.size();
            if (_size > max_nodes - BF) {
                return _size - 1;
            } else {
                // Get the last node one depth lower.
                return max_nodes - self.getMaxLeavesAtDepth(d) - 1;
            }
        }

        // Assumes leaf node and returns the previous leaf in-order.
        pub fn getPrevLeaf(self: *Self, leaf: NodeId) ?NodeId {
            const last = @intCast(u32, self.nodes.items.len) - 1;
            const last_d = self.getDepthAt(last);
            const first = self.getFirstAtDepth(last_d);
            if (leaf >= first) {
                if (leaf == first) {
                    // First in-order.
                    return null;
                } else {
                    return leaf - 1;
                }
            } else {
                // Leaf is in depth-1.
                const max_leaves = self.getMaxLeaves();
                const num_parents = (last - first) / BF + 1;
                const first_dm1 = first - max_leaves / BF;
                if (leaf == first_dm1 + num_parents) {
                    // At first leaf in depth-1
                    return last;
                } else {
                    return leaf - 1;
                }
            }
        }

        // Assumes leaf node and returns the next leaf in-order.
        pub fn getNextLeaf(self: *Self, leaf: NodeId) ?NodeId {
            const last = @intCast(u32, self.nodes.items.len) - 1;
            const last_d = self.getDepthAt(last);
            const first = self.getFirstAtDepth(last_d);
            if (leaf < last) {
                if (leaf == first - 1) {
                    // Last in-order.
                    return null;
                } else {
                    return leaf + 1;
                }
            } else {
                const max_leaves = self.getMaxLeaves();
                if (last >= first + max_leaves - BF) {
                    // Last in-order.
                    return null;
                } else {
                    // Get leaf one depth higher.
                    const num_parents = (last - first) / BF + 1;
                    const first_dm1 = first - max_leaves / BF;
                    return first_dm1 + num_parents;
                }
            }
        }

        // Assumes buffer is big enough. Caller should use getMaxLeaves() to ensure buffer size.
        pub fn getInOrderLeaves(self: *Self, buf: []NodeId) []const NodeId {
            const d = self.getDepth();
            const first_d = self.getFirstAtDepth(d);
            var i: u32 = 0;
            while (i < self.nodes.items.len - first_d) : (i += 1) {
                buf[i] = first_d + i;
            }
            const num_parents = (@intCast(u32, self.nodes.items.len - 1) - first_d) / BF + 1;
            const max_parents = self.getMaxLeavesAtDepth(d - 1);
            if (num_parents != max_parents) {
                const start = self.getFirstAtDepth(d - 1) + num_parents;
                const buf_end = i + (max_parents - num_parents);
                var j: u32 = 0;
                while (i < buf_end) : (i += 1) {
                    buf[i] = start + j;
                    j += 1;
                }
            }
            return buf[0..i];
        }

        pub fn getLeavesRange(self: *Self) stdx.IndexSlice(NodeId) {
            const d = self.getDepth();
            if (d == 0) {
                return .{ .start = 0, .end = 0 };
            }
            const first_d = self.getFirstAtDepth(d);
            const num_parents = (@intCast(u32, self.nodes.items.len - 1) - first_d) / BF + 1;
            const max_parents = self.getMaxLeavesAtDepth(d - 1);
            if (num_parents == max_parents) {
                return .{ .start = first_d, .end = first_d + self.getMaxLeavesAtDepth(d) };
            } else {
                const start = self.getFirstAtDepth(d - 1) + num_parents;
                return .{ .start = start, .end = start + (max_parents - num_parents) + @intCast(u32, self.nodes.items.len - first_d) };
            }
        }

        // First node at depth.
        // (BF^d - 1) / (BF - 1)
        pub fn getFirstAtDepth(self: *Self, d: u32) NodeId {
            _ = self;
            if (d < 2) {
                return d;
            } else {
                return (std.math.pow(u32, BF, d) - 1) / (BF - 1);
            }
        }

        // (BF^(d+1) - 1) / (BF - 1)
        pub fn getMaxNodesAtDepth(self: *Self, d: u32) u32 {
            _ = self;
            if (d < 1) {
                return 1;
            } else {
                return (std.math.pow(u32, BF, d + 1) - 1) / (BF - 1);
            }
        }

        pub fn getDepth(self: *Self) u32 {
            if (self.nodes.items.len == 0) {
                unreachable;
            }
            return self.getDepthAt(@intCast(u32, self.nodes.items.len - 1));
        }

        // Root is depth=0
        // trunc(log(BF, n * (BF - 1) + 1))
        fn getDepthAt(self: *Self, id: NodeId) u32 {
            _ = self;
            if (id < 2) {
                return id;
            } else {
                return @floatToInt(u32, @trunc(std.math.log(f32, BF, @intToFloat(f32, id * (BF - 1) + 1))));
            }
        }

        pub fn getMaxLeaves(self: *Self) u32 {
            return self.getMaxLeavesAtDepth(self.getDepth());
        }

        pub fn getMaxLeavesAtDepth(self: *Self, d: u32) u32 {
            _ = self;
            return std.math.pow(u32, BF, d);
        }

        pub fn swap(self: *Self, a: NodeId, b: NodeId) void {
            const a_node = self.getNodePtr(a);
            const b_node = self.getNodePtr(b);
            const temp = a_node.*;
            a_node.* = b_node.*;
            b_node.* = temp;
        }

        pub fn append(self: *Self, node: T) !NodeId {
            const id = @intCast(u32, self.nodes.items.len);
            try self.nodes.append(node);
            return id;
        }

        pub fn resize(self: *Self, _size: u32) !void {
            try self.nodes.resize(_size);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.nodes.clearRetainingCapacity();
        }

        pub fn size(self: *Self) u32 {
            return @intCast(u32, self.nodes.items.len);
        }
    };
}

test "CompleteTreeArray BF=2" {
    var tree = CompleteTreeArray(2, u32).init(t.alloc);
    defer tree.deinit();

    const root = try tree.append(1);
    try t.eq(root, 0);
    try t.eq(tree.getNode(root), 1);

    // Add more nodes.
    _ = try tree.append(2);
    _ = try tree.append(3);
    _ = try tree.append(4);

    var buf: [5]u32 = undefined;
    var children = tree.getChildren(0, &buf);
    try t.eq(children.len, 2);
    try t.eq(tree.getNode(children[0]), 2);
    try t.eq(tree.getNode(children[1]), 3);

    // Node with partial children list.
    children = tree.getChildren(1, &buf);
    try t.eq(children.len, 1);
    try t.eq(tree.getNode(children[0]), 4);

    // Node with no children list.
    children = tree.getChildren(2, &buf);
    try t.eq(children.len, 0);

    // Get parent.
    try t.eq(tree.getParent(0), null);
    try t.eq(tree.getParent(1), 0);
    try t.eq(tree.getParent(2), 0);
    try t.eq(tree.getParent(3), 1);

    // Get siblings.
    try t.eqSlice(u32, tree.getSiblings(0, &buf), &[_]u32{0});
    try t.eqSlice(u32, tree.getSiblings(1, &buf), &[_]u32{ 1, 2 });
    try t.eqSlice(u32, tree.getSiblings(2, &buf), &[_]u32{ 1, 2 });
    try t.eqSlice(u32, tree.getSiblings(3, &buf), &[_]u32{3});

    try t.eq(tree.getDepth(), 2);
    try t.eq(tree.getDepthAt(0), 0);
    try t.eq(tree.getDepthAt(1), 1);
    try t.eq(tree.getDepthAt(2), 1);
    try t.eq(tree.getDepthAt(3), 2);
    try t.eq(tree.getFirstAtDepth(2), 3);

    try t.eq(tree.getFirstLeaf(), 3);
    try t.eq(tree.getNextLeaf(3), 2);
    try t.eq(tree.getNextLeaf(2), null);
    try t.eq(tree.getPrevLeaf(2), 3);
    try t.eq(tree.getPrevLeaf(3), null);
    try t.eq(tree.getLastLeaf(), 2);

    try t.eq(tree.getMaxLeavesAtDepth(2), 4);
    try t.eq(tree.getLeavesRange(), .{ .start = 2, .end = 4 });

    try t.eqSlice(u32, tree.getInOrderLeaves(&buf), &[_]u32{ 3, 2 });

    try t.eq(tree.isLeafNodeBefore(2, 3), false);
}

test "CompleteTreeArray BF=3" {
    var tree = CompleteTreeArray(3, u32).init(t.alloc);
    defer tree.deinit();

    const root = try tree.append(1);
    try t.eq(root, 0);
    try t.eq(tree.getNode(root), 1);

    // Add more nodes.
    _ = try tree.append(2);
    _ = try tree.append(3);
    _ = try tree.append(4);
    _ = try tree.append(5);

    var buf: [5]u32 = undefined;
    var children = tree.getChildren(0, &buf);
    try t.eq(children.len, 3);
    try t.eq(tree.getNode(children[0]), 2);
    try t.eq(tree.getNode(children[1]), 3);
    try t.eq(tree.getNode(children[2]), 4);

    // Node with partial children list.
    children = tree.getChildren(1, &buf);
    try t.eq(children.len, 1);
    try t.eq(tree.getNode(children[0]), 5);

    // Node with no children list.
    children = tree.getChildren(2, &buf);
    try t.eq(children.len, 0);

    // Get parent.
    try t.eq(tree.getParent(0), null);
    try t.eq(tree.getParent(1), 0);
    try t.eq(tree.getParent(2), 0);
    try t.eq(tree.getParent(3), 0);
    try t.eq(tree.getParent(4), 1);

    // Get siblings.
    try t.eqSlice(u32, tree.getSiblings(0, &buf), &[_]u32{0});
    try t.eqSlice(u32, tree.getSiblings(1, &buf), &[_]u32{ 1, 2, 3 });
    try t.eqSlice(u32, tree.getSiblings(2, &buf), &[_]u32{ 1, 2, 3 });
    try t.eqSlice(u32, tree.getSiblings(3, &buf), &[_]u32{ 1, 2, 3 });
    try t.eqSlice(u32, tree.getSiblings(4, &buf), &[_]u32{4});

    try t.eq(tree.getDepth(), 2);
    try t.eq(tree.getDepthAt(13), 3);
    // Useful to test the threshold between depths.
    try t.eq(tree.getDepthAt(39), 3);
    try t.eq(tree.getDepthAt(40), 4);
    try t.eq(tree.getFirstAtDepth(2), 4);
    try t.eq(tree.getFirstAtDepth(3), 13);
    try t.eq(tree.getMaxNodesAtDepth(0), 1);
    try t.eq(tree.getMaxNodesAtDepth(1), 4);
    try t.eq(tree.getMaxNodesAtDepth(2), 13);
    try t.eq(tree.getMaxNodesAtDepth(3), 40);

    try t.eq(tree.getFirstLeaf(), 4);
    try t.eq(tree.getNextLeaf(4), 2);
    try t.eq(tree.getNextLeaf(2), 3);
    try t.eq(tree.getNextLeaf(3), null);
    try t.eq(tree.getPrevLeaf(3), 2);
    try t.eq(tree.getPrevLeaf(2), 4);
    try t.eq(tree.getPrevLeaf(4), null);
    try t.eq(tree.getLastLeaf(), 3);

    try t.eq(tree.getMaxLeavesAtDepth(2), 9);
    try t.eq(tree.getLeavesRange(), .{ .start = 2, .end = 5 });

    try t.eqSlice(u32, tree.getInOrderLeaves(&buf), &[_]u32{ 4, 2, 3 });

    try t.eq(tree.isLeafNodeBefore(2, 3), true);
    try t.eq(tree.isLeafNodeBefore(2, 4), false);
}

test "CompleteTreeArray BF=4" {
    var tree = CompleteTreeArray(4, u32).init(t.alloc);
    defer tree.deinit();

    try t.eq(tree.getFirstAtDepth(3), 21);
    try t.eq(tree.getDepthAt(21), 3);
}
