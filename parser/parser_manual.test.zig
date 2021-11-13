const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.parser_manual_test);

const _parser = @import("parser.zig");
const Parser = _parser.Parser;
const DebugInfo = _parser.DebugInfo;
const ParseConfig = _parser.ParseConfig;
const _grammar = @import("grammar.zig");
const Grammar = _grammar.Grammar;
const builder = @import("builder.zig");
const grammars = @import("grammars.zig");

// zig repo should be at "ProjectRoot/lib/zig"

test "Parse zig big" {
    const path = "./lib/zig/src/Sema.zig";

    const file = std.fs.cwd().openFile(path, .{}) catch unreachable;
    defer file.close();

    const src = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
    defer t.alloc.free(src);

    var grammar: Grammar = undefined;
    try builder.initGrammar(&grammar, t.alloc, grammars.ZigGrammar);
    defer grammar.deinit();

    var parser = Parser.init(t.alloc, &grammar);
    defer parser.deinit();

    var debug: DebugInfo = undefined;
    debug.init(t.alloc);
    defer debug.deinit();

    var str_buf = std.ArrayList(u8).init(t.alloc);
    defer str_buf.deinit();

    // stdx.debug.flag = true;
    const Config: ParseConfig = .{ .is_incremental = false };
    var res = parser.parseDebug(Config, src, &debug);
    defer res.deinit();

    if (!res.success) {
        str_buf.clearRetainingCapacity();
        res.ast.formatContextAtToken(str_buf.writer(), res.err_token_id);
        log.warn("{s}", .{str_buf.items});

        // buf.clearRetainingCapacity();
        // zig_parser.tokenizer.formatTokens(buf.writer());
        // log.warn("{s}", .{buf.items});

        // buf.clearRetainingCapacity();
        // ast.formatTree(buf.writer());
        // log.warn("{s}", .{buf.items});
    }

    try t.eq(debug.stats.parse_match_ops, 3621886);
    try t.eq(debug.stats.parse_rule_ops_no_cache, 1039435);

    const stmts = res.ast.getChildNodeList(res.ast.mb_root.?, 0);
    try t.eq(stmts.len, 415);
}

test "Parse zig std" {
    const trace = stdx.debug.trace();
    defer trace.endPrint("parsed zig std");

    var grammar: Grammar = undefined;
    try builder.initGrammar(&grammar, t.alloc, grammars.ZigGrammar);
    defer grammar.deinit();

    var parser = Parser.init(t.alloc, &grammar);
    defer parser.deinit();

    const Config: ParseConfig = .{ .is_incremental = false };

    var str_buf = std.ArrayList(u8).init(t.alloc);
    defer str_buf.deinit();

    const path = "./lib/zig/lib/std";
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    // var debug: DebugInfo = undefined;
    // debug.init(t.alloc);
    // defer debug.deinit();

    var walker = try dir.walk(t.alloc);
    defer walker.deinit();
    while (try walker.next()) |it| {
        if (it.kind == .File) {
            if (!stdx.string.endsWith(it.path, ".zig")) {
                continue;
            }
            if (stdx.string.endsWith(it.path, "_test.zig")) {
                continue;
            }
            log.warn("Parsing: {s}", .{it.path});
            const file = dir.openFile(it.path, .{}) catch unreachable;
            defer file.close();

            const src = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
            defer t.alloc.free(src);

            var res = parser.parse(Config, src);
            // var res = parser.parseDebug(Config, src, &debug);
            defer res.deinit();

            if (!res.success) {
                str_buf.clearRetainingCapacity();
                res.ast.formatContextAtToken(str_buf.writer(), res.err_token_id);
                log.warn("{s}", .{str_buf.items});

                // str_buf.clearRetainingCapacity();
                // debug.formatMaxCallStack(Config, &res.ast, str_buf.writer());
                // log.warn("{s}", .{str_buf.items});

                // str_buf.clearRetainingCapacity();
                // res.ast.formatTokens(str_buf.writer());
                // log.warn("{s}", .{str_buf.items});

                try t.fail();
            }

            const stmts = res.ast.getChildNodeList(res.ast.mb_root.?, 0);
            log.warn("{} statements", .{stmts.len});
        }
    }
}
