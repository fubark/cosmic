const std = @import("std");
const stdx = @import("stdx");
const algo = stdx.algo;
const log = stdx.log.scoped(.grammar);
const ds = stdx.ds;

const parser = @import("parser.zig");
const NodeTag = parser.NodeTag;
const NodePtr = parser.NodePtr;
const builder = @import("builder.zig");

pub const Grammar = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    token_decls: std.ArrayList(TokenDecl),

    // The decls used in the first pass to start matching each char.
    // After a match, the matched string can be replaced by another decl with @replace.
    token_main_decls: std.ArrayList(TokenDecl),

    // Maps a literal str to its tag. Tag is then used for fast comparisons.
    literal_tag_map: stdx.ds.OwnedKeyStringHashMap(LiteralTokenTag),
    next_literal_tag: LiteralTokenTag,

    decls: std.ArrayList(RuleDecl),
    ops: std.ArrayList(MatchOp),
    token_ops: std.ArrayList(TokenMatchOp),
    root_rule_name: []const u8,
    root_rule_id: RuleId,

    // String buf for dupes and unescaped strings.
    str_buf: std.ArrayList(u8),

    // Prevent allocating duplicate strings.
    str_buf_map: std.StringHashMap(CharSlice),

    // Buffer for charset ranges.
    charset_range_buf: std.ArrayList(CharSetRange),

    // Special node tags.
    decl_tag_end: NodeTag, // Exclusive.
    // TODO: Make these start at predefined values starting at 0 so we get comptime branching.
    // Would require realloc on readonly decls list since tags are used to index into them.
    null_node_tag: NodeTag, // Represents a null node. Used when setting node child fields.
    node_list_tag: NodeTag,
    string_value_tag: NodeTag,
    token_value_tag: NodeTag,
    char_value_tag: NodeTag,

    // Transient vars.
    token_match_op_buf: std.ArrayList(*TokenMatchOp),
    match_op_buf: std.ArrayList(*MatchOp),
    bit_buf: ds.BitArrayList,

    pub fn init(self: *Self, alloc: std.mem.Allocator, root_rule_name: []const u8) void {
        self.* = .{
            .alloc = alloc,
            .token_decls = std.ArrayList(TokenDecl).init(alloc),
            .token_main_decls = std.ArrayList(TokenDecl).init(alloc),
            .literal_tag_map = stdx.ds.OwnedKeyStringHashMap(LiteralTokenTag).init(alloc),
            .next_literal_tag = NullLiteralTokenTag + 1,
            .decls = std.ArrayList(RuleDecl).init(alloc),
            .ops = std.ArrayList(MatchOp).init(alloc),
            .token_ops = std.ArrayList(TokenMatchOp).init(alloc),
            .root_rule_name = root_rule_name,
            .root_rule_id = undefined,
            .node_list_tag = undefined,
            .string_value_tag = undefined,
            .char_value_tag = undefined,
            .token_value_tag = undefined,
            .decl_tag_end = undefined,
            .null_node_tag = undefined,
            .token_match_op_buf = std.ArrayList(*TokenMatchOp).init(alloc),
            .match_op_buf = std.ArrayList(*MatchOp).init(alloc),
            .bit_buf = ds.BitArrayList.init(alloc),
            .str_buf = std.ArrayList(u8).init(alloc),
            .str_buf_map = std.StringHashMap(CharSlice).init(alloc),
            .charset_range_buf = std.ArrayList(CharSetRange).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.literal_tag_map.deinit();
        self.token_decls.deinit();
        self.token_main_decls.deinit();
        self.token_ops.deinit();
        self.ops.deinit();
        self.decls.deinit();
        self.token_match_op_buf.deinit();
        self.match_op_buf.deinit();
        self.bit_buf.deinit();
        self.str_buf.deinit();
        self.str_buf_map.deinit();
        self.charset_range_buf.deinit();
    }

    // Should only be used before Grammar.build.
    fn addString(self: *Self, str: []const u8) CharSlice {
        const item = self.str_buf_map.getOrPut(str) catch unreachable;
        if (!item.found_existing) {
            const start = self.str_buf.items.len;
            self.str_buf.appendSlice(str) catch unreachable;
            const slice = CharSlice{ .start = @intCast(u32, start), .end = @intCast(u32, self.str_buf.items.len) };
            item.value_ptr.* = slice;
        }
        return item.value_ptr.*;
    }

    pub fn getString(self: *Self, slice: CharSlice) []const u8 {
        return self.str_buf.items[slice.start..slice.end];
    }

    fn addLiteralTokenTag(self: *Self, str: []const u8) LiteralTokenTag {
        if (self.literal_tag_map.get(str)) |_| {
            // For now prevent multiple declarations of the same literal.
            stdx.panicFmt("already added literal '{s}'", .{str});
        }
        self.literal_tag_map.put(str, self.next_literal_tag) catch unreachable;
        defer self.next_literal_tag += 1;
        return self.next_literal_tag;
    }

    // Build config before it can be used by the Parser.
    pub fn build(self: *Self, alloc: std.mem.Allocator) void {
        self.root_rule_id = self.findRuleDeclId(self.root_rule_name) orelse stdx.panicFmt("Couldn't find {s}", .{self.root_rule_name});

        // Assumes CharSlice is a unique key to the same string.
        var name_to_token_tag = std.AutoHashMap(CharSlice, TokenTag).init(alloc);
        defer name_to_token_tag.deinit();

        var name_to_rule = std.AutoHashMap(CharSlice, RuleId).init(alloc);
        defer name_to_rule.deinit();

        for (self.token_decls.items) |decl, idx| {
            name_to_token_tag.put(decl.name, @intCast(u32, idx)) catch unreachable;

            // Generate Rules that wrap TokenRules with a string value as the only field.
            const name = self.getString(decl.name);
            self.addRule(name, self.matchTokCap(name));

            if (decl.replace_name != null) {
                const target_tag = self.findTokenDecl(decl.replace_name.?) orelse stdx.panicFmt("Couldn't find {s}", .{decl.replace_name.?});
                const target_decl = &self.token_decls.items[target_tag];
                target_decl.replace_with = @intCast(u32, idx);
            }
        }
        for (self.decls.items) |it, idx| {
            name_to_rule.put(it.name, @intCast(u32, idx)) catch unreachable;
        }

        prepareTokenMatchOps(self, &name_to_token_tag);

        // Token processing after op resolving.
        for (self.token_decls.items) |decl| {
            if (decl.is_literal) {
                const op = self.token_ops.items[decl.op_id];
                // For now, just look for MatchChoice op and assign literal tag to the immediate MatchText children.
                if (op == .MatchChoice) {
                    var i = op.MatchChoice.ops.start;
                    while (i < op.MatchChoice.ops.end) : (i += 1) {
                        const child_op = self.token_ops.items[i];
                        if (child_op == .MatchText) {
                            const str = self.getString(child_op.MatchText.str);
                            _ = self.addLiteralTokenTag(str);
                        } else if (child_op == .MatchExactChar) {
                            _ = self.addLiteralTokenTag(&[_]u8{child_op.MatchExactChar.ch});
                        }
                    }
                } else if (op == .MatchText) {
                    const str = self.getString(op.MatchText.str);
                    _ = self.addLiteralTokenTag(str);
                } else stdx.panicFmt("unsupported {s}", .{@tagName(op)});
            }
        }

        prepareMatchOps(self, &name_to_token_tag, &name_to_rule);

        // Compute node data sizes after we resolved all capture vars in op_ids.
        for (self.decls.items) |*it| {
            var num_child_items: u32 = 0;
            var i = it.ops.start;
            while (i < it.ops.end) : (i += 1) {
                const op = self.ops.items[i];
                const capture = self.shouldCaptureRule(&op);
                if (capture) {
                    num_child_items += 1;
                }
            }
            it.num_child_items = num_child_items;
            it.data_size = num_child_items * @sizeOf(NodePtr);
        }

        // For each rule, check if it can do left term recursion.
        var visited_map = std.AutoHashMap(RuleId, void).init(alloc);
        defer visited_map.deinit();
        for (self.decls.items) |*decl, idx| {
            const rule_id = @intCast(u32, idx);
            decl.is_left_recursive = self.isLeftRecursive(rule_id, &visited_map);
        }

        // Special tags start after decls so that decls can be accessed by their tags directly.
        self.decl_tag_end = @intCast(NodeTag, self.decls.items.len);
        self.node_list_tag = self.decl_tag_end;
        self.string_value_tag = self.decl_tag_end + 1;
        self.char_value_tag = self.decl_tag_end + 2;
        self.null_node_tag = self.decl_tag_end + 3;
        self.token_value_tag = self.decl_tag_end + 4;

        // Generate the main token decls after they have computed values set.
        for (self.token_decls.items) |it| {
            if (it.replace_name == null) {
                self.token_main_decls.append(it) catch unreachable;
            }
        }
    }

    // Checks against the first term of a match op.
    // We need to track visited sub rules or the walking will be recursive.
    fn isLeftRecursive(self: *Self, rule_id: RuleId, visited_map: *std.AutoHashMap(RuleId, void)) bool {
        const Result = enum {
            NotLeftRecursive,
            LeftRecursive,
            // Indicates that a subbranch contains a MatchRule that matches the root.
            // A parent MatchSeq still needs to determine if it is a LeftRecursive.
            FoundSameMatchRule,
        };
        const S = struct {
            rule_id: RuleId,
            config: *Grammar,
            visited_map: *std.AutoHashMap(RuleId, void),

            fn visitFirstOpTerm(ctx: *@This(), op_id: MatchOpId) Result {
                const op = ctx.config.getMatchOp(op_id);
                switch (op) {
                    .MatchSeq => |inner| {
                        const res = visitFirstOpTerm(ctx, inner.ops.start);
                        if (res == .FoundSameMatchRule) {
                            const len = inner.ops.len();
                            if (len == 1) {
                                return res;
                            } else if (len > 1) {
                                return .LeftRecursive;
                            } else {
                                unreachable;
                            }
                        } else {
                            return res;
                        }
                    },
                    .MatchOptional => |inner| {
                        return visitFirstOpTerm(ctx, inner.op_id);
                    },
                    .MatchRule => |inner| {
                        if (ctx.rule_id == inner.rule_id) {
                            return .FoundSameMatchRule;
                        } else {
                            if (ctx.visited_map.contains(inner.rule_id)) {
                                return .NotLeftRecursive;
                            }
                            ctx.visited_map.put(inner.rule_id, {}) catch unreachable;
                            const rule = ctx.config.getRule(inner.rule_id);
                            const res = visitFirstOpTerm(ctx, rule.ops.start);
                            if (res == .FoundSameMatchRule) {
                                const num_ops = rule.ops.len();
                                if (num_ops == 1) {
                                    return res;
                                } else if (num_ops > 1) {
                                    return .LeftRecursive;
                                } else {
                                    unreachable;
                                }
                            } else {
                                return res;
                            }
                        }
                    },
                    .MatchChoice => |inner| {
                        var i = inner.ops.start;
                        while (i < inner.ops.end) : (i += 1) {
                            const res = visitFirstOpTerm(ctx, i);
                            if (res == .LeftRecursive or res == .FoundSameMatchRule) {
                                return res;
                            }
                        }
                        return .NotLeftRecursive;
                    },
                    .MatchNegLookahead, .MatchPosLookahead, .MatchLiteral, .MatchToken, .MatchTokenText, .MatchOneOrMore, .MatchZeroOrMore => {
                        return .NotLeftRecursive;
                    },
                    // else => stdx.panicFmt("unsupported {s}", .{@tagName(op)}),
                }
            }
        };
        var ctx = S{ .config = self, .rule_id = rule_id, .visited_map = visited_map };
        const rule = self.getRule(rule_id);
        visited_map.clearRetainingCapacity();
        return S.visitFirstOpTerm(&ctx, rule.ops.start) == .LeftRecursive;
    }

    pub fn shouldCaptureRule(self: *Self, rule: *const MatchOp) bool {
        _ = self;
        return switch (rule.*) {
            .MatchToken => |inner| inner.capture,
            .MatchTokenText => |inner| inner.capture,
            .MatchRule => |inner| !inner.skip,
            .MatchZeroOrMore => |inner| !inner.skip,
            .MatchOneOrMore => |_| true,
            .MatchSeq => |inner| inner.computed_capture,
            .MatchChoice => |inner| inner.computed_capture,
            .MatchOptional => |inner| inner.computed_capture,
            .MatchNegLookahead => false,
            .MatchPosLookahead => false,
            .MatchLiteral => |inner| inner.capture,
        };
    }

    pub fn getNumChildFields(self: *Self, tag: NodeTag) u32 {
        if (tag < self.node_list_tag) {
            return self.decls.items[tag].num_child_items;
        } else if (tag == self.node_list_tag) {
            return 1;
        } else {
            stdx.panicFmt("unsupported tag {}", .{tag});
        }
    }

    pub fn getNodeDataSize(self: *Self, tag: NodeTag) u32 {
        if (tag < self.node_list_tag) {
            return self.decls.items[tag].data_size;
        } else if (tag == self.node_list_tag) {
            return @sizeOf([]const NodePtr);
        } else {
            stdx.panicFmt("unsupported tag {}", .{tag});
        }
    }

    pub fn getMatchOp(self: *Self, id: MatchOpId) MatchOp {
        return self.ops.items[id];
    }

    pub fn getMatchOpName(self: *Self, id: MatchOpId) []const u8 {
        return @tagName(self.ops.items[id]);
    }

    pub fn getMatchOpDesc(self: *Self, id: MatchOpId) []const u8 {
        const static = struct {
            var buf: [128]u8 = undefined;
        };
        const op = self.ops.items[id];
        var fbs = std.io.fixedBufferStream(&static.buf);
        var writer = fbs.writer();
        std.fmt.format(writer, "{s} ", .{@tagName(op)}) catch {};
        if (op == .MatchLiteral) {
            const str = self.getString(op.MatchLiteral.str);
            std.fmt.format(writer, "{s} ", .{str}) catch {};
        }
        return fbs.getWritten();
    }

    pub fn getRule(self: *Self, id: RuleId) RuleDecl {
        return self.decls.items[id];
    }

    pub fn getRuleName(self: *Self, id: RuleId) []const u8 {
        return self.getString(self.decls.items[id].name);
    }

    pub fn getTokenName(self: *Self, tag: TokenTag) []const u8 {
        return self.getString(self.token_decls.items[tag].name);
    }

    pub fn getNodeTagName(self: *Self, id: NodeTag) []const u8 {
        if (id < self.decl_tag_end) {
            return self.getRuleName(id);
        } else if (id == self.node_list_tag) {
            return "NodeList";
        } else if (id == self.string_value_tag) {
            return "String";
        } else if (id == self.char_value_tag) {
            return "Char";
        } else if (id == self.null_node_tag) {
            return "Null";
        } else if (id == self.token_value_tag) {
            return "TokenString";
        } else {
            stdx.panicFmt("unsupported {}", .{id});
        }
    }

    fn findTokenDecl(self: *Self, name: []const u8) ?TokenTag {
        for (self.token_decls.items) |it, idx| {
            const token_name = self.getString(it.name);
            if (std.mem.eql(u8, token_name, name)) {
                return @intCast(u32, idx);
            }
        }
        return null;
    }

    pub fn findRuleDeclId(self: *Self, name: []const u8) ?RuleId {
        for (self.decls.items) |it, idx| {
            const rule_name = self.getString(it.name);
            if (std.mem.eql(u8, rule_name, name)) {
                return @intCast(u32, idx);
            }
        }
        return null;
    }

    pub fn findRuleDecl(self: *Self, name: []const u8) ?RuleDecl {
        const mb_id = self.findRuleDeclId(name);
        return if (mb_id) |id| self.getRule(id) else null;
    }

    pub fn addTokenOp(self: *Self, op: TokenMatchOp) TokenMatchOpId {
        self.token_ops.append(op) catch unreachable;
        return @intCast(TokenMatchOpId, self.token_ops.items.len - 1);
    }

    pub fn addTokenOps(self: *Self, ops: []const TokenMatchOp) TokenMatchOpSlice {
        const first = self.addTokenOp(ops[0]);
        for (ops[1..]) |it| {
            _ = self.addTokenOp(it);
        }
        return .{ .start = first, .end = first + @intCast(u32, ops.len) };
    }

    pub fn addTokenRule(self: *Self, name: []const u8, op: TokenMatchOp) void {
        self.addTokenRuleExt(name, op, false, false, null);
    }

    pub fn addTokenRuleExt(self: *Self, name: []const u8, op: TokenMatchOp, is_literal: bool, skip: bool, replace: ?[]const u8) void {
        const name_slice = self.addString(name);
        const op_id = self.addTokenOp(op);
        const tag = @intCast(u32, self.token_decls.items.len);
        self.token_decls.append(TokenDecl.init(tag, name_slice, op_id, is_literal, skip, replace)) catch unreachable;
    }

    pub fn addRuleExt(self: *Self, name: []const u8, op: MatchOp, is_inline: bool) void {
        const name_slice = self.addString(name);
        const op_id = self.addOp(op);
        if (op == .MatchSeq) {
            self.decls.append(RuleDecl.init(name_slice, op.MatchSeq.ops, is_inline)) catch unreachable;
        } else {
            const slice = MatchOpSlice{ .start = op_id, .end = op_id + 1 };
            self.decls.append(RuleDecl.init(name_slice, slice, is_inline)) catch unreachable;
        }
    }

    pub fn addRule(self: *Self, name: []const u8, op: MatchOp) void {
        self.addRuleExt(name, op, false);
    }

    pub fn addInlineRule(self: *Self, name: []const u8, op: MatchOp) void {
        self.addRuleExt(name, op, true);
    }

    pub fn addOp(self: *Self, op: MatchOp) MatchOpId {
        self.ops.append(op) catch unreachable;
        return @intCast(MatchOpId, self.ops.items.len - 1);
    }

    pub fn addOps(self: *Self, ops: []const MatchOp) MatchOpSlice {
        const first = self.addOp(ops[0]);
        for (ops[1..]) |it| {
            _ = self.addOp(it);
        }
        return .{ .start = first, .end = first + @intCast(u32, ops.len) };
    }

    pub fn matchTokCap(self: *Self, tag_name: []const u8) MatchOp {
        const slice = self.addString(tag_name);
        return .{
            .MatchToken = .{
                .capture = true,
                .tag_name = slice,
                .tag = undefined,
            },
        };
    }

    pub fn matchTokText(self: *Self, tag_name: []const u8, str: []const u8) MatchOp {
        return .{
            .MatchTokenText = .{
                .capture = false,
                .tag_name = self.addString(tag_name),
                .tag = undefined,
                .str = self.addString(str),
            },
        };
    }

    pub fn matchRule(self: *Self, name: []const u8) MatchOp {
        const slice = self.addString(name);
        return .{
            .MatchRule = .{
                .skip = false,
                .name = slice,
                .rule_id = undefined,
            },
        };
    }

    pub fn matchLiteral(self: *Self, str: []const u8) MatchOp {
        const slice = self.addString(str);
        return .{
            .MatchLiteral = .{
                .capture = false,
                .computed_literal_tag = undefined,
                .str = slice,
            },
        };
    }

    pub fn matchLiteralCap(self: *Self, str: []const u8) MatchOp {
        const slice = self.addString(str);
        return .{
            .MatchLiteral = .{
                .capture = true,
                .computed_literal_tag = undefined,
                .str = slice,
            },
        };
    }

    pub fn tokMatchText(self: *Self, str: []const u8) TokenMatchOp {
        const slice = self.addString(str);
        return .{ .MatchText = .{
            .str = slice,
        } };
    }
};

