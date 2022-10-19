const std = @import("std");
const stdx = @import("stdx");
const cs = @import("cscript.zig");

const NullId = std.math.maxInt(u32);

pub const VMcompiler = struct {
    alloc: std.mem.Allocator,
    buf: cs.ByteCodeBuffer,
    lastErr: []const u8,

    /// Context vars.
    src: []const u8,
    nodes: []const cs.Node,
    tokens: []const cs.Token,
    blocks: std.ArrayListUnmanaged(Block),
    curBlock: *Block,

    pub fn init(alloc: std.mem.Allocator) VMcompiler {
        return .{
            .alloc = alloc,
            .buf = cs.ByteCodeBuffer.init(alloc),
            .lastErr = "",
            .nodes = undefined,
            .tokens = undefined,
            .blocks = .{},
            .curBlock = undefined,
            .src = undefined,
        };
    }

    pub fn deinit(self: *VMcompiler) void {
        self.alloc.free(self.lastErr);
        self.blocks.deinit(self.alloc);
        self.buf.deinit();
    }

    pub fn compile(self: *VMcompiler, ast: cs.ParseResultView) !ResultView {
        self.buf.clear();
        self.blocks.clearRetainingCapacity();
        self.nodes = ast.nodes.items;
        self.src = ast.src;
        self.tokens = ast.tokens;

        const root = self.nodes[ast.root_id];

        try self.pushBlock();
        defer self.popBlock();

        self.genStatements(root.head.child_head, true) catch {
            return ResultView{
                .buf = self.buf,
                .hasError = true,
            };
        };

        return ResultView{
            .buf = self.buf,
            .hasError = false,
        };
    }

    fn pushBlock(self: *VMcompiler) !void {
        try self.blocks.append(self.alloc, Block.init());
        self.curBlock = &self.blocks.items[self.blocks.items.len-1];
    }

    fn popBlock(self: *VMcompiler) void {
        var last = self.blocks.pop();
        last.deinit(self.alloc);
        if (self.blocks.items.len > 0) {
            self.curBlock = &self.blocks.items[self.blocks.items.len-1];
        }
    }

    fn getScopedVarInfo(self: *VMcompiler, varName: []const u8) ?VarInfo {
        if (self.curBlock.vars.get(varName)) |info| {
            return info;
        }
        // Start looking at parent scopes.
        // var i = self.blocks.items.len - 1;
        // while (i > 0) {
        //     i -= 1;
        //     if (self.blocks.items[i].vars.get(var_name)) |desc| {
        //         return desc;
        //     }
        // }
        return null;
    }

    fn genStatements(self: *VMcompiler, head: cs.NodeId, comptime attachEnd: bool) anyerror!void {
        var cur_id = head;
        while (cur_id != NullId) {
            const node = self.nodes[cur_id];
            if (attachEnd) {
                if (node.next == NullId) {
                    try self.genStatement(node, false);
                } else {
                    try self.genStatement(node, true);
                }
            } else {
                try self.genStatement(node, true);
            }
            cur_id = node.next;
        }
        if (attachEnd) {
            try self.buf.pushOp(.end);
        }
    }

    /// discardTopExprReg is usually true since statements aren't expressions and evaluating child expressions
    /// would just grow the register stack unnecessarily. However, the last main statement requires the
    /// resulting expr to persist to return from `eval`.
    fn genStatement(self: *VMcompiler, node: cs.Node, comptime discardTopExprReg: bool) !void {
        // log.debug("gen stmt {}", .{node.node_t});
        switch (node.node_t) {
            .expr_stmt => {
                const expr = self.nodes[node.head.child_head];
                try self.genExpr(expr, discardTopExprReg);
            },
            .assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                if (left.node_t == .ident) {
                    const identToken = self.tokens[left.start_token];
                    const varName = self.src[identToken.start_pos .. identToken.data.end_pos];

                    const right = self.nodes[node.head.left_right.right];
                    if (self.getScopedVarInfo(varName)) |info| {
                        try self.genExpr(right, false);
                        try self.buf.pushOp1(.set, info.localOffset);
                    } else {
                        const offset = self.curBlock.allocValue();
                        try self.curBlock.vars.put(self.alloc, varName, .{
                            .vtype = AnyType,
                            .localOffset = offset,
                        });
                        try self.genExpr(right, false);
                        try self.buf.pushOp1(.setNew, offset);
                    }
                } else {
                    stdx.panic("unsupported assignment to left");
                }
            },
            .if_stmt => {
                const cond = self.nodes[node.head.left_right.left];
                try self.genExpr(cond, false);

                var opStart = self.buf.ops.items.len;
                var extraStart = self.buf.extras.items.len;
                try self.buf.pushOp2(.jumpNotCond, 0, 0);

                try self.genStatements(node.head.left_right.right, false);
                self.buf.setOpArgs2(opStart + 1, @intCast(u8, self.buf.ops.items.len - opStart), @intCast(u8, self.buf.extras.items.len - extraStart));

                var elseClauseId = node.head.left_right.extra;
                while (elseClauseId != NullId) {
                    const elseClause = self.nodes[elseClauseId];
                    if (elseClause.head.else_clause.cond == NullId) {
                        try self.genStatements(elseClause.head.else_clause.body_head, false);
                        break;
                    } else {
                        const elseCond = self.nodes[elseClause.head.else_clause.cond];
                        try self.genExpr(elseCond, false);

                        opStart = self.buf.ops.items.len;
                        extraStart = self.buf.extras.items.len;
                        try self.buf.pushOp2(.jumpNotCond, 0, 0);

                        try self.genStatements(elseClause.head.else_clause.body_head, false);
                        self.buf.setOpArgs2(opStart + 1, @intCast(u8, self.buf.ops.items.len - opStart), @intCast(u8, self.buf.extras.items.len - extraStart));
                        elseClauseId = elseClause.head.else_clause.else_clause;
                    }
                }
            },
            .return_expr_stmt => {
                const expr = self.nodes[node.head.child_head];
                try self.genExpr(expr, false);
                try self.buf.pushOp(.retTop);
            },
            else => return self.reportError("Unsupported node", .{}, node),
        }
    }

    fn genExpr(self: *VMcompiler, node: cs.Node, comptime discardTopExprReg: bool) anyerror!void {
        // log.debug("gen expr {}", .{node.node_t});
        switch (node.node_t) {
            .true_literal => {
                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushTrue);
                }
            },
            .false_literal => {
                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushFalse);
                }
            },
            .number => {
                if (!discardTopExprReg) {
                    const token = self.tokens[node.start_token];
                    const val = try std.fmt.parseFloat(f64, self.src[token.start_pos..token.data.end_pos]);
                    try self.buf.pushOp(.pushF64);
                    try self.buf.pushExtra(@bitCast(u64, val));
                }
            },
            .ident => {
                const token = self.tokens[node.start_token];
                const name = self.src[token.start_pos..token.data.end_pos];
                if (self.getScopedVarInfo(name)) |info| {
                    try self.buf.pushOp1(.load, info.localOffset);
                } else {
                    try self.buf.pushOp(.pushNone);
                }
            },
            .unary_expr => {
                const child = self.nodes[node.head.unary.child];
                const op = node.head.unary.op;
                switch (op) {
                    .not => {
                        if (!discardTopExprReg) {
                            try self.genExpr(child, false);
                            try self.buf.pushOp(.pushNot);
                        } else {
                            try self.genExpr(child, true);
                        }
                    },
                    else => return self.reportError("Unsupported unary op: {}", .{op}, node),
                }
            },
            .bin_expr => {
                const left = self.nodes[node.head.left_right.left];
                const right = self.nodes[node.head.left_right.right];

                try self.genExpr(left, discardTopExprReg);
                try self.genExpr(right, discardTopExprReg);

                const op = @intToEnum(cs.BinaryExprOp, node.head.left_right.extra);
                switch (op) {
                    .plus => {
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushAdd);
                        }
                    },
                    .and_op => {
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushAnd);
                        }
                    },
                    .or_op => {
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushOr);
                        }
                    },
                    else => return self.reportError("Unsupported binary op: {}", .{op}, node),
                }
            },
            else => return self.reportError("Unsupported node", .{}, node),
        }
    }

    fn reportError(self: *VMcompiler, comptime fmt: []const u8, args: anytype, node: cs.Node) anyerror {
        const token = self.tokens[node.start_token];
        const customMsg = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(customMsg);
        self.alloc.free(self.lastErr);
        self.lastErr = try std.fmt.allocPrint(self.alloc, "{s}: {} at {}", .{customMsg, node.node_t, token.start_pos});
        return error.CompileError;
    }
};

pub const ResultView = struct {
    buf: cs.ByteCodeBuffer,
    hasError: bool,
};

const Block = struct {
    stackLen: u32,
    vars: std.StringHashMapUnmanaged(VarInfo),

    fn init() Block {
        return .{
            .stackLen = 0,
            .vars = .{},
        };
    }

    fn deinit(self: *Block, alloc: std.mem.Allocator) void {
        self.vars.deinit(alloc);
    }

    fn allocValue(self: *Block) u8 {
        const idx = self.stackLen;
        self.stackLen += 1;
        if (idx <= std.math.maxInt(u8)) {
            return @intCast(u8, idx);
        } else stdx.panic("idx too big");
    }
};

const VarInfo = struct {
    vtype: Type,
    /// Stack offset from frame it was declared in.
    localOffset: u8,
};

const TypeTag = enum {
    any,
};

const Type = struct {
    typeT: TypeTag,
};

const AnyType = Type{
    .typeT = .any,
};