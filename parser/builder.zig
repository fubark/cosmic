const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.builder);
const string = stdx.string;

const grammar = @import("grammar.zig");
const CharSetRangeSlice = grammar.CharSetRangeSlice;
const CharSlice = grammar.CharSlice;
const Grammar = grammar.Grammar;
const TokenMatchOpId = grammar.TokenMatchOpId;
const TokenMatchOp = grammar.TokenMatchOp;
const TokenMatchOpSlice = grammar.TokenMatchOpSlice;
const MatchOpId = grammar.MatchOpId;
const MatchOp = grammar.MatchOp;
const MatchOpSlice = grammar.MatchOpSlice;
const _ast = @import("ast.zig");
const Tree = _ast.Tree;
const _parser = @import("parser.zig");
const NodeTag = _parser.NodeTag;
const NodePtr = _parser.NodePtr;
const Parser = _parser.Parser;
const ParseConfig = _parser.ParseConfig;
const grammars = @import("grammars.zig");

// Builds parser grammars.

// Creates a grammar to parse the grammar format.
// Since parsers currently only exist at runtime, we need to hardcode the rules.
pub fn initMetaGrammar(c: *Grammar, alloc: std.mem.Allocator) void {
    c.init(alloc, "Grammar");
    const op = c.addOp;
    const top = c.addTokenOp;
    const ops = c.addOps;
    const tops = c.addTokenOps;

    c.addRule("Grammar", matchZeroOrMore(
        op(c.matchRule("Declaration")),
    ));

    c.addInlineRule("Declaration", matchChoice(ops(&.{
        c.matchRule("RuleDeclaration"),
        c.matchRule("TokensDeclaration"),
    })));

    c.addRule("TokensDeclaration", matchSeq(ops(&.{
        c.matchTokText("Directive", "@tokens"),
        c.matchLiteral("{"),
        matchZeroOrMore(
            op(c.matchRule("TokenDeclaration")),
        ),
        c.matchLiteral("}"),
    })));

    c.addRule("TokenDeclaration", matchSeq(ops(&.{
        c.matchTokCap("Identifier"),
        matchZeroOrMore(
            op(c.matchRule("RuleDirective")),
        ),
        c.matchLiteral("{"),
        c.matchRule("Seq"),
        c.matchLiteral("}"),
    })));

    c.addRule("Seq", matchOneOrMore(op(
        matchChoice(ops(&.{
            c.matchRule("Choice"),
            c.matchRule("Term"),
        })),
    )));

    c.addRule("Choice", matchSeq(ops(&.{
        c.matchRule("Term"),
        matchOneOrMore(op(
            matchSeq(ops(&.{
                c.matchLiteralCap("|"),
                c.matchRule("Term"),
            })),
        )),
    })));

    c.addRule("RuleMatcher", matchSeq(ops(&.{
        c.matchRule("Identifier"),
        matchOptional(
            op(matchSeq(ops(&.{
                c.matchLiteral("="),
                c.matchRule("StringLiteral"),
            }))),
        ),
    })));

    c.addRule("Term", matchSeq(ops(&.{
        matchOptional(
            op(matchChoice(ops(&.{
                c.matchLiteralCap("!"),
                c.matchLiteralCap("&"),
            }))),
        ),
        matchChoice(ops(&.{
            c.matchRule("RuleMatcher"),
            c.matchRule("StringLiteral"),
            c.matchRule("Directive"),
            c.matchRule("CharSetLiteral"),
            matchSeq(ops(&.{
                c.matchLiteral("("),
                c.matchRule("Seq"),
                c.matchLiteral(")"),
            })),
        })),
        matchOptional(
            op(matchChoice(ops(&.{
                c.matchLiteralCap("*"),
                c.matchLiteralCap("+"),
                c.matchLiteralCap("?"),
            }))),
        ),
    })));

    c.addRule("RuleDeclaration", matchSeq(ops(&.{
        c.matchTokCap("Identifier"),
        matchZeroOrMore(
            op(c.matchRule("RuleDirective")),
        ),
        c.matchLiteral("{"),
        c.matchRule("Seq"),
        c.matchLiteral("}"),
    })));

    c.addRule("RuleDirective", matchSeq(ops(&.{
        c.matchTokCap("Directive"),
        matchOptional(
            op(matchSeq(ops(&.{
                c.matchLiteral("("),
                // Support just one param for now.
                c.matchRule("Identifier"),
                c.matchLiteral(")"),
            }))),
        ),
    })));

    c.addTokenRule("Directive", matchTokenSeq(tops(&.{
        matchExactChar('@'),
        matchTokenOneOrMore(top(matchAsciiLetter())),
    })));

    c.addTokenRule("Identifier", matchTokenOneOrMore(top(matchAsciiLetter())));

    c.addTokenRule("CharSetLiteral", matchTokenSeq(tops(&.{
        matchExactChar('['),
        matchUntilChar(']'),
    })));

    c.addTokenRule("StringLiteral", matchTokenSeq(tops(&.{
        matchExactChar('\''),
        matchTokenOneOrMore(top(
            matchTokenChoice(tops(&.{
                c.tokMatchText("\\\\"),
                c.tokMatchText("\\'"),
                matchNotChar('\''),
            })),
        )),
        matchExactChar('\''),
    })));

    c.addTokenRuleExt("Punctuator", matchTokenChoice(tops(&.{
        matchExactChar('{'),
        matchExactChar('}'),
        matchExactChar('('),
        matchExactChar(')'),
        matchExactChar('*'),
        matchExactChar('+'),
        matchExactChar('?'),
        matchExactChar('|'),
        matchExactChar('!'),
        matchExactChar('&'),
        matchExactChar('='),
    })), true, false, null);

    c.build(alloc);
}