fn initTokenMatchOpWalker(op_ids: []TokenMatchOp) algo.Walker([]TokenMatchOp, *TokenMatchOp) {
    const S = struct {
        fn _walk(ctx: *algo.WalkerContext(*TokenMatchOp), ops: []TokenMatchOp, op: *TokenMatchOp) void {
            _ = ctx;
            switch (op.*) {
                .MatchText, .MatchUntilChar, .MatchExactChar, .MatchNotChar, .MatchRangeChar, .MatchAsciiLetter, .MatchDigit, .MatchRegexChar, .MatchCharSet, .MatchNotCharSet, .MatchRule => {
                    // Nop.
                },
                .MatchOneOrMore => |inner| {
                    ctx.beginAddNode(1);
                    ctx.addNode(&ops[inner.op_id]);
                },
                .MatchZeroOrMore => |inner| {
                    ctx.beginAddNode(1);
                    ctx.addNode(&ops[inner.op_id]);
                },
                .MatchChoice => |inner| {
                    var i = inner.ops.start;
                    ctx.beginAddNode(inner.ops.len());
                    while (i < inner.ops.end) : (i += 1) {
                        var _op = &ops[i];
                        ctx.addNode(_op);
                    }
                },
                .MatchOptional => |m| {
                    ctx.beginAddNode(1);
                    ctx.addNode(&ops[m.op_id]);
                },
                .MatchNegLookahead => |m| {
                    ctx.beginAddNode(1);
                    ctx.addNode(&ops[m.op_id]);
                },
                .MatchPosLookahead => |m| {
                    ctx.beginAddNode(1);
                    ctx.addNode(&ops[m.op_id]);
                },
                .MatchSeq => |inner| {
                    var i = inner.ops.start;
                    ctx.beginAddNode(inner.ops.len());
                    while (i < inner.ops.end) : (i += 1) {
                        var _op = &ops[i];
                        ctx.addNode(_op);
                    }
                },
            }
        }
    };
    return algo.Walker([]TokenMatchOp, *TokenMatchOp).init(op_ids, S._walk);
}

