const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.parser_simple_test);

const _parser = @import("parser.zig");
const Parser = _parser.Parser;
const DebugInfo = _parser.DebugInfo;
const ParseConfig = _parser.ParseConfig;
const _grammar = @import("grammar.zig");
const Grammar = _grammar.Grammar;
const builder = @import("builder.zig");
const grammars = @import("grammars.zig");
const _ast = @import("ast.zig");

test "Parse zig simple" {
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

    var grammar: Grammar = undefined;
    try builder.initGrammar(&grammar, t.alloc, grammars.ZigGrammar);
    defer grammar.deinit();

    var parser = Parser.init(t.alloc, &grammar);
    defer parser.deinit();

    var debug: DebugInfo = undefined;
    debug.init(t.alloc);
    defer debug.deinit();

    const Config: ParseConfig = .{ .is_incremental = false };
    var res = parser.parseDebug(Config, src, &debug);
    defer res.deinit();

    if (!res.success) {
        str_buf.clearRetainingCapacity();
        res.ast.formatContextAtToken(str_buf.writer(), res.err_token_id);
        log.warn("{s}", .{str_buf.items});

        str_buf.clearRetainingCapacity();
        debug.formatMaxCallStack(Config, &res.ast, str_buf.writer());
        log.warn("{s}", .{str_buf.items});

        try t.fail();
    }

    // buf.clearRetainingCapacity();
    // zig_parser.tokenizer.formatTokens(buf.writer());
    // log.warn("{s}", .{buf.items});

    // buf.clearRetainingCapacity();
    // ast.formatTree(buf.writer());
    // log.warn("{s}", .{buf.items});
    
    const ast = res.ast;
    const stmts = ast.getChildNodeList(ast.mb_root.?, 0);
    try t.eq(stmts.len, 2);

    try t.eqStr(ast.getNodeTagName(stmts[0]), "VariableDecl");
    try t.eqStr(ast.getNodeTagName(stmts[1]), "FunctionDecl");
}

// test "Parse Typescript" {
    // const ts =
    //     \\type Item = {
    //     \\  title: string,
    //     \\  data: any,
    //     \\}
    //     \\function do(arg: string): Item {
    //     \\  if (arg == 'foo') {
    //     \\      return 123;
    //     \\  }
    //     \\}
    //     ;
// }