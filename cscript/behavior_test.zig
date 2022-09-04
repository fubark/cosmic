const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const t = stdx.testing;
const qjs = @import("qjs");

const cs = @import("cscript.zig");
const QJS = cs.QJS;
const log = stdx.log.scoped(.behavior_test);

test "await" {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\fun foo():
        \\  task = @asyncTask()
        \\  @queueTask(fun () => task.resolve(123))
        \\  return task.promise
        \\await foo()
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);

    // await on value.
    val = try run.evaluate(
        \\fun foo():
        \\  return 234
        \\await foo()
    );
    try t.eq(val.getInt32(), 234);
    run.deinitValue(val);
}

test "Indentation." {
    const run = Runner.create();
    defer run.destroy();

    // Detect end of block.
    var val = try run.evaluate(
        \\fun foo():
        \\  return 123
        \\foo()
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);

    // Comment before end of block.
    val = try run.evaluate(
        \\fun foo():
        \\  return 123
        \\  // Comment.
        \\foo()
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);
}

test "Numbers." {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\1
    );
    try t.eq(val.getInt32(), 1);
    run.deinitValue(val);

    val = try run.evaluate(
        \\-1
    );
    try t.eq(val.getInt32(), -1);
    run.deinitValue(val);
}

test "Parentheses" {
    const run = Runner.create();
    defer run.destroy();

    // Parentheses at left of binary expression.
    var val = try run.evaluate(
        \\(2 + 3) * 4
    );
    try t.eq(val.getInt32(), 20);
    run.deinitValue(val);

    // Parentheses at right of binary expression.
    val = try run.evaluate(
        \\2 * (3 + 4)
    );
    try t.eq(val.getInt32(), 14);
    run.deinitValue(val);

    // Nested parentheses.
    val = try run.evaluate(
        \\2 + ((3 + 4) / 7)
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);
}

test "Operator precedence." {
    const run = Runner.create();
    defer run.destroy();

    // Multiplication before addition.
    var val = try run.evaluate(
        \\2 + 3 * 4
    );
    try t.eq(val.getInt32(), 14);
    run.deinitValue(val);
}

test "Comments" {
    const run = Runner.create();
    defer run.destroy();

    // Single line comment.
    var val = try run.evaluate(
        \\// 1
        \\2
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);

    // Multiple single line comments.
    val = try run.evaluate(
        \\// 1
        \\// 2
        \\// 3
        \\4
    );
    try t.eq(val.getInt32(), 4);
    run.deinitValue(val);
}

test "Strings" {
    const run = Runner.create();
    defer run.destroy();

    // Single quotes.
    var val = try run.evaluate(
        \\block:
        \\  str = 'abc'
        \\  str
    );
    var str = try run.valueToString(val);
    try t.eqStr(str, "abc");
    t.alloc.free(str);

    // Unicode.
    val = try run.evaluate(
        \\block:
        \\  str = 'abc🦊xyz🐶'
        \\  str
    );
    str = try run.valueToString(val);
    try t.eqStr(str, "abc🦊xyz🐶");
    t.alloc.free(str);

    // Escape single quote.
    val = try run.evaluate(
        \\block:
        \\  str = 'ab\'c'
        \\  str
    );
    str = try run.valueToString(val);
    try t.eqStr(str, "ab'c");
    t.alloc.free(str);

    // Multi-line backtick literal.
    val = try run.evaluate(
        \\block:
        \\  str = `abc
        \\abc`
        \\  str
    );
    str = try run.valueToString(val);
    try t.eqStr(str, "abc\nabc");
    t.alloc.free(str);
}

