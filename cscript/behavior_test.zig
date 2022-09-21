const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const t = stdx.testing;
const qjs = @import("qjs");

const cs = @import("cscript.zig");
const QJS = cs.QJS;
const log = stdx.log.scoped(.behavior_test);

test "logic operators" {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\false or false
    );
    try t.eq(val.getBool(), false);
    run.deinitValue(val);

    val = try run.evaluate(
        \\false or true
    );
    try t.eq(val.getBool(), true);
    run.deinitValue(val);

    val = try run.evaluate(
        \\false and true
    );
    try t.eq(val.getBool(), false);
    run.deinitValue(val);

    val = try run.evaluate(
        \\true and true
    );
    try t.eq(val.getBool(), true);
    run.deinitValue(val);

    val = try run.evaluate(
        \\not false
    );
    try t.eq(val.getBool(), true);
    run.deinitValue(val);

    val = try run.evaluate(
        \\not true
    );
    try t.eq(val.getBool(), false);
    run.deinitValue(val);
}

test "boolean" {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\true
    );
    try t.eq(val.getBool(), true);
    run.deinitValue(val);

    val = try run.evaluate(
        \\false
    );
    try t.eq(val.getBool(), false);
    run.deinitValue(val);
}

test "@name" {
    const run = Runner.create();
    defer run.destroy();

    const parse_res = try run.parse(
        \\@name foo
    );
    try t.eqStr(parse_res.name, "foo");

    // Compile step skips the statement.
    const compile_res = try run.compile(
        \\@name foo
    );
    try t.eqStr(compile_res.output, "(function () {});");
}

