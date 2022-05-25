const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.incremental_test);

const _parser = @import("parser.zig");
const Parser = _parser.Parser;
const ParseConfig = _parser.ParseConfig;
const DebugInfo = _parser.DebugInfo;
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const builder = @import("builder.zig");
const grammars = @import("grammars.zig");
const document = stdx.textbuf.document;
const Document = document.Document;
const TokenId = @import("ast.zig").TokenId;
const NullToken = stdx.ds.CompactNull(TokenId);

test "Parser is_incremental=true" {
    const src =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\  const stdout = std.io.getStdOut().writer();
        \\  try stdout.print("Hello, {s}!\n", .{"world"});
        \\}
    ;

    var str_buf = std.ArrayList(u8).init(t.alloc);
    defer str_buf.deinit();

    var doc: Document = undefined;
    doc.init(t.alloc);
    defer doc.deinit();

    doc.loadSource(src);

    var gram: Grammar = undefined;
    try builder.initGrammar(&gram, t.alloc, grammars.ZigGrammar);
    defer gram.deinit();

    const Config: ParseConfig = .{ .is_incremental = true };
    var parser = Parser.init(t.alloc, &gram);
    defer parser.deinit();

    var res = parser.parse(Config, &doc);
    defer res.deinit();
    var ast = &res.ast;

    const tokens = &ast.tokens.tokens;
    const lines = &ast.tokens.lines;

    // Verify token lists per document line.
    try t.eq(doc.numLines(), @intCast(u32, lines.items.len));

    var token_id = tokens.getListHead(lines.items[doc.getLineId(0)].?).?;
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "const");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "std");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "=");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "@import");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "(");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), "\"std\"");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), ")");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 0, token_id), ";");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eq(token_id, NullToken);

    // Empty line so no token list.
    try t.eq(lines.items[doc.getLineId(1)], null);

    token_id = tokens.getListHead(lines.items[doc.getLineId(2)].?).?;
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "pub");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "fn");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "main");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "(");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), ")");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "!");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "void");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eqStr(ast.getTokenString(&doc, 2, token_id), "{");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eq(token_id, NullToken);

    // Skip to end.
    token_id = tokens.getListHead(lines.items[doc.getLineId(5)].?).?;
    try t.eqStr(ast.getTokenString(&doc, 5, token_id), "}");
    token_id = tokens.getNextIdNoCheck(token_id);
    try t.eq(token_id, NullToken);

    // str_buf.clearRetainingCapacity();
    // ast.formatTree(str_buf.writer());
    // log.warn("{s}", .{str_buf.items});

    // Verify ast nodes.
    const stmts = ast.getChildNodeList(ast.mb_root.?, 0);
    try t.eq(stmts.len, 2);

    try t.eqStr(ast.getNodeTagName(stmts[0]), "VariableDecl");
    try t.eqStr(ast.getNodeTagName(stmts[1]), "FunctionDecl");

    const func_stmts = ast.getChildNodeList(stmts[1], 4);
    try t.eq(func_stmts.len, 2);

    try t.eqStr(ast.getNodeTagName(func_stmts[0]), "VariableDecl");
    try t.eqStr(ast.getNodeTagName(func_stmts[1]), "TryExpr");
}

test "Insert text" {
    const src =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\  const stdout = std.io.getStdOut().writer();
        \\  try stdout.print("Hello, {s}!\n", .{"world"});
        \\}
    ;

    var str_buf = std.ArrayList(u8).init(t.alloc);
    defer str_buf.deinit();

    var doc: Document = undefined;
    doc.init(t.alloc);
    defer doc.deinit();

    var gram: Grammar = undefined;
    try builder.initGrammar(&gram, t.alloc, grammars.ZigGrammar);
    defer gram.deinit();

    const Config: ParseConfig = .{ .is_incremental = true };
    var parser = Parser.init(t.alloc, &gram);
    defer parser.deinit();

    var debug: DebugInfo = undefined;
    debug.init(t.alloc);
    defer debug.deinit();

    {
        // Insert before existing token that reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        // str_buf.clearRetainingCapacity();
        // ast.formatTree(str_buf.writer());
        // log.warn("{s}", .{str_buf.items});

        doc.insertIntoLine(2, 7, "_insert_");
        parser.reparseChangeDebug(Config, &doc, ast, 2, 7, "_insert_".len, &debug);
        try t.eq(debug.stats.inc_tokens_added, 2);
        try t.eq(debug.stats.inc_tokens_removed, 2);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "_insert_main");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }

    {
        // Insert in existing token reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        doc.insertIntoLine(2, 8, "_insert_");
        parser.reparseChangeDebug(Config, &doc, ast, 2, 8, "_insert_".len, &debug);
        try t.eq(debug.stats.inc_tokens_added, 1);
        try t.eq(debug.stats.inc_tokens_removed, 1);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "m_insert_ain");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }

    {
        // Insert after existing token reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        doc.insertIntoLine(2, 11, "_insert_");
        parser.reparseChangeDebug(Config, &doc, ast, 2, 11, "_insert_".len, &debug);
        try t.eq(debug.stats.inc_tokens_added, 1);
        try t.eq(debug.stats.inc_tokens_removed, 1);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "main_insert_");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }
}

test "Delete text" {
    const src =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\  const stdout = std.io.getStdOut().writer();
        \\  try stdout.print("Hello, {s}!\n", .{"world"});
        \\}
    ;

    var str_buf = std.ArrayList(u8).init(t.alloc);
    defer str_buf.deinit();

    var doc: Document = undefined;
    doc.init(t.alloc);
    defer doc.deinit();

    var gram: Grammar = undefined;
    try builder.initGrammar(&gram, t.alloc, grammars.ZigGrammar);
    defer gram.deinit();

    const Config: ParseConfig = .{ .is_incremental = true };
    var parser = Parser.init(t.alloc, &gram);
    defer parser.deinit();

    var debug: DebugInfo = undefined;
    debug.init(t.alloc);
    defer debug.deinit();

    {
        // Delete beginning of existing token that reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        // str_buf.clearRetainingCapacity();
        // ast.formatTree(str_buf.writer());
        // log.warn("{s}", .{str_buf.items});

        doc.removeRangeInLine(2, 7, 9);
        parser.reparseChangeDebug(Config, &doc, ast, 2, 7, -2, &debug);
        try t.eq(debug.stats.inc_tokens_added, 2);
        try t.eq(debug.stats.inc_tokens_removed, 2);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "in");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }

    {
        // Delete in existing token that reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        doc.removeRangeInLine(2, 8, 10);
        parser.reparseChangeDebug(Config, &doc, ast, 2, 8, -2, &debug);
        try t.eq(debug.stats.inc_tokens_added, 1);
        try t.eq(debug.stats.inc_tokens_removed, 1);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "mn");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }

    {
        // Delete ending of existing token that reparses as the same token tag.
        doc.loadSource(src);
        var res = parser.parse(Config, &doc);
        defer res.deinit();
        const ast = &res.ast;

        doc.removeRangeInLine(2, 9, 11);
        parser.reparseChangeDebug(Config, &doc, ast, 2, 9, -2, &debug);
        try t.eq(debug.stats.inc_tokens_added, 1);
        try t.eq(debug.stats.inc_tokens_removed, 1);
        const list_id = ast.getTokenList(&doc, 2);
        const token_id = ast.tokens.tokens.getIdAt(list_id, 2);
        try t.eqStr(ast.getTokenString(&doc, 2, token_id), "ma");
        try t.eqStr(ast.getTokenName(token_id), "IdentifierToken");
    }
}