fn initMatchOpWalker(op_ids: []MatchOp) algo.Walker([]MatchOp, *MatchOp) {
    const S = struct {
        fn _walk(ctx: *algo.WalkerContext(*MatchOp), ops: []MatchOp, op: *MatchOp) void {
            switch (op.*) {
                .MatchLiteral, .MatchToken, .MatchRule, .MatchTokenText => {
                    // Nop.
                },
                .MatchNegLookahead => |m| {
                    var inner = &ops[m.op_id];
                    ctx.beginAddNode(1);
                    ctx.addNode(inner);
                },
                .MatchPosLookahead => |m| {
                    var inner = &ops[m.op_id];
                    ctx.beginAddNode(1);
                    ctx.addNode(inner);
                },
                .MatchOptional => |inner| {
                    var _op = &ops[inner.op_id];
                    ctx.beginAddNode(1);
                    ctx.addNode(_op);
                },
                .MatchSeq => |inner| {
                    var i = inner.ops.start;
                    ctx.beginAddNode(inner.ops.len());
                    while (i < inner.ops.end) : (i += 1) {
                        var _op = &ops[i];
                        ctx.addNode(_op);
                    }
                },
                .MatchChoice => |inner| {
                    var i = inner.ops.start;
                    ctx.beginAddNode(inner.ops.len());
                    while (i < inner.ops.end) : (i += 1) {
                        var _op = &ops[i];
                        ctx.addNode(_op);
                    }
                },
                .MatchOneOrMore => |inner| {
                    var _op = &ops[inner.op_id];
                    ctx.beginAddNode(1);
                    ctx.addNode(_op);
                },
                .MatchZeroOrMore => |inner| {
                    var _op = &ops[inner.op_id];
                    ctx.beginAddNode(1);
                    ctx.addNode(_op);
                },
            }
        }
    };
    return algo.Walker([]MatchOp, *MatchOp).init(op_ids, S._walk);
}

