const std = @import("std");
const stdx = @import("../stdx.zig");
const ds = stdx.ds;
const t = stdx.testing;
const log = stdx.log.scoped(.walk);

// Iterative walking. Let's us reuse the same walkers for dfs/bfs walking.
// Also makes it easier to add features at comptime like abort during a visit.
// Depends on a buffer or creates it's own from provided allocator.
pub fn walkPre(
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
    buf: *std.ArrayList(Node),
) void {
    var queuer = ReverseAddToBuffer(Node){ .buf = buf };
    const S = struct {
        queuer: *QueueIface(Node),
        buf: *std.ArrayList(Node),
        walker: *WalkerIface(Node),
        ctx: *VisitContext(Config),
        user_ctx: Context,
        user_visit: UserVisit(Config, Context, Node),

        fn walk(self: *@This(), node: Node) void {
            self.walker.setQueuer(self.queuer);
            self.queuer.addNodes(&.{node});
            while (self.buf.items.len > 0) {
                const last = self.buf.pop();
                self.user_visit(self.ctx, self.user_ctx, last);
                if (Config.enable_abort and self.ctx.aborted) {
                    break;
                }
                if (Config.enable_skip and self.ctx.skipped) {
                    self.ctx.skipped = false;
                    continue;
                }
                self.walker.walk(last);
            }
        }
    };
    var ctx: VisitContext(Config) = .{};
    var state = S{
        .queuer = &queuer.iface,
        .buf = buf,
        .walker = walker,
        .ctx = &ctx,
        .user_ctx = user_ctx,
        .user_visit = user_visit,
    };
    buf.clearRetainingCapacity();
    state.walk(root);
}

pub fn walkPreAlloc(
    alloc: std.mem.Allocator,
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
) void {
    var buf = std.ArrayList(Node).init(alloc);
    defer buf.deinit();
    walkPre(Config, Context, user_ctx, Node, root, walker, user_visit, &buf);
}

test "walkPreAlloc" {
    const S = struct {
        fn visit(_: *VisitContext(.{}), res: *std.ArrayList(u32), node: TestNode) void {
            res.append(node.val) catch unreachable;
        }
    };

    var res = std.ArrayList(u32).init(t.alloc);
    defer res.deinit();
    walkPreAlloc(t.alloc, .{}, *std.ArrayList(u32), &res, TestNode, TestGraph, TestWalker.getIface(), S.visit);

    try t.eqSlice(u32, res.items, &[_]u32{ 1, 2, 4, 3 });
}

// Uses a bit_buf to track whether a node in the stack has pushed its children onto the stack.
// Repeatedly checks top of the stack. If it has been expanded then it's visited and popped,
// otherwise its children are pushed onto the stack.
pub fn walkPost(
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
    buf: *std.ArrayList(Node),
    bit_buf: *ds.BitArrayList,
) void {
    var queuer = ReverseAddToBuffer(Node){ .buf = buf };
    const S = struct {
        queuer: *QueueIface(Node),
        buf: *std.ArrayList(Node),
        bit_buf: *ds.BitArrayList,
        walker: *WalkerIface(Node),
        ctx: *VisitContext(Config),
        user_ctx: Context,
        user_visit: UserVisit(Config, Context, Node),

        fn walk(self: *@This(), node: Node) void {
            self.walker.setQueuer(self.queuer);
            self.queuer.addNodes(&.{node});
            self.bit_buf.appendUnset() catch unreachable;
            while (self.buf.items.len > 0) {
                if (self.bit_buf.isSet(self.buf.items.len - 1)) {
                    const last = self.buf.pop();
                    self.user_visit(self.ctx, self.user_ctx, last);
                } else {
                    const last = self.buf.items[self.buf.items.len - 1];
                    self.bit_buf.set(self.buf.items.len - 1);
                    const last_len = self.buf.items.len;
                    self.walker.walk(last);
                    self.bit_buf.resize(self.buf.items.len) catch unreachable;
                    self.bit_buf.unsetRange(last_len, self.buf.items.len);
                }
            }
        }
    };
    var ctx: VisitContext(Config) = .{};
    var state = S{
        .queuer = &queuer.iface,
        .buf = buf,
        .bit_buf = bit_buf,
        .walker = walker,
        .ctx = &ctx,
        .user_ctx = user_ctx,
        .user_visit = user_visit,
    };
    buf.clearRetainingCapacity();
    bit_buf.clearRetainingCapacity();
    state.walk(root);
}

