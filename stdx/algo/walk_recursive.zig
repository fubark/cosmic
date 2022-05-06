// Walking that doesn't need allocations.

pub fn UserVisit(comptime Node: type, comptime Context: type, comptime IncludeEnter: bool) type {
    if (IncludeEnter) {
        return fn(Context, Node, enter: bool) void;
    } else {
        return fn(Context, Node) void;
    }
}

fn VisitIface(comptime Node: type) type {
    return struct {
        visit_fn: fn(*@This(), Node) void,

        fn visit(self: *@This(), node: Node) void {
            self.visit_fn(self, node);
        }
    };
}

pub fn WalkContext(comptime Context: type, comptime Node: type) type {
    return struct {
        visitor: *VisitIface(Node),
        user_ctx: Context,

        pub fn visit(self: *@This(), node: Node) void {
            self.visitor.visit(node);
        }
    };
}

fn UserWalkFn(comptime Context: type, comptime Node: type) type {
    return fn (*WalkContext(Context, Node), Node) void;
}

pub fn Walker(comptime Context: type, comptime Node: type) type {
    return struct {
        ctx: WalkContext(Context, Node),
        user_walk: UserWalkFn(Context, Node),

        pub fn init(user_ctx: Context, user_walk: UserWalkFn(Context, Node)) @This() {
            return .{
                .ctx = .{
                    // Visit iface is injected when walker is used.
                    .visitor = undefined,
                    .user_ctx = user_ctx,
                },
                .user_walk = user_walk,
            };
        }

        pub fn walk(self: *@This(), visitor: *VisitIface(Node), node: Node) void {
            self.ctx.visitor = visitor;
            self.user_walk(&self.ctx, node);
        }
    };
}

pub fn ChildArrayListWalker(comptime Node: type) Walker(void, Node) {
    const S = struct {
        fn walk(ctx: *WalkContext(void, Node), node: Node) void {
            for (node.children.items) |it| {
                ctx.visit(it);
            }
        }
    };
    return Walker(void, Node).init({}, S.walk);
}

pub fn walkPrePost(comptime Context: type, user_ctx: Context, comptime Node: type, root: Node,
        walker: anytype, user_visit: UserVisit(Node, Context, true)) void {
    const S = struct {
        inner: VisitIface(Node) = .{
            .visit_fn = visit,
        },
        user_ctx: Context,
        user_visit: UserVisit(Node, Context, true),
        walker: @TypeOf(walker),

        fn visit(ptr: *VisitIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "inner", ptr);
            self.user_visit(self.user_ctx, node, true);
            self.walker.walk(ptr, node);
            self.user_visit(self.user_ctx, node, false);
        }
    };
    var visitor = S{ .user_visit = user_visit, .user_ctx = user_ctx, .walker = walker };
    visitor.inner.visit(root);
}

pub fn walkPre(comptime Context: type, user_ctx: Context, comptime Node: type, root: Node, 
        walker: anytype, user_visit: UserVisit(Node, Context, false)) void {
    const S = struct {
        inner: VisitIface(Node) = .{
            .visit_fn = visit,
        },
        user_ctx: Context,
        user_visit: UserVisit(Node, Context, false),
        walker: @TypeOf(walker),

        fn visit(ptr: *VisitIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "inner", ptr);
            self.user_visit(self.user_ctx, node);
            self.walker.walk(ptr, node);
        }
    };
    var visitor = S{ .user_visit = user_visit, .user_ctx = user_ctx, .walker = walker };
    visitor.inner.visit(root);
}

pub fn walkPost(comptime Context: type, user_ctx: Context, comptime Node: type, root: Node, 
        walker: anytype, user_visit: UserVisit(Node, Context, false)) void {
    const S = struct {
        inner: VisitIface(Node) = .{
            .visit_fn = visit,
        },
        user_ctx: Context,
        user_visit: UserVisit(Node, Context, false),
        walker: @TypeOf(walker),

        fn visit(ptr: *VisitIface(Node), node: Node) void {
            const self = @fieldParentPtr(@This(), "inner", ptr);
            self.walker.walk(ptr, node);
            self.user_visit(self.user_ctx, node);
        }
    };
    var visitor = S{ .user_visit = user_visit, .user_ctx = user_ctx, .walker = walker };
    visitor.inner.visit(root);
}

