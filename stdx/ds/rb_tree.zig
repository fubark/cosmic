const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const log = stdx.log.scoped(.rb_tree);

const Id = u32;
const OptId = Id;
const NullId = stdx.ds.CompactNull(Id);

const Color = enum(u1) {
    Black,
    Red,
};

/// Based on Zig's rb node pointer based implementation:
/// https://github.com/ziglang/std-lib-orphanage/blob/master/std/rb.zig
/// Deletion logic was redone from https://www.youtube.com/watch?v=CTvfzU_uNKE as guidance.
/// Visualize: https://www.cs.usfca.edu/~galles/visualization/RedBlack.html
pub fn RbTree(comptime Value: type) type {
    return struct {
        const Self = @This();

        root: OptId,
        buf: stdx.ds.CompactUnorderedList(Id, Node),
        cmpFn: fn (Value, Value) std.math.Order,

        const Node = struct {
            left: OptId,
            right: OptId,
            val: Value,

            parent: OptId,
            color: Color,

            fn getParentOpt(self: Node) ?Id {
                if (self.parent == NullId) {
                    return null;
                } else {
                    return self.parent;
                }
            }

            fn isRoot(self: Node) bool {
                return self.parent == NullId;
            }

            fn setChild(self: *Node, child: Id, is_left: bool) void {
                if (is_left) {
                    self.left = child;
                } else {
                    self.right = child;
                }
            }
        };

        pub fn init(alloc: std.mem.Allocator, cmp: fn (Value, Value) std.math.Order) Self {
            return .{
                .root = NullId,
                .buf = stdx.ds.CompactUnorderedList(Id, Node).init(alloc),
                .cmpFn = cmp,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buf.deinit();
        }

        /// Re-sorts a tree with a new compare function
        pub fn sort(self: *Self, cmp: fn (Value, Value) std.math.Order) !void {
            self.cmpFn = cmp;
            self.root = NullId;
            var iter = self.buf.iterator();
            while (iter.next()) |node| {
                self.buf.remove(iter.idx-1);
                _ = try self.insert(node.val);
            }
        }

        pub fn first(self: Self) ?Id {
            if (self.root == NullId) {
                return null;
            }
            var id = self.root;
            var node = self.buf.getAssumeExists(id);
            while (node.left != NullId) {
                id = node.left;
                node = self.buf.getAssumeExists(id);
            }
            return id;
        }

        pub fn firstFrom(self: Self, node_id: Id) Id {
            var id = node_id;
            var node = self.buf.getAssumeExists(id);
            while (node.left != NullId) {
                id = node.left;
                node = self.buf.getAssumeExists(id);
            }
            return id;
        }

        pub fn last(self: Self) ?Id {
            if (self.root == NullId) {
                return null;
            }
            var id = self.root;
            var node = self.buf.getAssumeExists(id);
            while (node.right != NullId) {
                id = node.right;
                node = self.buf.getAssumeExists(id);
            }
            return id;
        }

        pub fn allocValuesInOrder(self: Self, alloc: std.mem.Allocator) []const Value {
            var vals = std.ArrayList(Id).initCapacity(alloc, self.buf.size()) catch unreachable;
            var cur = self.first();
            while (cur) |id| {
                vals.appendAssumeCapacity(self.get(id).?);
                cur = self.getNext(id);
            }
            return vals.toOwnedSlice();
        }

        pub fn allocNodeIdsInOrder(self: Self, alloc: std.mem.Allocator) []const Id {
            var node_ids = std.ArrayList(Id).initCapacity(alloc, self.buf.size()) catch unreachable;
            var cur = self.first();
            while (cur) |id| {
                node_ids.appendAssumeCapacity(id);
                cur = self.getNext(id);
            }
            return node_ids.toOwnedSlice();
        }

        /// User code typically wouldn't need the node, but it is available for testing.
        pub fn getNode(self: Self, id: Id) ?Node {
            return self.buf.get(id);
        }

        pub fn get(self: Self, id: Id) ?Value {
            if (self.buf.get(id)) |node| {
                return node.val;
            } else return null;
        }

        fn getSibling(self: Self, parent: *Node, child_id: Id) OptId {
            _ = self;
            if (parent.left == child_id) {
                return parent.right;
            } else {
                return parent.left;
            }
        }

        // Replacement node (with it's children) are relinked in place of node . Node (with it's children) become detached from tree.
        fn transplant(self: *Self, node_id: Id, node: *Node, r_id: Id, mb_rnode: ?*Node) void {
            if (node_id == self.root) {
                self.root = r_id;
            } else {
                const parent = self.buf.getPtrAssumeExists(node.parent);
                parent.setChild(r_id, parent.left == node_id);
            }
            if (mb_rnode) |rnode| {
                rnode.parent = node.parent;
            }
        }

        /// If node is not part of tree, error is returned.
        pub fn remove(self: *Self, node_id: Id) anyerror!void {
            var node = self.buf.getPtr(node_id) orelse return error.DoesNotExist;

            var to_fix_nid: u32 = undefined;

            if (node.left == NullId) {
                const mb_rnode: ?*Node = if (node.right != NullId) self.buf.getPtrAssumeExists(node.right) else null;
                self.transplant(node_id, node, node.right, mb_rnode);
                to_fix_nid = node.right;
            } else if (node.right == NullId) {
                const mb_rnode: ?*Node = if (node.left != NullId) self.buf.getPtrAssumeExists(node.left) else null;
                self.transplant(node_id, node, node.left, mb_rnode);
                to_fix_nid = node.left;
            } else {
                const r_id = self.firstFrom(node.right);
                const r_node = self.buf.getPtrAssumeExists(r_id);

                // Normally this would be a value copy but since ids are tied to their nodes, the replacement node is relinked in place of the target node.
                // Transplant only relinks parent of replacement node.
                const r_parent = r_node.parent;
                self.transplant(node_id, node, r_id, r_node);
                if (r_parent != node_id) {
                    const rp = self.buf.getPtrAssumeExists(r_parent);
                    rp.setChild(node_id, rp.left == r_id);
                    node.parent = r_parent;
                } else {
                    node.parent = r_id;
                }

                // Swap colors.
                const tmp_color = r_node.color;
                r_node.color = node.color;
                node.color = tmp_color;

                // Copy r_node value to node; a recursive call to delete node will be called.
                node.val = r_node.val;

                // Relink r_node left and node left.
                // Note: r_node shouldn't have a left child since firstFrom would have returned it the child instead.
                self.buf.getPtrAssumeExists(node.left).parent = r_id;
                r_node.left = node.left;
                node.left = NullId;

                // Relink r_node right and node right.
                // Note: tmp_right can't be null since node should have two children.
                const tmp_right = node.right;
                if (r_node.right != NullId) {
                    self.buf.getPtrAssumeExists(r_node.right).parent = node_id;
                }
                node.right = r_node.right;
                if (tmp_right != r_id) {
                    self.buf.getPtrAssumeExists(tmp_right).parent = r_id;
                    r_node.right = tmp_right;
                }

                // Reduced to zero or one children case. Recurse once.
                try self.remove(node_id);
                return;
            }

            // If red was removed, just remove the node and finish.
            if (node.color == .Red) {
                self.buf.remove(node_id);
            } else {
                // If black was removed and replacement is red. Paint replacement black and we are done.
                if (to_fix_nid == NullId) {
                    // Double black. Perform fix.
                    self.removeFixUp(to_fix_nid, node.parent);
                } else {
                    const r_node = self.buf.getPtrAssumeExists(to_fix_nid);
                    if (r_node.color == .Red) {
                        // Can mark black and be done since a black was removed.
                        r_node.color = .Black;
                    } else {
                        // Double black. Perform fix.
                        self.removeFixUp(to_fix_nid, r_node.parent);
                    }
                }
                self.buf.remove(node_id);
            }
        }

        /// Handle double black cases.
        /// Assumes node is a double black. Since the node could be null, the current parent is also required.
        pub fn removeFixUp(self: *Self, node_id: OptId, parent_id: OptId) void {
            _ = node_id;

            // Case 1: Root case.
            if (parent_id == NullId) {
                return;
            }

            const parent = self.buf.getPtrAssumeExists(parent_id);
            const s_id = self.getSibling(parent, node_id);
            const is_right_sibling = parent.left == node_id;
            // Sibling must exist since node is a double black.
            const sibling = self.buf.getPtrAssumeExists(s_id);
            const s_left: ?*Node = if (sibling.left != NullId) self.buf.getPtrAssumeExists(sibling.left) else null;
            const s_right: ?*Node = if (sibling.right != NullId) self.buf.getPtrAssumeExists(sibling.right) else null;
            const s_left_black = s_left == null or s_left.?.color == .Black;
            const s_right_black = s_right == null or s_right.?.color == .Black;

            if (parent.color == .Black and sibling.color == .Red) {
                if (s_left_black and s_right_black) {
                    if (is_right_sibling) {
                        // Case 2: parent is black, right sibling is red and has two black children.
                        self.rotateLeft(parent_id, parent);
                    } else {
                        // Case 2: parent is black, left sibling is red and has two black children.
                        self.rotateRight(parent_id, parent);
                    }
                    parent.color = .Red;
                    sibling.color = .Black;
                    self.removeFixUp(node_id, parent_id);
                    return;
                }
            }

            if (parent.color == .Black and sibling.color == .Black) {
                // Case 3: left or right sibling with both black children.
                if (s_left_black and s_right_black) {
                    sibling.color = .Red;
                    // Recurse at parent.
                    self.removeFixUp(parent_id, parent.parent);
                    return;
                }
            }

            if (parent.color == .Red and sibling.color == .Black) {
                // Case 4: left or right sibling with both black children.
                if (s_left_black and s_right_black) {
                    parent.color = .Black;
                    sibling.color = .Red;
                    return;
                }
            }

            if (parent.color == .Black and sibling.color == .Black) {
                // Case 5: parent is black, right sibling is black, sibling has red left child and black right child.
                if (is_right_sibling and s_left != null and s_left.?.color == .Red and s_right_black) {
                    self.rotateRight(s_id, sibling);
                    sibling.color = .Red;
                    s_left.?.color = .Black;
                    // Call again to check for case 6.
                    self.removeFixUp(node_id, parent_id);
                    return;
                }
                // Case 5: parent is black, left sibiling is black, sibling has red right child and black left child.
                if (!is_right_sibling and s_right != null and s_right.?.color == .Red and s_left_black) {
                    self.rotateLeft(s_id, sibling);
                    sibling.color = .Red;
                    s_right.?.color = .Black;
                    // Call again to check for case 6.
                    self.removeFixUp(node_id, parent_id);
                    return;
                }
            }

            if (sibling.color == .Black) {
                // Case 6: right sibling with red right child.
                if (is_right_sibling and s_right != null and s_right.?.color == .Red) {
                    self.rotateLeft(parent_id, parent);
                    sibling.color = parent.color;
                    parent.color = .Black;
                    s_right.?.color = .Black;
                    return;
                }
                // Case 6: left sibling with red left child.
                if (!is_right_sibling and s_left != null and s_left.?.color == .Red) {
                    self.rotateRight(parent_id, parent);
                    sibling.color = parent.color;
                    parent.color = .Black;
                    s_left.?.color = .Black;
                    return;
                }
            }
        }

        /// Duplicate keys are not allowed. 
        pub fn insert(self: *Self, val: Value) !Id {
            var maybe_id: ?Id = undefined;
            var maybe_parent: ?Id = undefined;
            var is_left: bool = undefined;

            maybe_id = self.doLookup(val, &maybe_parent, &is_left);
            if (maybe_id) |_| {
                return error.DuplicateKey;
            }

            const new_id = try self.buf.add(.{
                .left = NullId,
                .right = NullId,
                .color = .Red,
                .parent = maybe_parent orelse NullId,
                .val = val,
            });

            if (maybe_parent) |parent| {
                self.buf.getPtrAssumeExists(parent).setChild(new_id, is_left);
            } else {
                self.root = new_id;
            }

            var node_id = new_id;
            while (true) {
                var node = self.buf.getPtrAssumeExists(node_id);
                const parent_id = node.getParentOpt() orelse break;
                var parent = self.buf.getPtrAssumeExists(parent_id);
                if (parent.color == .Black) {
                    // Current is red, parent is black. Nothing left to do.
                    break;
                }
                // If parent is red, there must be a grand parent that is black.
                var grandpa_id = parent.getParentOpt() orelse unreachable;
                var grandpa = self.buf.getPtrAssumeExists(grandpa_id);

                if (parent_id == grandpa.left) {
                    var opt_psibling = grandpa.right;
                    const mb_psibling: ?*Node = if (opt_psibling != NullId) self.buf.getPtrAssumeExists(opt_psibling) else null;
                    if (mb_psibling == null or mb_psibling.?.color == .Black) {
                        // Case #5, parent is red, parent sibling is black, node is inner grandchild. Rotate left first.
                        if (node_id == parent.right) {
                            self.rotateLeft(parent_id, parent);
                            parent = node; // Just rotated
                        }
                        parent.color = .Black;
                        grandpa.color = .Red;
                        self.rotateRight(grandpa_id, grandpa);
                    } else {
                        // parent and parent sibling are both red. Set both to black, and grand parent to red.
                        parent.color = .Black;
                        mb_psibling.?.color = .Black;
                        grandpa.color = .Red;
                        node_id = grandpa_id;
                    }
                } else {
                    var opt_psibling = grandpa.left;
                    const mb_psibling: ?*Node = if (opt_psibling != NullId) self.buf.getPtrAssumeExists(opt_psibling) else null;
                    if (mb_psibling == null or mb_psibling.?.color == .Black) {
                        // Case #5, parent is red, parent sibling is black, node is inner grandchild. Rotate right first.
                        if (node_id == parent.left) {
                            self.rotateRight(parent_id, parent);
                            parent = node; // Just rotated
                        }
                        parent.color = .Black;
                        grandpa.color = .Red;
                        self.rotateLeft(grandpa_id, grandpa);
                    } else {
                        // parent and parent sibling are both red. Set both to black, and grand parent to red.
                        parent.color = .Black;
                        mb_psibling.?.color = .Black;
                        grandpa.color = .Red;
                        node_id = grandpa_id;
                    }
                }
            }
            // This was an insert, there is at least one node.
            self.buf.getPtrAssumeExists(self.root).color = .Black;
            return new_id;
        }

        /// lookup searches for the value of key, using binary search. It will
        /// return a pointer to the node if it is there, otherwise it will return null.
        /// Complexity guaranteed O(log n), where n is the number of nodes book-kept
        /// by tree.
        pub fn lookup(self: Self, val: Value) ?Id {
            var parent: ?Id = undefined;
            var is_left: bool = undefined;
            return self.doLookup(val, &parent, &is_left);
        }

        fn doLookup(self: Self, val: Value, pparent: *?Id, is_left: *bool) ?Id {
            var opt_id = self.root;

            pparent.* = null;
            is_left.* = false;

            while (opt_id != NullId) {
                const node = self.buf.getAssumeExists(opt_id);
                const res = self.cmpFn(node.val, val);
                if (res == .eq) {
                    return opt_id;
                }
                pparent.* = opt_id;
                switch (res) {
                    .gt => {
                        is_left.* = true;
                        opt_id = node.left;
                    },
                    .lt => {
                        is_left.* = false;
                        opt_id = node.right;
                    },
                    .eq => unreachable, // handled above
                }
            }
            return null;
        }

        ///     e
        ///    /
        ///  (a)
        ///  / \
        /// b   c
        ///    /
        ///   d
        /// Given a, rotate a to b and c to a. a's parent becomes c and right becomes d. c's parent bcomes e and left becomes a.
        fn rotateLeft(self: *Self, node_id: Id, node: *Node) void {
            if (node.right == NullId) {
                unreachable;
            }
            var right = self.buf.getPtrAssumeExists(node.right);
            if (!node.isRoot()) {
                var parent = self.buf.getPtrAssumeExists(node.parent);
                if (parent.left == node_id) {
                    parent.left = node.right;
                } else {
                    parent.right = node.right;
                }
                right.parent = node.parent;
            } else {
                self.root = node.right;
                right.parent = NullId;
            }
            node.parent = node.right;
            node.right = right.left;
            if (node.right != NullId) {
                self.buf.getPtrAssumeExists(node.right).parent = node_id;
            }
            right.left = node_id;
        }

        /// Works similarily to rotateLeft for the right direction.
        fn rotateRight(self: *Self, node_id: Id, node: *Node) void {
            if (node.left == NullId) {
                unreachable;
            }
            var left = self.buf.getPtrAssumeExists(node.left);
            if (!node.isRoot()) {
                var parent = self.buf.getPtrAssumeExists(node.parent);
                if (parent.left == node_id) {
                    parent.left = node.left;
                } else {
                    parent.right = node.left;
                }
                left.parent = node.parent;
            } else {
                self.root = node.left;
                left.parent = NullId;
            }
            node.parent = node.left;
            node.left = left.right;
            if (node.left != NullId) {
                self.buf.getPtrAssumeExists(node.left).parent = node_id;
            }
            left.right = node_id;
        }

        pub fn getNext(self: Self, id: Id) ?Id {
            var node = self.buf.getAssumeExists(id);
            if (node.right != NullId) {
                var cur = node.right;
                node = self.buf.getAssumeExists(cur);
                while (node.left != NullId) {
                    cur = node.left;
                    node = self.buf.getAssumeExists(cur);
                }
                return cur;
            }
            var cur = id;
            while (true) {
                if (node.parent != NullId) {
                    var p = self.buf.getAssumeExists(node.parent);
                    if (cur != p.right) {
                        return node.parent;
                    }
                    cur = node.parent;
                    node = p;
                } else {
                    return null;
                }
            }
        }
    };
}

fn testCompare(left: u32, right: u32) std.math.Order {
    if (left < right) {
        return .lt;
    } else if (left == right) {
        return .eq;
    } else if (left > right) {
        return .gt;
    }
    unreachable;
}

fn testCompareReverse(left: u32, right: u32) std.math.Order {
    return testCompare(right, left);
}

test "Insert case #1: current node parent is black" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const root = try tree.insert(10);
    const node = try tree.insert(9);

    try t.eq(tree.getNode(root).?.color, .Black);
    try t.eq(tree.getNode(root).?.left, node);
    try t.eq(tree.getNode(node).?.color, .Red);
    try t.eq(tree.getNode(node).?.parent, root);
}