fn prepareTokenMatchOps(config: *Grammar, name_to_token_tag: *const std.AutoHashMap(CharSlice, TokenTag)) void {
    const S = struct {
        config: *Grammar,
        name_to_token_tag: *const std.AutoHashMap(CharSlice, TokenTag),

        fn resolve(_: *algo.VisitContext(.{}), c: *@This(), op: *TokenMatchOp) void {
            switch (op.*) {
                .MatchRule => |*inner| {
                    inner.tag = c.config.findTokenDecl(inner.name).?;
                },
                .MatchCharSet => |*inner| {
                    // TODO: Remove resolved fields, it's probably slower than referencing str_buf directly.
                    inner.resolved_charset = c.config.str_buf.items[inner.charset.start..inner.charset.end];
                },
                .MatchNotCharSet => |*inner| {
                    inner.resolved_charset = c.config.str_buf.items[inner.charset.start..inner.charset.end];
                },
                .MatchOptional,
                .MatchText,
                .MatchUntilChar,
                .MatchExactChar,
                .MatchNotChar,
                .MatchRangeChar,
                .MatchAsciiLetter,
                .MatchDigit,
                .MatchRegexChar,
                .MatchZeroOrMore,
                .MatchOneOrMore,
                .MatchChoice,
                .MatchNegLookahead,
                .MatchPosLookahead,
                .MatchSeq,
                => {},
            }
        }
    };

    var ctx = S{
        .config = config,
        .name_to_token_tag = name_to_token_tag,
    };

    var walker = initTokenMatchOpWalker(config.token_ops.items);
    for (config.token_decls.items) |decl| {
        const op = &config.token_ops.items[decl.op_id];
        algo.walkPost(.{}, *S, &ctx, *TokenMatchOp, op, walker.getIface(), S.resolve, &config.token_match_op_buf, &config.bit_buf);
    }
}

