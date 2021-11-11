const std = @import("std");
const stdx = @import("stdx");
const log = stdx.log.scoped(.ast);

const document = @import("common").document;

const _parser = @import("parser.zig");
const Parser = _parser.Parser;
const NodePtr = _parser.NodePtr;
const TokenRef = _parser.TokenRef;
const NodeSlice = _parser.NodeSlice;
const NodeTokenPtr = _parser.NodeTokenPtr;
const NodeId = _parser.NodeId;
const ParseConfig = _parser.ParseConfig;
const Source = _parser.Source;
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const TokenTag = grammar.TokenTag;
const LiteralTokenTag = grammar.LiteralTokenTag;
const ds = stdx.ds;
const algo = stdx.algo;

// Currently, the token data is owned by Tree and node data is owned by the parser.
// The plan is to move token ownership to the parser as well and implement copy to a standalone tree.
// When we have an incremental tree, we might need to copy over the parser cache too.
pub fn Tree(comptime Config: ParseConfig) type {
    return struct {
        const Self = @This();

        mb_root: ?NodePtr,
        alloc: *std.mem.Allocator,
        grammar: *Grammar,

        // TODO: rename to token_buf
        tokens: TokenBuffer(Config),
        nodeptr_buf: std.ArrayList(NodePtr),

        // Currently points to parser buffers.
        node_ptrs: *std.ArrayList(NodePtr),
        node_slices: *std.ArrayList(NodeSlice),
        node_tokens: *std.ArrayList(NodeTokenPtr),

        src: Source(Config),

        pub fn init(self: *Self, alloc: *std.mem.Allocator, parser: *Parser, src: Source(Config)) void {
            self.* = .{
                .mb_root = null,
                .alloc = alloc,
                .tokens = undefined,
                .node_ptrs = &parser.buf.node_ptrs,
                .node_slices = &parser.buf.node_slices,
                .node_tokens = &parser.buf.node_tokens,
                .grammar = parser.grammar,
                .nodeptr_buf = std.ArrayList(NodePtr).init(alloc),
                .src = src,
            };
            if (Config.is_incremental) {
                self.tokens = .{
                    .lines = std.ArrayList(?TokenListId).init(alloc),
                    .tokens = ds.CompactManySinglyLinkedList(TokenListId, TokenId, Token).init(alloc),
                    .temp_head_id = undefined,
                };
                self.tokens.temp_head_id = self.tokens.tokens.addDetachedItem(undefined) catch unreachable;
            } else {
                self.tokens = ds.CompactSinglyLinkedList(TokenId, Token).init(alloc);
            }
        }

        pub fn deinit(self: *Self) void {
            // if (self.mb_root) |root| {
            //     self.destroyNodeDeep(root);
            // }
            self.nodeptr_buf.deinit();
            self.tokens.deinit();
        }

        pub fn getNodeTagName(self: *const Self, node: NodePtr) []const u8 {
            return self.grammar.getNodeTagName(node.tag);
        }

        pub fn getChildNode(self: *const Self, node: NodePtr, idx: u32) NodePtr {
            if (node.tag >= self.grammar.decl_tag_end) {
                stdx.panic("Expected node");
            }
            const fields = self.node_slices.items[node.id];
            return self.node_ptrs.items[fields.start + idx];
        }

        pub fn getChildNodeList(self: *const Self, node: NodePtr, idx: u32) []const NodePtr {
            if (node.tag >= self.grammar.decl_tag_end) {
                stdx.panic("Expected node");
            }
            const fields = self.node_slices.items[node.id];
            const child = self.node_ptrs.items[fields.start + idx];
            if (child.tag != self.grammar.node_list_tag) {
                stdx.panic("Expected node list");
            }
            const list = self.node_slices.items[child.id];
            return self.node_ptrs.items[list.start..list.end];
        }

        pub fn getChildStringValue(self: *const Self, node: NodePtr, idx: u32) []const u8 {
            if (node.tag >= self.grammar.decl_tag_end) {
                stdx.panic("Expected node");
            }
            const child = self.getChildAssumeParentSyntaxNode(node, idx);
            return self.getNodeTokenString(child);
        }

        pub fn getNodeTokenString(self: *const Self, node: NodePtr) []const u8 {
            if (node.tag != self.grammar.token_value_tag) {
                stdx.panic("Expected token value node");
            }
            const node_token = self.node_tokens.items[node.id];
            const token = self.getToken(node_token.token_id);
            if (Config.is_incremental) {
                return self.src.getSubstringFromLineLoc(node_token.token_ctx, token.loc.start, token.loc.end);
            } else {
                return self.src[token.loc.start..token.loc.end];
            }
        }

        pub fn getNodeTokenChar(self: *const Self, node: NodePtr) u8 {
            if (node.tag != self.grammar.token_value_tag) {
                stdx.panic("Expected token value node");
            }
            const node_token = self.node_tokens.items[node.id];
            const token = self.getToken(node_token.token_id);
            if (Config.is_incremental) {
                return self.src.getSubstringFromLineLoc(node_token.token_ctx, token.loc.start, token.loc.end)[0];
            } else {
                return self.src[token.loc.start];
            }
        }

        pub fn getChildNodeOpt(self: *const Self, node: NodePtr, idx: u32) ?NodePtr {
            const child = self.getChildNode(node, idx);
            if (child.tag == self.grammar.null_node_tag) {
                return null;
            } else {
                return child;
            }
        }

        fn getChildCharValue(self: *const Self, node: NodePtr, idx: u32) u8 {
            if (node.tag >= self.grammar.decl_tag_end) {
                stdx.panic("Expected node");
            }
            const child = self.getChildAssumeParentSyntaxNode(node, idx);
            return self.getCharValue(child);
        }

        fn getChildAssumeParentSyntaxNode(self: *const Self, parent: NodePtr, idx: u32) NodePtr {
            const fields = self.node_slices.items[parent.id];
            return self.node_ptrs.items[fields.start + idx];
        }

        // pub fn getCharValue(self: *const Self, node: NodePtr) u8 {
        //     if (node.tag != self.grammar.char_value_tag) {
        //         stdx.panic("Expected char value node");
        //     }
        //     return @intCast(u8, @ptrToInt(node.data));
        // }

        // pub fn getStringValue(self: *const Self, node: NodePtr) []const u8 {
        //     if (node.tag != self.grammar.string_value_tag) {
        //         stdx.panic("Expected string value node");
        //     }
        //     const str_len = std.mem.bytesToValue(u32, node.data[0..@sizeOf(u32)]);
        //     const str = node.data[@sizeOf(u32)..@sizeOf(u32)+str_len];
        //     return str;
        // }

        fn writeDoubleQuoteEscaped(writer: anytype, str: []const u8) !void {
            for (str) |ch| {
                switch (ch) {
                    '\n' => _ = try writer.write("\\n"),
                    '"' => _ = try writer.write("\\\""),
                    else => try writer.writeByte(ch),
                }
            }
        }

        fn getToken(self: *const Self, id: TokenId) Token {
            if (Config.is_incremental) {
                return self.tokens.tokens.get(id);
            } else {
                return self.tokens.get(id);
            }
        }

        pub fn getTokenName(self: *Self, id: TokenId) []const u8 {
            const token = self.getToken(id);
            return self.grammar.getTokenName(token.tag);
        }

        usingnamespace if (Config.is_incremental) struct {

            pub fn getTokenString(self: *const Self, doc: *document.Document, line_idx: u32, id: TokenId) []const u8 {
                const loc = doc.findLineLoc(line_idx);
                return self.getTokenStringByLoc(doc, loc, id);
            }

            pub fn getTokenStringByLoc(self: *const Self, doc: *document.Document, loc: document.LineLocation, id: TokenId) []const u8 {
                const token = self.tokens.tokens.get(id);
                return doc.getSubstringFromLineLoc(loc, token.loc.start, token.loc.end);
            }

            pub fn getTokenList(self: *Self, doc: *document.Document, line_idx: u32) TokenListId {
                const line_id = doc.getLineId(line_idx);
                return self.tokens.lines.items[line_id].?;
            }

        } else struct {

            pub fn getTokenString(self: *const Self, id: TokenId) []const u8 {
                const token = self.getToken(id);
                return self.src[token.loc.start..token.loc.end];
            }
        };

        pub fn formatTree(self: *Self, writer: anytype) void {
            const S = struct {
                indent: u32,
                writer: @TypeOf(writer),
                tree: *const Self,

                fn visit(ctx: *algo.VisitContext(.{}), c: *@This(), node: NodePtr) void {
                    if (ctx.enter) {
                        const tag_name = c.tree.getNodeTagName(node);
                        c.writer.writeByteNTimes(' ', c.indent*2) catch unreachable;
                        std.fmt.format(c.writer, "{s}", .{tag_name}) catch unreachable;
                        if (node.tag == c.tree.grammar.string_value_tag) {
                            // c.writer.print(" \"", .{}) catch unreachable;
                            // writeDoubleQuoteEscaped(c.writer, c.tree.getStringValue(node)) catch unreachable;
                            // c.writer.print("\"", .{}) catch unreachable;
                            unreachable;
                        } else if (node.tag == c.tree.grammar.token_value_tag) {
                            c.writer.print(" \"", .{}) catch unreachable;
                            writeDoubleQuoteEscaped(c.writer, c.tree.getNodeTokenString(node)) catch unreachable;
                            c.writer.print("\"", .{}) catch unreachable;
                        } else if (node.tag == c.tree.grammar.char_value_tag) {
                            // c.writer.print(" \'{c}\'", .{c.tree.getCharValue(node)}) catch unreachable;
                            unreachable;
                        }
                        _ = c.writer.write("\n") catch unreachable;
                        c.indent += 1;
                    } else {
                        c.indent -= 1;
                    }
                }
            };
            var ctx = S{ .indent = 0, .writer = writer, .tree = self };
            var walker = initNodeWalker(Config, self);
            _ = writer.write("\n") catch unreachable;
            algo.walkPrePost(.{}, *S, &ctx, NodePtr, self.mb_root.?, walker.getIface(), S.visit, &self.nodeptr_buf, &self.grammar.bit_buf);
        }

        // TODO: Also add printTokens
        pub fn formatTokens(self: *const Self, writer: anytype) void {
            if (Config.is_incremental) {
                unreachable;
            } else {
                var cur = self.tokens.getFirst();
                while (cur != null) {
                    const tok = self.tokens.get(cur.?);
                    const str_slice = self.grammar.token_decls.items[tok.tag].name;
                    const str = self.grammar.getString(str_slice);
                    std.fmt.format(writer, "[{}] {s} \"{s}\" ", .{cur.?, str, self.src[tok.loc.start..tok.loc.end]}) catch unreachable;
                    // std.fmt.format(writer, "[{}-{}] {s} \"{s}\" ", .{tok.loc.start, tok.loc.end, self.tags.items[tok.tag], self.src[tok.loc.start..tok.loc.end]}) catch unreachable;
                    cur = self.tokens.getNext(cur.?);
                }
            }
        }

        pub fn formatContextAtToken(self: *const Self, writer: anytype, tok_ref: TokenRef(Config)) void {
            if (Config.is_incremental) {
                unreachable;
            } else {
                const MaxLinesBefore = 30;
                const MaxLinesAfter = 30;

                const tok_id = tok_ref;
                const tok = self.tokens.get(tok_id);
                const before = if (std.mem.lastIndexOf(u8, self.src[0..tok.loc.start], "\n")) |res| res + 1 else 0;
                const after = if (std.mem.indexOfPos(u8, self.src, tok.loc.end, "\n")) |res| res + 1 else self.src.len;
                const before_line = self.src[before..tok.loc.start];
                const after_line = self.src[tok.loc.end..after];

                const before_num_lines = std.mem.count(u8, self.src[0..before], "\n");
                if (before_num_lines > MaxLinesBefore) {
                    _ = writer.write("TRUNCATED REST\n") catch unreachable;
                    const idx = stdx.mem.lastIndexOfNth(u8, self.src[0..before], "\n", @intCast(u32, MaxLinesBefore)).? + 1;
                    var iter = stdx.string.splitLines(self.src[idx..before]);
                    var i: u32 = 0;
                    while (i < MaxLinesBefore) : (i += 1) {
                        const line = iter.next().?;
                        writer.print("{s}\n", .{line}) catch unreachable;
                    }
                } else {
                    _ = writer.write(self.src[0..before]) catch unreachable;
                }

                writer.print("----------------[{}]\n", .{before_num_lines}) catch unreachable;
                writer.print("{s}>>>|{s}|<<<{s}", .{before_line, self.src[tok.loc.start..tok.loc.end], after_line}) catch unreachable;
                _ = writer.write("----------------\n") catch unreachable;

                const after_num_lines = std.mem.count(u8, self.src[after..], "\n");
                if (after_num_lines > MaxLinesAfter) {
                    var iter = stdx.string.splitLines(self.src[after..]);
                    var i: u32 = 0;
                    while (i < MaxLinesAfter) : (i += 1) {
                        const line = iter.next().?;
                        writer.print("{s}\n", .{line}) catch unreachable;
                    }
                    _ = writer.write("TRUNCATED REST\n") catch unreachable;
                } else {
                    _ = writer.write(self.src[after..]) catch unreachable;
                }
            }
        }

        // TODO: Destroy functions will only be used for standalone ast (doesn't depend on parser buffer)
        // fn destroyNode(self: *Self, node: NodePtr) void {
        //     // log.warn("destroying node {s}", .{self.grammar.getNodeTagName(node.tag)});
        //     if (node.tag < self.grammar.node_list_tag) {
        //         const size = self.grammar.getNodeDataSize(node.tag);
        //         self.alloc.free(node.data[0..size]);
        //     } else if (node.tag == self.grammar.node_list_tag) {
        //         const slice = std.mem.bytesToValue([]const NodePtr, node.data[0..@sizeOf([]const NodePtr)]);

        //         // First destroy the node ptr array.
        //         self.alloc.free(slice);

        //         const size = self.grammar.getNodeDataSize(node.tag);
        //         self.alloc.free(node.data[0..size]);
        //     } else if (node.tag == self.grammar.string_value_tag) {
        //         const str_len = std.mem.bytesToValue(u32, node.data[0..@sizeOf(u32)]);
        //         self.alloc.free(node.data[0..@sizeOf(u32)+str_len]);
        //     } else if (node.tag == self.grammar.char_value_tag) {
        //         // Nop.
        //     } else if (node.tag == self.grammar.null_node_tag) {
        //         // Nop.
        //     } else stdx.panicFmt("unsupported node: {}", .{node.tag});
        // }

        // pub fn destroyNodesDeep(self: *Self, roots: []const NodePtr) void {
        //     for (roots) |it| {
        //         self.destroyNodeDeep(it);
        //     }
        // }

        // pub fn destroyNodesDeepExclude(self: *Self, roots: []const NodePtr, exclude_id: NodeId) void {
        //     for (roots) |it| {
        //         self.destroyNodeDeepExclude(it, exclude_id);
        //     }
        // }

        // pub fn destroyNodeDeep(self: *Self, root: NodePtr) void {
        //     const S = struct {
        //         fn visit(_: *walk.VisitContext(.{}), tree: *Self, node: NodePtr) void {
        //             tree.destroyNode(node);
        //         }
        //     };
        //     var walker = initNodeWalker(Config, self);
        //     walk.walkPost(.{}, *Self, self, NodePtr, root, walker.getIface(), S.visit, &self.nodeptr_buf, &self.grammar.bit_buf);
        // }

        // pub fn destroyNodeDeepExclude(self: *Self, root: NodePtr, exclude_id: NodeId) void {
        //     const WalkerConfig = walk.WalkerConfig{ .enable_skip = true };
        //     const S = struct {
        //         exclude_id: NodeId,
        //         parser: *Self,

        //         fn visit(c: *walk.VisitContext(WalkerConfig), ctx: *@This(), node: NodePtr) void {
        //             if (c.enter) {
        //                 if (node.id == ctx.exclude_id) {
        //                     c.skip();
        //                 }
        //             } else {
        //                 ctx.parser.destroyNode(node);
        //             }
        //         }
        //     };
        //     var ctx = S{ .exclude_id = exclude_id, .parser = self };
        //     var walker = initNodeWalker(Config, self);
        //     walk.walkPrePost(WalkerConfig, *S, &ctx, NodePtr, root, walker.getIface(), S.visit, &self.nodeptr_buf, &self.grammar.bit_buf);
        // }
    };
}

