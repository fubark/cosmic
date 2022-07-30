const std = @import("std");
const stdx = @import("stdx");
const string = stdx.string;
const algo = stdx.algo;
const ds = stdx.ds;
const t = stdx.testing;
const builtin = @import("builtin");

const tracy = stdx.debug.tracy;
const document = stdx.textbuf.document;
const Document = document.Document;
const LineChunkId = document.LineChunkId;

const log = stdx.log.scoped(.parser);
const tokenizer = @import("tokenizer.zig");
const Tokenizer = tokenizer.Tokenizer;
const grammar = @import("grammar.zig");
const RuleId = grammar.RuleId;
const RuleDecl = grammar.RuleDecl;
const MatchOp = grammar.MatchOp;
const MatchOpId = grammar.MatchOpId;
const Grammar = grammar.Grammar;
const _ast = @import("ast.zig");
const Tree = _ast.Tree;
const TokenId = _ast.TokenId;
const TokenListId = _ast.TokenListId;
const Token = _ast.Token;
const LineTokenBuffer = _ast.LineTokenBuffer;
const NullToken = stdx.ds.CompactNull(TokenId);

// Creates a runtime parser from a PEG based config grammar.
// Parses in linear time with respect to source size using a memoization cache. Two cache implementations depending on token list size.
// Supports left recursion.
// Supports look-ahead operators.
// Initial support for incremental retokenize.
// TODO: Implement incremental reparsing.
// TODO: Use literal hashmap for token choice ops
// TODO: Flatten rules with the same starting ops.

// LINKS:
// https://medium.com/@gvanrossum_83706/peg-parsing-series-de5d41b2ed60
// https://pest.rs/book/grammars/peg.html

const DebugParseRule = false and builtin.mode == .Debug;

// Sources with more tokens than this threshold use a cache map instead of a cache stack for parse rule memoization.
const CacheMapTokenThreshold = 10000;