test "Insert case #2/#3/#4: both parent and parent sibling are red" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const root = try tree.insert(10);
    const parent = try tree.insert(9);
    const psibling = try tree.insert(11);
    const node = try tree.insert(8);

    try t.eq(tree.getNode(root).?.color, .Black);
    try t.eq(tree.getNode(root).?.left, parent);
    try t.eq(tree.getNode(root).?.right, psibling);
    try t.eq(tree.getNode(parent).?.color, .Black);
    try t.eq(tree.getNode(parent).?.left, node);
    try t.eq(tree.getNode(psibling).?.color, .Black);
    try t.eq(tree.getNode(node).?.color, .Red);
    try t.eq(tree.getNode(node).?.parent, parent);
}

test "Insert case #5: parent is red but parent sibling is black, node is inner grandchild" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const root = try tree.insert(100);
    const parent = try tree.insert(50);
    _ = try tree.insert(150);
    _ = try tree.insert(25);
    const node = try tree.insert(75);
    _ = try tree.insert(80);
    _ = try tree.insert(70);
    _ = try tree.insert(60);

    try t.eq(tree.getNode(node).?.parent, NullId);
    try t.eq(tree.getNode(node).?.color, .Black);
    try t.eq(tree.getNode(node).?.right, root);
    try t.eq(tree.getNode(node).?.left, parent);

    try t.eq(tree.getNode(root).?.color, .Red);
    try t.eq(tree.getNode(root).?.parent, node);

    try t.eq(tree.getNode(parent).?.color, .Red);
    try t.eq(tree.getNode(parent).?.parent, node);
}