test "initMetaGrammar" {
    var c: Grammar = undefined;
    initMetaGrammar(&c, t.alloc);
    defer c.deinit();

    const grammar_src =
        \\Program { Statement* }
        \\Statement @inline { ReturnStatement }
        \\ReturnStatement { 'return' Identifier }
        \\@tokens {
        \\  Identifier { [a-zA-Z] [a-zA-Z0-9_]* }
        \\  Keyword @literal @replace(Identifier) { 'return' }
        \\}
    ;

    var zig_grammar: Grammar = undefined;
    try initGrammar(&zig_grammar, t.alloc, grammar_src);
    defer zig_grammar.deinit();

    // Test parsing decls.
    const NumDeclsGeneratedFromTokenDecls = 2;
    try t.eq(zig_grammar.decls.items.len, 3 + NumDeclsGeneratedFromTokenDecls);
    try t.eq(zig_grammar.token_decls.items.len, 2);

    // Test parsing repetition "*" operator.
    const program_decl = zig_grammar.findRuleDecl("Program").?;
    var op = zig_grammar.getMatchOp(program_decl.ops.start);
    try t.eqUnionEnum(op, .MatchZeroOrMore);
    const inner_op = zig_grammar.getMatchOp(op.MatchZeroOrMore.op_id);
    try t.eqStr(zig_grammar.getString(inner_op.MatchRule.name), "Statement");

    // Test parsing @inline.
    const statement_decl = zig_grammar.findRuleDecl("Statement").?;
    try t.eq(statement_decl.is_inline, true);
}