pub const Parser = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    tokenizer: Tokenizer,
    decls: []const RuleDecl,
    ops: []const MatchOp,
    grammar: *Grammar,

    buf: struct {
        // Node ptrs.
        node_ptrs: std.ArrayList(NodePtr),

        // Slices to node_ptrs.
        node_slices: std.ArrayList(NodeSlice),

        // Node data that points to tokens.
        node_tokens: std.ArrayList(NodeTokenPtr),
    },

    // Used to accumulate nodes together to create a list.
    node_list_stack: std.ArrayList(NodePtr),

    // For nodes that don't point to any additional data.
    next_scalar_node_id: NodeId,

    // Used to detect recursive calls to parseRule
    is_parsing_rule_stack: ds.BitArrayList,

    // Memoization stack to cache parseRule results at every token position.
    // TODO: A future optimization could bucket rules that match the same first token together. It could save more memory.
    parse_rule_cache_stack: std.ArrayList(CacheItem),

    // Use a cache map for source with many tokens. It's slower than the cache stack but uses way a lot less memory.
    parse_rule_cache_map: std.AutoHashMap(u32, CacheItem),

    // The current starting pos in the stack bufs.
    rule_stack_start: u32,

    pub fn init(alloc: std.mem.Allocator, g: *Grammar) Self {
        var new = Self{
            .alloc = alloc,
            .tokenizer = Tokenizer.init(g),
            .decls = g.decls.items,
            .ops = g.ops.items,
            .grammar = g,
            .node_list_stack = std.ArrayList(NodePtr).init(alloc),
            .is_parsing_rule_stack = ds.BitArrayList.init(alloc),
            .parse_rule_cache_stack = std.ArrayList(CacheItem).init(alloc),
            .parse_rule_cache_map = std.AutoHashMap(u32, CacheItem).init(alloc),
            .rule_stack_start = undefined,
            .next_scalar_node_id = 1,
            .buf = .{
                .node_ptrs = std.ArrayList(NodePtr).init(alloc),
                .node_slices = std.ArrayList(NodeSlice).init(alloc),
                .node_tokens = std.ArrayList(NodeTokenPtr).init(alloc),
            },
        };
        return new;
    }

    pub fn deinit(self: *Self) void {
        self.node_list_stack.deinit();
        self.is_parsing_rule_stack.deinit();
        self.parse_rule_cache_stack.deinit();
        self.parse_rule_cache_map.deinit();
        self.buf.node_ptrs.deinit();
        self.buf.node_slices.deinit();
        self.buf.node_tokens.deinit();
    }

    fn parseMatchManyWithLeftTerm(self: *Self, comptime Context: type, ctx: *Context, comptime OneOrMore: bool, op_id: MatchOpId, left_id: RuleId, left_node: NodePtr) ParseNodeWithLeftResult {

        // Save starting point and accumulate children on the stack.
        const list_start = self.node_list_stack.items.len;
        defer self.node_list_stack.shrinkRetainingCapacity(list_start);

        var consumed_left = false;
        inner: {
            while (true) {
                const mark = ctx.state.mark();
                const res = self.parseMatchOpWithLeftTerm(Context, ctx, op_id, left_id, left_node);
                if (res.matched) {
                    if (res.node_ptr) |node_ptr| {
                        self.node_list_stack.append(node_ptr) catch unreachable;
                    }
                    if (res.consumed_left) {
                        consumed_left = true;
                        break;
                    }
                } else {
                    ctx.state.restoreMark(&mark);
                    break :inner;
                }
            }
            // Parse the right terms.
            while (true) {
                const mark = ctx.state.mark();
                const res = self.parseMatchOp(Context, ctx, op_id);
                if (res.matched) {
                    if (res.node_ptr) |node_ptr| {
                        self.node_list_stack.append(node_ptr) catch unreachable;
                    }
                } else {
                    ctx.state.restoreMark(&mark);
                    break :inner;
                }
            }
        }

        const num_children = @intCast(u32, self.node_list_stack.items.len - list_start);
        if (OneOrMore and num_children == 0) {
            return NoLeftMatch;
        }

        const list_id = @intCast(u32, self.buf.node_slices.items.len);
        const start = @intCast(u32, self.buf.node_ptrs.items.len);
        self.buf.node_slices.append(.{
            .start = start,
            .end = start + num_children,
        }) catch unreachable;

        self.buf.node_ptrs.appendSlice(self.node_list_stack.items[list_start..]) catch unreachable;

        return .{
            .matched = true,
            .consumed_left = consumed_left,
            .node_ptr = .{
                .id = list_id,
                .tag = self.grammar.node_list_tag,
            },
        };
    }

    // TODO: Since we only cache rules, we might need to create a separate stack so we don't keep creating new list nodes at the same pos.
    fn parseMatchMany(self: *Self, comptime Context: type, ctx: *Context, comptime OneOrMore: bool, op_id: MatchOpId) ParseNodeResult {

        // Save starting point and accumulate children on the stack.
        const list_start = self.node_list_stack.items.len;
        defer self.node_list_stack.shrinkRetainingCapacity(list_start);

        while (true) {
            const mark = ctx.state.mark();
            const res = self.parseMatchOp(Context, ctx, op_id);
            if (res.matched) {
                if (res.node_ptr) |node_ptr| {
                    self.node_list_stack.append(node_ptr) catch unreachable;
                }
            } else {
                ctx.state.restoreMark(&mark);
                break;
            }
        }

        const num_children = @intCast(u32, self.node_list_stack.items.len - list_start);
        if (OneOrMore and num_children == 0) {
            return NoMatch;
        }

        const list_id = @intCast(u32, self.buf.node_slices.items.len);
        const start = @intCast(u32, self.buf.node_ptrs.items.len);
        self.buf.node_slices.append(.{
            .start = start,
            .end = start + num_children,
        }) catch unreachable;

        self.buf.node_ptrs.appendSlice(self.node_list_stack.items[list_start..]) catch unreachable;

        return .{
            .matched = true,
            .node_ptr = .{
                .id = list_id,
                .tag = self.grammar.node_list_tag,
            },
        };
    }

    fn parseMatchOpWithLeftTerm(self: *Self, comptime Context: type, ctx: *Context, id: MatchOpId, left_id: RuleId, left_node: NodePtr) ParseNodeWithLeftResult {
        const op = self.ops[id];
        switch (op) {
            .MatchOptional => |inner| {
                const res = self.parseMatchOpWithLeftTerm(Context, ctx, inner.op_id, left_id, left_node);
                if (res.matched) {
                    return res;
                } else {
                    return .{
                        .matched = true,
                        .consumed_left = false,
                        .node_ptr = null,
                    };
                }
            },
            .MatchNegLookahead => |m| {
                const mark = ctx.state.mark();
                const res = self.parseMatchOpWithLeftTerm(Context, ctx, m.op_id, left_id, left_node);
                if (res.matched) {
                    ctx.state.restoreMark(&mark);
                    return NoLeftMatch;
                } else {
                    return .{
                        .matched = true,
                        .consumed_left = false,
                        .node_ptr = null,
                    };
                }
            },
            .MatchPosLookahead => |m| {
                const mark = ctx.state.mark();
                const res = self.parseMatchOpWithLeftTerm(Context, ctx, m.op_id, left_id, left_node);
                if (res.matched) {
                    ctx.state.restoreMark(&mark);
                    return .{
                        .matched = true,
                        .consumed_left = false,
                        .node_ptr = null,
                    };
                } else {
                    return NoLeftMatch;
                }
            },
            .MatchRule => |inner| {
                // log.warn("MatchRule", .{});
                if (inner.rule_id == left_id) {
                    return .{
                        .matched = true,
                        .consumed_left = true,
                        .node_ptr = left_node,
                    };
                } else {
                    const res = self.parseRuleWithLeftTerm(Context, ctx, inner.rule_id, left_id, left_node, true);
                    if (res.matched) {
                        return res;
                    }
                }
            },
            .MatchSeq => |inner| {
                const mark = ctx.state.mark();

                var last_match: ?NodePtr = null;
                var i = inner.ops.start;
                while (i < inner.ops.end) : (i += 1) {
                    const res = self.parseMatchOpWithLeftTerm(Context, ctx, i, left_id, left_node);
                    if (res.matched) {
                        if (res.node_ptr != null) {
                            last_match = res.node_ptr;
                        }
                        if (res.consumed_left) {
                            i += 1;
                            break;
                        }
                    } else {
                        ctx.state.restoreMark(&mark);
                        return NoLeftMatch;
                    }
                }

                while (i < inner.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (res.matched) {
                        if (res.node_ptr != null) {
                            last_match = res.node_ptr;
                        }
                    } else {
                        ctx.state.restoreMark(&mark);
                        return NoLeftMatch;
                    }
                }

                return .{
                    .matched = true,
                    .consumed_left = true,
                    .node_ptr = last_match,
                };
            },
            .MatchOneOrMore => |m| {
                return self.parseMatchManyWithLeftTerm(Context, ctx, true, m.op_id, left_id, left_node);
            },
            .MatchChoice => |inner| {
                // log.warn("MatchChoice", .{});
                var i = inner.ops.start;
                while (i < inner.ops.end) : (i += 1) {
                    const res = self.parseMatchOpWithLeftTerm(Context, ctx, i, left_id, left_node);
                    if (res.matched) {
                        return res;
                    }
                }
            },
            .MatchToken, .MatchLiteral => {
                return NoLeftMatch;
            },
            else => stdx.panicFmt("unsupported: {s}", .{@tagName(op)}),
        }
        return NoLeftMatch;
    }

    // Assume each op will leave the parser pos in the right place on match or no match.
    fn parseMatchOp(self: *Self, comptime Context: type, ctx: *Context, id: MatchOpId) ParseNodeResult {
        if (Context.debug) {
            ctx.debug.stats.parse_match_ops += 1;
        }

        const op = self.ops[id];
        switch (op) {
            .MatchToken => |inner| {
                // log.warn("MatchToken {s}", .{self.grammar.getTokenName(inner.tag)});
                if (ctx.state.nextAtEnd()) {
                    return NoMatch;
                }
                const next = ctx.state.peekNext();
                if (inner.tag == next.tag) {
                    const token_ctx = ctx.state.getTokenContext();
                    defer _ = ctx.state.consumeNext(Context.useCacheMap);
                    return self.createMatchedNodeTokenResult(token_ctx, ctx.state.getAssertNextTokenId(), inner.capture);
                }
            },
            .MatchLiteral => |m| {
                // Fast comparison with precomputed literal tags.
                if (ctx.state.nextAtEnd()) {
                    return NoMatch;
                }
                const next = ctx.state.peekNext();
                if (m.computed_literal_tag == next.literal_tag) {
                    const token_ctx = ctx.state.getTokenContext();
                    defer _ = ctx.state.consumeNext(Context.useCacheMap);
                    return self.createMatchedNodeTokenResult(token_ctx, ctx.state.getAssertNextTokenId(), m.capture);
                }
            },
            .MatchTokenText => |inner| {
                // log.warn("MatchTokenText '{s}'", .{inner.str});
                if (ctx.state.nextAtEnd()) {
                    return NoMatch;
                }
                const next = ctx.state.peekNext();
                if (inner.tag == next.tag) {
                    const token_ctx = ctx.state.getTokenContext();
                    const str = ctx.state.getTokenString(token_ctx, next);
                    const inner_str = self.grammar.getString(inner.str);
                    if (stdx.string.eq(inner_str, str)) {
                        defer _ = ctx.state.consumeNext(Context.useCacheMap);
                        return self.createMatchedNodeTokenResult(token_ctx, ctx.state.getAssertNextTokenId(), inner.capture);
                    }
                }
            },
            .MatchZeroOrMore => |inner| {
                return self.parseMatchMany(Context, ctx, false, inner.op_id);
            },
            .MatchOneOrMore => |inner| {
                return self.parseMatchMany(Context, ctx, true, inner.op_id);
            },
            .MatchRule => |inner| {
                if (DebugParseRule) {
                    if (ctx.state.next_tok_id != null) {
                        const str = ctx.ast.getTokenString(ctx.state.next_tok_id.?);
                        log.warn("parseRule {s} {} '{s}'", .{ self.grammar.getRuleName(inner.rule_id), ctx.state.next_tok_id, str });
                    }
                }
                const res = self.parseRule(Context, ctx, inner.rule_id);
                if (res.matched) {
                    if (DebugParseRule) {
                        if (ctx.state.next_tok_id != null) {
                            const str = ctx.ast.getTokenString(ctx.state.next_tok_id.?);
                            log.warn("MATCHED {s} {} '{s}'", .{ self.grammar.getRuleName(inner.rule_id), ctx.state.next_tok_id, str });
                        }
                    }
                    return res;
                }
            },
            .MatchOptional => |m| {
                // log.warn("MatchOptional", .{});
                const res = self.parseMatchOp(Context, ctx, m.op_id);
                if (res.matched) {
                    return res;
                } else {
                    // Report to parent that we still matched.
                    return .{
                        .matched = true,
                        .node_ptr = null,
                    };
                }
            },
            .MatchNegLookahead => |m| {
                // Returns no match if inner op matches and resets position.
                // Returns match if inner op doesn't match but does not advance the position.
                const mark = ctx.state.mark();
                const res = self.parseMatchOp(Context, ctx, m.op_id);
                if (res.matched) {
                    ctx.state.restoreMark(&mark);
                    return NoMatch;
                } else {
                    return .{
                        .matched = true,
                        .node_ptr = null,
                    };
                }
            },
            .MatchPosLookahead => |m| {
                // Returns match if inner op matches but does not advance the position.
                // Returns no match if inner op doesn't match.
                const mark = ctx.state.mark();
                const res = self.parseMatchOp(Context, ctx, m.op_id);
                if (res.matched) {
                    ctx.state.restoreMark(&mark);
                    return .{
                        .matched = true,
                        .node_ptr = null,
                    };
                } else {
                    return NoMatch;
                }
            },
            .MatchSeq => |inner| {
                // log.warn("MatchSeq", .{});
                const mark = ctx.state.mark();

                var last_match: ?NodePtr = null;
                var i = inner.ops.start;
                while (i < inner.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (res.matched) {
                        if (res.node_ptr != null) {
                            last_match = res.node_ptr;
                        }
                    } else {
                        ctx.state.restoreMark(&mark);
                        return NoMatch;
                    }
                }
                return .{
                    .matched = true,
                    .node_ptr = last_match,
                };
            },
            .MatchChoice => |inner| {
                // log.warn("MatchChoice", .{});
                var i = inner.ops.start;
                while (i < inner.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (res.matched) {
                        return res;
                    }
                }
            },
        }
        return NoMatch;
    }

    fn setNodeField(self: *Self, _: RuleId, list_start: u32, idx: *u32, op_id: MatchOpId, node_ptr: ?NodePtr) void {
        const op = &self.ops[op_id];
        if (self.grammar.shouldCaptureRule(op)) {
            if (node_ptr != null) {
                // Save child field.
                self.node_list_stack.items[list_start + idx.*] = node_ptr.?;
            } else {
                // Save null field.
                self.node_list_stack.items[list_start + idx.*] = .{
                    .id = 0,
                    .tag = self.grammar.null_node_tag,
                };
            }
            idx.* += 1;
        }
    }

    fn parseRuleWithLeftTerm(self: *Self, comptime Context: type, ctx: *Context, id: RuleId, left_id: RuleId, left_node: NodePtr, check_recursion: bool) ParseNodeWithLeftResult {

        // log.warn("parseRuleWithLeftTerm {s} {}", .{self.grammar.getRuleName(id), ctx.state.next_tok_id});
        if (Context.debug) {
            const frame = CallFrame{
                .parse_rule_id = id,
                .next_token_id = ctx.state.next_tok_id,
            };
            ctx.debug.call_stack.append(frame) catch unreachable;
            if (self.rule_stack_start + self.decls.len == self.is_parsing_rule_stack.buf.items.len) {
                // Copy the current call stack if this is furthest token idx reached.
                ctx.debug.max_call_stack.resize(ctx.debug.call_stack.items.len) catch unreachable;
                std.mem.copy(CallFrame, ctx.debug.max_call_stack.items, ctx.debug.call_stack.items);
            }
        }
        defer if (Context.debug) {
            _ = ctx.debug.call_stack.pop();
        };

        const stack_pos = self.rule_stack_start + id;
        if (check_recursion) {
            if (self.is_parsing_rule_stack.isSet(stack_pos)) {
                return NoLeftMatch;
            }
            self.is_parsing_rule_stack.set(stack_pos);
        }
        defer {
            if (check_recursion) {
                self.is_parsing_rule_stack.unset(stack_pos);
            }
        }

        const decl = self.decls[id];

        const mark = ctx.state.mark();
        inner: {
            if (decl.is_inline) {
                // Super decl will just return it's child and won't create a new node.
                // TODO: What to do with multiple children? Currently we just return that last matched child node.
                var last: ?NodePtr = null;
                var i: u32 = decl.ops.start;
                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOpWithLeftTerm(Context, ctx, i, left_id, left_node);
                    if (!res.matched) {
                        break :inner;
                    } else {
                        if (res.node_ptr != null) {
                            last = res.node_ptr.?;
                        }
                        if (res.consumed_left) {
                            i += 1;
                            break;
                        }
                    }
                }

                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (!res.matched) {
                        break :inner;
                    } else {
                        if (res.node_ptr != null) {
                            last = res.node_ptr.?;
                        }
                    }
                }
                return .{
                    .matched = true,
                    .consumed_left = true,
                    .node_ptr = last,
                };
            } else {
                const list_start = @intCast(u32, self.node_list_stack.items.len);
                defer self.node_list_stack.shrinkRetainingCapacity(list_start);

                const num_fields = self.grammar.getNumChildFields(id);
                self.node_list_stack.resize(list_start + num_fields) catch unreachable;

                // Keep matching with given left node until an op consumed it.
                // Some ops can match but not consume it. eg. MatchOptional
                var cur_field: u32 = 0;
                var i = decl.ops.start;
                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOpWithLeftTerm(Context, ctx, i, left_id, left_node);
                    if (!res.matched) {
                        break :inner;
                    } else {
                        self.setNodeField(id, list_start, &cur_field, i, res.node_ptr);
                        if (res.consumed_left) {
                            i += 1;
                            break;
                        }
                    }
                }

                // Parse the rest of the ops normally.
                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (!res.matched) {
                        break :inner;
                    } else {
                        self.setNodeField(id, list_start, &cur_field, i, res.node_ptr);
                    }
                }

                if (num_fields > 0) {
                    const list_id = @intCast(u32, self.buf.node_slices.items.len);
                    const start = @intCast(u32, self.buf.node_ptrs.items.len);
                    self.buf.node_slices.append(.{
                        .start = start,
                        .end = start + num_fields,
                    }) catch unreachable;
                    self.buf.node_ptrs.appendSlice(self.node_list_stack.items[list_start..]) catch unreachable;
                    return .{ .matched = true, .consumed_left = true, .node_ptr = NodePtr{
                        .id = list_id,
                        .tag = id,
                    } };
                } else {
                    return .{ .matched = true, .consumed_left = true, .node_ptr = NodePtr{
                        .id = self.getNextScalarNodeId(),
                        .tag = id,
                    } };
                }
            }
        }
        // Failed to match. Revert to start state.
        ctx.state.restoreMark(&mark);
        return NoLeftMatch;
    }

    fn parseRuleDefault(self: *Self, comptime Context: type, ctx: *Context, id: RuleId) ParseNodeResult {
        // log.warn("parsing rule {s}", .{self.grammar.getRuleName(id)});
        const decl = self.decls[id];

        const mark = ctx.state.mark();
        inner: {
            if (decl.is_inline) {
                // Super decl will just return it's child and won't create a new node.
                // TODO: What to do with multiple children? Currently we just return that last matched child node.
                var last: ?NodePtr = null;
                var i: u32 = decl.ops.start;
                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (!res.matched) {
                        break :inner;
                    } else {
                        if (res.node_ptr != null) {
                            last = res.node_ptr.?;
                        }
                    }
                }
                return .{
                    .matched = true,
                    .node_ptr = last,
                };
            } else {
                const list_start = @intCast(u32, self.node_list_stack.items.len);
                defer self.node_list_stack.shrinkRetainingCapacity(list_start);

                const num_fields = self.grammar.getNumChildFields(id);
                self.node_list_stack.resize(list_start + num_fields) catch unreachable;

                var cur_field: u32 = 0;
                var i = decl.ops.start;
                while (i < decl.ops.end) : (i += 1) {
                    const res = self.parseMatchOp(Context, ctx, i);
                    if (!res.matched) {
                        // log.warn("failed at idx {}", .{i - decl.ops.start});
                        break :inner;
                    } else {
                        self.setNodeField(id, list_start, &cur_field, i, res.node_ptr);
                    }
                }

                if (num_fields > 0) {
                    const list_id = @intCast(u32, self.buf.node_slices.items.len);
                    const start = @intCast(u32, self.buf.node_ptrs.items.len);
                    self.buf.node_slices.append(.{
                        .start = start,
                        .end = start + num_fields,
                    }) catch unreachable;
                    self.buf.node_ptrs.appendSlice(self.node_list_stack.items[list_start..]) catch unreachable;
                    return .{ .matched = true, .node_ptr = NodePtr{
                        .id = list_id,
                        .tag = id,
                    } };
                } else {
                    return .{
                        .matched = true,
                        .node_ptr = NodePtr{
                            .id = self.getNextScalarNodeId(),
                            .tag = id,
                        },
                    };
                }
            }
        }
        // Failed to match. Revert to start state.
        ctx.state.restoreMark(&mark);
        return NoMatch;
    }

    fn getNextScalarNodeId(self: *Self) NodeId {
        defer self.next_scalar_node_id += 1;
        return self.next_scalar_node_id;
    }

    fn getCachedParseRule(self: *Self, comptime UseCacheMap: bool, key: u32) ?CacheItem {
        if (UseCacheMap) {
            return self.parse_rule_cache_map.get(key);
        } else {
            const res = self.parse_rule_cache_stack.items[key];
            return if (res.state != .Empty) res else null;
        }
    }

    fn setCachedParseRule(self: *Self, comptime UseCacheMap: bool, key: u32, res: CacheItem) void {
        if (UseCacheMap) {
            // log.warn("set cached {}", .{res});
            self.parse_rule_cache_map.put(key, res) catch unreachable;
        } else {
            self.parse_rule_cache_stack.items[key] = res;
        }
    }

    fn parseRule(self: *Self, comptime Context: type, ctx: *Context, id: RuleId) ParseNodeResult {
        if (Context.debug) {
            const frame = CallFrame{
                .parse_rule_id = id,
                .next_token_id = ctx.state.next_tok_id,
            };
            ctx.debug.call_stack.append(frame) catch unreachable;
            if (self.rule_stack_start + self.decls.len == self.is_parsing_rule_stack.buf.items.len) {
                // Copy the current call stack if this is furthest token idx reached.
                ctx.debug.max_call_stack.resize(ctx.debug.call_stack.items.len) catch unreachable;
                std.mem.copy(CallFrame, ctx.debug.max_call_stack.items, ctx.debug.call_stack.items);
            }
        }
        defer if (Context.debug) {
            _ = ctx.debug.call_stack.pop();
        };

        const stack_pos = self.rule_stack_start + id;
        if (self.is_parsing_rule_stack.isSet(stack_pos)) {
            // If we're parsing the same rule and haven't advanced return NoMatch.
            return NoMatch;
        }
        self.is_parsing_rule_stack.set(stack_pos);
        defer self.is_parsing_rule_stack.unset(stack_pos);

        var final_res: ParseNodeResult = undefined;

        // Check cache.
        // log.warn("{} {}", .{stack_pos, self.parse_rule_cache_stack.items.len});
        const mb_cache_res = self.getCachedParseRule(Context.useCacheMap, stack_pos);
        if (mb_cache_res) |cache_res| {
            const cache_state = cache_res.state;
            if (cache_state == .Match) {
                if (Context.State == TokenState) {
                    const mark = TokenState.Mark{
                        .next_tok_id = cache_res.next_token_id,
                        .rule_stack_start = cache_res.rule_stack_start,
                    };
                    ctx.state.restoreMark(&mark);
                } else if (Context.State == LineTokenState) {
                    const mark = LineTokenState.Mark{
                        .rule_stack_start = cache_res.rule_stack_start,
                        .next_tok_id = cache_res.next_token_id,
                        .leaf_id = cache_res.next_token_ctx.leaf_id,
                        .chunk_line_idx = cache_res.next_token_ctx.chunk_line_idx,
                    };
                    ctx.state.restoreMark(&mark);
                } else unreachable;

                // Restoring mark either advances the token pointer or stays the same place.
                if (stack_pos - id < self.rule_stack_start) {
                    // Reset any existing stack frame if we advanced.
                    const new_size = self.rule_stack_start + self.decls.len;
                    self.is_parsing_rule_stack.unsetRange(self.rule_stack_start, new_size);
                }

                return .{
                    .matched = true,
                    .node_ptr = cache_res.node_ptr,
                };
            } else {
                return NoMatch;
            }
        }
        defer if (mb_cache_res == null) {
            if (final_res.matched) {
                if (Context.State == TokenState) {
                    self.setCachedParseRule(Context.useCacheMap, stack_pos, .{
                        .state = .Match,
                        .node_ptr = final_res.node_ptr,
                        .next_token_id = ctx.state.next_tok_id,
                        .rule_stack_start = self.rule_stack_start,
                    });
                } else if (Context.State == LineTokenState) {
                    self.setCachedParseRule(Context.useCacheMap, stack_pos, .{
                        .state = .Match,
                        .node_ptr = final_res.node_ptr,
                        .next_token_ctx = ctx.state.getTokenContext(),
                        .next_token_id = ctx.state.next_tok_id,
                        .rule_stack_start = self.rule_stack_start,
                    });
                } else unreachable;
            } else {
                self.setCachedParseRule(Context.useCacheMap, stack_pos, .{
                    .state = .NoMatch,
                });
            }
        };

        if (Context.debug) {
            ctx.debug.stats.parse_rule_ops_no_cache += 1;
        }

        const rule = self.grammar.getRule(id);
        if (rule.is_left_recursive) {
            // First parse rule normally.
            var res = self.parseRuleDefault(Context, ctx, id);

            if (res.node_ptr == null) {
                // Matched but didn't capture. Initialize as a null node_ptr and continue with left recursion.
                res.node_ptr = .{
                    .id = 0,
                    .tag = self.grammar.null_node_tag,
                };
            }

            // Continue to try left recursion until it fails.
            while (true) {
                const new_res = self.parseRuleWithLeftTerm(Context, ctx, id, id, res.node_ptr.?, false);
                if (new_res.matched) {
                    res = .{ .matched = true, .node_ptr = new_res.node_ptr };
                } else {
                    break;
                }
            }
            final_res = res;
            return final_res;
        } else {
            final_res = self.parseRuleDefault(Context, ctx, id);
            return final_res;
        }
    }

    fn resetParser(self: *Self, comptime UseHashMap: bool) void {
        self.rule_stack_start = 0;
        const size = self.rule_stack_start + self.decls.len;
        self.is_parsing_rule_stack.clearRetainingCapacity();
        self.is_parsing_rule_stack.resizeFillNew(size, false) catch unreachable;
        self.parse_rule_cache_map.clearRetainingCapacity();
        if (UseHashMap) {
            self.parse_rule_cache_stack.clearRetainingCapacity();
        } else {
            self.parse_rule_cache_stack.resize(size) catch unreachable;
            std.mem.set(CacheItem, self.parse_rule_cache_stack.items[0..size], .{});
        }

        self.next_scalar_node_id = 1;
        self.node_list_stack.clearRetainingCapacity();

        self.buf.node_ptrs.clearRetainingCapacity();
        self.buf.node_slices.clearRetainingCapacity();
        self.buf.node_tokens.clearRetainingCapacity();
    }

    pub fn parse(self: *Self, comptime Config: ParseConfig, src: Source(Config)) ParseResult(Config) {
        return self.parseMain(Config, src, {});
    }

    pub fn parseDebug(self: *Self, comptime Config: ParseConfig, src: Source(Config), debug: *DebugInfo) ParseResult(Config) {
        return self.parseMain(Config, src, debug);
    }

    fn parseInternal(self: *Self, comptime Config: ParseConfig, comptime UseCacheMap: bool, comptime Debug: bool, debug: anytype, src: Source(Config), res: *ParseResult(Config)) void {
        const State = if (Config.is_incremental) LineTokenState else TokenState;
        const Context = ParseContext(State, Tree(Config), UseCacheMap, Debug);
        var ctx: Context = undefined;
        ctx.state.init(self, src, &res.ast.tokens);
        ctx.ast = &res.ast;
        if (Debug) {
            ctx.debug = debug;
        }
        self.resetParser(Context.useCacheMap);
        res.ast.mb_root = self.parseRule(Context, &ctx, self.grammar.root_rule_id).node_ptr;
        // Check if we reached the end.
        if (ctx.state.nextAtEnd()) {
            res.success = true;
        } else {
            res.success = false;
            res.err_token_id = ctx.state.getErrorToken();
        }
    }

    fn parseMain(self: *Self, comptime Config: ParseConfig, src: Source(Config), debug: anytype) ParseResult(Config) {
        const trace = tracy.trace(@src());
        defer trace.end();

        var ast: Tree(Config) = undefined;
        ast.init(self.alloc, self, src);

        var res: ParseResult(Config) = undefined;
        res.ast = ast;

        const Debug = @TypeOf(debug) == *DebugInfo;
        if (Debug) {
            debug.reset();
        }

        self.tokenizer.tokenize(Config, src, &res.ast.tokens);
        stdx.debug.abortIfUserFlagSet();

        const useCacheMap = res.ast.getNumTokens() > CacheMapTokenThreshold;
        if (useCacheMap) {
            self.parseInternal(Config, true, Debug, debug, src, &res);
        } else {
            self.parseInternal(Config, false, Debug, debug, src, &res);
        }
        return res;
    }

    pub fn reparseChange(self: *Self, comptime Config: ParseConfig, src: Source(Config), cur_ast: *Tree(Config), line_idx: u32, col_idx: u32, change_size: i32) void {
        self.reparseChangeMain(Config, src, cur_ast, line_idx, col_idx, change_size, {});
    }

    pub fn reparseChangeDebug(self: *Self, comptime Config: ParseConfig, src: Source(Config), cur_ast: *Tree(Config), line_idx: u32, col_idx: u32, change_size: i32, debug: *DebugInfo) void {
        self.reparseChangeMain(Config, src, cur_ast, line_idx, col_idx, change_size, debug);
    }

    // col_idx is the the starting pos where the change took place.
    // positive change_size indicates it was an insert/replace.
    // negative change_size indicates it was a delete/replace.
    fn reparseChangeMain(self: *Self, comptime Config: ParseConfig, src: Source(Config), cur_ast: *Tree(Config), line_idx: u32, col_idx: u32, change_size: i32, debug: anytype) void {
        const Debug = @TypeOf(debug) == *DebugInfo;
        if (Debug) {
            debug.reset();
        }
        self.tokenizer.retokenizeChange(src, &cur_ast.tokens, line_idx, col_idx, change_size, debug);
    }

    fn createMatchedNodeTokenResult(self: *Self, token_ctx: anytype, token_id: TokenId, capture: bool) ParseNodeResult {
        if (capture) {
            const id = @intCast(u32, self.buf.node_tokens.items.len);
            if (@TypeOf(token_ctx) == LineTokenContext) {
                self.buf.node_tokens.append(.{ .token_ctx = token_ctx, .token_id = token_id }) catch unreachable;
            } else {
                self.buf.node_tokens.append(.{ .token_ctx = .{ .leaf_id = 0, .chunk_line_idx = 0 }, .token_id = token_id }) catch unreachable;
            }
            return .{
                .matched = true,
                .node_ptr = .{
                    .id = id,
                    .tag = self.grammar.token_value_tag,
                },
            };
        } else {
            return .{
                .matched = true,
                .node_ptr = null,
            };
        }
    }

    // TODO: Keeping this code in case we need to detach an ast tree from the underlying source.
    // fn createStringNodeData(self: *Self, str: []const u8) [*]u8 {
    //     _ = self;
    //     const data = self.alloc.alloc(u8, @sizeOf(u32) + str.len) catch unreachable;
    //     std.mem.copy(u8, data[0..@sizeOf(u32)], &std.mem.toBytes(@intCast(u32, str.len)));
    //     std.mem.copy(u8, data[@sizeOf(u32)..], str);
    //     return data.ptr;
    // }
    // fn createMatchedStringNodeResult(self: *Self, str: []const u8, capture: bool) ParseNodeResult {
    //     if (capture) {
    //         if (str.len == 1) {
    //             // Create a char value node instead to avoid extra allocation.
    //             return .{
    //                 .matched = true,
    //                 .node_ptr = .{
    //                     .id = self.getNextNodeId(),
    //                     .tag = self.grammar.char_value_tag,
    //                     .data = @intToPtr([*]u8, str[0]),
    //                 },
    //             };
    //         } else {
    //             return .{
    //                 .matched = true,
    //                 .node_ptr = .{
    //                     .id = self.getNextNodeId(),
    //                     .tag = self.grammar.string_value_tag,
    //                     .data = self.createStringNodeData(str),
    //                 },
    //             };
    //         }
    //     } else {
    //         return .{
    //             .matched = true,
    //             .node_ptr = null,
    //         };
    //     }
    // }
};