test "Insert case #6: parent is red but parent sibling is black, node is outer grandchild" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const root = try tree.insert(100);
    const parent = try tree.insert(50);
    _ = try tree.insert(150);
    const node = try tree.insert(25);
    _ = try tree.insert(70);
    _ = try tree.insert(20);
    _ = try tree.insert(30);
    _ = try tree.insert(15);

    try t.eq(tree.getNode(parent).?.parent, NullId);
    try t.eq(tree.getNode(parent).?.color, .Black);
    try t.eq(tree.getNode(parent).?.right, root);
    try t.eq(tree.getNode(parent).?.left, node);

    try t.eq(tree.getNode(root).?.color, .Red);
    try t.eq(tree.getNode(root).?.parent, parent);

    try t.eq(tree.getNode(node).?.color, .Red);
    try t.eq(tree.getNode(node).?.parent, parent);
}

test "Insert in order." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    _ = try tree.insert(1);
    _ = try tree.insert(2);
    _ = try tree.insert(3);
    _ = try tree.insert(4);
    _ = try tree.insert(5);
    _ = try tree.insert(6);
    _ = try tree.insert(7);
    _ = try tree.insert(8);
    _ = try tree.insert(9);
    _ = try tree.insert(10);

    const vals = tree.allocValuesInOrder(t.alloc);
    defer t.alloc.free(vals);
    try t.eqSlice(Id, vals, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });
}