fn BuildConfigContext(comptime Config: ParseConfig) type {
    return struct {
        const Self = @This();

        RuleMatcher: NodeTag,
        Identifier: NodeTag,
        StringLiteral: NodeTag,
        Directive: NodeTag,
        Seq: NodeTag,
        Term: NodeTag,
        Choice: NodeTag,
        CharSetLiteral: NodeTag,

        op_list_stack: *std.ArrayList(MatchOp),
        top_list_stack: *std.ArrayList(TokenMatchOp),
        ast: Tree(Config),
        config: *Grammar,

        // Given a match op expression node, recursively add match ops to the config.
        // Uses a stack to accumulate a list of child ops.
        // Adds child ops to config but returns the current op.
        fn buildMatchOpFromExprNode(self: *Self, node: NodePtr) MatchOp {
            if (node.tag == self.Seq) {
                const save_state = self.op_list_stack.items.len;
                const terms = self.ast.getChildNodeList(node, 0);
                for (terms) |it| {
                    if (it.tag == self.Term) {
                        const op = self.buildMatchOpFromTerm(it);
                        self.op_list_stack.append(op) catch unreachable;
                    } else if (it.tag == self.Choice) {
                        const op = self.buildMatchOpFromExprNode(it);
                        self.op_list_stack.append(op) catch unreachable;
                    } else {
                        stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(it.tag)});
                    }
                }
                const ops = self.op_list_stack.items[save_state..];
                if (ops.len == 1) {
                    // Reduce to single child op.
                    const op = ops[0];
                    self.op_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                } else {
                    const op = matchSeq(self.config.addOps(ops));
                    self.op_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                }
            } else if (node.tag == self.Choice) {
                const save_state = self.op_list_stack.items.len;

                const first_term = self.ast.getChildNode(node, 0);
                const first_op = self.buildMatchOpFromTerm(first_term);
                self.op_list_stack.append(first_op) catch unreachable;

                const terms = self.ast.getChildNodeList(node, 1);
                for (terms) |it| {
                    if (it.tag == self.Term) {
                        const op = self.buildMatchOpFromTerm(it);
                        self.op_list_stack.append(op) catch unreachable;
                    } else {
                        stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(it.tag)});
                    }
                }
                const ops = self.op_list_stack.items[save_state..];
                if (ops.len == 1) {
                    // Reduce to single child op.
                    const op = ops[0];
                    self.op_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                } else {
                    const op = matchChoice(self.config.addOps(ops));
                    self.op_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                }
            } else {
                stdx.panicFmt("unsupported {}", .{node.tag});
            }
        }

        // Add the smallest single term op into the config.
        fn buildMatchOpFromTerm(self: *Self, term: NodePtr) MatchOp {
            const mb_pred = self.ast.getChildNodeOpt(term, 0);
            const inner = self.ast.getChildNode(term, 1);
            const mb_reps = self.ast.getChildNodeOpt(term, 2);

            var op: MatchOp = undefined;
            if (inner.tag == self.RuleMatcher) {
                const rule_ident = self.ast.getChildNode(inner, 0);
                const mb_eq_str = self.ast.getChildNodeOpt(inner, 1);
                const rule_name = self.ast.getChildStringValue(rule_ident, 0);
                if (mb_eq_str) |eq_str| {
                    const str = self.ast.getChildStringValue(eq_str, 0);
                    const without_quotes = str[1 .. str.len - 1];
                    op = self.config.matchTokText(rule_name, without_quotes);
                } else {
                    op = self.config.matchRule(rule_name);
                }
            } else if (inner.tag == self.StringLiteral) {
                const text = self.ast.getChildStringValue(inner, 0);
                const without_quotes = text[1 .. text.len - 1];
                op = self.config.matchLiteral(without_quotes);
            } else if (inner.tag == self.Seq) {
                op = self.buildMatchOpFromExprNode(inner);
            } else {
                stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(inner.tag)});
            }

            // Wrap with repetition op.
            if (mb_reps) |reps| {
                const ch = self.ast.getNodeTokenChar(reps);
                op = switch (ch) {
                    '*' => matchZeroOrMore(self.config.addOp(op)),
                    '?' => matchOptional(self.config.addOp(op)),
                    '+' => matchOneOrMore(self.config.addOp(op)),
                    else => stdx.panicFmt("unsupported {c}", .{ch}),
                };
            }

            // Wrap with lookahead op.
            if (mb_pred) |pred| {
                const ch = self.ast.getNodeTokenChar(pred);
                op = switch (ch) {
                    '&' => matchPosLookahead(self.config.addOp(op)),
                    '!' => matchNegLookahead(self.config.addOp(op)),
                    else => stdx.panicFmt("unsupported {c}", .{ch}),
                };
            }

            return op;
        }

        fn buildTokenMatchOpFromTerm(self: *Self, term: NodePtr) TokenMatchOp {
            const mb_pred = self.ast.getChildNodeOpt(term, 0);
            const base = self.ast.getChildNode(term, 1);
            const mb_reps = self.ast.getChildNodeOpt(term, 2);

            var op = buildTokenMatchOpFromTermBase(self, base);

            // Wrap with repetition op.
            if (mb_reps) |reps| {
                const ch = self.ast.getNodeTokenChar(reps);
                op = switch (ch) {
                    '*' => matchTokenZeroOrMore(self.config.addTokenOp(op)),
                    '+' => matchTokenOneOrMore(self.config.addTokenOp(op)),
                    '?' => matchTokenOptional(self.config.addTokenOp(op)),
                    else => stdx.panicFmt("unsupported {c}", .{ch}),
                };
            }

            // Wrap with predicate op.
            if (mb_pred) |pred| {
                const ch = self.ast.getNodeTokenChar(pred);
                op = switch (ch) {
                    '!' => matchTokenNegLookahead(self.config.addTokenOp(op)),
                    '&' => matchTokenPosLookahead(self.config.addTokenOp(op)),
                    else => stdx.panicFmt("unsupported {c}", .{ch}),
                };
            }

            return op;
        }

        fn buildTokenMatchOpFromTermBase(self: *Self, term: NodePtr) TokenMatchOp {
            if (term.tag == self.StringLiteral) {
                const text = self.ast.getChildStringValue(term, 0);
                const without_quotes = text[1 .. text.len - 1];
                const final_text = unescapeText(self.config, without_quotes);
                return .{ .MatchText = .{ .str = final_text } };
            } else if (term.tag == self.CharSetLiteral) {
                const text = self.ast.getChildStringValue(term, 0);
                // Truncate the surrounding bracket chars.
                const without_delim = text[1 .. text.len - 1];

                var chars: CharSlice = undefined;
                var char_ranges: CharSetRangeSlice = undefined;
                var negate: bool = undefined;
                parseCharSet(self.config, &chars, &char_ranges, &negate, without_delim);

                // log.warn("CHARSET PARAMS: {s} {}", .{chars, char_ranges});
                // var i: u32 = char_ranges.start;
                // while (i < char_ranges.end) : (i += 1) {
                //     const range = self.config.charset_range_buf.items[i];
                //     log.warn("{c} - {c}", .{range.start, range.end_incl});
                // }

                if (!negate) {
                    return matchTokenCharSet(chars, char_ranges);
                } else {
                    return matchTokenNotCharSet(chars, char_ranges);
                }
            } else if (term.tag == self.Directive) {
                const dir = self.ast.getChildStringValue(term, 0);
                if (stdx.string.eq(dir, "@asciiLetter")) {
                    return matchAsciiLetter();
                } else {
                    stdx.panicFmt("unsupported directive {s}", .{dir});
                }
            } else if (term.tag == self.Seq) {
                return self.buildTokenMatchOpFromNode(term);
            } else if (term.tag == self.RuleMatcher) {
                const rule_ident = self.ast.getChildNode(term, 0);
                const rule_name = self.ast.getChildStringValue(rule_ident, 0);
                const mb_eq_str = self.ast.getChildNodeOpt(term, 1);
                if (mb_eq_str) |eq_str| {
                    const str = self.ast.getChildStringValue(eq_str, 0);
                    _ = str;
                    stdx.panic("unsupported");
                } else {
                    return matchTokenRule(rule_name);
                }
            } else {
                stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(term.tag)});
            }
        }

        fn buildTokenMatchOpFromNode(self: *Self, node: NodePtr) TokenMatchOp {
            if (node.tag == self.Seq) {
                const save_state = self.top_list_stack.items.len;
                const terms = self.ast.getChildNodeList(node, 0);
                for (terms) |it| {
                    if (it.tag == self.Term) {
                        const op = buildTokenMatchOpFromTerm(self, it);
                        self.top_list_stack.append(op) catch unreachable;
                    } else if (it.tag == self.Choice) {
                        const op = buildTokenMatchOpFromNode(self, it);
                        self.top_list_stack.append(op) catch unreachable;
                    } else {
                        stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(it.tag)});
                    }
                }
                const ops = self.top_list_stack.items[save_state..];
                if (ops.len == 1) {
                    // Reduce to single child op.
                    const op = ops[0];
                    self.top_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                } else {
                    const op = matchTokenSeq(self.config.addTokenOps(ops));
                    self.top_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                }
            } else if (node.tag == self.Choice) {
                const save_state = self.top_list_stack.items.len;

                const first_term = self.ast.getChildNode(node, 0);
                const first_op = buildTokenMatchOpFromTerm(self, first_term);
                self.top_list_stack.append(first_op) catch unreachable;

                const terms = self.ast.getChildNodeList(node, 1);
                for (terms) |it| {
                    if (it.tag == self.Term) {
                        const op = buildTokenMatchOpFromTerm(self, it);
                        self.top_list_stack.append(op) catch unreachable;
                    } else {
                        stdx.panicFmt("unsupported {s}", .{self.ast.grammar.getNodeTagName(it.tag)});
                    }
                }
                const ops = self.top_list_stack.items[save_state..];
                if (ops.len == 1) {
                    const op = ops[0];
                    self.top_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                } else {
                    const op = matchTokenChoice(self.config.addTokenOps(ops));
                    self.top_list_stack.shrinkRetainingCapacity(save_state);
                    return op;
                }
            } else {
                stdx.panicFmt("unsupported {}", .{node.tag});
            }
        }
    };
}