fn Mark(comptime Config: ParseConfig) type {
    if (Config.incremental) {
        return LineTokenState.Mark;
    } else {
        return TokenState.Mark;
    }
}

const TokenState = struct {
    const Self = @This();

    const Mark = struct {
        next_tok_id: TokenId,
        rule_stack_start: u32,
    };

    src: []const u8,
    tokens: *std.ArrayList(Token),

    next_tok_id: TokenId,
    rule_stack_start: *u32,
    is_parsing_rule_stack: *ds.BitArrayList,
    parse_rule_cache_stack: *std.ArrayList(CacheItem),
    num_decls: u32,

    fn init(
        self: *Self,
        parser: *Parser,
        src: []const u8,
        tokens: *std.ArrayList(Token),
    ) void {
        self.* = .{
            .src = src,
            .next_tok_id = 0,
            .tokens = tokens,
            .rule_stack_start = &parser.rule_stack_start,
            .is_parsing_rule_stack = &parser.is_parsing_rule_stack,
            .parse_rule_cache_stack = &parser.parse_rule_cache_stack,
            .num_decls = @intCast(u32, parser.decls.len),
        };
    }

    inline fn mark(self: *Self) Self.Mark {
        return .{
            .next_tok_id = self.next_tok_id,
            .rule_stack_start = self.rule_stack_start.*,
        };
    }

    inline fn restoreMark(self: *Self, m: *const Self.Mark) void {
        // log.warn("restoreMark {}", .{m.next_tok_id});
        self.next_tok_id = m.next_tok_id;
        self.rule_stack_start.* = m.rule_stack_start;
    }

    inline fn nextAtEnd(self: *Self) bool {
        return self.next_tok_id == self.tokens.items.len;
    }

    inline fn peekNext(self: *Self) Token {
        return self.tokens.items[self.next_tok_id];
    }

    inline fn getAssertNextTokenId(self: *Self) TokenId {
        return self.next_tok_id;
    }

    fn consumeNext(self: *Self, comptime UseCacheMap: bool) Token {
        // Push new set since we advanced the parser pos.
        self.rule_stack_start.* += self.num_decls;
        const new_size = self.rule_stack_start.* + self.num_decls;
        if (self.is_parsing_rule_stack.buf.items.len < new_size) {
            self.is_parsing_rule_stack.resize(new_size) catch unreachable;
        }
        self.is_parsing_rule_stack.unsetRange(self.rule_stack_start.*, new_size);

        if (!UseCacheMap) {
            if (self.parse_rule_cache_stack.items.len < new_size) {
                self.parse_rule_cache_stack.resize(new_size) catch unreachable;
                std.mem.set(CacheItem, self.parse_rule_cache_stack.items[self.rule_stack_start.*..new_size], .{});
            }
        }

        defer self.next_tok_id += 1;
        return self.tokens.items[self.next_tok_id];
    }

    // Since we already use a stack frame at each token increment, we can use the len to determine the token index.
    fn getErrorToken(self: *Self) TokenId {
        const token_idx = self.is_parsing_rule_stack.buf.items.len / self.num_decls - 1;
        return @intCast(u32, token_idx);
    }

    inline fn getNextTokenRef(self: *Self) ?TokenId {
        return self.next_tok_id;
    }

    inline fn getTokenContext(_: *Self) void {
        return;
    }

    inline fn getTokenString(self: *Self, _: void, token: Token) []const u8 {
        return self.src[token.loc.start..token.loc.end];
    }
};