test "Insert in reverse order." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    _ = try tree.insert(10);
    _ = try tree.insert(9);
    _ = try tree.insert(8);
    _ = try tree.insert(7);
    _ = try tree.insert(6);
    _ = try tree.insert(5);
    _ = try tree.insert(4);
    _ = try tree.insert(3);
    _ = try tree.insert(2);
    _ = try tree.insert(1);

    const vals = tree.allocValuesInOrder(t.alloc);
    defer t.alloc.free(vals);
    try t.eqSlice(Id, vals, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });
}

test "inserting and looking up" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();
    const orig: u32 = 1000;
    const node_id = try tree.insert(orig);
    // Assert that identical value finds the same pointer
    try t.eq(tree.lookup(1000), node_id);
    // Assert that insert duplicate returns error.
    try t.expectError(tree.insert(1000), error.DuplicateKey);
    try t.eq(tree.lookup(1000), node_id);
    try t.eq(tree.get(node_id).?, orig);
    // Assert that if looking for a non-existing value, return null.
    try t.eq(tree.lookup(1234), null);
}

test "multiple inserts, followed by calling first and last" {
    // if (@import("builtin").arch == .aarch64) {
    //     // TODO https://github.com/ziglang/zig/issues/3288
    //     return error.SkipZigTest;
    // }
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    _ = try tree.insert(0);
    _ = try tree.insert(1);
    _ = try tree.insert(2);
    const third_id = try tree.insert(3);
    try t.eq(tree.get(tree.first().?).?, 0);
    try t.eq(tree.get(tree.last().?).?, 3);
    try t.eq(tree.lookup(3), third_id);
    tree.sort(testCompareReverse) catch unreachable;
    try t.eq(tree.get(tree.first().?).?, 3);
    try t.eq(tree.get(tree.last().?).?, 0);
    try t.eq(tree.lookup(3), third_id);
}