test "implicit await" {
    const run = Runner.create();
    defer run.destroy();

    var val = try run.evaluate(
        \\fun foo() apromise:
        \\  task = @asyncTask()
        \\  @queueTask(fun () => task.resolve(123))
        \\  return task.promise
        \\1 + foo()
    );
    try t.eq(val.getInt32(), 124);
    run.deinitValue(val);
}

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

    // New block requires at least one statement.
    const parse_res = try run.parse(
        \\if true:
        \\return 123 
    );
    try t.eq(parse_res.has_error, true);
    try t.expect(std.mem.indexOf(u8, parse_res.err_msg, "Block requires at least one statement. Use the `pass` statement as a placeholder.") != null);

    // Continue from parent indentation.
    val = try run.evaluate(
        \\fun foo():
        \\  if false:
        \\    pass
        \\  return 123 
        \\foo()
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);

    // Continue from grand parent indentation.
    val = try run.evaluate(
        \\fun foo():
        \\  if false:
        \\    if false:
        \\      pass
        \\  return 123 
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

test "Lists" {
    const run = Runner.create();
    defer run.destroy();

    // Number entry.
    var val = try run.evaluate(
        \\block:
        \\  a = []
        \\  a[2] = 3
        \\  a[2]
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);

    // Start to end index slice.
    val = try run.evaluate(
        \\block:
        \\  a = [1, 2, 3, 4, 5]
        \\  a[1..4]
    );
    var val_slice = try run.valueToIntSlice(val);
    try t.eqSlice(i32, val_slice, &.{ 2, 3, 4 });
    run.deinitValue(val);
    t.alloc.free(val_slice);

    // Start index to end of list.
    val = try run.evaluate(
        \\block:
        \\  a = [1, 2, 3, 4, 5]
        \\  a[3..]
    );
    val_slice = try run.valueToIntSlice(val);
    try t.eqSlice(i32, val_slice, &.{ 4, 5 });
    run.deinitValue(val);
    t.alloc.free(val_slice);

    // Start of list to end index.
    val = try run.evaluate(
        \\block:
        \\  a = [1, 2, 3, 4, 5]
        \\  a[..3]
    );
    val_slice = try run.valueToIntSlice(val);
    try t.eqSlice(i32, val_slice, &.{ 1, 2, 3 });
    run.deinitValue(val);
    t.alloc.free(val_slice);
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

    var val = try run.evaluate(
        \\block:
        \\  foo = true
        \\  if foo then 123 else 456
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);
    val = try run.evaluate(
        \\block:
        \\  foo = false
        \\  if foo then 123 else 456
    );
    try t.eq(val.getInt32(), 456);
    run.deinitValue(val);
}

test "if statement" {
    const run = Runner.create();
    defer run.destroy();

    // If/else.
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

    // elif.
    val = try run.evaluate(
        \\block:
        \\  if false:
        \\    456
        \\  elif true:
        \\    123
        \\  else:
        \\    456
    );
    try t.eq(val.getInt32(), 123);
    run.deinitValue(val);
}

test "Infinite for loop." {
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
}

test "Conditional for loop." {
    const run = Runner.create();
    defer run.destroy();

    // `for` with condition expression.
    var val = try run.evaluate(
        \\block:
        \\  i = 0
        \\  for i != 10:
        \\    i += 1
        \\  i
    );
    try t.eq(val.getInt32(), 10);
    run.deinitValue(val);
}

test "For loop over list." {
    const run = Runner.create();
    defer run.destroy();

    // Basic.
    var val = try run.evaluate(
        \\block:
        \\  list = [1, 2, 3]
        \\  sum = 0
        \\  for list as it:
        \\     sum += it
        \\  sum
    );
    try t.eq(val.getInt32(), 6);
    run.deinitValue(val);
}

test "For loop over range." {
    const run = Runner.create();
    defer run.destroy();

    // Basic.
    var val = try run.evaluate(
        \\block:
        \\  iters = 0
        \\  for 0..10 as i:
        \\     iters += 1
        \\  iters
    );
    try t.eq(val.getInt32(), 10);
    run.deinitValue(val);

    // two `for` with range don't interfere with each other
    val = try run.evaluate(
        \\block:
        \\  iters = 0
        \\  for 0..10 as i:
        \\     iters += 1
        \\  for 0..10 as i:
        \\     iters += 1
        \\  iters
    );
    try t.eq(val.getInt32(), 20);
    run.deinitValue(val);

    // two `for` with non const max value don't interfere with each other
    val = try run.evaluate(
        \\block:
        \\  foo = 10
        \\  iters = 0
        \\  for 0..foo as i:
        \\     iters += 1
        \\  for 0..foo as i:
        \\     iters += 1
        \\  iters
    );
    try t.eq(val.getInt32(), 20);
    run.deinitValue(val);

    // Increment by step.
    val = try run.evaluate(
        \\block:
        \\  iters = 0
        \\  for 0..10 as i += 3:
        \\     iters += 1
        \\  iters
    );
    try t.eq(val.getInt32(), 4);
    run.deinitValue(val);

    // Increment by non const step value. Two loops after another.
    val = try run.evaluate(
        \\block:
        \\  iters = 0
        \\  step = 3
        \\  for 0..10 as i += step:
        \\     iters += 1
        \\  for 0..10 as i += step:
        \\     iters += 1
        \\  iters
    );
    try t.eq(val.getInt32(), 8);
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

test "Lambdas" {
    const run = Runner.create();
    defer run.destroy();

    // Lambda with no params.
    var val = try run.evaluate(
        \\foo = fun () => 2 + 2
        \\foo()
    );
    try t.eq(val.getInt32(), 4);
    run.deinitValue(val);

    // Lambda with one param.
    val = try run.evaluate(
        \\foo = fun (bar) => bar + 2
        \\foo(1)
    );
    try t.eq(val.getInt32(), 3);
    run.deinitValue(val);

    // Lambda with multiple param.
    val = try run.evaluate(
        \\foo = fun (bar, inc) => bar + inc
        \\foo(20, 10)
    );
    try t.eq(val.getInt32(), 30);
    run.deinitValue(val);

    // Lambda assign declaration.
    val = try run.evaluate(
        \\foo = {}
        \\fun foo.bar():
        \\  return 2
        \\foo.bar()
    );
    try t.eq(val.getInt32(), 2);
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
        \\1 + 2 + 3
    );
    try t.eq(val.getInt32(), 6);
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

    // Modulus
    val = try run.evaluate(
        \\3 % 2
    );
    try t.eq(val.getInt32(), 1);
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

    engine: cs.JsEngine,
    promise: qjs.JSValue,
    watchPromiseFunc: qjs.JSValue,
    evalGeneratorSrcFunc: qjs.JSValue,

    tasks: std.ArrayList(qjs.JSValue),
    eval_promise_res: ?qjs.JSValue,

    fn create() *Runner {
        var new = t.alloc.create(Runner) catch fatal();
        new.* = .{
            .parser = cs.Parser.init(t.alloc),
            .compiler = undefined,
            .engine = cs.JsEngine.init(t.alloc),
            .promise = undefined,
            .tasks = std.ArrayList(qjs.JSValue).init(t.alloc),
            .watchPromiseFunc = undefined,
            .evalGeneratorSrcFunc = undefined,
            .eval_promise_res = undefined,
        };
        new.compiler.init(t.alloc);
        const engine = &new.engine;
        const ctx = new.engine.inner.ctx;
        qjs.JS_SetContextOpaque(ctx, new);

        const global = qjs.JS_GetGlobalObject(ctx);
        defer qjs.JS_FreeValue(ctx, global);

        new.promise = qjs.JS_GetPropertyStr(ctx, global, "Promise");

        // Run qjs_init.js
        const val = cs.JsValue{
            .inner = qjs.JS_Eval(ctx, qjs_init_js, qjs_init_js.len, "eval", qjs.JS_EVAL_TYPE_GLOBAL),
        };
        defer qjs.JS_FreeValue(ctx, val.inner);
        const val_t = engine.getValueTag(val);
        if (val_t == .exception) {
            const exception = qjs.JS_GetException(ctx);
            const str = qjs.JS_ToCString(ctx, exception);
            defer qjs.JS_FreeCString(ctx, str);
            stdx.panicFmt("init js exception {s}", .{ str });
        }

        const internal = qjs.JS_GetPropertyStr(ctx, global, "_internal");
        defer qjs.JS_FreeValue(ctx, internal);
        new.watchPromiseFunc = qjs.JS_GetPropertyStr(ctx, internal, "watchPromise");
        new.evalGeneratorSrcFunc = qjs.JS_GetPropertyStr(ctx, internal, "evalGeneratorSrc");

        var func = qjs.JS_NewCFunction(ctx, promiseResolved, "promiseResolved", 2);
        var ret = qjs.JS_SetPropertyStr(ctx, internal, "promiseResolved", func);
        if (ret != 1) {
            stdx.panicFmt("set property {}", .{ret});
        }

        func = qjs.JS_NewCFunction(ctx, runEventLoop, "runEventLoop", 0);
        ret = qjs.JS_SetPropertyStr(ctx, internal, "runEventLoop", func);
        if (ret != 1) {
            stdx.panicFmt("set property {}", .{ret});
        }

        return new;
    }

    fn destroy(self: *Runner) void {
        self.tasks.deinit();

        const ctx = self.engine.inner.ctx;
        qjs.JS_FreeValue(ctx, self.promise);
        qjs.JS_FreeValue(ctx, self.watchPromiseFunc);
        qjs.JS_FreeValue(ctx, self.evalGeneratorSrcFunc);
        self.engine.deinit();
        self.parser.deinit();
        self.compiler.deinit();
        t.alloc.destroy(self);
    }

    fn parse(self: *Runner, src: []const u8) !cs.ParseResultView {
        return try self.parser.parse(src);
    }

    fn compile(self: *Runner, src: []const u8) !cs.JsTargetResultView {
        const ast_res = try self.parser.parse(src);
        if (ast_res.has_error) {
            log.debug("Parse Error: {s}", .{ast_res.err_msg});
            return error.ParseError;
        }
        return try self.compiler.compile(ast_res, .{ .wrap_in_func = true });
    }

    fn evaluate(self: *Runner, src: []const u8) !cs.JsValue {
        const ast_res = try self.parser.parse(src);
        if (ast_res.has_error) {
            log.debug("Parse Error: {s}", .{ast_res.err_msg});
            return error.ParseError;
        }

        const res = try self.compiler.compile(ast_res, .{});
        if (res.has_error) {
            log.debug("Compile Error: {s}", .{res.err_msg});
            return error.CompileError;
        }

        log.debug("out: {s}", .{res.output});

        const ctx = self.engine.inner.ctx;

        const csrc = try std.cstr.addNullByte(t.alloc, res.output);
        defer t.alloc.free(csrc);

        if (res.wrapped_in_generator) {
            const js_src = qjs.JS_NewStringLen(ctx, res.output.ptr, res.output.len);
            const val = cs.JsValue{
                .inner = qjs.JS_Call(ctx, self.evalGeneratorSrcFunc, qjs.Undefined, 1, &[_]qjs.JSValue{ js_src }),
            };
            const tag = self.engine.getValueTag(val);
            if (tag == .exception) {
                const str = try self.getExceptionString(val);
                defer t.alloc.free(str);
                log.err("Runtime exception: {s}", .{str});
                return error.RuntimeError;
            }
            return val;
        }

        const val = self.engine.eval(csrc);
        const tag = self.engine.getValueTag(val);
        if (tag == .exception) {
            const str = try self.getExceptionString(val);
            defer t.alloc.free(str);
            log.err("Runtime exception: {s}", .{str});
            return error.RuntimeError;
        } else {
            self.eval_promise_res = null;
            if (qjs.JS_IsInstanceOf(ctx, val.inner, self.promise) == 1) {
                defer qjs.JS_FreeValue(ctx, val.inner);
                    
                const id = qjs.JS_NewInt32(ctx, 1);
                _ = qjs.JS_Call(ctx, self.watchPromiseFunc, qjs.Undefined, 2, &[_]qjs.JSValue{ id, val.inner });
                qjs.js_std_loop(ctx);
                if (self.eval_promise_res) |promise_res| {
                    return cs.JsValue{ .inner = promise_res };
                }

                if (self.tasks.items.len == 0) {
                    return error.UnresolvedPromise;
                }
                while (self.tasks.items.len > 0) {
                    const num_tasks = self.tasks.items.len;
                    for (self.tasks.items[0..num_tasks]) |task| {
                        const task_res = qjs.JS_Call(ctx, task, qjs.Undefined, 0, null);
                        qjs.JS_FreeValue(ctx, task);

                        const task_res_tag = QJS.getTag(ctx, task_res);
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
                    qjs.js_std_loop(ctx);

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
        self.engine.deinitValue(val);
    }

    pub fn valueToString(self: *Runner, val: cs.JsValue) ![]const u8 {
        return self.engine.valueToString(val);
    }

    pub fn valueToIntSlice(self: *Runner, val: cs.JsValue) ![]const i32 {
        return self.engine.valueToIntSlice(val);
    }

    pub fn getExceptionString(self: *Runner, val: cs.JsValue) ![]const u8 {
        // Assumes val is the exception of last execution.
        _ = val;
        const ctx = self.engine.inner.ctx;
        const exception = qjs.JS_GetException(ctx);
        defer qjs.JS_FreeValue(ctx, exception);

        return self.engine.valueToString(.{ .inner = exception });
    }
};

fn promiseResolved(ctx: ?*qjs.JSContext, _: qjs.JSValueConst, _: c_int, argv: [*c]qjs.JSValueConst) callconv(.C) qjs.JSValue {
    const runner = stdx.mem.ptrCastAlign(*Runner, qjs.JS_GetContextOpaque(ctx));
    const id = QJS.getInt32(argv[0]);
    _ = id;
    const js_ctx = runner.engine.inner.ctx;
    runner.eval_promise_res = qjs.JS_DupValue(js_ctx, argv[1]);
    return qjs.Undefined;
}

fn runEventLoop(ctx: ?*qjs.JSContext, _: qjs.JSValueConst, _: c_int, argv: [*c]qjs.JSValueConst) callconv(.C) qjs.JSValue {
    _ = argv;
    const runner = stdx.mem.ptrCastAlign(*Runner, qjs.JS_GetContextOpaque(ctx));
    const js_ctx = runner.engine.inner.ctx;
    qjs.js_std_loop(js_ctx);
    return qjs.Undefined;
}