pub fn initGrammar(c: *Grammar, alloc: std.mem.Allocator, src: []const u8) !void {
    var gc: Grammar = undefined;
    initMetaGrammar(&gc, alloc);
    defer gc.deinit();

    const Config = ParseConfig{ .is_incremental = false };
    var parser = Parser.init(alloc, &gc);
    defer parser.deinit();

    var debug: _parser.DebugInfo = undefined;
    debug.init(t.alloc);
    defer debug.deinit();

    var res = parser.parseDebug(Config, src, &debug);
    defer res.deinit();

    var str_buf = std.ArrayList(u8).init(alloc);
    defer str_buf.deinit();

    if (!res.success) {
        str_buf.clearRetainingCapacity();
        res.ast.formatContextAtToken(str_buf.writer(), res.err_token_id);
        log.warn("{s}", .{str_buf.items});

        // str_buf.clearRetainingCapacity();
        // res.ast.formatTokens(str_buf.writer());
        // log.warn("Tokens: {s}", .{str_buf.items});

        str_buf.clearRetainingCapacity();
        debug.formatMaxCallStack(Config, &res.ast, str_buf.writer());
        log.warn("{s}", .{str_buf.items});

        return error.ParseError;
    }

    // var str_buf = std.ArrayList(u8).init(alloc);
    // defer str_buf.deinit();
    // grammar_ast.formatTree(str_buf.writer());
    // log.warn("Tree: {s}", .{str_buf.items});

    initGrammarFromAst(Config, c, alloc, res.ast);
}