test "Remove root with no children." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    try t.eq(tree.root, a);

    try tree.remove(a);
    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{});
}

test "Remove root with left red child." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.left, b);
    try t.eq(tree.getNode(b).?.color, .Red);

    try tree.remove(a);
    try t.eq(tree.getNode(b).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b });
}

test "Remove root with right red child." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(15);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.right, b);
    try t.eq(tree.getNode(b).?.color, .Red);

    try tree.remove(a);
    try t.eq(tree.getNode(b).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b });
}

test "Remove root with two red children." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.left, b);
    try t.eq(tree.getNode(a).?.right, c);
    try t.eq(tree.getNode(b).?.color, .Red);
    try t.eq(tree.getNode(c).?.color, .Red);

    try tree.remove(a);
    try t.eq(tree.root, c);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(c).?.left, b);
    try t.eq(tree.getNode(b).?.color, .Red);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b, c });
}

test "Remove red non-root." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.left, b);
    try t.eq(tree.getNode(b).?.color, .Red);

    try tree.remove(b);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ a });
}

test "Remove black non-root with left red child." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(3);
    const b = try tree.insert(2);
    const c = try tree.insert(4);
    const d = try tree.insert(1);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(b);

    try t.eq(tree.getNode(d).?.parent, a);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ d, a, c });
}