const LineTokenState = struct {
    const Self = @This();

    const Mark = struct {
        rule_stack_start: u32,
        leaf_id: document.NodeId,
        chunk_line_idx: u32,
        next_tok_id: TokenId,
    };

    rule_stack_start: *u32,
    is_parsing_rule_stack: *ds.BitArrayList,
    parse_rule_cache_stack: *std.ArrayList(CacheItem),

    doc: *Document,
    buf: *LineTokenBuffer,

    // Current line data.
    next_tok_id: TokenId,
    leaf_id: document.NodeId,
    chunk: []document.LineId,
    chunk_line_idx: u32,

    last_leaf_id: u32,
    last_chunk_size: u32,

    num_decls: u32,

    fn init(
        self: *Self,
        parser: *Parser,
        doc: *Document,
        buf: *LineTokenBuffer,
    ) void {
        const last_leaf_id = doc.getLastLeaf();
        const last_leaf = doc.getNode(last_leaf_id);

        self.* = .{
            .doc = doc,
            .buf = buf,
            .rule_stack_start = &parser.rule_stack_start,
            .is_parsing_rule_stack = &parser.is_parsing_rule_stack,
            .parse_rule_cache_stack = &parser.parse_rule_cache_stack,
            .leaf_id = undefined,
            .chunk = undefined,
            .chunk_line_idx = undefined,
            .next_tok_id = undefined,
            .last_leaf_id = last_leaf_id,
            .last_chunk_size = last_leaf.Leaf.chunk.size,
            .num_decls = @intCast(u32, parser.decls.len),
        };
        self.seekToFirstToken();
    }

    fn getLineTokenIterator(self: *Self, loc: document.LineLocation) LineTokenIterator {
        return LineTokenIterator.init(self.doc, self.buf.lines.items, &self.buf.tokens, loc, .{
            .leaf_id = self.last_leaf_id,
            .chunk_line_idx = self.last_chunk_size - 1,
        });
    }

    fn getErrorToken(self: *Self) TokenId {
        const token_idx = self.is_parsing_rule_stack.buf.items.len / self.num_decls - 1;
        var i: u32 = 0;
        var iter = self.getLineTokenIterator(self.doc.findLineLoc(0));
        while (iter.next()) |token_id| {
            if (i == token_idx) {
                return token_id;
            } else {
                i += 1;
            }
        }
        unreachable;
    }

    inline fn mark(self: *Self) Self.Mark {
        return .{
            .rule_stack_start = self.rule_stack_start.*,
            .leaf_id = self.leaf_id,
            .chunk_line_idx = self.chunk_line_idx,
            .next_tok_id = self.next_tok_id,
        };
    }

    inline fn restoreMark(self: *Self, m: *const Self.Mark) void {
        // log.warn("restoreMark {} {} {}", .{m.leaf_id, m.chunk_line_idx, m.next_tok_id});
        self.rule_stack_start.* = m.rule_stack_start;
        self.leaf_id = m.leaf_id;
        self.next_tok_id = m.next_tok_id;
        self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
        self.chunk_line_idx = m.chunk_line_idx;
    }

    inline fn nextAtEnd(self: *Self) bool {
        return self.next_tok_id == NullToken;
    }

    inline fn peekNext(self: *Self) Token {
        return self.buf.tokens.getNoCheck(self.next_tok_id);
    }

    inline fn getAssertNextTokenId(self: *Self) TokenId {
        return if (self.next_tok_id != NullToken) self.next_tok_id else unreachable;
    }

    // Find the first next_tok_id and set line context.
    fn seekToFirstToken(self: *Self) void {
        self.leaf_id = self.doc.getFirstLeaf();
        self.chunk_line_idx = 0;

        while (true) {
            if (self.leaf_id == self.last_leaf_id and self.chunk_line_idx == self.last_chunk_size) {
                self.next_tok_id = NullToken;
                return;
            }

            self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
            const line_id = self.chunk[self.chunk_line_idx];

            if (self.buf.lines.items[line_id]) |list_id| {
                self.next_tok_id = self.buf.tokens.getListHead(list_id).?;
                return;
            }

            self.chunk_line_idx += 1;
            if (self.chunk_line_idx == self.chunk.len) {
                // Advance to next chunk.
                self.leaf_id = self.doc.getNextLeafNode(self.leaf_id).?;
                self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
                self.chunk_line_idx = 0;
            }
        }
    }

    // Called by consumeNext, so it assumes there is a next token.
    fn seekToNextToken(self: *Self) void {
        self.next_tok_id = self.buf.tokens.getNextIdNoCheck(self.next_tok_id);
        if (self.next_tok_id != NullToken) {
            // It's the next node in the list.
            return;
        }
        // Find the next list head by iterating line chunks.
        while (true) {
            self.chunk_line_idx += 1;
            if (self.leaf_id == self.last_leaf_id and self.chunk_line_idx == self.last_chunk_size) {
                self.next_tok_id = NullToken;
                return;
            }
            if (self.chunk_line_idx == self.chunk.len) {
                stdx.debug.abort();
                // Advance to next chunk.
                self.leaf_id = self.doc.getNextLeafNode(self.leaf_id).?;
                self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
                self.chunk_line_idx = 0;
            }
            const line_id = self.chunk[self.chunk_line_idx];
            if (self.buf.lines.items[line_id]) |list_id| {
                if (self.buf.tokens.getListHead(list_id)) |head| {
                    self.next_tok_id = head;
                    return;
                }
            }
        }
    }

    // Assumes there is a next token. Shouldn't be called without checking nextAtEnd first.
    fn consumeNext(self: *Self, comptime UseCacheMap: bool) Token {
        // log.warn("parser consume next {}", .{self.next_tok_id});
        const item = self.buf.tokens.getNodePtrAssumeExists(self.next_tok_id);
        self.seekToNextToken();

        // Push new set since we advanced the parser pos.
        self.rule_stack_start.* += self.num_decls;
        const new_size = self.rule_stack_start.* + self.num_decls;
        if (self.is_parsing_rule_stack.buf.items.len < new_size) {
            self.is_parsing_rule_stack.resize(new_size) catch unreachable;
        }
        self.is_parsing_rule_stack.unsetRange(self.rule_stack_start.*, new_size);

        if (!UseCacheMap) {
            if (self.parse_rule_cache_stack.items.len < new_size) {
                self.parse_rule_cache_stack.resize(new_size) catch unreachable;
                std.mem.set(CacheItem, self.parse_rule_cache_stack.items[self.rule_stack_start.*..new_size], .{});
            }
        }

        return item.data;
    }

    inline fn getTokenContext(self: *Self) LineTokenContext {
        return .{
            .leaf_id = self.leaf_id,
            .chunk_line_idx = self.chunk_line_idx,
        };
    }

    inline fn getTokenString(self: *Self, ctx: LineTokenContext, token: Token) []const u8 {
        return self.doc.getSubstringFromLineLoc(ctx, token.loc.start, token.loc.end);
    }
};