test "Dictionairies" {
    const run = Runner.create();
    defer run.destroy();

    // Number entry.
    var val = try run.evaluate(
        \\block:
        \\  a = {
        \\    b: 32
        \\  }
        \\  a.b
    );
    try t.eq(val.getInt32(), 32);
    run.deinitValue(val);

    // String entry.
    val = try run.evaluate(
        \\block:
        \\  a = {
        \\    b: 'hello'
        \\  }
        \\  a.b
    );
    const str = try run.valueToString(val);
    defer t.alloc.free(str);
    try t.eqStr(str, "hello");
    run.deinitValue(val);

    // Nested list.
    val = try run.evaluate(
        \\block:
        \\  a = {
        \\    b: [ 1, 2 ]
        \\  }
        \\  a.b[1]
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);

    // Nested list with items separated by new line.
    val = try run.evaluate(
        \\block:
        \\  a = {
        \\    b: [
        \\      1
        \\      2
        \\    ]
        \\  }
        \\  a.b[1]
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);
}

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
        \\block:
        \\  i = 0
        \\  for:
        \\    i += 1
        \\    if i == 10:
        \\      break
        \\  i
    );
    try t.eq(val.getInt32(), 10);
    run.deinitValue(val);

    // `for` with condition expression.
    val = try run.evaluate(
        \\block:
        \\  i = 0
        \\  for i != 10:
        \\    i += 1
        \\  i
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

test "Function named parameters call." {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\fun foo(a, b):
        \\  return a - b
        \\foo(a: 3, b: 1)
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);

    val = try run.evaluate(
        \\fun foo(a, b):
        \\  return a - b
        \\foo(a: 1, b: 3)
    );
    try t.eq(val.getInt32(), -2);
    run.deinitValue(val);

    // New line as arg separation.
    val = try run.evaluate(
        \\fun foo(a, b):
        \\  return a - b
        \\foo(
        \\  a: 3
        \\  b: 1
        \\)
    );
    try t.eq(val.getInt32(), 2);
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

test "Binary Expressions" {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\1 + 2
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);

    val = try run.evaluate(
        \\3 - 1
    );
    try t.eq(val.getInt32(), 2);
    run.deinitValue(val);

    val = try run.evaluate(
        \\3 * 4
    );
    try t.eq(val.getInt32(), 12);
    run.deinitValue(val);

    val = try run.evaluate(
        \\20 / 5
    );
    try t.eq(val.getInt32(), 4);
    run.deinitValue(val);

    // Right function call.
    val = try run.evaluate(
        \\fun foo():
        \\  return 123
        \\1 + foo()
    );
    try t.eq(val.getInt32(), 124);
    run.deinitValue(val);
}

const qjs_init_js = @embedFile("qjs_init.js");