test "Remove black non-root with right red child." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(3);
    const b = try tree.insert(2);
    const c = try tree.insert(4);
    const d = try tree.insert(5);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(c);

    try t.eq(tree.getNode(d).?.parent, a);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b, a, d });
}

test "Remove non-root with double black case: Parent is red, right sibling is black, and sibling's children are black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(15);
    const b = try tree.insert(10);
    const c = try tree.insert(20);
    const d = try tree.insert(17);
    const e = try tree.insert(23);
    const f = try tree.insert(25);
    try tree.remove(f);
    try t.eq(tree.getNode(c).?.color, .Red);
    try t.eq(tree.getNode(d).?.color, .Black);
    try t.eq(tree.getNode(e).?.color, .Black);
    try t.eq(tree.getNode(e).?.left, NullId);
    try t.eq(tree.getNode(e).?.right, NullId);

    try tree.remove(d);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(c).?.left, NullId);
    try t.eq(tree.getNode(e).?.color, .Red);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b, a, c, e });
}

test "Remove non-root with double black case: Parent is red, left sibling is black, and sibling's children are black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(15);
    const b = try tree.insert(10);
    const c = try tree.insert(20);
    const d = try tree.insert(13);
    const e = try tree.insert(7);
    const f = try tree.insert(5);
    try tree.remove(f);
    try t.eq(tree.getNode(b).?.color, .Red);
    try t.eq(tree.getNode(d).?.color, .Black);
    try t.eq(tree.getNode(e).?.color, .Black);
    try t.eq(tree.getNode(e).?.left, NullId);
    try t.eq(tree.getNode(e).?.right, NullId);

    try tree.remove(d);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(b).?.right, NullId);
    try t.eq(tree.getNode(e).?.color, .Red);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ e, b, a, c });
}