const LineTokenContext = document.LineLocation;

pub fn Source(comptime Config: ParseConfig) type {
    if (Config.is_incremental) {
        return *Document;
    } else {
        return []const u8;
    }
}

const ParseNodeWithLeftResult = struct {
    matched: bool,
    consumed_left: bool,
    node_ptr: ?NodePtr,
};
const ParseNodeResult = struct {
    // TODO: accpet 3 values NoMatch/MatchAdvance/MatchNoAdvance like tokenizer
    matched: bool,

    // TODO: After making null_tag a predefined, remove optional to simplify.
    //       Whether node_ptr is defined depends on matched.
    node_ptr: ?NodePtr,
};
const NoLeftMatch = ParseNodeWithLeftResult{ .matched = false, .consumed_left = false, .node_ptr = null };
const NoMatch = ParseNodeResult{ .matched = false, .node_ptr = null };

pub const DebugInfo = struct {
    const Self = @This();

    stats: struct {
        inc_tokens_added: u32,
        inc_tokens_removed: u32,

        // Evaluated match ops, includes parseRules made a cache hit.
        parse_match_ops: u32,

        // Evaluated parse rules that didn't return early from a cache hit.
        parse_rule_ops_no_cache: u32,
    },

    call_stack: std.ArrayList(CallFrame),

    // If parsing failed, this is the call stack we want.
    max_call_stack: std.ArrayList(CallFrame),

    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .stats = undefined,
            .call_stack = std.ArrayList(CallFrame).init(alloc),
            .max_call_stack = std.ArrayList(CallFrame).init(alloc),
        };
        self.reset();
    }

    pub fn deinit(self: *Self) void {
        self.call_stack.deinit();
        self.max_call_stack.deinit();
    }

    pub fn reset(self: *Self) void {
        self.stats = .{
            .inc_tokens_added = 0,
            .inc_tokens_removed = 0,
            .parse_match_ops = 0,
            .parse_rule_ops_no_cache = 0,
        };
        self.call_stack.clearRetainingCapacity();
        self.max_call_stack.clearRetainingCapacity();
    }

    pub fn formatMaxCallStack(self: *Self, comptime Config: ParseConfig, ast: *const Tree(Config), writer: anytype) void {
        const first = self.max_call_stack.items[0];
        writer.print("{s}({}'{s}')", .{ ast.grammar.getRuleName(first.parse_rule_id), first.next_token_id, ast.getTokenString(first.next_token_id.?) }) catch unreachable;
        for (self.max_call_stack.items[1..]) |frame| {
            writer.print(" -> {s}({}'{s}')", .{ ast.grammar.getRuleName(frame.parse_rule_id), frame.next_token_id, ast.getTokenString(frame.next_token_id.?) }) catch unreachable;
        }
        writer.print("\n", .{}) catch unreachable;
    }
};

