const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const log = stdx.log.scoped(.tokenizer);

const trace = stdx.debug.tracy.trace;
const document = @import("common").document;
const Document = document.Document;
const LineChunk = document.LineChunk;
const LineChunkId = document.LineChunkId;

const ast = @import("ast.zig");
const LineTokenBuffer = ast.LineTokenBuffer;
const TokenListId = ast.TokenListId;
const TokenId = ast.TokenId;
const Token = ast.Token;
const TokenBuffer = ast.TokenBuffer;
const parser = @import("parser.zig");
const DebugInfo = parser.DebugInfo;
const ParseConfig = parser.ParseConfig;
const Source = parser.Source;
const grammar = @import("grammar.zig");
const CharSetRange = grammar.CharSetRange;
const TokenDecl = grammar.TokenDecl;
const TokenMatchOp = grammar.TokenMatchOp;
const TokenTag = grammar.TokenTag;
const LiteralTokenTag = grammar.LiteralTokenTag;
const NullLiteralTokenTag = grammar.NullLiteralTokenTag;
const NullToken = stdx.ds.CompactNull(TokenId);

pub const Tokenizer = struct {
    const Self = @This();

    decls: []const TokenDecl,
    main_decls: []const TokenDecl,

    ops: []const TokenMatchOp,
    literal_tag_map: stdx.ds.OwnedKeyStringHashMap(LiteralTokenTag),
    charset_ranges: []const CharSetRange,
    str_buf: []const u8,

    pub fn init(g: *const grammar.Grammar) Self {
        return .{
            .decls = g.token_decls.items,
            .main_decls = g.token_main_decls.items,
            .ops = g.token_ops.items,
            .literal_tag_map = g.literal_tag_map,
            .charset_ranges = g.charset_range_buf.items,
            .str_buf = g.str_buf.items,
        };
    }

    pub fn tokenize(self: *Self, comptime Config: ParseConfig, src: Source(Config), buf: *TokenBuffer(Config)) void {
        const t = trace(@src());
        defer t.end();

        const State = if (Config.is_incremental) LineSourceState(false) else StringBufferState;

        const Context = TokenizeContext(State, false);
        const TConfig: TokenizeConfig = .{
            .Context = Context,
            .debug = false,
        };

        var ctx: Context = undefined;
        ctx.state.init(src, buf);
        defer ctx.state.deinit();

        self.tokenizeMain(TConfig, &ctx);
    }

    // col_idx is the start of the change.
    pub fn retokenizeChange(self: *Self, doc: *Document, buf: *LineTokenBuffer, line_idx: u32, col_idx: u32, change_size: i32, debug: anytype) void {
        const t = trace(@src());
        defer t.end();

        const Debug = @TypeOf(debug) == *DebugInfo;
        const Context = TokenizeContext(LineSourceState(true), Debug);
        const TConfig: TokenizeConfig = .{
            .Context = Context,
            .debug = Debug,
        };

        var ctx: Context = undefined;
        ctx.state.initAtTokenBeforePosition(doc, buf, line_idx, col_idx, change_size);
        if (Debug) {
            ctx.debug = debug;
        }
        defer ctx.state.deinit();

        // log.warn("starting at: \"{s}\":{}", .{ctx.state.line, ctx.state.next_ch_idx});
        // log.warn("stopping at: {}", .{ctx.state.stop_ch_idx});

        self.tokenizeMain(TConfig, &ctx);
    }

    fn tokenizeMain(self: *Self, comptime Config: TokenizeConfig, ctx: *Config.Context) void {
        while (true) {
            if (ctx.state.nextAtEnd()) {
                break;
            }

            // log.warn("{}", .{ctx.state.next_ch_idx});
            if (Config.Context.State == LineSourceState(true)) {
                if (ctx.state.next_ch_idx == ctx.state.stop_ch_idx) {
                    // Stop early for incremental tokenize.
                    ctx.state.reconcileCurrentTokenList(Config.debug, ctx.debug, ctx.state.stop_token_id);
                    break;
                }
            }

            const start = ctx.state.mark();
            inner: {
                for (self.main_decls) |it| {
                    // Since token decls can have nested ops but returns only one token,
                    // advanceWithOp only advances next_ch_idx. We create the token afterwards.
                    const op = &self.ops[it.op_id];
                    if (self.advanceWithOp(&ctx.state, op) == MatchAdvance) {
                        if (it.skip) {
                            // Stop matching and advance.
                            break :inner;
                        }

                        // Attempt to replace this rule match with a different rule.
                        if (it.replace_with != null and self.replace(Config, ctx, start, ctx.state.mark(), it.replace_with.?)) {
                            break :inner;
                        }

                        const next = ctx.state.mark();

                        const literal_tag = if (it.is_literal) b: {
                            const str = ctx.state.getString(start, next);
                            break :b self.literal_tag_map.get(str).?;
                        } else NullLiteralTokenTag;

                        switch (Config.Context.State) {
                            StringBufferState => {
                                const tok = Token.init(@intCast(u32, it.tag), literal_tag, start, next);
                                ctx.state.appendToken(Config.debug, ctx.debug, tok);
                            },
                            LineSourceState(false),
                            LineSourceState(true),
                            => {
                                const end_idx = ctx.state.getTokenEndIdxFromStartLine(start, next);
                                const tok = Token.init(@intCast(u32, it.tag), literal_tag, start.next_ch_idx, end_idx);
                                ctx.state.appendToken(Config.debug, ctx.debug, tok);
                            },
                            else => unreachable,
                        }
                        break :inner;
                    } else {
                        continue;
                    }
                }
                // No token was matched, advance so we can still progress.
                _ = ctx.state.consumeNext();
            }
        }
    }

    // Returns whether it was replaced.
    fn replace(self: *Self, comptime Config: TokenizeConfig, ctx: *Config.Context, start: Config.Context.State.Mark, end: Config.Context.State.Mark, replace_rule_tag: TokenTag) bool {
        const replace_rule = self.decls[replace_rule_tag];
        if (replace_rule.is_literal) {
            const str = ctx.state.getString(start, end);

            // If we are replacing with a literal rule then we can just check if it exists in the literal map.
            const literal_tag = self.literal_tag_map.map.get(str);
            if (literal_tag == null) {
                return false;
            }

            switch (Config.Context.State) {
                StringBufferState => {
                    const tok = Token.init(replace_rule_tag, literal_tag.?, start, end);
                    ctx.state.appendToken(Config.debug, ctx.debug, tok);
                },
                LineSourceState(false), LineSourceState(true) => {
                    const end_idx = ctx.state.getTokenEndIdxFromStartLine(start, end);
                    const tok = Token.init(replace_rule_tag, literal_tag.?, start.next_ch_idx, end_idx);
                    ctx.state.appendToken(Config.debug, ctx.debug, tok);
                },
                else => unreachable,
            }
            return true;
        }

        stdx.panic("TODO: support replace for non literal rules");

        // // Save state first.
        // const save_next = self.next_ch_idx;
        // const save_end = self.end_idx;
        // defer {
        //     self.next_ch_idx = save_next;
        //     self.end_idx = save_end;
        // }

        // self.next_ch_idx = start;
        // self.end_idx = end;

        // const op = &self.ops[replace_rule.op_id];
        // if (!self.advanceWithOp(op)) {
        //     return false;
        // }

        // // Must match the entire text to replace it.
        // if (!self.nextAtEnd()) {
        //     return false;
        // }

        // const tok = Token.init(replace_rule_tag, NullLiteralTokenTag, self.src[start..end], start, end);
        // last_token_id.* = self.tokens.insertAfter(last_token_id.*, tok) catch unreachable;
        // return true;
    }

    // Advances the current tokenizer position and returns whether the op matched.
    fn advanceWithOp(self: *Self, state: anytype, op: *const TokenMatchOp) MatchOpResult {
        switch (op.*) {
            .MatchRule => |inner| {
                const decl = self.decls[inner.tag];
                const _op = &self.ops[decl.op_id];
                return self.advanceWithOp(state, _op);
            },
            .MatchCharSet => |inner| {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                var i: u32 = inner.ranges.start;
                while (i < inner.ranges.end) : (i += 1) {
                    const range = self.charset_ranges[i];
                    if (ch >= range.start and ch <= range.end_incl) {
                        _ = state.consumeNext();
                        return MatchAdvance;
                    }
                }
                if (stdx.string.indexOf(inner.resolved_charset, ch) != null) {
                    _ = state.consumeNext();
                    return MatchAdvance;
                } else {
                    return NoMatch;
                }
            },
            .MatchNotCharSet => |inner| {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                var i: u32 = inner.ranges.start;
                while (i < inner.ranges.end) : (i += 1) {
                    const range = self.charset_ranges[i];
                    if (ch >= range.start and ch <= range.end_incl) {
                        return NoMatch;
                    }
                }
                if (stdx.string.indexOf(inner.resolved_charset, ch) == null) {
                    _ = state.consumeNext();
                    return MatchAdvance;
                } else {
                    return NoMatch;
                }
            },
            .MatchText => |inner| {
                const mark = state.mark();
                var i = inner.str.start;
                while (i < inner.str.end) : (i += 1) {
                    const exp_ch = self.str_buf[i];
                    if (state.nextAtEnd()) {
                        state.gotoMark(mark);
                        return NoMatch;
                    }
                    var ch = state.consumeNext();
                    if (ch != exp_ch) {
                        state.gotoMark(mark);
                        return NoMatch;
                    }
                }
                return MatchAdvance;
            },
            .MatchUntilChar => |m| {
                const mark = state.mark();
                while (true) {
                    if (state.nextAtEnd()) {
                        state.gotoMark(mark);
                        return NoMatch;
                    }
                    var ch = state.consumeNext();
                    if (ch == m.ch) {
                        return MatchAdvance;
                    }
                }
            },
            .MatchNotChar => |m| {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                if (ch == m.ch) {
                    return NoMatch;
                } else {
                    _ = state.consumeNext();
                    return MatchAdvance;
                }
            },
            .MatchExactChar => |inner| {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                if (ch != inner.ch) {
                    return NoMatch;
                } else {
                    _ = state.consumeNext();
                    return MatchAdvance;
                }
            },
            .MatchZeroOrMore => |inner| {
                // log.warn("MatchZeroOrMore {}", .{state.next_ch_idx});
                const inner_op = self.ops[inner.op_id];
                var res = MatchNoAdvance;
                while (true) {
                    const _res = self.advanceWithOp(state, &inner_op);
                    if (_res == MatchAdvance) {
                        // Must have match and advanced to continue or we will enter infinite loop.
                        res = MatchAdvance;
                        continue;
                    } else {
                        return res;
                    }
                }
            },
            .MatchOneOrMore => |m| {
                const inner_op = self.ops[m.op_id];
                if (self.advanceWithOp(state, &inner_op) != MatchAdvance) {
                    return NoMatch;
                }
                while (true) {
                    if (self.advanceWithOp(state, &inner_op) == MatchAdvance) {
                        continue;
                    } else {
                        return MatchAdvance;
                    }
                }
            },
            .MatchDigit => |m| {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                if (!std.ascii.isDigit(ch)) {
                    return NoMatch;
                }
                _ = state.consumeNext();
                if (m == .One) {
                    return MatchAdvance;
                } else if (m == .OneOrMore) {
                    while (!state.nextAtEnd()) {
                        ch = state.peekNext();
                        if (!std.ascii.isDigit(ch)) {
                            break;
                        }
                        _ = state.consumeNext();
                    }
                    return MatchAdvance;
                }
            },
            .MatchAsciiLetter => {
                if (state.nextAtEnd()) {
                    return NoMatch;
                }
                var ch = state.peekNext();
                if (!std.ascii.isAlpha(ch)) {
                    return NoMatch;
                } else {
                    _ = state.consumeNext();
                    return MatchAdvance;
                }
            },
            .MatchChoice => |inner| {
                var i = inner.ops.start;
                while (i < inner.ops.end) : (i += 1) {
                    const inner_op = &self.ops[i];
                    const res = self.advanceWithOp(state, inner_op);
                    if (res != NoMatch) {
                        return res;
                    }
                }
                return NoMatch;
            },
            .MatchOptional => |m| {
                const inner_op = &self.ops[m.op_id];
                const res = self.advanceWithOp(state, inner_op);
                if (res != NoMatch) {
                    return res;
                } else {
                    return MatchNoAdvance;
                }
            },
            .MatchNegLookahead => |m| {
                // Returns no match if inner op matches and resets position.
                // Returns match if inner op doesn't match but does not advance the position.
                const inner_op = &self.ops[m.op_id];
                const mark = state.mark();
                const res = self.advanceWithOp(state, inner_op);
                switch (res) {
                    NoMatch => return MatchNoAdvance,
                    MatchAdvance => {
                        state.gotoMark(mark);
                        return NoMatch;
                    },
                    MatchNoAdvance => return NoMatch,
                    else => unreachable,
                }
            },
            .MatchPosLookahead => |m| {
                // Returns match if inner op matches but does not advance the position.
                // Returns no match if inner op doesn't match.
                const inner_op = &self.ops[m.op_id];
                const mark = state.mark();
                const res = self.advanceWithOp(state, inner_op);
                switch (res) {
                    NoMatch => return NoMatch,
                    MatchAdvance => {
                        state.gotoMark(mark);
                        return MatchNoAdvance;
                    },
                    MatchNoAdvance => return MatchNoAdvance,
                    else => unreachable,
                }
            },
            .MatchSeq => |inner| {
                var i = inner.ops.start;
                var res = NoMatch;
                const mark = state.mark();
                while (i < inner.ops.end) : (i += 1) {
                    const inner_op = &self.ops[i];
                    // log.warn("op {}", .{inner_op});
                    const _res = self.advanceWithOp(state, inner_op);
                    if (_res == NoMatch) {
                        state.gotoMark(mark);
                        return NoMatch;
                    } else {
                        res |= _res;
                    }
                }
                return res;
            },
            .MatchRegexChar,
            .MatchRangeChar,
            => stdx.panicFmt("unsupported rule: {s}", .{@tagName(op.*)}),
        }
        unreachable;
    }
};