fn prepareMatchOps(g: *Grammar, name_to_token_tag: *const std.AutoHashMap(CharSlice, TokenTag), name_to_rule: *const std.AutoHashMap(CharSlice, RuleId)) void {
    const S = struct {
        g: *Grammar,
        name_to_token_tag: *const std.AutoHashMap(CharSlice, TokenTag),
        name_to_rule: *const std.AutoHashMap(CharSlice, RuleId),

        fn resolve(_: *algo.VisitContext(.{}), self: *@This(), op: *MatchOp) void {
            // Set match op tags.
            // Compute capture.
            switch (op.*) {
                .MatchToken => |*inner| {
                    inner.tag = self.name_to_token_tag.get(inner.tag_name) orelse stdx.panicFmt("Couldn't find {s}", .{self.g.getString(inner.tag_name)});
                },
                .MatchTokenText => |*inner| {
                    inner.tag = self.name_to_token_tag.get(inner.tag_name) orelse stdx.panicFmt("Couldn't find {s}", .{self.g.getString(inner.tag_name)});
                },
                .MatchRule => |*inner| {
                    inner.rule_id = self.name_to_rule.get(inner.name) orelse stdx.panicFmt("Couldn't find {s}", .{self.g.getString(inner.name)});
                },
                .MatchOptional => |*inner| {
                    const child_rule = self.g.ops.items[inner.op_id];
                    inner.computed_capture = self.g.shouldCaptureRule(&child_rule);
                },
                .MatchSeq => |*inner| b: {
                    var i = inner.ops.start;
                    while (i < inner.ops.end) : (i += 1) {
                        const child_op = self.g.ops.items[i];
                        if (self.g.shouldCaptureRule(&child_op)) {
                            inner.computed_capture = true;
                            break :b;
                        }
                    }
                    inner.computed_capture = false;
                },
                .MatchChoice => |*inner| b: {
                    var i = inner.ops.start;
                    while (i < inner.ops.end) : (i += 1) {
                        const child_op = self.g.ops.items[i];
                        if (self.g.shouldCaptureRule(&child_op)) {
                            inner.computed_capture = true;
                            break :b;
                        }
                    }
                    inner.computed_capture = false;
                },
                .MatchLiteral => |*inner| {
                    const str = self.g.getString(inner.str);
                    if (self.g.literal_tag_map.get(str)) |literal_tag| {
                        inner.computed_literal_tag = literal_tag;
                    } else {
                        log.warn("literal tags: {}", .{self.g.literal_tag_map.count()});
                        stdx.panicFmt("expected literal tag for '{s}'", .{self.g.getString(inner.str)});
                    }
                },
                .MatchNegLookahead, .MatchPosLookahead, .MatchOneOrMore, .MatchZeroOrMore => {
                    // Nop.
                },
            }
        }
    };

    var ctx = S{
        .g = g,
        .name_to_token_tag = name_to_token_tag,
        .name_to_rule = name_to_rule,
    };

    var walker = initMatchOpWalker(g.ops.items);
    for (g.decls.items) |decl| {
        var i = decl.ops.start;
        while (i < decl.ops.end) : (i += 1) {
            const op = &g.ops.items[i];
            // Visit the leaf nodes first so we can compute whether op_ids need to be captured by looking at its children.
            algo.walkPost(.{}, *S, &ctx, *MatchOp, op, walker.getIface(), S.resolve, &g.match_op_buf, &g.bit_buf);
        }
    }
}

