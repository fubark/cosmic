const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const t = stdx.testing;
const qjs = @import("qjs");

const cs = @import("cscript.zig");
const log = stdx.log.scoped(.behavior_test);

test "variables" {
    const run = Runner.create();
    defer run.destroy();

    // Variable declaration.
    var val = try run.evaluate(
        \\block:
        \\  a = 1
        \\  a
    );
    try t.eq(val.getInt32(), 1);
    run.deinitValue(val);

    // Overwrite existing var.
    val = try run.evaluate(
        \\block:
        \\  a = 1
        \\  a = 2
        \\  a
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);

    // Use existing var.
    val = try run.evaluate(
        \\block:
        \\  a = 1
        \\  b = a + 2
        \\  b
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);
}

test "if expression" {
    const run = Runner.create();
    defer run.destroy();

    // Same line, single expression.
    // TODO: Implement if expr in one line.
    var val = try run.evaluate(
        \\block:
        \\  foo = true
        \\  if foo:
        \\    123
        \\  else:
        \\    456
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);
    val = try run.evaluate(
        \\block:
        \\  foo = false
        \\  if foo:
        \\    123
        \\  else:
        \\    456
    );
    try t.eq(val.getInt32(), 456);
    run.deinitValue(val);
}

test "for statement" {
    const run = Runner.create();
    defer run.destroy();

    // Infinite loop clause.
    var val = try run.evaluate(
        \\i = 0
        \\for:
        \\    i += 1
        \\    if i == 10:
        \\        break
        \\i
    );
    try t.eq(val.getInt32(), 10);
    run.deinitValue(val);
}

test "function declaration" {
    const run = Runner.create();
    defer run.destroy();

    // Function with no params.
    var val = try run.evaluate(
        \\fun foo():
        \\    return 2 + 2
        \\foo()
    );
    try t.eq(val.getInt32(), 4);
    run.deinitValue(val);

    // Function with one param.
    val = try run.evaluate(
        \\fun foo(bar):
        \\    return bar + 2
        \\foo(1)
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);

    // Function with multiple param.
    val = try run.evaluate(
        \\fun foo(bar, inc):
        \\    return bar + inc
        \\foo(20, 10)
    );
    try t.eq(val.getInt32(), 30);
    run.deinitValue(val);
}

test "access expression" {
    const run = Runner.create();
    defer run.destroy();

    // One level of access from parent.
    var val = try run.evaluate(
        \\block:
        \\  dict = { a: fun () => 5 }
        \\  dict.a()
    );
    try t.eq(val.getInt32(), 5);
    run.deinitValue(val);

    // Multiple levels of access from parent.
    val = try run.evaluate(
        \\block:
        \\  dict = { a: { b: fun () => 5 } }
        \\  dict.a.b()
    );
    try t.eq(val.getInt32(), 5);
    run.deinitValue(val);
}

const Runner = struct {
    parser: cs.Parser,
    compiler: cs.JsTargetCompiler,

    impl: *qjs.JSRuntime,
    ctx: *qjs.JSContext,

    fn create() *Runner {
        var new = t.alloc.create(Runner) catch fatal();
        new.* = .{
            .parser = cs.Parser.init(t.alloc),
            .compiler = cs.JsTargetCompiler.init(t.alloc),
            .impl = undefined,
            .ctx = undefined,
        };
        new.impl = qjs.JS_NewRuntime().?;
        new.ctx = qjs.JS_NewContext(new.impl).?;
        return new;
    }

    fn destroy(self: *Runner) void {
        qjs.JS_FreeContext(self.ctx);
        qjs.JS_FreeRuntime(self.impl);
        self.parser.deinit();
        self.compiler.deinit();
        t.alloc.destroy(self);
    }

    fn evaluate(self: *Runner, src: []const u8) !cs.JsValue {
        const ast_res = self.parser.parse(src);
        if (ast_res.has_error) {
            log.debug("Parse Error: {s}", .{ast_res.err_msg});
            return error.ParseError;
        }

        const res = self.compiler.compile(ast_res, .{});
        if (res.has_error) {
            log.debug("Compile Error: {s}", .{res.err_msg});
            return error.CompileError;
        }

        log.debug("out: {s}", .{res.output});

        const csrc = try std.cstr.addNullByte(t.alloc, res.output);
        defer t.alloc.free(csrc);
        const val = cs.JsValue{
            .inner = qjs.JS_Eval(self.ctx, csrc.ptr, csrc.len, "eval", qjs.JS_EVAL_TYPE_GLOBAL),
        };
        if (val.getTag(self.ctx) == .exception) {
            const str = try self.getExceptionString(val);
            defer t.alloc.free(str);
            log.err("Runtime exception: {s}", .{str});
            return error.RuntimeError;
        }
        return val;
    }

    fn deinitValue(self: *Runner, val: cs.JsValue) void {
        qjs.JS_FreeValue(self.ctx, val.inner);
    }

    pub fn valueToString(self: *Runner, val: cs.JsValue) ![]const u8 {
        const str = qjs.JS_ToCString(self.ctx, val.inner);
        defer qjs.JS_FreeCString(self.ctx, str);
        return try self.alloc.dupe(u8, stdx.cstr.spanOrEmpty(str));
    }

    pub fn getExceptionString(self: *Runner, val: cs.JsValue) ![]const u8 {
        // Assumes val is the exception of last execution.
        _ = val;
        const exception = qjs.JS_GetException(self.ctx);
        defer qjs.JS_FreeValue(self.ctx, exception);
        const str = qjs.JS_ToCString(self.ctx, exception);
        defer qjs.JS_FreeCString(self.ctx, str);
        return try t.alloc.dupe(u8, stdx.cstr.spanOrEmpty(str));
    }
};