pub fn initGrammarFromAst(comptime Config: ParseConfig, c: *Grammar, alloc: std.mem.Allocator, ast: Tree(Config)) void {
    const root = ast.mb_root.?;
    c.init(alloc, "Program");

    // Tags.
    const RuleDeclaration = ast.grammar.findRuleDeclId("RuleDeclaration").?;
    const TokensDeclaration = ast.grammar.findRuleDeclId("TokensDeclaration").?;
    const TokenDeclaration = ast.grammar.findRuleDeclId("TokenDeclaration").?;
    const RuleDirective = ast.grammar.findRuleDeclId("RuleDirective").?;

    var op_list_stack = std.ArrayList(MatchOp).init(alloc);
    defer op_list_stack.deinit();
    var top_list_stack = std.ArrayList(TokenMatchOp).init(alloc);
    defer top_list_stack.deinit();

    var ctx = BuildConfigContext(Config){
        .RuleMatcher = ast.grammar.findRuleDeclId("RuleMatcher").?,
        .Identifier = ast.grammar.findRuleDeclId("Identifier").?,
        .StringLiteral = ast.grammar.findRuleDeclId("StringLiteral").?,
        .Seq = ast.grammar.findRuleDeclId("Seq").?,
        .Directive = ast.grammar.findRuleDeclId("Directive").?,
        .CharSetLiteral = ast.grammar.findRuleDeclId("CharSetLiteral").?,
        .Term = ast.grammar.findRuleDeclId("Term").?,
        .Choice = ast.grammar.findRuleDeclId("Choice").?,
        .op_list_stack = &op_list_stack,
        .top_list_stack = &top_list_stack,
        .ast = ast,
        .config = c,
    };

    // Process decls.
    const decls = ast.getChildNodeList(root, 0);
    for (decls) |it| {
        if (it.tag == RuleDeclaration) {
            const name = ast.getChildStringValue(it, 0);
            // log.warn("build rule {s}", .{name});
            const dirs = ast.getChildNodeList(it, 1);
            var is_inline = false;
            for (dirs) |d_it| {
                if (d_it.tag == RuleDirective) {
                    const dir_name = ast.getChildStringValue(d_it, 0);
                    if (stdx.string.eq(dir_name, "@inline")) {
                        is_inline = true;
                    }
                } else stdx.panicFmt("unsupported {s}", .{ast.grammar.getNodeTagName(it.tag)});
            }
            const seq = ast.getChildNode(it, 2);
            const op = ctx.buildMatchOpFromExprNode(seq);
            c.addRuleExt(name, op, is_inline);
        } else if (it.tag == TokensDeclaration) {
            const tdecls = ast.getChildNodeList(it, 0);
            for (tdecls) |d_it| {
                if (d_it.tag == TokenDeclaration) {
                    const name = ast.getChildStringValue(d_it, 0);
                    // log.warn("build token rule {s}", .{name});
                    const dirs = ast.getChildNodeList(d_it, 1);
                    var is_literal = false;
                    var skip = false;
                    var replace: ?[]const u8 = null;
                    for (dirs) |dir| {
                        if (dir.tag == RuleDirective) {
                            const dir_name = ast.getChildStringValue(dir, 0);
                            if (string.eq(dir_name, "@literal")) {
                                is_literal = true;
                            } else if (string.eq(dir_name, "@skip")) {
                                skip = true;
                            } else if (string.eq(dir_name, "@replace")) {
                                const ident = ast.getChildNodeOpt(dir, 1);
                                if (ident == null) {
                                    stdx.panic("expected param");
                                }
                                replace = ast.getChildStringValue(ident.?, 0);
                            } else stdx.panicFmt("unsupported {s}", .{dir_name});
                        } else {
                            stdx.panicFmt("unsupported {}", .{dir.tag});
                        }
                    }
                    const seq = ast.getChildNode(d_it, 2);
                    const op = ctx.buildTokenMatchOpFromNode(seq);
                    c.addTokenRuleExt(name, op, is_literal, skip, replace);
                } else {
                    stdx.panicFmt("unsupported {}", .{d_it.tag});
                }
            }
        } else {
            stdx.panicFmt("unsupported {}", .{it.tag});
        }
    }
    c.build(alloc);
}