const CallFrame = struct {
    parse_rule_id: RuleId,
    next_token_id: ?TokenId,
};

fn ParseContext(comptime State: type, comptime Ast: type, comptime UseCacheMap: bool, comptime Debug: bool) type {
    return struct {
        const State = State;
        const debug = Debug;
        const useCacheMap = UseCacheMap;

        state: State,
        ast: *Ast,
        debug: if (Debug) *DebugInfo else void,
    };
}

pub const ParseConfig = struct {
    is_incremental: bool = true,
};

// Contains parse rule result at some parser position.
const CacheItem = struct {
    const State = enum {
        Empty,
        NoMatch,
        Match,
    };

    state: State = .Empty,

    // Only defined when state == .Matched
    node_ptr: ?NodePtr = undefined,
    next_token_ctx: LineTokenContext = undefined,
    next_token_id: TokenId = undefined,
    rule_stack_start: u32 = undefined,
};

pub const NodeTokenPtr = struct {
    // Used only for incremental parser to locate a line relative token.
    // TODO: When incremental ast reparsing is implemented, this will probably go away.
    token_ctx: LineTokenContext,

    token_id: TokenId,
};

// Points to data which can be a list of other NodePtrs or a NodeTokenPtr.
pub const NodePtr = struct {
    id: NodeId,
    tag: NodeTag,
};