pub fn initNodeWalker(comptime Config: ParseConfig, _ast: *const Tree(Config)) algo.Walker(*const Tree(Config), NodePtr) {
    const S = struct {
        fn _walk(ctx: *algo.WalkerContext(NodePtr), ast: *const Tree(Config), node: NodePtr) void {
            // log.warn("walk {s}", .{p.g.getNodeTagName(node.tag)});
            if (node.tag < ast.grammar.decl_tag_end) {
                const decl = ast.grammar.decls.items[node.tag];
                // log.warn("node size {}", .{decl.num_child_items});
                const fields = ast.node_slices.items[node.id];
                ctx.beginAddNode(decl.num_child_items);
                var i = fields.start;
                while (i < fields.end) : (i += 1) {
                    ctx.addNode(ast.node_ptrs.items[i]);
                }
            } else if (node.tag == ast.grammar.node_list_tag) {
                const slice = ast.node_slices.items[node.id];
                // log.warn("node list size {}", .{slice.len});
                ctx.beginAddNode(@intCast(u32, slice.len()));
                var i = slice.start;
                while (i < slice.end) : (i += 1) {
                    ctx.addNode(ast.node_ptrs.items[i]);
                }
            } else if (node.tag == ast.grammar.token_value_tag) {
                // Nop.
            } else if (node.tag == ast.grammar.string_value_tag) {
                // Nop.
            } else if (node.tag == ast.grammar.char_value_tag) {
                // Nop.
            } else if (node.tag == ast.grammar.null_node_tag) {
                // Nop.
            } else stdx.panicFmt("unsupported tag {}", .{node.tag});
        }
    };
    return algo.Walker(*const Tree(Config), NodePtr).init(_ast, S._walk);
}