pub fn walkPostAlloc(
    alloc: std.mem.Allocator,
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
) void {
    var buf = std.ArrayList(Node).init(alloc);
    defer buf.deinit();
    var bit_buf = ds.BitArrayList.init(alloc);
    defer bit_buf.deinit();
    walkPost(Config, Context, user_ctx, Node, root, walker, user_visit, &buf, &bit_buf);
}

test "walkPostAlloc" {
    const S = struct {
        fn visit(_: *VisitContext(.{}), res: *std.ArrayList(u32), node: TestNode) void {
            res.append(node.val) catch unreachable;
        }
    };

    var res = std.ArrayList(u32).init(t.alloc);
    defer res.deinit();
    walkPostAlloc(t.alloc, .{}, *std.ArrayList(u32), &res, TestNode, TestGraph, TestWalker.getIface(), S.visit);

    try t.eqSlice(u32, res.items, &[_]u32{ 4, 2, 3, 1 });
}

// Uses a bit_buf to track whether a node in the stack has pushed its children onto the stack.
// Repeatedly checks top of the stack. If it has been expanded then it's visited and popped,
// otherwise its children is pushed onto the stack.
// VisitContext.enter is set true when we first process the node and add it's children,
// and false when we pop it from the stack.
pub fn walkPrePost(
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
    buf: *std.ArrayList(Node),
    bit_buf: *ds.BitArrayList,
) void {
    var queuer = ReverseAddToBuffer(Node){ .buf = buf };
    const S = struct {
        queuer: *QueueIface(Node),
        buf: *std.ArrayList(Node),
        bit_buf: *ds.BitArrayList,
        walker: *WalkerIface(Node),
        ctx: *VisitContext(Config),
        user_ctx: Context,
        user_visit: UserVisit(Config, Context, Node),

        fn walk(self: *@This(), node: Node) void {
            self.walker.setQueuer(self.queuer);
            self.queuer.addNodes(&.{node});
            self.bit_buf.appendUnset() catch unreachable;
            while (self.buf.items.len > 0) {
                if (self.bit_buf.isSet(self.buf.items.len - 1)) {
                    const last = self.buf.pop();
                    self.ctx.enter = false;
                    self.user_visit(self.ctx, self.user_ctx, last);
                } else {
                    const last = self.buf.items[self.buf.items.len - 1];
                    self.ctx.enter = true;
                    self.user_visit(self.ctx, self.user_ctx, last);
                    self.bit_buf.set(self.buf.items.len - 1);

                    if (Config.enable_skip and self.ctx.skipped) {
                        _ = self.buf.pop();
                        self.ctx.skipped = false;
                        continue;
                    }

                    const last_len = self.buf.items.len;
                    self.walker.walk(last);
                    self.bit_buf.resize(self.buf.items.len) catch unreachable;
                    self.bit_buf.unsetRange(last_len, self.buf.items.len);
                }
            }
        }
    };
    var ctx: VisitContext(Config) = .{};
    var state = S{
        .queuer = &queuer.iface,
        .buf = buf,
        .bit_buf = bit_buf,
        .walker = walker,
        .ctx = &ctx,
        .user_ctx = user_ctx,
        .user_visit = user_visit,
    };
    buf.clearRetainingCapacity();
    bit_buf.clearRetainingCapacity();
    state.walk(root);
}

pub fn walkPrePostAlloc(
    alloc: std.mem.Allocator,
    comptime Config: WalkerConfig,
    comptime Context: type,
    user_ctx: Context,
    comptime Node: type,
    root: Node,
    walker: *WalkerIface(Node),
    user_visit: UserVisit(Config, Context, Node),
) void {
    var buf = std.ArrayList(Node).init(alloc);
    defer buf.deinit();
    var bit_buf = ds.BitArrayList.init(alloc);
    defer bit_buf.deinit();
    walkPrePost(Config, Context, user_ctx, Node, root, walker, user_visit, &buf, &bit_buf);
}