fn unescapeText(c: *Grammar, input: []const u8) CharSlice {
    const State = enum {
        Start,
        Backslash,
    };
    const start_id = c.str_buf.items.len;
    var state = State.Start;
    for (input) |ch| {
        const uch = switch (state) {
            .Start => switch (ch) {
                '\\' => {
                    state = .Backslash;
                    continue;
                },
                else => ch,
            },
            .Backslash => b: {
                var _uch: u8 = switch (ch) {
                    'n' => '\n',
                    '\'' => '\'',
                    '\\' => '\\',
                    else => stdx.panicFmt("unsupported escaped char \\{c}", .{ch}),
                };
                state = .Start;
                break :b _uch;
            },
        };
        c.str_buf.append(uch) catch unreachable;
    }
    return .{ .start = @intCast(u32, start_id), .end = @intCast(u32, c.str_buf.items.len) };
}

// Unescape chars and add char ranges.
fn parseCharSet(c: *Grammar, res_chars: *CharSlice, res_char_ranges: *CharSetRangeSlice, res_negate: *bool, input: []const u8) void {
    const State = enum {
        Start,
        Backslash,
    };
    const res_start_idx = c.str_buf.items.len;
    const res_range_start_idx = c.charset_range_buf.items.len;
    var range_start_ch: ?u8 = null;
    var last_char: ?u8 = null;
    var parse_range_end: bool = false;
    var state = State.Start;
    res_negate.* = false;
    for (input) |ch, i| {
        const uch = switch (state) {
            .Start => switch (ch) {
                '\\' => {
                    state = .Backslash;
                    continue;
                },
                '-' => {
                    if (last_char != null) {
                        range_start_ch = last_char.?;
                        parse_range_end = true;
                        continue;
                    } else {
                        stdx.panic("Expected start char for charset range.");
                    }
                },
                '^' => b: {
                    if (i == 0) {
                        // Skip first ^ operator and set charset as negated.
                        res_negate.* = true;
                        continue;
                    } else {
                        break :b ch;
                    }
                },
                else => ch,
            },
            .Backslash => b: {
                var _uch: u8 = switch (ch) {
                    'n' => '\n',
                    '-' => '-',
                    else => stdx.panicFmt("unsupported escaped char \\{c}", .{ch}),
                };
                state = .Start;
                break :b _uch;
            },
        };
        if (parse_range_end) {
            c.charset_range_buf.append(.{ .start = range_start_ch.?, .end_incl = uch }) catch unreachable;
            parse_range_end = false;
        } else {
            if (i + 1 == input.len or input[i + 1] != '-') {
                c.str_buf.append(uch) catch unreachable;
            }
        }
        last_char = uch;
    }
    res_chars.* = .{ .start = @intCast(u32, res_start_idx), .end = @intCast(u32, c.str_buf.items.len) };
    res_char_ranges.* = .{ .start = @intCast(u32, res_range_start_idx), .end = @intCast(u32, c.charset_range_buf.items.len) };
}