// Multiple roots.
pub fn walkPreMany(comptime Context: type, ctx: Context, comptime NodeType: type, roots: []const NodeType, 
        walker: anytype, user_visit: UserVisit(NodeType, Context, false)) void {
    for (roots) |it| {
        walkPre(Context, ctx, NodeType, it, walker, user_visit);
    }
}

pub fn walkPrePostMany(comptime Context: type, ctx: Context, NodeType: type, roots: []const NodeType, 
        walker: anytype, user_visit: UserVisit(NodeType, Context, true)) void {
    for (roots) |it| {
        walkPrePost(Context, ctx, NodeType, it, walker, user_visit);
    }
}

fn SearchVisitIface(comptime Node: type) type {
    return struct {
        visit_fn: fn(*@This(), Node) ?Node,

        fn visit(self: *@This(), node: Node) ?Node {
            return self.visit_fn(self, node);
        }
    };
}

pub fn SearchWalkContext(comptime Context: type, comptime Node: type) type {
    return struct {
        visitor: *SearchVisitIface(Node),
        user_ctx: Context,

        pub fn visit(self: *@This(), node: Node) ?Node {
            return self.visitor.visit(node);
        }
    };
}

pub fn UserPredicate(comptime Context: type, comptime Node: type) type {
    return fn(Context, Node) bool;
}

pub fn UserSearchWalkFn(comptime Context: type, comptime Node: type) type {
    return fn(*SearchWalkContext(Context, Node), Node) ?Node;
}

pub fn SearchWalker(comptime Context: type, comptime Node: type) type {
    return struct {
        ctx: SearchWalkContext(Context, Node),
        user_walk: UserSearchWalkFn(Context, Node),

        pub fn init(user_ctx: Context, user_walk: UserSearchWalkFn(Context, Node)) @This() {
            return .{
                .ctx = .{
                    // Visit iface is injected when walker is used.
                    .visitor = undefined,
                    .user_ctx = user_ctx,
                },
                .user_walk = user_walk,
            };
        }

        pub fn walk(self: *@This(), visitor: *SearchVisitIface(Node), node: Node) ?Node {
            self.ctx.visitor = visitor;
            return self.user_walk(&self.ctx, node);
        }
    };
}

pub fn ChildArrayListSearchWalker(comptime Node: type) SearchWalker(void, Node) {
    const S = struct {
        fn walk(ctx: *SearchWalkContext(void, Node), node: Node) ?Node {
            for (node.children.items) |it| {
                if (ctx.visit(it)) |res| {
                    return res;
                }
            }
            return null;
        }
    };
    return SearchWalker(void, Node).init({}, S.walk);
}

pub fn searchPre(comptime Context: type, user_ctx: Context, comptime Node: type, root: Node, 
        walker: anytype, user_visit: UserPredicate(Context, Node)) ?Node {
    const S = struct {
        visitor: SearchVisitIface(Node) = .{
            .visit_fn = visit,
        },
        user_visit: UserPredicate(Context, Node),
        user_ctx: Context,
        walker: @TypeOf(walker),

        fn visit(iface: *SearchVisitIface(Node), node: Node) ?Node {
            const self = @fieldParentPtr(@This(), "visitor", iface);
            if (self.user_visit(self.user_ctx, node)) {
                return node;
            }
            return self.walker.walk(iface, node);
        }
    };
    var ctx = S{
        .user_ctx = user_ctx,
        .walker = walker,
        .user_visit = user_visit,
    };
    return ctx.visitor.visit(root);
}

pub fn searchPreMany(comptime Context: type, ctx: Context, comptime Node: type, roots: []const Node, 
        walker: anytype, pred: UserPredicate(Context, Node)) ?Node {
    for (roots) |it| {
        if (searchPre(Context, ctx, Node, it, walker, pred)) |res| {
            return res;
        }
    }
    return null;
}