pub const RuleId = u32;
pub const RuleDecl = struct {
    name: CharSlice,

    // These ops match like a seq and parses into child fields of the root node.
    ops: MatchOpSlice,

    // Skip creating an AST node for this rule and return child node instead.
    // Useful for Statement, Declaration, Expression decls.
    is_inline: bool,

    // This is computed in Grammar.build.
    // If true, there exists a sub expression where the left term is itself and additional terms follow.
    // Before returning the first match result, it will try to recursively match itself against those recursive expressions.
    is_left_recursive: bool,

    // Computed.
    num_child_items: u32,
    data_size: u32,

    fn init(name: CharSlice, ops: MatchOpSlice, is_inline: bool) @This() {
        return .{
            .name = name,
            .is_inline = is_inline,
            .ops = ops,
            .num_child_items = undefined,
            .data_size = undefined,
            .is_left_recursive = undefined,
        };
    }
};

pub const MatchOpId = u32;
pub const MatchOpSlice = ds.IndexSlice(MatchOpId);

pub const MatchOp = union(enum) {
    MatchOneOrMore: struct {
        op_id: MatchOpId,
    },

    MatchZeroOrMore: struct {
        skip: bool,
        op_id: MatchOpId,
    },

    MatchToken: struct {
        capture: bool,
        tag_name: CharSlice,
        // Tag is set by Grammar.build.
        tag: TokenTag,
    },

    // Match any literal token with text value.
    // Literal tokens are created if there is a TokenDecl with a top level TokenMatchOp.MatchLiteral op.
    MatchLiteral: struct {
        capture: bool,
        computed_literal_tag: LiteralTokenTag,
        str: CharSlice,
    },

    // Match token and text value.
    MatchTokenText: struct {
        // By default matching exact token text is not included in the parsed ast.
        // Setting capture to true would include it.
        // TODO: Should be captureName: ?[]const u8
        capture: bool,

        tag_name: CharSlice,
        tag: TokenTag,

        str: CharSlice,
    },

    MatchRule: struct {
        // By default matching other rules is included into the parsed ast.
        skip: bool,
        name: CharSlice,
        rule_id: RuleId,
    },

    // Matches all and returns last matching child up to parent.
    // TODO: multiple matching children should be returned as NodeList
    MatchSeq: struct {
        computed_capture: bool,
        ops: MatchOpSlice,
    },

    // Returns matching child up to parent.
    MatchChoice: struct {
        // capture is computed by looking at it's child op_ids.
        computed_capture: bool,
        ops: MatchOpSlice,
    },

    // Returns matching child up to parent.
    MatchOptional: struct {
        // Instead of returning the child, return a bool value
        capture_bool: bool,
        computed_capture: bool,
        op_id: MatchOpId,
    },

    MatchNegLookahead: struct {
        op_id: MatchOpId,
    },

    MatchPosLookahead: struct {
        op_id: MatchOpId,
    },
};