const MatchOpResult = u2;
const NoMatch: MatchOpResult = 0b0_0;
// Matched but didn't advance the pointer. (eg. Optional, ZeroOrMore matchers)
const MatchNoAdvance: MatchOpResult = 0b1_0;
// Matched and advanced the pointer.
const MatchAdvance: MatchOpResult = 0b1_1;

const StringBufferState = struct {
    const Self = @This();
    const Mark = u32;
    const Type = StateType{
        .StringBuffer = {},
    };

    next_ch_idx: u32,
    end_idx: u32,
    src: []const u8,
    buf: *std.ArrayList(Token),

    fn init(self: *Self, src: []const u8, buf: *std.ArrayList(Token)) void {
        self.* = .{
            .src = src,
            .end_idx = @intCast(u32, src.len),
            .next_ch_idx = 0,
            .buf = buf,
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    inline fn appendToken(self: *Self, comptime Debug: bool, debug: anytype, token: Token) void {
        _ = Debug;
        _ = debug;
        self.buf.append(token) catch unreachable;
    }

    inline fn mark(self: *const Self) u32 {
        return self.next_ch_idx;
    }

    inline fn gotoMark(self: *Self, _mark: u32) void {
        self.next_ch_idx = _mark;
    }

    inline fn nextAtEnd(self: *const Self) bool {
        return self.next_ch_idx >= self.end_idx;
    }

    inline fn peekNext(self: *Self) u8 {
        return self.src[self.next_ch_idx];
    }

    inline fn getString(self: *Self, start: u32, end: u32) []const u8 {
        return self.src[start..end];
    }

    inline fn consumeNext(self: *Self) u8 {
        const ch = self.src[self.next_ch_idx];
        self.next_ch_idx += 1;
        return ch;
    }
};

// This is fast at iterating a document line tree since it will track the current leaf and continue to the next.
// This also means that it won't pick up inserts/deletes from the document during parsing.
// TODO: move Incremental into inner function comptime.
fn LineSourceState(comptime Incremental: bool) type {
    return struct {
        const Self = @This();
        const Type = StateType{ .LineSource = .{
            .is_incremental = Incremental,
        } };
        const Mark = struct {
            next_ch_idx: u32,
            leaf_id: document.NodeId,
            chunk_line_idx: u32,
        };

        doc: *Document,

        // Current line data.
        next_ch_idx: u32,
        end_ch_idx: u32,
        leaf_id: document.NodeId,
        chunk: []document.LineId,
        chunk_line_idx: u32,
        line: []const u8,

        last_leaf_id: document.NodeId,
        last_chunk_size: u32,

        cur_token_list_last: TokenId,

        buf: *LineTokenBuffer,

        //// For incremental.
        inc_offset: i32,
        stop_line_loc: document.LineLocation,
        stop_ch_idx: u32,
        stop_token_id: TokenId,
        // Detached token sublist that needs to be reconciled with updated list once we're done with the current line.
        cur_detached_token: TokenId,

        fn init(self: *Self, doc: *Document, buf: *LineTokenBuffer) void {
            const leaf_id = doc.getFirstLeaf();

            const last_leaf_id = doc.getLastLeaf();
            const last_leaf = doc.getNode(last_leaf_id);

            // Ensure doc line map is big enough.
            buf.lines.resize(doc.lines.size()) catch unreachable;

            self.* = .{
                .doc = doc,
                .next_ch_idx = 0,
                .chunk = doc.getLeafLineChunkSlice(leaf_id),
                .leaf_id = leaf_id,
                .end_ch_idx = undefined,
                .chunk_line_idx = 0,
                .line = undefined,
                .last_leaf_id = last_leaf_id,
                .last_chunk_size = last_leaf.Leaf.chunk.size,
                .buf = buf,
                .cur_token_list_last = undefined,
                .stop_line_loc = undefined,
                .stop_ch_idx = undefined,
                .stop_token_id = undefined,
                .cur_detached_token = undefined,
                .inc_offset = undefined,
            };

            if (self.chunk.len > 0) {
                self.line = doc.getLineById(self.chunk[self.chunk_line_idx]);
                self.end_ch_idx = @intCast(u8, self.line.len);
            } else {
                self.end_ch_idx = 0;
            }
            self.cur_token_list_last = self.buf.temp_head_id;
        }

        fn initAtTokenBeforePosition(self: *Self, doc: *Document, buf: *LineTokenBuffer, line_idx: u32, col_idx: u32, change_size: i32) void {
            const loc = doc.findLineLoc(line_idx);
            self.* = .{
                .doc = doc,
                .buf = buf,
                .leaf_id = loc.leaf_id,
                .chunk_line_idx = loc.chunk_line_idx,
                .chunk = self.doc.getLeafLineChunkSlice(loc.leaf_id),
                .next_ch_idx = undefined,
                .end_ch_idx = undefined,
                .line = undefined,
                .last_leaf_id = undefined,
                .last_chunk_size = undefined,
                .cur_token_list_last = undefined,
                .stop_ch_idx = undefined,
                .stop_line_loc = undefined,
                .stop_token_id = undefined,
                .cur_detached_token = undefined,
                .inc_offset = change_size,
            };

            // Find stop first before the token list is segmented.
            self.seekStopToFirstTokenFromLine(loc);
            if (std.meta.eql(self.stop_line_loc, loc) and self.stop_token_id != NullToken) {
                // For inserts, change end is where the change starts.
                // For deletes, change end is where the change starts + deleted characters.
                const change_end_col = if (change_size > 0) col_idx else col_idx + std.math.absCast(change_size);
                self.seekStopToFirstTokenAtAfterChangeEndCol(change_end_col);
            }

            const mb_prev_id = self.seekToFirstTokenBeforePos(col_idx);
            if (mb_prev_id) |prev_id| {
                self.cur_token_list_last = prev_id;
                self.cur_detached_token = self.buf.tokens.detachAfter(prev_id) catch unreachable;
            } else {
                self.cur_token_list_last = self.buf.temp_head_id;
                self.cur_detached_token = NullToken;
            }
        }

        usingnamespace if (Incremental) struct {
            pub fn reconcileCurrentTokenList(self: *Self, comptime Debug: bool, debug: anytype, reuse_token_id: TokenId) void {
                // log.warn("reuse: {}", .{reuse_token_id});
                // log.warn("detached: {}", .{self.cur_detached_token});
                // log.warn("last: {}", .{self.cur_token_list_last});

                // Removes tokens from detached end sublist that are not reused.
                var cur_token_id = self.cur_detached_token;
                while (cur_token_id != reuse_token_id) {
                    const next = self.buf.tokens.getNodeAssumeExists(cur_token_id).next;
                    self.buf.tokens.removeDetached(cur_token_id);
                    cur_token_id = next;
                    if (Debug) {
                        debug.stats.inc_tokens_removed += 1;
                    }
                }

                // Update reusable sublist with pos offset.
                cur_token_id = reuse_token_id;
                while (cur_token_id != NullToken) {
                    const cur = self.buf.tokens.getNodePtrAssumeExists(cur_token_id);
                    cur.data.loc.start +%= @bitCast(u32, self.inc_offset);
                    cur.data.loc.end +%= @bitCast(u32, self.inc_offset);
                    cur_token_id = cur.next;
                }

                // Reattach resusable end sublist.
                if (reuse_token_id != NullToken) {
                    self.buf.tokens.setDetachedToEnd(self.cur_token_list_last, reuse_token_id);
                }
            }

            // Assumes stop_token_id already refers to a token on the same line.
            pub fn seekStopToFirstTokenAtAfterChangeEndCol(self: *Self, col_idx: u32) void {
                while (true) {
                    const token = self.buf.tokens.get(self.stop_token_id).?;
                    if (token.loc.start >= col_idx) {
                        self.stop_ch_idx = token.loc.start +% @bitCast(u32, self.inc_offset);
                        return;
                    }
                    self.stop_token_id = self.buf.tokens.getNextIdNoCheck(self.stop_token_id);
                    if (self.stop_token_id == NullToken) {
                        const line_id = self.doc.getLineIdByLoc(self.stop_line_loc);
                        const line = self.doc.getLineById(line_id);
                        self.stop_ch_idx = @intCast(u32, line.len) +% @bitCast(u32, self.inc_offset);
                        return;
                    }
                }
            }

            pub fn seekStopToNextToken(self: *Self) void {
                while (true) {
                    const token = self.buf.tokens.get(self.stop_token_id).?;
                    if (token.loc.start +% @bitCast(u32, self.inc_offset) >= self.next_ch_idx) {
                        self.stop_ch_idx = token.loc.start +% @bitCast(u32, self.inc_offset);
                        return;
                    }
                    self.stop_token_id = self.buf.tokens.getNextIdNoCheck(self.stop_token_id);
                    if (self.stop_token_id == NullToken) {
                        const line_id = self.doc.getLineIdByLoc(self.stop_line_loc);
                        const line = self.doc.getLineById(line_id);
                        self.stop_ch_idx = @intCast(u32, line.len);
                        return;
                    }
                }
            }

            pub fn seekStopToFirstTokenFromLine(self: *Self, loc: document.LineLocation) void {
                self.stop_line_loc = loc;
                var chunk = self.doc.getLeafLineChunkSlice(self.stop_line_loc.leaf_id);
                while (true) {
                    const line_id = chunk[self.stop_line_loc.chunk_line_idx];
                    if (self.buf.lines.items[line_id]) |list_id| {
                        self.stop_token_id = self.buf.tokens.getListHead(list_id).?;
                        self.stop_ch_idx = self.buf.tokens.getAssumeExists(self.stop_token_id).loc.start;
                        return;
                    }
                    if (self.stop_line_loc.leaf_id == self.last_leaf_id and self.stop_line_loc.chunk_line_idx == self.last_chunk_size) {
                        self.stop_token_id = NullToken;
                        self.stop_ch_idx = @intCast(u32, self.doc.getLine(line_id).len);
                    }
                    self.stop_line_loc.chunk_line_idx += 1;
                    if (self.stop_line_loc.chunk_line_idx == chunk.len) {
                        // Advance chunk.
                        self.stop_line_loc.leaf_id = self.doc.getNextLeafNode(self.stop_line_loc.leaf_id).?;
                        self.stop_line_loc.chunk_line_idx = 0;
                    }
                }
            }

            // Assumes line loc is already on the same line as col pos.
            // Returns the token that precedes the token seeked to. Useful for caller to detach list.
            pub fn seekToFirstTokenBeforePos(self: *Self, col_idx: u32) ?TokenId {
                const line_id = self.chunk[self.chunk_line_idx];
                if (self.buf.lines.items[line_id]) |list_id| {
                    // Find first token in the line at or precedes col_idx.
                    const head = self.buf.tokens.getListHead(list_id);
                    var prev: ?TokenId = null;
                    var cur_token_id = head.?;
                    var cur_item = self.buf.tokens.getNodeAssumeExists(cur_token_id);
                    if (cur_item.data.loc.start < col_idx) {
                        // First token is before col_idx.
                        while (cur_item.next != NullToken) {
                            const next = self.buf.tokens.getNodeAssumeExists(cur_item.next);
                            if (next.data.loc.start >= col_idx) {
                                // Found starting point.
                                break;
                            }
                            prev = cur_token_id;
                            cur_token_id = cur_item.next;
                            cur_item = next;
                        }
                        self.next_ch_idx = cur_item.data.loc.start;
                        self.line = self.doc.getLineById(line_id);
                        self.end_ch_idx = @intCast(u32, self.line.len);
                        return prev;
                    }
                }
                var list_id = self.seekToPrevLineWithTokens();
                if (list_id == null) {
                    // Start at first line.
                    if (self.chunk.len > 0) {
                        self.next_ch_idx = 0;
                        self.line = self.doc.getLineById(self.chunk[self.chunk_line_idx]);
                        self.end_ch_idx = @intCast(u32, self.line.len);
                        return null;
                    } else {
                        unreachable;
                    }
                } else {
                    // Start at last token in the list.
                    stdx.panic("TODO");
                }
            }

            // Returns list id if found.
            // Returns null if we reached top.
            pub fn seekToPrevLineWithTokens(self: *Self) ?TokenListId {
                const first_leaf = self.doc.getFirstLeaf();
                while (true) {
                    if (self.leaf_id == first_leaf and self.chunk_line_idx == 0) {
                        return null;
                    }
                    if (self.chunk_line_idx == 0) {
                        // Step back one chunk.
                        self.leaf_id = self.doc.getPrevLeafNode(self.leaf_id).?;
                        self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
                        self.chunk_line_idx = @intCast(u32, self.chunk.len) - 1;
                    } else {
                        self.chunk_line_idx -= 1;
                    }

                    const line_id = self.chunk[self.chunk_line_idx];
                    if (self.buf.lines.items[line_id]) |list_id| {
                        return list_id;
                    }
                }
            }
        } else struct {};

        fn deinit(_: *Self) void {
            // Nop.
        }

        inline fn appendToken(self: *Self, comptime Debug: bool, debug: anytype, token: Token) void {
            // log.warn("appendToken: {} {s}", .{token.loc, self.doc.getSubstringFromLineLoc(.{.leaf_id = self.leaf_id, .chunk_line_idx = self.chunk_line_idx}, token.loc.start, token.loc.end)});
            self.cur_token_list_last = self.buf.tokens.insertAfter(self.cur_token_list_last, token) catch unreachable;
            if (Debug) {
                debug.stats.inc_tokens_added += 1;
            }
            if (Incremental) {
                if (self.next_ch_idx > self.stop_ch_idx) {
                    // Token exceeded stop pos, seek to next stop pos.
                    self.seekStopToNextToken();
                }
            }
        }

        inline fn mark(self: *const Self) Mark {
            return .{
                .next_ch_idx = self.next_ch_idx,
                .leaf_id = self.leaf_id,
                .chunk_line_idx = self.chunk_line_idx,
            };
        }

        inline fn gotoMark(self: *Self, m: Mark) void {
            // log.warn("goto mark {}", .{m});
            self.next_ch_idx = m.next_ch_idx;
            self.leaf_id = m.leaf_id;
            self.chunk_line_idx = m.chunk_line_idx;

            self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
            self.line = self.doc.getLineById(self.chunk[self.chunk_line_idx]);
            self.end_ch_idx = @intCast(u8, self.line.len);
        }

        inline fn nextAtEnd(self: *const Self) bool {
            return self.leaf_id == self.last_leaf_id and self.chunk_line_idx == self.last_chunk_size;
        }

        inline fn peekNext(self: *Self) u8 {
            if (self.next_ch_idx == self.line.len) {
                return '\n';
            } else {
                return self.line[self.next_ch_idx];
            }
        }

        fn beforeNextLine(self: *Self) void {
            if (Incremental) {
                stdx.panic("TODO");
            } else {
                if (self.cur_token_list_last != self.buf.temp_head_id) {
                    // Add accumulated token list and map it from doc line id.
                    const head = self.buf.tokens.getNextIdNoCheck(self.buf.temp_head_id);
                    const list_id = self.buf.tokens.addListWithDetachedHead(head) catch unreachable;
                    const line_id = self.doc.getLineIdByLoc(.{ .leaf_id = self.leaf_id, .chunk_line_idx = self.chunk_line_idx });
                    self.buf.lines.items[line_id] = list_id;
                    _ = self.buf.tokens.detachAfter(self.buf.temp_head_id) catch unreachable;
                    self.cur_token_list_last = self.buf.temp_head_id;
                    // log.warn("set token list to line {} {} {}", .{line_id, self.leaf_id, self.chunk_line_idx});
                }
            }
        }

        fn consumeNext(self: *Self) u8 {
            if (self.next_ch_idx == self.end_ch_idx) {
                self.next_ch_idx = 0;
                if (self.chunk_line_idx == self.chunk.len) {
                    // Advance to the next line chunk.
                    if (self.doc.getNextLeafNode(self.leaf_id)) |next| {
                        stdx.debug.abort();
                        self.beforeNextLine();
                        self.leaf_id = next;
                        self.chunk = self.doc.getLeafLineChunkSlice(self.leaf_id);
                        self.chunk_line_idx = 0;
                        if (self.chunk.len > 0) {
                            self.line = self.doc.getLineById(self.chunk[0]);
                            self.end_ch_idx = @intCast(u32, self.line.len);
                        } else {
                            unreachable;
                        }
                    } else {
                        unreachable;
                    }
                } else {
                    self.beforeNextLine();
                    self.chunk_line_idx += 1;
                }
                return '\n';
            }
            const ch = self.line[self.next_ch_idx];
            self.next_ch_idx += 1;
            return ch;
        }

        inline fn getString(self: *Self, start: Mark, end: Mark) []const u8 {
            return self.doc.getString(
                start.leaf_id,
                start.chunk_line_idx,
                start.next_ch_idx,
                end.leaf_id,
                end.chunk_line_idx,
                end.next_ch_idx,
            );
        }

        // From given start line, get the end token idx by adding all the missing chars inbetween.
        fn getTokenEndIdxFromStartLine(self: *Self, start: Mark, end: Mark) u32 {
            if (start.leaf_id == end.leaf_id and start.chunk_line_idx == end.chunk_line_idx) {
                return end.next_ch_idx;
            } else {
                var res = end.next_ch_idx;

                // Add up all previous lines.
                var leaf_id = start.leaf_id;
                var chunk = self.doc.getLeafLineChunkSlice(leaf_id);
                var chunk_line_idx = start.chunk_line_idx;

                while (true) {
                    if (leaf_id == end.leaf_id and chunk_line_idx == end.chunk_line_idx) {
                        break;
                    }
                    const line = self.doc.getLineById(chunk[chunk_line_idx]);
                    res += @intCast(u32, line.len) + 1;
                    chunk_line_idx += 1;
                    if (chunk_line_idx == chunk.len) {
                        // Advance chunk.
                        leaf_id = self.doc.getNextLeafNode(leaf_id).?;
                        chunk = self.doc.getLeafLineChunkSlice(leaf_id);
                        chunk_line_idx = 0;
                    }
                }

                return res;
            }
        }
    };
}

const StateType = union(enum) {
    LineSource: struct {
        is_incremental: bool,
    },
    StringBuffer: void,
};

const TokenizeConfig = struct {
    Context: type,
    debug: bool,
};

fn TokenizeContext(comptime State: type, debug: bool) type {
    return struct {
        const State = State;

        state: State,
        debug: if (debug) *DebugInfo else void,
    };
}
