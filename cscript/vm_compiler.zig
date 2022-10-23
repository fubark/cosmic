const std = @import("std");
const stdx = @import("stdx");
const cs = @import("cscript.zig");

const NullId = std.math.maxInt(u32);
const log = stdx.log.scoped(.vm_compiler);
const f64Neg1 = cs.Value.initF64(-1);

pub const VMcompiler = struct {
    alloc: std.mem.Allocator,
    vm: *cs.VM,
    buf: cs.ByteCodeBuffer,
    lastErr: []const u8,

    /// Context vars.
    src: []const u8,
    nodes: []const cs.Node,
    tokens: []const cs.Token,
    funcDecls: []const cs.FunctionDeclaration,
    funcParams: []const cs.FunctionParam,
    blocks: std.ArrayListUnmanaged(Block),
    jumpStack: std.ArrayListUnmanaged(Jump),
    curBlock: *Block,

    pub fn init(self: *VMcompiler, vm: *cs.VM) void {
        self.* = .{
            .alloc = vm.alloc,
            .vm = vm,
            .buf = cs.ByteCodeBuffer.init(vm.alloc),
            .lastErr = "",
            .nodes = undefined,
            .tokens = undefined,
            .funcDecls = undefined,
            .funcParams = undefined,
            .blocks = .{},
            .jumpStack = .{},
            .curBlock = undefined,
            .src = undefined,
        };
    }

    pub fn deinit(self: *VMcompiler) void {
        self.alloc.free(self.lastErr);
        self.blocks.deinit(self.alloc);
        self.buf.deinit();
        self.jumpStack.deinit(self.alloc);
    }

    pub fn compile(self: *VMcompiler, ast: cs.ParseResultView) !ResultView {
        self.buf.clear();
        self.blocks.clearRetainingCapacity();
        self.nodes = ast.nodes.items;
        self.funcDecls = ast.func_decls.items;
        self.funcParams = ast.func_params;
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
        self.buf.mainLocalSize = self.curBlock.vars.size;

        return ResultView{
            .buf = self.buf,
            .hasError = false,
        };
    }

    fn endLocals(self: *VMcompiler) !void {
        var iter = self.curBlock.vars.valueIterator();
        while (iter.next()) |info| {
            if (info.rcCandidate) {
                try self.buf.pushOp1(.release, info.localOffset);
            }
        }
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
            try self.endLocals();
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
                _ = try self.genExpr(expr, discardTopExprReg);
            },
            .break_stmt => {
                try self.jumpStack.append(self.alloc, .{
                    .pc = @intCast(u32, self.buf.ops.items.len),
                });
                try self.buf.pushOp1(.jump, 0);
            },
            .add_assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                if (left.node_t == .ident) {
                    const identToken = self.tokens[left.start_token];
                    const varName = self.src[identToken.start_pos .. identToken.data.end_pos];

                    if (self.getScopedVarInfo(varName)) |info| {
                        const right = self.nodes[node.head.left_right.right];
                        const rtype = try self.genExpr(right, false);
                        if (info.vtype.typeT != .any and rtype.typeT != info.vtype.typeT) {
                            return self.reportError("Type mismatch: Expected {}", .{info.vtype.typeT}, node);
                        }
                        try self.buf.pushOp1(.addSet, info.localOffset);
                    } else stdx.panic("variable not declared");
                } else {
                    stdx.panicFmt("unsupported assignment to left {}", .{left.node_t});
                }
            },
            .assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                if (left.node_t == .ident) {
                    const identToken = self.tokens[left.start_token];
                    const varName = self.src[identToken.start_pos .. identToken.data.end_pos];

                    const right = self.nodes[node.head.left_right.right];
                    if (self.getScopedVarInfo(varName)) |info| {
                        const rtype = try self.genExpr(right, false);
                        if (info.vtype.typeT != .any and rtype.typeT != info.vtype.typeT) {
                            return self.reportError("Type mismatch: Expected {}", .{info.vtype.typeT}, node);
                        }
                        try self.buf.pushOp1(.set, info.localOffset);
                    } else {
                        const rtype = try self.genExpr(right, false);
                        const offset = self.curBlock.allocValue();
                        try self.curBlock.vars.put(self.alloc, varName, .{
                            .vtype = rtype,
                            .localOffset = offset,
                            .rcCandidate = rtype.rcCandidate,
                        });
                        try self.buf.pushOp1(.setNew, offset);
                    }
                } else if (left.node_t == .arr_access_expr) {
                    const accessLeft = self.nodes[left.head.left_right.left];
                    _ = try self.genExpr(accessLeft, false);
                    const accessRight = self.nodes[left.head.left_right.right];
                    _ = try self.genExpr(accessRight, false);

                    const right = self.nodes[node.head.left_right.right];
                    _ = try self.genExpr(right, false);
                    try self.buf.pushOp(.setIndex);
                } else {
                    stdx.panicFmt("unsupported assignment to left {}", .{left.node_t});
                }
            },
            .func_decl => {
                const func = self.funcDecls[node.head.func.decl_id];

                const name = self.src[func.name.start..func.name.end];
                const symId = try self.vm.ensureFuncSym(name);

                const jumpOpStart = self.buf.ops.items.len;
                try self.buf.pushOp1(.jump, 0);

                try self.pushBlock();
                const opStart = @intCast(u32, self.buf.ops.items.len);
                // Declare params.
                if (func.params.end > func.params.start) {
                    for (self.funcParams[func.params.start..func.params.end]) |param| {
                        const paramName = self.src[param.name.start..param.name.end];
                        const paramT = AnyType;
                        const offset = self.curBlock.allocValue();
                        try self.curBlock.vars.put(self.alloc, paramName, .{
                            .vtype = paramT,
                            .localOffset = offset,
                            .rcCandidate = paramT.rcCandidate,
                        });
                    }
                }
                try self.genStatements(node.head.func.body_head, false);
                // TODO: Check last statement to skip adding ret.
                try self.endLocals();
                try self.buf.pushOp(.ret);

                // Reserve another local for the call return info.
                _ = self.curBlock.allocValue();

                const numLocals = self.curBlock.vars.size + 1;
                self.popBlock();

                self.buf.setOpArgs1(jumpOpStart + 1, @intCast(u8, self.buf.ops.items.len - jumpOpStart));

                const sym = cs.FuncSymbolEntry.initFunc(opStart, numLocals);
                try self.vm.setFuncSym(symId, sym);
            },
            .for_inf_stmt => {
                self.curBlock.pcSave = @intCast(u32, self.buf.ops.items.len);
                self.curBlock.jumpStackSave = @intCast(u32, self.jumpStack.items.len);

                // TODO: generate gas meter checks.
                // if (self.opts.gas_meter != .none) {
                //     try self.indent();
                //     if (self.opts.gas_meter == .error_interrupt) {
                //         _ = try self.writer.write("__interrupt_count += 1; if (__interrupt_count > __interrupt_max) throw globalThis._internal.interruptSym;\n");
                //     } else if (self.opts.gas_meter == .yield_interrupt) {
                //         _ = try self.writer.write("__interrupt_count += 1; if (__interrupt_count > __interrupt_max) yield globalThis._internal.interruptSym;\n");
                //     }
                // }

                try self.genStatements(node.head.child_head, false);
                try self.buf.pushOp1(.jumpBack, @intCast(u8, self.buf.ops.items.len - self.curBlock.pcSave));

                // Patch break jumps.
                for (self.jumpStack.items[self.curBlock.jumpStackSave..]) |jump| {
                    self.buf.setOpArgs1(jump.pc + 1, @intCast(u8, self.buf.ops.items.len - jump.pc));
                }
                self.jumpStack.items.len = self.curBlock.jumpStackSave;
            },
            .if_stmt => {
                const cond = self.nodes[node.head.left_right.left];
                _ = try self.genExpr(cond, false);

                var opStart = self.buf.ops.items.len;
                try self.buf.pushOp1(.jumpNotCond, 0);

                try self.genStatements(node.head.left_right.right, false);
                self.buf.setOpArgs1(opStart + 1, @intCast(u8, self.buf.ops.items.len - opStart));

                var elseClauseId = node.head.left_right.extra;
                while (elseClauseId != NullId) {
                    const elseClause = self.nodes[elseClauseId];
                    if (elseClause.head.else_clause.cond == NullId) {
                        try self.genStatements(elseClause.head.else_clause.body_head, false);
                        break;
                    } else {
                        const elseCond = self.nodes[elseClause.head.else_clause.cond];
                        _ = try self.genExpr(elseCond, false);

                        opStart = self.buf.ops.items.len;
                        try self.buf.pushOp1(.jumpNotCond, 0);

                        try self.genStatements(elseClause.head.else_clause.body_head, false);
                        self.buf.setOpArgs1(opStart + 1, @intCast(u8, self.buf.ops.items.len - opStart));
                        elseClauseId = elseClause.head.else_clause.else_clause;
                    }
                }
            },
            .return_expr_stmt => {
                const expr = self.nodes[node.head.child_head];
                _ = try self.genExpr(expr, false);

                if (self.blocks.items.len == 1) {
                    try self.endLocals();
                    try self.buf.pushOp(.end);
                } else {
                    try self.endLocals();
                    try self.buf.pushOp(.retTop);
                }
            },
            else => return self.reportError("Unsupported node", .{}, node),
        }
    }

    fn genExpr(self: *VMcompiler, node: cs.Node, comptime discardTopExprReg: bool) anyerror!Type {
        // log.debug("gen expr {}", .{node.node_t});
        switch (node.node_t) {
            .true_literal => {
                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushTrue);
                }
                return BoolType;
            },
            .false_literal => {
                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushFalse);
                }
                return BoolType;
            },
            .arr_literal => {
                var expr_id = node.head.child_head;
                var i: u32 = 0;
                while (expr_id != NullId) : (i += 1) {
                    var expr = self.nodes[expr_id];
                    _ = try self.genExpr(expr, discardTopExprReg);
                    expr_id = expr.next;
                }

                if (!discardTopExprReg) {
                    try self.buf.pushOp1(.pushList, @intCast(u8, i));
                }
                return ListType;
            },
            .number => {
                if (!discardTopExprReg) {
                    const token = self.tokens[node.start_token];
                    const literal = self.src[token.start_pos..token.data.end_pos];
                    const val = try std.fmt.parseFloat(f64, literal);
                    const idx = try self.buf.pushConst(.{ .val = @bitCast(u64, val) });
                    try self.buf.pushOp1(.pushConst, @intCast(u8, idx));
                }
                return NumberType;
            },
            .ident => {
                const token = self.tokens[node.start_token];
                const name = self.src[token.start_pos..token.data.end_pos];
                if (self.getScopedVarInfo(name)) |info| {
                    try self.buf.pushOp1(.load, info.localOffset);
                    return info.vtype;
                } else {
                    try self.buf.pushOp(.pushNone);
                    return AnyType;
                }
            },
            .arr_range_expr => {
                const arr = self.nodes[node.head.arr_range_expr.arr];
                _ = try self.genExpr(arr, discardTopExprReg);

                if (node.head.arr_range_expr.left == NullId) {
                    if (!discardTopExprReg) {
                        const idx = try self.buf.pushConst(.{ .val = 0 });
                        try self.buf.pushOp1(.pushConst, @intCast(u8, idx));
                    }
                } else {
                    const left = self.nodes[node.head.arr_range_expr.left];
                    _ = try self.genExpr(left, discardTopExprReg);
                }
                if (node.head.arr_range_expr.right == NullId) {
                    if (!discardTopExprReg) {
                        const idx = try self.buf.pushConst(.{ .val = f64Neg1.val });
                        try self.buf.pushOp1(.pushConst, @intCast(u8, idx));
                    }
                } else {
                    const right = self.nodes[node.head.arr_range_expr.right];
                    _ = try self.genExpr(right, discardTopExprReg);
                }

                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushSlice);
                }
                return ListType;
            },
            .arr_access_expr => {
                const left = self.nodes[node.head.left_right.left];
                _ = try self.genExpr(left, discardTopExprReg);

                const index = self.nodes[node.head.left_right.right];
                _ = try self.genExpr(index, discardTopExprReg);

                if (!discardTopExprReg) {
                    try self.buf.pushOp(.pushIndex);
                }
                return AnyType;
            },
            .unary_expr => {
                const child = self.nodes[node.head.unary.child];
                const op = node.head.unary.op;
                switch (op) {
                    .not => {
                        _ = try self.genExpr(child, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushNot);
                        }
                        return BoolType;
                    },
                    else => return self.reportError("Unsupported unary op: {}", .{op}, node),
                }
            },
            .bin_expr => {
                const left = self.nodes[node.head.left_right.left];
                const right = self.nodes[node.head.left_right.right];

                var ltype: Type = undefined;
                var rtype: Type = undefined;

                const op = @intToEnum(cs.BinaryExprOp, node.head.left_right.extra);
                switch (op) {
                    .plus => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushAdd);
                        }
                        return NumberType;
                    },
                    .minus => {
                        // Generating pushMinus1 for fib.cy increases performance ~10-12%.
                        var leftVar: u8 = 255;
                        if (left.node_t == .ident) {
                            const token = self.tokens[left.start_token];
                            const name = self.src[token.start_pos .. token.data.end_pos];
                            if (self.getScopedVarInfo(name)) |info| {
                                leftVar = info.localOffset;
                            }
                        }
                        if (leftVar == 255) {
                            _ = try self.genExpr(left, discardTopExprReg);
                        }
                        var rightVar: u8 = 255;
                        if (right.node_t == .ident) {
                            const token = self.tokens[right.start_token];
                            const name = self.src[token.start_pos .. token.data.end_pos];
                            if (self.getScopedVarInfo(name)) |info| {
                                rightVar = info.localOffset;
                            }
                        }
                        if (rightVar == 255) {
                            _ = try self.genExpr(right, discardTopExprReg);
                        }

                        if (!discardTopExprReg) {
                            if (leftVar != rightVar) {
                                try self.buf.pushOp2(.pushMinus1, leftVar, rightVar);
                            } else {
                                if (leftVar == 255) {
                                    try self.buf.pushOp(.pushMinus);
                                } else {
                                    try self.buf.pushOp2(.pushMinus2, leftVar, leftVar);
                                }
                            }
                        }
                        return NumberType;
                    },
                    .and_op => {
                        ltype = try self.genExpr(left, discardTopExprReg);
                        rtype = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushAnd);
                        }
                        if (ltype.typeT == rtype.typeT) {
                            return ltype;
                        } else return AnyType;
                    },
                    .or_op => {
                        ltype = try self.genExpr(left, discardTopExprReg);
                        rtype = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushOr);
                        }
                        if (ltype.typeT == rtype.typeT) {
                            return ltype;
                        } else return AnyType;
                    },
                    .equal_equal => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushCompare);
                        }
                        return BoolType;
                    },
                    .less => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushLess);
                        }
                        return BoolType;
                    },
                    .less_equal => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushLessEqual);
                        }
                        return BoolType;
                    },
                    .greater => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushGreater);
                        }
                        return BoolType;
                    },
                    .greater_equal => {
                        _ = try self.genExpr(left, discardTopExprReg);
                        _ = try self.genExpr(right, discardTopExprReg);
                        if (!discardTopExprReg) {
                            try self.buf.pushOp(.pushGreaterEqual);
                        }
                        return BoolType;
                    },
                    else => return self.reportError("Unsupported binary op: {}", .{op}, node),
                }
            },
            .call_expr => {
                const callee = self.nodes[node.head.func_call.callee];
                if (!node.head.func_call.has_named_arg) {
                    if (callee.node_t == .access_expr) {
                        const right = self.nodes[callee.head.left_right.right];
                        if (right.node_t == .ident) {
                            const left = self.nodes[callee.head.left_right.left];
                            _ = try self.genExpr(left, false);

                            var numArgs: u32 = 1;
                            var arg_id = node.head.func_call.arg_head;
                            while (arg_id != NullId) : (numArgs += 1) {
                                const arg = self.nodes[arg_id];
                                _ = try self.genExpr(arg, false);
                                arg_id = arg.next;
                            }

                            const identToken = self.tokens[right.start_token];
                            const str = self.src[identToken.start_pos .. identToken.data.end_pos];
                            // const slice = try self.buf.getStringConst(str);
                            // try self.buf.pushExtra(.{ .two = .{ slice.start, slice.end } });
                            const symId = try self.vm.ensureStructSym(str);

                            try self.buf.pushOp2(.callObjSym, @intCast(u8, symId), @intCast(u8, numArgs));
                            return AnyType;
                        } else return self.reportError("Unsupported callee", .{}, node);
                    } else if (callee.node_t == .ident) {
                        const token = self.tokens[callee.start_token];
                        const name = self.src[token.start_pos..token.data.end_pos];

                        if (self.getScopedVarInfo(name)) |_| {
                            stdx.panic("unsupported call expr on scoped var");
                        } else {
                            var numArgs: u32 = 0;
                            var arg_id = node.head.func_call.arg_head;
                            while (arg_id != NullId) : (numArgs += 1) {
                                const arg = self.nodes[arg_id];
                                _ = try self.genExpr(arg, false);
                                arg_id = arg.next;
                            }

                            const symId = try self.vm.ensureFuncSym(name);
                            if (discardTopExprReg) {
                                try self.buf.pushOp2(.callSym, @intCast(u8, symId), @intCast(u8, numArgs));
                            } else {
                                try self.buf.pushOp2(.pushCallSym, @intCast(u8, symId), @intCast(u8, numArgs));
                            }
                            return AnyType;
                        }
                    } else return self.reportError("Unsupported callee", .{}, node);
                } else return self.reportError("Unsupported named args", .{}, node);
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
    pcSave: u32,
    jumpStackSave: u32,

    fn init() Block {
        return .{
            .stackLen = 0,
            .vars = .{},
            .pcSave = 0,
            .jumpStackSave = 0,
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
    /// Is possibly referencing an object that has ref count.
    rcCandidate: bool,
};

const TypeTag = enum {
    any,
    boolean,
    number,
    list,
};

const Type = struct {
    typeT: TypeTag,
    rcCandidate: bool,
};

const AnyType = Type{
    .typeT = .any,
    .rcCandidate = true,
};

const BoolType = Type{
    .typeT = .boolean,
    .rcCandidate = false,
};

const NumberType = Type{
    .typeT = .number,
    .rcCandidate = false,
};

const ListType = Type{
    .typeT = .list,
    .rcCandidate = true,
};

const ValueAddrType = enum {
    frameOffset,
};

const ValueAddr = struct {
    addrT: ValueAddrType,
    inner: union {
        frameOffset: u32,
    },
};

const Jump = struct {
    pc: u32,
};