test "walkPrePostAlloc" {
    const S = struct {
        fn visit(_: *VisitContext(.{}), res: *std.ArrayList(u32), node: TestNode) void {
            res.append(node.val) catch unreachable;
        }
    };

    var res = std.ArrayList(u32).init(t.alloc);
    defer res.deinit();
    walkPrePostAlloc(t.alloc, .{}, *std.ArrayList(u32), &res, TestNode, TestGraph, TestWalker.getIface(), S.visit);

    try t.eqSlice(u32, res.items, &[_]u32{ 1, 2, 4, 4, 2, 3, 3, 1 });
}

test "walkPrePostAlloc with skip" {
    const Config = WalkerConfig{ .enable_skip = true };
    const S = struct {
        fn visit(ctx: *VisitContext(Config), res: *std.ArrayList(u32), node: TestNode) void {
            if (ctx.enter) {
                if (node.val == 2) {
                    ctx.skip();
                }
            }
            res.append(node.val) catch unreachable;
        }
    };

    var res = std.ArrayList(u32).init(t.alloc);
    defer res.deinit();
    walkPrePostAlloc(t.alloc, Config, *std.ArrayList(u32), &res, TestNode, TestGraph, TestWalker.getIface(), S.visit);

    try t.eqSlice(u32, res.items, &[_]u32{ 1, 2, 3, 3, 1 });
}

pub const WalkerConfig = struct {
    // Allows visitor to stop the code.
    enable_abort: bool = false,

    // Allows visitor to skip the current node before it walks to its children.
    enable_skip: bool = false,
};

fn AddToBuffer(comptime Node: type) type {
    return struct {
        iface: QueueIface(Node) = .{
            .begin_add_node_fn = beginAddNode,
            .add_node_fn = addNode,
            .add_nodes_fn = addNodes,
        },
        buf: *std.ArrayList(Node),
        cur_insert_idx: u32 = 0,

        fn beginAddNode(iface: *QueueIface(Node), size: u32) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            const new_len = @intCast(u32, self.buf.items.len) + size;
            self.cur_insert_idx = self.buf.items.len;
            self.buf.resize(new_len) catch unreachable;
        }

        fn addNode(iface: *QueueIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            self.buf.items[self.cur_insert_idx] = node;
            self.cur_insert_idx += 1;
        }

        fn addNodes(iface: *QueueIface(Node), nodes: []const Node) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            self.buf.appendSlice(nodes) catch unreachable;
        }
    };
}

pub fn ReverseAddToBuffer(comptime Node: type) type {
    return struct {
        iface: QueueIface(Node) = .{
            .begin_add_node_fn = beginAddNode,
            .add_node_fn = addNode,
            .add_nodes_fn = addNodes,
        },
        buf: *std.ArrayList(Node),
        // Use idx plus one to avoid integer overflow.
        cur_insert_idx_p1: u32 = 0,

        fn beginAddNode(iface: *QueueIface(Node), size: u32) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            const new_len = @intCast(u32, self.buf.items.len) + size;
            self.cur_insert_idx_p1 = new_len;
            self.buf.resize(new_len) catch unreachable;
        }

        fn addNode(iface: *QueueIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            self.cur_insert_idx_p1 -= 1;
            self.buf.items[self.cur_insert_idx_p1] = node;
        }

        fn addNodes(iface: *QueueIface(Node), nodes: []const Node) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            var i: u32 = @intCast(u32, nodes.len);
            while (i > 0) {
                i -= 1;
                self.buf.append(nodes[i]) catch unreachable;
            }
        }
    };
}