fn matchChoice(ops: MatchOpSlice) MatchOp {
    return .{ .MatchChoice = .{
        .computed_capture = undefined,
        .ops = ops,
    } };
}

fn matchSeq(ops: MatchOpSlice) MatchOp {
    return .{
        .MatchSeq = .{
            .computed_capture = undefined,
            .ops = ops,
        },
    };
}

fn matchOptionalCapBool(id: MatchOpId) MatchOp {
    return .{
        .MatchOptional = .{
            .computed_capture = undefined,
            .capture_bool = true,
            .op_id = id,
        },
    };
}

fn matchNegLookahead(id: MatchOpId) MatchOp {
    return .{
        .MatchNegLookahead = .{
            .op_id = id,
        },
    };
}

fn matchPosLookahead(id: MatchOpId) MatchOp {
    return .{
        .MatchPosLookahead = .{
            .op_id = id,
        },
    };
}

fn matchOptional(id: MatchOpId) MatchOp {
    return .{
        .MatchOptional = .{
            .computed_capture = undefined,
            .capture_bool = false,
            .op_id = id,
        },
    };
}

fn matchOneOrMore(id: MatchOpId) MatchOp {
    return .{ .MatchOneOrMore = .{
        .op_id = id,
    } };
}

fn matchZeroOrMore(id: MatchOpId) MatchOp {
    return .{ .MatchZeroOrMore = .{
        .skip = false,
        .op_id = id,
    } };
}

fn matchTokenOptional(id: TokenMatchOpId) TokenMatchOp {
    return .{
        .MatchOptional = .{
            .op_id = id,
        },
    };
}

fn matchTokenOneOrMore(id: TokenMatchOpId) TokenMatchOp {
    return .{ .MatchOneOrMore = .{
        .op_id = id,
    } };
}

fn matchTokenZeroOrMore(id: TokenMatchOpId) TokenMatchOp {
    return .{ .MatchZeroOrMore = .{
        .op_id = id,
    } };
}

fn matchTokenNegLookahead(id: TokenMatchOpId) TokenMatchOp {
    return .{ .MatchNegLookahead = .{
        .op_id = id,
    } };
}

fn matchTokenPosLookahead(id: TokenMatchOpId) TokenMatchOp {
    return .{ .MatchPosLookahead = .{
        .op_id = id,
    } };
}

fn matchTokenRule(name: []const u8) TokenMatchOp {
    return .{
        .MatchRule = .{
            .name = name,
            .tag = undefined,
        },
    };
}

fn matchUntilChar(ch: u8) TokenMatchOp {
    return .{
        .MatchUntilChar = .{
            .ch = ch,
        },
    };
}

fn matchNotChar(ch: u8) TokenMatchOp {
    return .{
        .MatchNotChar = .{
            .ch = ch,
        },
    };
}

fn matchExactChar(ch: u8) TokenMatchOp {
    return .{ .MatchExactChar = .{
        .ch = ch,
    } };
}

fn matchTokenSeq(ops: TokenMatchOpSlice) TokenMatchOp {
    return .{
        .MatchSeq = .{
            .ops = ops,
        },
    };
}

fn matchTokenNotCharSet(charset: CharSlice, ranges: CharSetRangeSlice) TokenMatchOp {
    return .{ .MatchNotCharSet = .{
        .resolved_charset = undefined,
        .charset = charset,
        .ranges = ranges,
    } };
}

fn matchTokenCharSet(charset: CharSlice, ranges: CharSetRangeSlice) TokenMatchOp {
    return .{ .MatchCharSet = .{
        .resolved_charset = undefined,
        .charset = charset,
        .ranges = ranges,
    } };
}

fn matchTokenChoice(
    ops: TokenMatchOpSlice,
) TokenMatchOp {
    return .{
        .MatchChoice = .{
            .ops = ops,
        },
    };
}

fn matchDigit(one_or_more: bool) TokenMatchOp {
    return .{
        .MatchDigit = if (one_or_more) .OneOrMore else .One,
    };
}

fn matchAsciiLetter() TokenMatchOp {
    return .{
        .MatchAsciiLetter = {},
    };
}