test "Remove non-root with double black case: Right sibling is black, and sibling's right child is red." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(20);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(c).?.right, d);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(b);
    try t.eq(tree.root, c);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ a, c, d });
}

test "Remove non-root with double black case: Left sibling is black, and sibling's left child is red." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(4);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(b).?.left, d);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(c);
    try t.eq(tree.root, b);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ d, b, a });
}

test "Remove non-root with double black case: Parent is black, right sibling is red, sibling's children are black" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(20);
    const e = try tree.insert(25);
    const f = try tree.insert(30);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Red);
    try t.eq(tree.getNode(d).?.left, c);
    try t.eq(tree.getNode(d).?.right, e);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(e).?.color, .Black);

    try tree.remove(b);
    try t.eq(tree.root, d);
    try t.eq(tree.getNode(c).?.color, .Red);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);
    try t.eq(tree.getNode(e).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ a, c, d, e, f });
}

test "Remove non-root with double black case: Parent is black, left sibling is red, sibling's children are black" {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(4);
    const e = try tree.insert(3);
    const f = try tree.insert(2);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Red);
    try t.eq(tree.getNode(d).?.left, e);
    try t.eq(tree.getNode(d).?.right, b);
    try t.eq(tree.getNode(e).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);

    try tree.remove(c);
    try t.eq(tree.root, d);
    try t.eq(tree.getNode(b).?.color, .Red);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);
    try t.eq(tree.getNode(e).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ f, e, d, b, a });
}

test "Remove non-root with double black case: Parent is black, right sibling is black, sibling's left child is red, sibling's right child is black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(13);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(c).?.left, d);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(b);
    try t.eq(tree.root, d);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ a, d, c });
}

test "Remove non-root with double black case: Parent is black, left sibling is black, sibling's right child is red, sibling's left child is black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(10);
    const b = try tree.insert(5);
    const c = try tree.insert(15);
    const d = try tree.insert(7);
    try t.eq(tree.getNode(c).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(b).?.right, d);
    try t.eq(tree.getNode(d).?.color, .Red);

    try tree.remove(c);
    try t.eq(tree.root, d);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(d).?.color, .Black);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b, d, a });
}

test "Remove non-root with double black case: Parent is black, right sibling is black, and sibling's children are black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(15);
    const b = try tree.insert(10);
    const c = try tree.insert(20);
    const d = try tree.insert(5);
    try tree.remove(d);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Black);

    try tree.remove(b);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Red);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ a, c });
}

test "Remove non-root with double black case: Parent is black, left sibling is black, and sibling's children are black." {
    var tree = RbTree(u32).init(t.alloc, testCompare);
    defer tree.deinit();

    const a = try tree.insert(15);
    const b = try tree.insert(10);
    const c = try tree.insert(20);
    const d = try tree.insert(5);
    try tree.remove(d);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Black);
    try t.eq(tree.getNode(c).?.color, .Black);

    try tree.remove(c);
    try t.eq(tree.root, a);
    try t.eq(tree.getNode(a).?.color, .Black);
    try t.eq(tree.getNode(b).?.color, .Red);

    const node_ids = tree.allocNodeIdsInOrder(t.alloc);
    defer t.alloc.free(node_ids);
    try t.eqSlice(Id, node_ids, &.{ b, a });
}