fn QueueIface(comptime Node: type) type {
    return struct {
        begin_add_node_fn: fn (*@This(), u32) void,
        add_node_fn: fn (*@This(), Node) void,
        add_nodes_fn: fn (*@This(), []const Node) void,

        // When using addNode, a size is required if you want the order natural order to be FIFO.
        // You are then expected to supply that many nodes with addNode.
        fn beginAddNode(self: *@This(), size: u32) void {
            self.begin_add_node_fn(self, size);
        }

        fn addNode(self: *@This(), node: Node) void {
            self.add_node_fn(self, node);
        }

        pub fn addNodes(self: *@This(), nodes: []const Node) void {
            self.add_nodes_fn(self, nodes);
        }
    };
}

fn UserVisit(comptime Config: WalkerConfig, comptime Context: type, comptime Node: type) type {
    return fn (*VisitContext(Config), Context, Node) void;
}

pub fn VisitContext(comptime Config: WalkerConfig) type {
    return struct {
        const Self = @This();

        aborted: bool = false,

        // Used by walkPrePost to indicate entering/leaving the node.
        enter: bool = true,

        // Used by walkPre to skip walking to children for the current node.
        skipped: bool = false,

        usingnamespace if (Config.enable_abort) struct {
            pub fn abort(self: *Self) void {
                self.aborted = true;
            }
        } else struct {};

        usingnamespace if (Config.enable_skip) struct {
            pub fn skip(self: *Self) void {
                self.skipped = true;
            }
        } else struct {};
    };
}

fn UserWalker(comptime Context: type, comptime Node: type) type {
    return fn (*WalkerContext(Node), Context, Node) void;
}

pub fn WalkerContext(comptime Node: type) type {
    return struct {
        queuer: *QueueIface(Node),

        pub fn beginAddNode(self: *@This(), size: u32) void {
            self.queuer.beginAddNode(size);
        }

        pub fn addNode(self: *@This(), node: Node) void {
            self.queuer.addNode(node);
        }

        pub fn addNodes(self: *@This(), nodes: []const Node) void {
            self.queuer.addNodes(nodes);
        }
    };
}

pub fn Walker(comptime Context: type, comptime Node: type) type {
    return struct {
        iface: WalkerIface(Node) = .{
            .walk_fn = walk,
            .set_queuer_fn = setQueuer,
        },
        ctx: WalkerContext(Node),
        user_ctx: Context,
        user_walk: UserWalker(Context, Node),

        pub fn init(user_ctx: Context, user_walk: UserWalker(Context, Node)) @This() {
            return .{
                .ctx = .{
                    .queuer = undefined,
                },
                .user_ctx = user_ctx,
                .user_walk = user_walk,
            };
        }

        pub fn getIface(self: *@This()) *WalkerIface(Node) {
            return &self.iface;
        }

        pub fn walk(iface: *WalkerIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            self.user_walk(&self.ctx, self.user_ctx, node);
        }

        pub fn setQueuer(iface: *WalkerIface(Node), queuer: *QueueIface(Node)) void {
            const self = @fieldParentPtr(@This(), "iface", iface);
            self.ctx.queuer = queuer;
        }
    };
}

pub fn WalkerIface(comptime Node: type) type {
    return struct {
        walk_fn: fn (*@This(), node: Node) void,
        set_queuer_fn: fn (*@This(), queuer: *QueueIface(Node)) void,

        pub fn walk(self: *@This(), node: Node) void {
            self.walk_fn(self, node);
        }

        pub fn setQueuer(self: *@This(), queuer: *QueueIface(Node)) void {
            self.set_queuer_fn(self, queuer);
        }
    };
}

pub const TestNode = struct {
    val: u32,
    children: []const @This(),
};

pub const TestGraph = TestNode{
    .val = 1,
    .children = &[_]TestNode{
        .{
            .val = 2,
            .children = &[_]TestNode{.{
                .val = 4,
                .children = &.{},
            }},
        },
        .{
            .val = 3,
            .children = &.{},
        },
    },
};

pub var TestWalker = b: {
    const S = struct {
        fn walk(ctx: *WalkerContext(TestNode), _: void, node: TestNode) void {
            ctx.addNodes(node.children);
        }
    };
    break :b Walker(void, TestNode).init({}, S.walk);
};