pub const TokenId = u32;
const Location = struct {
    start: u32,
    end: u32,
};

pub const Token = struct {

    tag: TokenTag,

    // Separate tag for exact string matching.
    literal_tag: LiteralTokenTag,

    loc: Location,

    pub fn init(tag: TokenTag, literal_tag: LiteralTokenTag, start: u32, end: u32) @This() {
        return .{
            .tag = tag,
            .literal_tag = literal_tag,
            .loc = .{
                .start = start,
                .end = end,
            }
        };
    }
};

pub fn TokenBuffer(comptime Config: ParseConfig) type {
    if (Config.is_incremental) {
        return LineTokenBuffer;
    } else {
        return ds.CompactSinglyLinkedList(TokenId, Token);
    }
}

pub const LineTokenBuffer = struct {
    // Maps one to one from Document line ids to tokens list.
    lines: std.ArrayList(?TokenListId),

    // One buffer for all linked lists.
    tokens: ds.CompactManySinglyLinkedList(TokenListId, TokenId, Token),

    // Temp head to initialize a list's head before using CompactManySinglyLinkedList.insertAfter.
    temp_head_id: TokenId,

    fn deinit(self: *@This()) void {
        self.lines.deinit();
        self.tokens.deinit();
    }
};

pub const TokenListId = u32;