// Index into a buffer.
pub const NodeId = u32;

// Index to RuleDecl and special node types.
pub const NodeTag = u32;

pub const NodeSlice = ds.IndexSlice(u32);

pub fn ParseResult(comptime Config: ParseConfig) type {
    return struct {
        success: bool,
        err_token_id: TokenId,
        ast: Tree(Config),

        pub fn deinit(self: *@This()) void {
            self.ast.deinit();
        }
    };
}

pub fn TokenRef(comptime Config: ParseConfig) type {
    if (Config.is_incremental) {
        return struct {
            line_ctx: LineTokenContext,
            token_id: TokenId,
        };
    } else return TokenId;
}

const LineTokenIterator = struct {
    const Self = @This();

    cur_loc: document.LineLocation,
    cur_chunk_line_end_idx: u32,
    next_token_id: TokenId,
    end_loc: document.LineLocation,
    token_lists: []const ?TokenListId,
    tokens: *ds.CompactManySinglyLinkedList(TokenListId, TokenId, Token),
    doc: *Document,

    fn init(doc: *Document, token_lists: []const ?TokenListId, tokens: *ds.CompactManySinglyLinkedList(TokenListId, TokenId, Token), loc: document.LineLocation, end_loc: document.LineLocation) Self {
        var res = Self{
            .doc = doc,
            .tokens = tokens,
            .cur_loc = loc,
            .cur_chunk_line_end_idx = @intCast(u32, doc.getLeafLineChunkSlice(loc.leaf_id).len) - 1,
            .next_token_id = NullToken,
            .end_loc = end_loc,
            .token_lists = token_lists,
        };
        res.seekToNextLineHead();
        return res;
    }

    fn seekToNextLineHead(self: *Self) void {
        while (true) {
            if (std.meta.eql(self.cur_loc, self.end_loc)) {
                self.next_token_id = NullToken;
                return;
            }
            const line_id = self.doc.getLineIdByLoc(self.cur_loc);
            if (self.token_lists[line_id]) |list_id| {
                self.next_token_id = self.tokens.getListHead(list_id).?;
                return;
            } else {
                self.cur_loc.leaf_id = self.doc.getNextLeafNode(self.cur_loc.leaf_id).?;
                self.cur_loc.chunk_line_idx = 0;
                self.cur_chunk_line_end_idx = @intCast(u32, self.doc.getLeafLineChunkSlice(self.cur_loc.leaf_id).len) - 1;
            }
        }
    }

    fn next(self: *Self) ?TokenId {
        if (self.next_token_id == NullToken) {
            return null;
        } else {
            defer {
                self.next_token_id = self.tokens.getNextIdNoCheck(self.next_token_id);
                if (self.next_token_id == NullToken) {
                    if (self.cur_loc.chunk_line_idx == self.cur_chunk_line_end_idx) {
                        if (!std.meta.eql(self.cur_loc, self.end_loc)) {
                            self.cur_loc.leaf_id = self.doc.getNextLeafNode(self.cur_loc.leaf_id).?;
                            self.cur_loc.chunk_line_idx = 0;
                            self.cur_chunk_line_end_idx = @intCast(u32, self.doc.getLeafLineChunkSlice(self.cur_loc.leaf_id).len) - 1;
                            self.seekToNextLineHead();
                        }
                    } else {
                        self.cur_loc.chunk_line_idx += 1;
                    }
                }
            }
            return self.next_token_id;
        }
    }
};
