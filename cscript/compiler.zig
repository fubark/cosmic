const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;

const parser = @import("parser.zig");
const NullId = std.math.maxInt(u32);
const log = stdx.log.scoped(.compiler);

const IndentWidth = 4;

// Special types.
const AnyId: CTypeId = 0;
const PromiseId: CTypeId = 1;
const LastPrimitiveId = 1;

pub const JsTargetCompiler = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8),
    last_err: []const u8,

    /// Context vars.
    func_decls: []const parser.FunctionDeclaration,
    func_params: []const parser.FunctionParam,
    nodes: []const parser.Node,
    node_list: *std.ArrayListUnmanaged(parser.Node),

    tokens: []const parser.Token,
    src: []const u8,
    writer: std.ArrayListUnmanaged(u8).Writer,
    opts: CompileOptions,
    buf: std.ArrayListUnmanaged(u8),
    use_generators: bool,
    top_level_async: bool,

    block_stack: std.ArrayListUnmanaged(BlockState),
    ctypes: std.ArrayListUnmanaged(CType),

    cur_indent: u32,
    cur_block: *BlockState,

    pub fn init(alloc: std.mem.Allocator) JsTargetCompiler {
        const new = JsTargetCompiler{
            .alloc = alloc,
            .out = .{},
            .func_decls = undefined,
            .func_params = undefined,
            .nodes = undefined,
            .node_list = undefined,
            .tokens = undefined,
            .src = undefined,
            .last_err = "",
            .writer = undefined,
            .cur_indent = 0,
            .cur_block = undefined,
            .block_stack = .{},
            .buf = .{},
            .opts = undefined,
            .use_generators = undefined,
            .top_level_async = undefined,
            .ctypes = .{},
        };
        return new;
    }

    pub fn deinit(self: *JsTargetCompiler) void {
        self.block_stack.deinit(self.alloc);
        self.out.deinit(self.alloc);
        self.alloc.free(self.last_err);
        self.buf.deinit(self.alloc);
        self.ctypes.deinit(self.alloc);
    }

    pub fn compile(self: *JsTargetCompiler, ast: parser.ResultView, opts: CompileOptions) !ResultView {
        try self.ctypes.resize(self.alloc, LastPrimitiveId + 1);
        self.func_decls = ast.func_decls;
        self.func_params = ast.func_params;
        self.nodes = ast.nodes.items;
        self.node_list = ast.nodes;
        self.tokens = ast.tokens;
        self.src = ast.src;
        self.out.clearRetainingCapacity();
        self.writer = self.out.writer(self.alloc);
        self.cur_indent = 0;
        self.block_stack.clearRetainingCapacity();
        defer {
            for (self.block_stack.items) |*block| {
                block.deinit(self.alloc);
            } 
        }

        self.opts = opts;
        self.use_generators = opts.gas_meter == .yield_interrupt;
        self.top_level_async = false;

        const root = self.nodes[ast.root_id];

        // First perform analysis.
        self.pushBlock();
        try self.analyze(root);

        for (self.block_stack.items) |*block| {
            block.deinit(self.alloc);
        } 
        self.block_stack.clearRetainingCapacity();
        // Analyze can transform the ast.
        self.nodes = self.node_list.items;

        if (self.top_level_async) {
            // Last stmt is turned into a return statement.
            var prev: parser.NodeId = undefined;
            const last = parser.getLastStmt(self.nodes, root.head.child_head, &prev);
            const node = self.nodes[last];
            if (node.node_t == .expr_stmt) {
                // Turn into return statement.
                ast.nodes.items[last].node_t = .return_expr_stmt;
            }
        }

        self.pushBlock();
        self.genStatements(root.head.child_head) catch {
            return ResultView{
                .output = "",
                .err_msg = self.last_err,
                .has_error = true,
            };
        };

        if (self.top_level_async) {
            try self.out.insertSlice(self.alloc, 0, "(async function () {");
            try self.out.appendSlice(self.alloc, "})();");
        }

        return ResultView{
            .output = self.out.items,
            .err_msg = "",
            .has_error = false,
        };
    }

    fn analyze(self: *JsTargetCompiler, root: parser.Node) !void {
        var cur_id = root.head.child_head;
        while (cur_id != NullId) {
            const node = self.nodes[cur_id];
            try self.analyzeRootStmt(node);
            cur_id = node.next;
        }
    }

    fn analyzeRootStmt(self: *JsTargetCompiler, stmt: parser.Node) !void {
        switch (stmt.node_t) {
            .expr_stmt => {
                const expr = self.nodes[stmt.head.child_head];
                try self.analyzeRootExpr(stmt.head.child_head, expr);
            },
            .func_decl => {
                const func = self.func_decls[stmt.head.func.decl_id];
                const name = self.src[func.name.start..func.name.end];
                if (self.getScopedVarDesc(name) == null) {
                    const return_ctype = if (func.return_type) |slice| b: {
                        const str = self.src[slice.start..slice.end];
                        if (std.mem.eql(u8, "apromise", str)) {
                            break :b PromiseId;
                        }
                        break :b AnyId;
                    } else AnyId;

                    try self.cur_block.vars.put(self.alloc, name, .{
                        .ctype = .{
                            .ctype_t = .func,
                            .inner = .{
                                .func = .{
                                    .return_ctype = return_ctype,
                                },
                            },
                        },
                    });
                }
            },
            else => return,
        }
    }

    fn getScopedVarDesc(self: *JsTargetCompiler, var_name: []const u8) ?VarDesc {
        if (self.cur_block.vars.get(var_name)) |desc| {
            return desc;
        }
        // Start looking at parent scopes.
        var i = self.block_stack.items.len - 1;
        while (i > 0) {
            i -= 1;
            if (self.block_stack.items[i].vars.get(var_name)) |desc| {
                return desc;
            }
        }
        return null;
    }

    fn getScopedVarType(self: *JsTargetCompiler, var_name: []const u8) CType {
        if (self.getScopedVarDesc(var_name)) |desc| {
            return desc.ctype;
        } else return AnyCtype;
    }

    fn getOrResolveType(self: *JsTargetCompiler, expr_id: parser.NodeId) CType {
        const expr = self.nodes[expr_id];
        switch (expr.node_t) {
            .ident => {
                const token = self.tokens[expr.start_token];
                const var_name = self.src[token.start_pos .. token.data.end_pos];
                return self.getScopedVarType(var_name);
            },
            else => return AnyCtype,
        }
    }

    fn analyzeRootExpr(self: *JsTargetCompiler, expr_id: parser.NodeId, expr: parser.Node) anyerror!void {
        switch (expr.node_t) {
            .call_expr => {
                const ctype = self.getOrResolveType(expr.head.func_call.callee);
                var wrap_await = false;
                switch (ctype.ctype_t) {
                    .any => {
                        self.top_level_async = true;
                        wrap_await = true;
                    },
                    .func => {
                        if (ctype.inner.func.return_ctype == PromiseId) {
                            self.top_level_async = true;
                            wrap_await = true;
                        }
                    },
                    else => {},
                }
                if (wrap_await) {
                    const dupe_id = parser.pushNodeToList(self.alloc, self.node_list, .call_expr, expr.start_token);
                    self.node_list.items[dupe_id].head = expr.head;

                    self.node_list.items[expr_id].node_t = .await_expr;
                    self.node_list.items[expr_id].head = .{
                        .child_head = dupe_id,
                    };
                }
            },
            .await_expr => {
                self.top_level_async = true;
                const child = self.nodes[expr.head.child_head];
                if (child.node_t != .call_expr) {
                    try self.analyzeRootExpr(expr.head.child_head, child);
                }
            },
            .bin_expr => {
                const left = self.nodes[expr.head.left_right.left];
                try self.analyzeRootExpr(expr.head.left_right.left, left);
                const right = self.nodes[expr.head.left_right.right];
                try self.analyzeRootExpr(expr.head.left_right.right, right);
            },
            else => return,
        }
    }

    fn declVar(self: *JsTargetCompiler, name: []const u8, value: []const u8) !void {
        if (!self.cur_block.vars.contains(name)) {
            // Variable declaration.
            try self.cur_block.vars.put(self.alloc, name);
            
            try self.indent();
            _ = try self.writer.write("let ");
            _ = try self.writer.write(name);
            _ = try self.writer.write(" = ");
            _ = try self.writer.write(value);
            _ = try self.writer.write(";\n");
        } else return error.DuplicateVar;
    }

    fn pushBlock(self: *JsTargetCompiler) void {
        self.block_stack.append(self.alloc, .{
            .vars = .{},
        }) catch fatal();
        self.cur_block = &self.block_stack.items[self.block_stack.items.len-1];
    }

    fn popBlock(self: *JsTargetCompiler) void {
        var last = self.block_stack.pop();
        last.deinit(self.alloc);
        self.cur_block = &self.block_stack.items[self.block_stack.items.len-1];
    }

    fn genStatements(self: *JsTargetCompiler, head: parser.NodeId) anyerror!void {
        var cur_id = head;
        while (cur_id != NullId) {
            const node = self.nodes[cur_id];
            try self.genStatement(node);
            cur_id = node.next;
        }
    }

    fn genFunctionParams(self: *JsTargetCompiler, params_slice: stdx.IndexSlice(u32)) !void {
        _ = try self.writer.write("(");
        if (params_slice.end > params_slice.start) {
            const params = self.func_params[params_slice.start..params_slice.end];
            var first = params[0];
            _ = try self.writer.write(self.src[first.name.start..first.name.end]);
            for (params[1..]) |param| {
                _ = try self.writer.write(", ");
                _ = try self.writer.write(self.src[param.name.start..param.name.end]);
            }
        }
        _ = try self.writer.write(")");
    }
    
    inline fn indent(self: *JsTargetCompiler) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent);
    }

    fn genStatement(self: *JsTargetCompiler, node: parser.Node) !void {
        // log.debug("gen stmt {}", .{node.node_t});
        switch (node.node_t) {
            .break_stmt => {
                try self.indent();
                _ = try self.writer.write("break;\n");
            },
            .return_stmt => {
                try self.indent();
                _ = try self.writer.write("return;\n");
            },
            .return_expr_stmt => {
                _ = try self.writer.write("return ");
                const expr = self.nodes[node.head.child_head];
                try self.genExpression(expr);
                _ = try self.writer.write(";\n");
            },
            .add_assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                try self.indent();
                try self.genExpression(left);
                _ = try self.writer.write(" += ");
                const right = self.nodes[node.head.left_right.right];
                try self.genExpression(right);
                _ = try self.writer.write(";\n");
            },
            .assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                var is_decl = false;
                if (left.node_t == .ident) {
                    const ident_tok = self.tokens[left.start_token];
                    const var_name = self.src[ident_tok.start_pos .. ident_tok.data.end_pos];

                    if (self.getScopedVarDesc(var_name) == null) {
                        // Variable declaration.
                        try self.cur_block.vars.put(self.alloc, var_name, .{
                            .ctype = AnyCtype,
                        });
                        is_decl = true;
                    }
                }

                try self.indent();
                if (is_decl) {
                    _ = try self.writer.write("let ");
                }
                try self.genExpression(left);
                _ = try self.writer.write(" = ");
                const right = self.nodes[node.head.left_right.right];
                try self.genExpression(right);
                _ = try self.writer.write(";\n");
            },
            .at_stmt => {
                // Skip for now.
            },
            .expr_stmt => {
                const expr = self.nodes[node.head.child_head];
                try self.indent();
                try self.genExpression(expr);
                _ = try self.writer.write(";\n");
            },
            .func_decl => {
                const func = self.func_decls[node.head.func.decl_id];

                try self.indent();
                _ = try self.writer.write("function ");
                _ = try self.writer.write(self.src[func.name.start..func.name.end]);

                try self.genFunctionParams(func.params);
                _ = try self.writer.write(" {\n");

                self.cur_indent += IndentWidth;
                try self.genStatements(node.head.func.body_head);
                self.cur_indent -= IndentWidth;

                try self.indent();
                _ = try self.writer.write("};\n");
            },
            .label_decl => {
                try self.indent();
                _ = try self.writer.write("{\n");

                self.cur_indent += IndentWidth;
                try self.genStatements(node.head.left_right.right);
                self.cur_indent -= IndentWidth;

                try self.indent();
                _ = try self.writer.write("}\n");
            },
            .if_stmt => {
                try self.indent();
                _ = try self.writer.write("if (");
                const cond = self.nodes[node.head.left_right.left];
                try self.genExpression(cond);
                _ = try self.writer.write(") {\n");

                self.cur_indent += IndentWidth;
                try self.genStatements(node.head.left_right.right);
                self.cur_indent -= IndentWidth;

                if (node.head.left_right.extra != NullId) {
                    const next = self.nodes[node.head.left_right.extra];
                    if (next.node_t == .else_clause) {
                        try self.indent();
                        _ = try self.writer.write("} else {\n");

                        self.cur_indent += IndentWidth;
                        try self.genStatements(next.head.child_head);
                        self.cur_indent -= IndentWidth;
                    } else return self.reportError(error.Unsupported, "Unsupported clause.", .{}, next);
                }

                try self.indent();
                _ = try self.writer.write("}\n");
            },
            .for_cond_stmt => {
                try self.indent();
                _ = try self.writer.write("while (");
                const cond = self.nodes[node.head.left_right.left];
                try self.genExpression(cond);
                _ = try self.writer.write(") {\n");

                try self.genForBody(node.head.left_right.right);

                try self.indent();
                _ = try self.writer.write("}\n");
            },
            .for_inf_stmt => {
                try self.indent();
                _ = try self.writer.write("while (true) {\n");

                try self.genForBody(node.head.child_head);

                try self.indent();
                _ = try self.writer.write("}\n");
            },
            else => return self.reportError(error.Unsupported, "Unsupported node", .{}, node),
        }
    }

    fn genForBody(self: *JsTargetCompiler, first_stmt_id: parser.NodeId) !void {
        self.cur_indent += IndentWidth;
        if (self.opts.gas_meter != .none) {
            try self.indent();
            if (self.opts.gas_meter == .error_interrupt) {
                _ = try self.writer.write("__interrupt_count += 1; if (__interrupt_count > __interrupt_max) throw new Error('Interrupted');\n");
            } else if (self.opts.gas_meter == .yield_interrupt) {
                _ = try self.writer.write("__interrupt_count += 1; if (__interrupt_count > __interrupt_max) yield new Error('Interrupted');\n");
            }
        }
        try self.genStatements(first_stmt_id);
        self.cur_indent -= IndentWidth;
    }

    fn genExpression(self: *JsTargetCompiler, node: parser.Node) anyerror!void {
        // log.debug("gen expr {}", .{node.node_t});
        switch (node.node_t) {
            .ident => {
                const token = self.tokens[node.start_token];
                _ = try self.writer.write(self.src[token.start_pos..token.data.end_pos]);
            },
            .at_ident => {
                const ident = self.nodes[node.head.annotation.child];
                const token = self.tokens[ident.start_token];
                _ = try self.writer.print("globalThis.{s}", .{self.src[token.start_pos..token.data.end_pos]});
            },
            .number => {
                const token = self.tokens[node.start_token];
                _ = try self.writer.write(self.src[token.start_pos..token.data.end_pos]);
            },
            .string => {
                const token = self.tokens[node.start_token];
                _ = try self.writer.write(self.src[token.start_pos..token.data.end_pos]);
            },
            .dict_literal => {
                _ = try self.writer.write("{");

                var entry_id = node.head.child_head;
                while (entry_id != NullId) {
                    var entry = self.nodes[entry_id];
                    const key = self.nodes[entry.head.left_right.left];
                    try self.genExpression(key);
                    _ = try self.writer.write(": ");
                    const val_expr = self.nodes[entry.head.left_right.right];
                    try self.genExpression(val_expr);
                    entry_id = entry.next;
                    if (entry_id != NullId) {
                        _ = try self.writer.write(",");
                    }   
                }

                _ = try self.writer.write("}");
            },
            .arr_literal => {
                _ = try self.writer.write("[");

                var expr_id = node.head.child_head;
                while (expr_id != NullId) {
                    var expr = self.nodes[expr_id];
                    try self.genExpression(expr);
                    expr_id = expr.next;
                    if (expr_id != NullId) {
                        _ = try self.writer.write(",");
                    }   
                }

                _ = try self.writer.write("]");
            },
            .await_expr => {
                _ = try self.writer.write("await ");
                var expr = self.nodes[node.head.child_head];
                try self.genExpression(expr);
            },
            .lambda_multi => {
                const func = self.func_decls[node.head.func.decl_id];

                if (self.use_generators) {
                    _ = try self.writer.write("(function* ");
                } else {
                    _ = try self.writer.write("(function ");
                }

                try self.genFunctionParams(func.params);
                _ = try self.writer.write(" {\n");

                self.cur_indent += IndentWidth;
                try self.genStatements(node.head.func.body_head);
                self.cur_indent -= IndentWidth;

                _ = try self.writer.write("})");
            },
            .lambda_single => {
                const func = self.func_decls[node.head.func.decl_id];

                if (self.use_generators) {
                    _ = try self.writer.write("(function* ");
                } else {
                    _ = try self.writer.write("(function ");
                }

                try self.genFunctionParams(func.params);
                _ = try self.writer.write(" { return ");

                const body_expr = self.nodes[node.head.func.body_head];
                try self.genExpression(body_expr);

                _ = try self.writer.write("; })");
            },
            .unary_expr => {
                const child = self.nodes[node.head.unary.child];
                const op = node.head.unary.op;
                switch (op) {
                    .minus => {
                        try self.writer.writeByte('-');
                        try self.genExpression(child);
                    },
                    // else => return self.reportError(error.Unsupported, "Unsupported unary op: {}", .{op}, node),
                }
            },
            .bin_expr => {
                const left = self.nodes[node.head.left_right.left];
                if (left.node_t == .bin_expr) {
                    try self.writer.writeByte('(');
                    try self.genExpression(left);
                    try self.writer.writeByte(')');
                } else {
                    try self.genExpression(left);
                }
                const op = @intToEnum(parser.BinaryExprOp, node.head.left_right.extra);
                switch (op) {
                    .plus => {
                        try self.writer.writeByte('+');
                    },
                    .minus => {
                        try self.writer.writeByte('-');
                    },
                    .equal_equal => {
                        _ = try self.writer.write("==");
                    },
                    .bang_equal => {
                        _ = try self.writer.write("!=");
                    },
                    .less => {
                        try self.writer.writeByte('<');
                    },
                    .less_equal => {
                        _ = try self.writer.write("<=");
                    },
                    .greater => {
                        try self.writer.writeByte('>');
                    },
                    .greater_equal => {
                        _ = try self.writer.write(">=");
                    },
                    .star => {
                        _ = try self.writer.write("*");
                    },
                    .slash => {
                        _ = try self.writer.write("/");
                    },
                    .percent => {
                        _ = try self.writer.write("%");
                    },
                    else => return self.reportError(error.Unsupported, "Unsupported binary op: {}", .{op}, node),
                }

                const right = self.nodes[node.head.left_right.right];
                if (right.node_t == .bin_expr) {
                    try self.writer.writeByte('(');
                    try self.genExpression(right);
                    try self.writer.writeByte(')');
                } else {
                    try self.genExpression(right);
                }
            },
            .access_expr => {
                const left = self.nodes[node.head.left_right.left];
                try self.genExpression(left);

                const right = self.nodes[node.head.left_right.right];
                if (right.node_t == .ident) {
                    _ = try self.writer.writeByte('.');
                    try self.genExpression(right);
                } else {
                    _ = try self.writer.writeByte('[');
                    try self.genExpression(right);
                    _ = try self.writer.writeByte(']');
                }
            },
            .call_expr => {
                if (!node.head.func_call.has_named_arg) {
                    // No named args.
                    const left = self.nodes[node.head.func_call.callee];
                    try self.genExpression(left);
                    _ = try self.writer.write("(");
                    var arg_id = node.head.func_call.arg_head;
                    if (arg_id != NullId) {
                        var arg = self.nodes[arg_id];
                        try self.genExpression(arg);
                        arg_id = arg.next;
                        while (arg_id != NullId) {
                            arg = self.nodes[arg_id];
                            _ = try self.writer.write(", ");
                            try self.genExpression(arg);
                            arg_id = arg.next;
                        }
                    }
                    _ = try self.writer.write(")");
                } else {
                    // Named args.
                    _ = try self.writer.write("_internal.callNamed(");
                    const left = self.nodes[node.head.func_call.callee];
                    try self.genExpression(left);
                    _ = try self.writer.write(", [");

                    var arg_id = node.head.func_call.arg_head;
                    if (arg_id != NullId) {
                        var arg = self.nodes[arg_id];
                        if (arg.node_t != .named_arg) {
                            try self.genExpression(arg);
                            arg_id = arg.next;
                            while (arg_id != NullId) {
                                arg = self.nodes[arg_id];
                                if (arg.node_t == .named_arg) {
                                    break;
                                }
                                _ = try self.writer.write(", ");
                                try self.genExpression(arg);
                                arg_id = arg.next;
                            }
                        }
                    }
                    _ = try self.writer.write("], {");
                    var narg = self.nodes[arg_id];
                    var name = self.nodes[narg.head.left_right.left];
                    try self.genExpression(name);
                    _ = try self.writer.write(": ");
                    var arg = self.nodes[narg.head.left_right.right];
                    try self.genExpression(arg);

                    arg_id = narg.next;
                    while (arg_id != NullId) {
                        _ = try self.writer.write(", ");
                        narg = self.nodes[arg_id];
                        name = self.nodes[narg.head.left_right.left];
                        try self.genExpression(name);
                        _ = try self.writer.write(": ");
                        arg = self.nodes[narg.head.left_right.right];
                        try self.genExpression(arg);
                        arg_id = arg.next;
                    }
                    _ = try self.writer.write("})");
                }
            },
            .if_expr => {
                _ = try self.writer.write("if (");
                const cond = self.nodes[node.head.left_right.left];
                try self.genExpression(cond);
                _ = try self.writer.write(") { ");
                const body = self.nodes[node.head.left_right.right];
                try self.genExpression(body);
                if (node.head.left_right.extra != NullId) {
                    const next = self.nodes[node.head.left_right.extra];
                    if (next.node_t == .else_clause) {
                        _ = try self.writer.write(" } else { ");
                        const else_body = self.nodes[next.head.child_head];
                        try self.genExpression(else_body);
                    } else {
                        return self.reportError(error.Unsupported, "Unsupported node", .{}, next);
                    }
                }
                _ = try self.writer.write(" }");
            },
            else => return self.reportError(error.Unsupported, "Unsupported node", .{}, node),
        }
    }

    fn reportError(self: *JsTargetCompiler, err: anyerror, comptime fmt: []const u8, args: anytype, node: parser.Node) anyerror {
        const token = self.tokens[node.start_token];
        self.alloc.free(self.last_err);
        const custom_msg = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(custom_msg);
        self.last_err = try std.fmt.allocPrint(self.alloc, "{s}: {} at {}", .{custom_msg, node.node_t, token.start_pos});
        return err;
    }
};

pub const ResultView = struct {
    output: []const u8,
    err_msg: []const u8,
    has_error: bool,
};

const BlockState = struct {
    vars: std.StringHashMapUnmanaged(VarDesc),

    fn deinit(self: *BlockState, alloc: std.mem.Allocator) void {
        self.vars.deinit(alloc);
    }
};

const VarDesc = struct {
    ctype: CType,
};

const CompileOptions = struct {
    gas_meter: GasMeterOption = .none,
};

const GasMeterOption = enum(u2) {
    none,
    error_interrupt,
    yield_interrupt,
};

const CTypeKind = enum {
    any,
    func,
    struct_t,
};

const CTypeId = u32;
const CType = struct {
    ctype_t: CTypeKind,
    inner: union {
        any: void,
        func: struct {
            return_ctype: u32
        },
        struct_t: u32,
    },
};

const AnyCtype = CType{
    .ctype_t = .any,
    .inner = .{
        .any = {},
    },
};