// Index into the decls array.
pub const TokenTag = u32;

// Id starting from 1 assigned to each unique literal token. Useful for fast comparisons.
pub const LiteralTokenTag = u32;

// Id 0 is reserved for no literal token tag.
pub const NullLiteralTokenTag: LiteralTokenTag = 0;

pub const TokenDecl = struct {
    tag: TokenTag,

    name: CharSlice,
    op_id: TokenMatchOpId,

    // Match but skip adding to token list.
    skip: bool,

    // The matches from this rule should also be assigned a literal tag.
    is_literal: bool,

    // Which token name to replace.
    replace_name: ?[]const u8,

    // Set by config prepare step.
    replace_with: ?TokenTag,

    pub fn init(tag: TokenTag, name: CharSlice, op_id: TokenMatchOpId, is_literal: bool, skip: bool, replace_name: ?[]const u8) @This() {
        return .{
            .tag = tag,
            .name = name,
            .op_id = op_id,
            .skip = skip,
            .is_literal = is_literal,
            .replace_name = replace_name,
            .replace_with = null,
        };
    }
};

pub const TokenMatchOpId = u32;
pub const TokenMatchOpSlice = ds.IndexSlice(TokenMatchOpId);

// eg. [a-zA-Z0-9]
pub const CharSetRange = struct {
    start: u8,
    end_incl: u8,
};
const CharSetRangeId = u32;
pub const CharSetRangeSlice = ds.IndexSlice(CharSetRangeId);

