const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;

const parser = @import("parser.zig");
const NullId = std.math.maxInt(u32);
const log = stdx.log.scoped(.compiler);

const IndentWidth = 4;

pub const JsTargetCompiler = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8),
    last_err: []const u8,

    /// Context vars.
    func_decls: []const parser.FunctionDeclaration,
    func_params: []const parser.FunctionParam,
    nodes: []const parser.Node,
    tokens: []const parser.Token,
    src: []const u8,
    writer: std.ArrayListUnmanaged(u8).Writer,
    opts: CompileOptions,
    buf: std.ArrayListUnmanaged(u8),
    use_generators: bool,

    vars: std.StringHashMapUnmanaged(VarDesc),
    block_stack: std.ArrayListUnmanaged(BlockState),

    cur_indent: u32,

    pub fn init(alloc: std.mem.Allocator) JsTargetCompiler {
        return .{
            .alloc = alloc,
            .out = .{},
            .func_decls = undefined,
            .func_params = undefined,
            .nodes = undefined,
            .tokens = undefined,
            .src = undefined,
            .last_err = "",
            .writer = undefined,
            .cur_indent = 0,
            .vars = .{},
            .block_stack = .{},
            .buf = .{},
            .opts = undefined,
            .use_generators = undefined,
        };
    }

    pub fn deinit(self: *JsTargetCompiler) void {
        self.block_stack.deinit(self.alloc);
        self.vars.deinit(self.alloc);
        self.out.deinit(self.alloc);
        self.alloc.free(self.last_err);
        self.buf.deinit(self.alloc);
    }

    pub fn compile(self: *JsTargetCompiler, ast: parser.ResultView, opts: CompileOptions) ResultView {
        self.func_decls = ast.func_decls;
        self.func_params = ast.func_params;
        self.nodes = ast.nodes.items;
        self.tokens = ast.tokens;
        self.src = ast.src;
        self.out.clearRetainingCapacity();
        self.writer = self.out.writer(self.alloc);
        self.cur_indent = 0;
        self.vars.clearRetainingCapacity();
        self.block_stack.clearRetainingCapacity();
        self.opts = opts;
        self.use_generators = opts.gas_meter == .yield_interrupt;

        const root = self.nodes[ast.root_id];

        self.pushBlock();
        self.genStatements(root.head.child_head) catch {
            return .{
                .output = "",
                .err_msg = self.last_err,
                .has_error = true,
            };
        };
        self.popBlock();

        return .{
            .output = self.out.items,
            .err_msg = "",
            .has_error = false,
        };
    }

    fn declVar(self: *JsTargetCompiler, name: []const u8, value: []const u8) !void {
        const res = try self.vars.getOrPut(self.alloc, name);
        if (!res.found_existing) {
            // Variable declaration.
            const block = &self.block_stack.items[self.block_stack.items.len-1];
            try block.vars.append(self.alloc, name);
            res.value_ptr.* = .{ .dummy = true };
            
            try self.indent();
            _ = try self.writer.write("let ");
            _ = try self.writer.write(name);
            _ = try self.writer.write(" = ");
            _ = try self.writer.write(value);
            _ = try self.writer.write(";\n");
        } else {
            return error.DuplicateVar;
        }
    }

    fn pushBlock(self: *JsTargetCompiler) void {
        self.block_stack.append(self.alloc, .{
            .vars = .{},
        }) catch fatal();
    }

    fn popBlock(self: *JsTargetCompiler) void {
        var last = self.block_stack.pop();
        for (last.vars.items) |name| {
            _ = self.vars.remove(name);
        }
        last.deinit(self.alloc);
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
                _ = try self.writer.write("break\n");
            },
            .return_stmt => {
                try self.indent();
                _ = try self.writer.write("return\n");
            },
            .return_expr_stmt => {
                _ = try self.writer.write("return ");
                const expr = self.nodes[node.head.child_head];
                try self.genExpression(expr);
                _ = try self.writer.writeByte('\n');
            },
            .add_assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                try self.indent();
                try self.genExpression(left);
                _ = try self.writer.write(" += ");
                const right = self.nodes[node.head.left_right.right];
                try self.genExpression(right);
                _ = try self.writer.write("\n");
            },
            .assign_stmt => {
                const left = self.nodes[node.head.left_right.left];
                var is_decl = false;
                if (left.node_t == .ident) {
                    const ident_tok = self.tokens[left.start_token];
                    const var_name = self.src[ident_tok.start_pos .. ident_tok.data.end_pos];
                    const res = try self.vars.getOrPut(self.alloc, var_name);
                    if (!res.found_existing) {
                        // Variable declaration.
                        const block = &self.block_stack.items[self.block_stack.items.len-1];
                        try block.vars.append(self.alloc, var_name);
                        res.value_ptr.* = .{ .dummy = true };
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
                _ = try self.writer.write("\n");
            },
            .expr_stmt => {
                const expr = self.nodes[node.head.child_head];
                try self.indent();
                try self.genExpression(expr);
                _ = try self.writer.write("\n");
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
                _ = try self.writer.write("}\n");
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
            .number => {
                const token = self.tokens[node.start_token];
                _ = try self.writer.write(self.src[token.start_pos..token.data.end_pos]);
            },
            .string => {
                const token = self.tokens[node.start_token];
                _ = try self.writer.write(self.src[token.start_pos..token.data.end_pos]);
            },
            .dict_entry => {
                const key = self.nodes[node.head.left_right.left];
                try self.genExpression(key);
                _ = try self.writer.write(": ");
                const val_expr = self.nodes[node.head.left_right.right];
                try self.genExpression(val_expr);
                if (node.next != NullId) {
                    _ = try self.writer.write(",");
                    try self.genExpression(self.nodes[node.next]);
                }
            },
            .dict_literal => {
                _ = try self.writer.write("{");
                const first_entry = self.nodes[node.head.child_head];
                try self.genExpression(first_entry);
                _ = try self.writer.write("}");
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

                _ = try self.writer.write("})\n");
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

                _ = try self.writer.write("; })\n");
            },
            .bin_expr => {
                const left = self.nodes[node.head.left_right.left];
                try self.genExpression(left);
                const op = @intToEnum(parser.BinaryExprOp, node.head.left_right.extra);
                switch (op) {
                    .plus => {
                        try self.writer.writeByte('+');
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
                    else => return self.reportError(error.Unsupported, "Unsupported binary op: {}", .{op}, node),
                }
                const right = self.nodes[node.head.left_right.right];
                try self.genExpression(right);
            },
            .access_expr => {
                const left = self.nodes[node.head.left_right.left];
                try self.genExpression(left);
                _ = try self.writer.writeByte('.');
                const right = self.nodes[node.head.left_right.right];
                try self.genExpression(right);
            },
            .call_expr => {
                const left = self.nodes[node.head.left_right.left];
                try self.genExpression(left);
                _ = try self.writer.write("(");
                var arg_id = node.head.left_right.right;
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
                    _ = try self.writer.write(")");
                } else {
                    _ = try self.writer.write(")");
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

const ResultView = struct {
    output: []const u8,
    err_msg: []const u8,
    has_error: bool,
};

const BlockState = struct {
    vars: std.ArrayListUnmanaged([]const u8),

    fn deinit(self: *BlockState, alloc: std.mem.Allocator) void {
        self.vars.deinit(alloc);
    }
};

const VarDesc = struct {
    dummy: bool,
};

const CompileOptions = struct {
    gas_meter: GasMeterOption = .none,
};

const GasMeterOption = enum(u2) {
    none,
    error_interrupt,
    yield_interrupt,
};