const Runner = struct {
    parser: cs.Parser,
    compiler: cs.JsTargetCompiler,

    impl: *qjs.JSRuntime,
    ctx: *qjs.JSContext,
    promise: qjs.JSValue,
    watchPromiseFunc: qjs.JSValue,

    tasks: std.ArrayList(qjs.JSValue),
    eval_promise_res: ?qjs.JSValue,

    fn create() *Runner {
        var new = t.alloc.create(Runner) catch fatal();
        new.* = .{
            .parser = cs.Parser.init(t.alloc),
            .compiler = cs.JsTargetCompiler.init(t.alloc),
            .impl = undefined,
            .ctx = undefined,
            .promise = undefined,
            .tasks = std.ArrayList(qjs.JSValue).init(t.alloc),
            .watchPromiseFunc = undefined,
            .eval_promise_res = undefined,
        };
        const rt = qjs.JS_NewRuntime().?;
        new.impl = rt;
        new.ctx = qjs.JS_NewContext(new.impl).?;
        qjs.JS_SetContextOpaque(new.ctx, new);

        const global = qjs.JS_GetGlobalObject(new.ctx);
        defer qjs.JS_FreeValue(new.ctx, global);

        var func = qjs.JS_NewCFunction(new.ctx, queueTask, "queueTask", 1);
        var ret = qjs.JS_SetPropertyStr(new.ctx, global, "queueTask", func);
        if (ret != 1) {
            stdx.panicFmt("set property {}", .{ret});
        }

        new.promise = qjs.JS_GetPropertyStr(new.ctx, global, "Promise");

        // Run qjs_init.js
        const val = cs.JsValue{
            .inner = qjs.JS_Eval(new.ctx, qjs_init_js, qjs_init_js.len, "eval", qjs.JS_EVAL_TYPE_GLOBAL),
        };
        defer qjs.JS_FreeValue(new.ctx, val.inner);
        const val_t = val.getTag(new.ctx);
        if (val_t == .exception) {
            const exception = qjs.JS_GetException(new.ctx);
            const str = qjs.JS_ToCString(new.ctx, exception);
            defer qjs.JS_FreeCString(new.ctx, str);
            stdx.panicFmt("init js exception {s}", .{ str });
        }

        const internal = qjs.JS_GetPropertyStr(new.ctx, global, "_internal");
        defer qjs.JS_FreeValue(new.ctx, internal);
        new.watchPromiseFunc = qjs.JS_GetPropertyStr(new.ctx, internal, "watchPromise");

        func = qjs.JS_NewCFunction(new.ctx, promiseResolved, "promiseResolved", 2);
        ret = qjs.JS_SetPropertyStr(new.ctx, internal, "promiseResolved", func);
        if (ret != 1) {
            stdx.panicFmt("set property {}", .{ret});
        }

        return new;
    }

    fn destroy(self: *Runner) void {
        self.tasks.deinit();
        qjs.JS_FreeValue(self.ctx, self.promise);
        qjs.JS_FreeValue(self.ctx, self.watchPromiseFunc);
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

        const tag = val.getTag(self.ctx);
        if (tag == .exception) {
            const str = try self.getExceptionString(val);
            defer t.alloc.free(str);
            log.err("Runtime exception: {s}", .{str});
            return error.RuntimeError;
        } else {
            self.eval_promise_res = null;
            if (qjs.JS_IsInstanceOf(self.ctx, val.inner, self.promise) == 1) {
                defer qjs.JS_FreeValue(self.ctx, val.inner);
                    
                const id = qjs.JS_NewInt32(self.ctx, 1);
                _ = qjs.JS_Call(self.ctx, self.watchPromiseFunc, qjs.Undefined, 2, &[_]qjs.JSValue{ id, val.inner });
                qjs.js_std_loop(self.ctx);
                if (self.eval_promise_res) |promise_res| {
                    return cs.JsValue{ .inner = promise_res };
                }

                if (self.tasks.items.len == 0) {
                    return error.UnresolvedPromise;
                }
                while (self.tasks.items.len > 0) {
                    const num_tasks = self.tasks.items.len;
                    for (self.tasks.items[0..num_tasks]) |task| {
                        const task_res = qjs.JS_Call(self.ctx, task, qjs.Undefined, 0, null);
                        qjs.JS_FreeValue(self.ctx, task);

                        const task_res_tag = QJS.getTag(self.ctx, task_res);
                        if (task_res_tag == .exception) {
                            const str = try self.getExceptionString(.{ .inner = task_res });
                            defer t.alloc.free(str);
                            log.err("Task exception: {s}", .{str});
                            return error.RuntimeError;
                        }
                        log.debug("call task {}", .{task_res_tag});
                    }
                    try self.tasks.replaceRange(0, num_tasks, &.{});

                    // Deplete event loop.
                    qjs.js_std_loop(self.ctx);

                    if (self.eval_promise_res) |promise_res| {
                        return cs.JsValue{ .inner = promise_res };
                    }
                }
                return error.UnresolvedPromise;
            }
        }
        return val;
    }

    fn deinitValue(self: *Runner, val: cs.JsValue) void {
        qjs.JS_FreeValue(self.ctx, val.inner);
    }

    pub fn valueToString(self: *Runner, val: cs.JsValue) ![]const u8 {
        const str = qjs.JS_ToCString(self.ctx, val.inner);
        defer qjs.JS_FreeCString(self.ctx, str);
        return try t.alloc.dupe(u8, stdx.cstr.spanOrEmpty(str));
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

fn queueTask(ctx: ?*qjs.JSContext, _: qjs.JSValueConst, _: c_int, argv: [*c]qjs.JSValueConst) callconv(.C) qjs.JSValue {
    const runner = stdx.mem.ptrCastAlign(*Runner, qjs.JS_GetContextOpaque(ctx));
    const dupe = qjs.JS_DupValue(runner.ctx, argv[0]);
    runner.tasks.append(dupe) catch fatal();
    log.debug("queued task", .{});
    return qjs.Undefined;
}

fn promiseResolved(ctx: ?*qjs.JSContext, _: qjs.JSValueConst, _: c_int, argv: [*c]qjs.JSValueConst) callconv(.C) qjs.JSValue {
    const runner = stdx.mem.ptrCastAlign(*Runner, qjs.JS_GetContextOpaque(ctx));
    const id = QJS.getInt32(argv[0]);
    _ = id;
    runner.eval_promise_res = qjs.JS_DupValue(runner.ctx, argv[1]);
    return qjs.Undefined;
}