const CharId = u32;
pub const CharSlice = ds.IndexSlice(CharId);

pub const TokenMatchOp = union(enum) {
    MatchRule: struct {
        name: []const u8,
        tag: TokenTag,
    },
    MatchCharSet: struct {
        // When building, a CharSlice is added but is resolved to a slice in Grammar.build
        // TODO: remove this, its faster with ptr from the buffer
        resolved_charset: []const u8,
        charset: CharSlice,
        ranges: CharSetRangeSlice,
    },
    MatchNotCharSet: struct {
        resolved_charset: []const u8,
        charset: CharSlice,
        ranges: CharSetRangeSlice,
    },
    MatchZeroOrMore: struct {
        op_id: TokenMatchOpId,
    },
    MatchOneOrMore: struct {
        op_id: TokenMatchOpId,
    },
    MatchText: struct {
        str: CharSlice,
    },
    MatchUntilChar: struct {
        ch: u8,
    },
    MatchExactChar: struct {
        ch: u8,
    },
    MatchNotChar: struct {
        ch: u8,
    },
    MatchRangeChar: struct {
        start: u8,
        // Inclusive.
        end: u8,
        mod: MatchModifier,
    },
    MatchAsciiLetter: void,
    MatchDigit: MatchModifier,
    MatchRegexChar: struct {
        expr: []const u8,
    },
    // Tokenizer needs to save the state before trying each path.
    MatchChoice: struct {
        ops: TokenMatchOpSlice,
    },
    MatchSeq: struct {
        ops: TokenMatchOpSlice,
    },
    MatchOptional: struct {
        op_id: TokenMatchOpId,
    },
    MatchPosLookahead: struct {
        op_id: TokenMatchOpId,
    },
    MatchNegLookahead: struct {
        op_id: TokenMatchOpId,
    },
};

const MatchModifier = enum {
    One,
    OneOrMore,
};
