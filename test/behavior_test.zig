const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");
const v8 = @import("v8");
const t = stdx.testing;
const uv = @import("uv");

const runtime = @import("../runtime/runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const main = @import("../runtime/main.zig");
const env_ns = @import("../runtime/env.zig");
const Environment = env_ns.Environment;
const WriterIface = env_ns.WriterIface;
const log = stdx.log.scoped(.behavior_test);
const adapter = @import("../runtime/adapter.zig");
const FuncDataUserPtr = adapter.FuncDataUserPtr;

// For tests that need to verify what the runtime is doing.
// Not completely E2E tests (eg. writing to stderr is intercepted) but close enough.
// For js behavior tests, see test/js.

test "behavior: JS syntax error prints stack trace to stderr" {
    {
        const res = runScript(
            \\class {
        );
        defer res.deinit();
        try t.eq(res.success, false);
        try t.eqStr(res.stderr,
            \\class {
            \\      ^
            \\Uncaught SyntaxError: Unexpected token '{'
            \\    at /test.js:1:6
            \\
        );
    }
    {
        // Case where v8 returns the same message start/end column indicator.
        const res = runScript(
            \\class Foo {
            \\    x: 0
        );
        defer res.deinit();
        try t.eq(res.success, false);
        try t.eqStr(res.stderr,
            \\    x: 0
            \\    ^
            \\Uncaught SyntaxError: Unexpected identifier
            \\    at /test.js:2:4
            \\
        );
    }
}

test "behavior: JS main script runtime error prints stack trace to stderr" {
    {
        const res = runScript(
            \\foo
        );
        defer res.deinit();
        try t.eq(res.success, false);
        try t.eqStr(res.stderr,
            \\ReferenceError: foo is not defined
            \\    at /test.js:1:1
            \\
        );
    }
    {
        // Async stack trace chain that fails in native async function.
        const res = runScript(
            \\async function foo2() {
            \\    await cs.files.getPathInfoAsync('does_not_exist')
            \\}
            \\async function foo1() {
            \\    await foo2()
            \\}
            \\await foo1()
        );
        defer res.deinit();
        try t.eq(res.success, true);
        var first_frame: []const u8 = undefined;
        defer t.alloc.free(first_frame);
        const stderr_rest = extractLine(res.stderr, 1, &first_frame);
        defer t.alloc.free(stderr_rest);
        try t.expect(std.mem.startsWith(u8, first_frame, "    at cs.files.getPathInfoAsync gen_api.js"));
        try t.eqStr(stderr_rest,
            \\ApiError: FileNotFound
            \\    at async foo2 /test.js:2:5
            \\    at async foo1 /test.js:5:5
            \\    at async /test.js:7:1
            \\
        );
    }
}

test "behavior: puts, print, dump prints to stdout" {
    const res = runScript(
        \\puts('foo')
        \\puts({ a: 123 })
        \\print('foo\n')
        \\print({ a: 123 }, '\n')
        \\dump('foo')
        \\dump({ a: 123 })
        \\dump(function foo() {})
        \\dump(() => {})
    );
    defer res.deinit();
    try t.eq(res.success, true);

    // puts should print the value as a string.
    // print should print the value as a string.
    // dump should print the value as a descriptive string.
    try t.eqStr(res.stdout,
        \\foo
        \\[object Object]
        \\foo
        \\[object Object] 
        \\"foo"
        \\{ a: 123 }
        \\(Function: foo)
        \\(Function)
        \\
    );
}

test "behavior: CLI help, version, command usages." {
    {
        // "cosmic" prints out main usage.
        const res = runCmd(&.{"cosmic"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.expect(std.mem.startsWith(u8, res.stdout, "Usage: cosmic [command] [options]"));
    }
    {
        // "cosmic help" prints out main usage.
        const res = runCmd(&.{"cosmic", "help"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.expect(std.mem.startsWith(u8, res.stdout, "Usage: cosmic [command] [options]"));
    }
    {
        // "cosmic version" prints out the version and v8 version.
        const res = runCmd(&.{"cosmic", "version"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        const exp_version = try std.fmt.allocPrint(t.alloc, 
            \\cosmic {s}
            \\v8 {s}
            \\
            , .{ build_options.VersionName, v8.getVersion() }
        );
        defer t.alloc.free(exp_version);
        try t.eqStr(res.stdout, exp_version);
    }
    {
        // "cosmic run -h" prints out usage.
        const res = runCmd(&.{"cosmic", "run", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic run [src-path]
            \\       cosmic [src-path]
            \\
            \\Flags:
            \\  --test-api   Include the cs.test api.
            \\
            \\Run a js file.
            \\
        );
    }
    {
        // "cosmic run --help" prints out usage.
        const res = runCmd(&.{"cosmic", "run", "--help"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic run [src-path]
            \\       cosmic [src-path]
            \\
            \\Flags:
            \\  --test-api   Include the cs.test api.
            \\
            \\Run a js file.
            \\
        );
    }
    {
        // "cosmic dev -h" prints out usage.
        const res = runCmd(&.{"cosmic", "dev", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic dev [src-path]
            \\
            \\Flags:
            \\  --test-api   Include the cs.test api.
            \\
            \\Run a js file in dev mode.
            \\Dev mode enables hot reloading of your scripts whenever they are modified.
            \\It also includes a HUD for viewing debug output and running commands.
            \\
        );
    }
    {
        // "cosmic test -h" prints out usage.
        const res = runCmd(&.{"cosmic", "test", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic test [src-path]
            \\
            \\Run a js file with the test runner.
            \\Test runner also includes an additional API module `cs.test`
            \\which is not available during normal execution with `cosmic run`.
            \\A short test report will be printed at the end.
            \\Any test failure will result in a non 0 exit code.
            \\
        );
    }
    {
        // "cosmic shell -h" prints out usage.
        const res = runCmd(&.{"cosmic", "shell", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic shell
            \\
            \\Starts the runtime with an interactive shell.
            \\TODO: Support window API in the shell.
            \\
        );
    }
    {
        // "cosmic http -h" prints out usage.
        const res = runCmd(&.{"cosmic", "http", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic http [dir-path] [addr=127.0.0.1:8081]
            \\
            \\Starts an HTTP server binding to the address [addr] and serve files from the public directory root at [dir-path].
            \\[addr] contains a host and port separated by `:`. The host is optional and defaults to `127.0.0.1`.
            \\The port is optional and defaults to 8081.
            \\
        );
    }
    {
        // "cosmic https -h" prints out usage.
        const res = runCmd(&.{"cosmic", "https", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic https [dir-path] [public-key-path] [private-key-path] [port=127.0.0.1:8081]
            \\
            \\Starts an HTTPS server binding to the address [addr] and serve files from the public directory root at [dir-path].
            \\Paths to public and private keys must be absolute or relative to the public root path.
            \\[addr] contains a host and port separated by `:`. The host is optional and defaults to `127.0.0.1`.
            \\The port is optional and defaults to 8081.
            \\
        );
    }
}

test "behavior: 'cosmic http' starts server with 'localhost' as host address." {
    const cwd = try std.fs.path.resolve(t.alloc, &.{});
    defer {
        std.os.chdir(cwd) catch unreachable;
        t.alloc.free(cwd);
    }

    const S = struct {
        fn onMainScriptDone(_: ?*anyopaque, rt: *RuntimeContext) !void {
            defer rt.requestShutdown();

            const ids = rt.allocResourceIdsByTag(.CsHttpServer);
            defer rt.alloc.free(ids);

            try t.eq(ids.len, 1);
            const server = rt.getResourcePtr(.CsHttpServer, ids[0]).?;
            const addr = server.allocBindAddress(rt.alloc);
            defer addr.deinit(rt.alloc);
            try t.eqStr(addr.host, "127.0.0.1");
            try t.eq(addr.port, 8081);
        }
    };

    const res = runCmd(&.{"cosmic", "http", "./test/assets", "localhost:8081"}, .{
        .on_main_script_done = S.onMainScriptDone,
    });
    defer res.deinit();

    try t.eq(res.success, true);
    try t.eqStr(res.stdout,
        \\HTTP server started. Binded to 127.0.0.1:8081.
        \\
    );
}

test "behavior: 'cosmic http' starts an HTTP server and handles request" {
    const cwd = try std.fs.path.resolve(t.alloc, &.{});
    defer {
        std.os.chdir(cwd) catch unreachable;
        t.alloc.free(cwd);
    }

    const Context = struct {
        const Self = @This();

        passed: bool = false,
    };
    var ctx: Context = .{};

    const S = struct {
        fn onMainScriptDone(ptr: ?*anyopaque, rt: *RuntimeContext) !void {
            const ctx_ = stdx.ptrCastAlign(*Context, ptr);
            var res = rt.evalModuleScript(
                \\const res = await cs.http.getAsync('http://localhost:8081/index.html')
                \\cs.test.eq(res, `<html>
                \\<head>
                \\    <link rel="stylesheet" href="style.css">
                \\</head>
                \\<body>
                \\    <img src="logo.png" />
                \\    <p>Hello World!</p>
                \\</body>
                \\</html>
                \\`)
            ) catch unreachable;
            defer res.deinit(rt.alloc);

            rt.attachPromiseHandlers(res.eval.?.inner, ctx_, onEvalSuccess, onEvalFailure) catch unreachable;
        }
        fn onEvalSuccess(ctx_: *Context, rt: *RuntimeContext, _: v8.Value) void {
            ctx_.passed = true;
            rt.requestShutdown();
        }
        // fn onEvalFailure(ctx_: FuncDataUserPtr(*Context), rt: *RuntimeContext, err: v8.Value) void {
        fn onEvalFailure(ctx_: *Context, rt: *RuntimeContext, err: v8.Value) void {
            const trace_str = runtime.allocExceptionJsStackTraceString(rt, err);
            defer rt.alloc.free(trace_str);
            rt.env.errorFmt("{s}", .{trace_str});

            ctx_.passed = false;
            rt.requestShutdown();
        }
    };

    const res = runCmd(&.{"cosmic", "http", "./test/assets", ":8081"}, .{
        .on_main_script_done = S.onMainScriptDone,
        .on_main_script_done_ctx = &ctx,
    });
    defer res.deinit();

    try t.eq(res.success, true);
    try t.eq(ctx.passed, true);
    try t.eqStr(res.stdout,
        \\HTTP server started. Binded to 127.0.0.1:8081.
        \\GET /index.html [200]
        \\
    );
}

test "behavior: 'cosmic https' starts an HTTPS server and handles request." {
    const cwd = try std.fs.path.resolve(t.alloc, &.{});
    defer {
        std.os.chdir(cwd) catch unreachable;
        t.alloc.free(cwd);
    }

    const Context = struct {
        const Self = @This();

        passed: bool = false,
    };
    var ctx: Context = .{};

    const S = struct {
        fn onMainScriptDone(ptr: ?*anyopaque, rt: *RuntimeContext) !void {
            const ctx_ = stdx.ptrCastAlign(*Context, ptr);
            var res = rt.evalModuleScript(
                \\const res = await cs.http.requestAsync('https://localhost:8081/index.html', {
                \\    certFile: './localhost.crt',
                \\})
                \\cs.test.eq(res.body, `<html>
                \\<head>
                \\    <link rel="stylesheet" href="style.css">
                \\</head>
                \\<body>
                \\    <img src="logo.png" />
                \\    <p>Hello World!</p>
                \\</body>
                \\</html>
                \\`)
            ) catch unreachable;
            defer res.deinit(rt.alloc);

            rt.attachPromiseHandlers(res.eval.?.inner, ctx_, onEvalSuccess, onEvalFailure) catch unreachable;
        }
        fn onEvalSuccess(ctx_: *Context, rt: *RuntimeContext, _: v8.Value) void {
            ctx_.passed = true;
            rt.requestShutdown();
        }
        // fn onEvalFailure(ctx_: FuncDataUserPtr(*Context), rt: *RuntimeContext, err: v8.Value) void {
        fn onEvalFailure(ctx_: *Context, rt: *RuntimeContext, err: v8.Value) void {
            const trace_str = runtime.allocExceptionJsStackTraceString(rt, err);
            defer rt.alloc.free(trace_str);
            rt.env.errorFmt("{s}", .{trace_str});

            ctx_.passed = false;
            rt.requestShutdown();
        }
    };

    const res = runCmd(&.{"cosmic", "https", "./test/assets", "./localhost.crt", "./localhost.key", ":8081"}, .{
        .on_main_script_done = S.onMainScriptDone,
        .on_main_script_done_ctx = &ctx,
    });
    defer res.deinit();

    try t.eq(res.success, true);
    try t.eq(ctx.passed, true);
    try t.eqStr(res.stdout,
        \\HTTPS server started. Binded to 127.0.0.1:8081.
        \\GET /index.html [200]
        \\
    );
}

const RunResult = struct {
    const Self = @This();

    success: bool,
    stdout: []const u8,
    stderr: []const u8,

    fn deinit(self: Self) void {
        t.alloc.free(self.stdout);
        t.alloc.free(self.stderr);
    }
};

fn runCmd(cmd: []const []const u8, env: Environment) RunResult {
    var stdout_capture = std.ArrayList(u8).init(t.alloc);
    var stdout_writer = stdout_capture.writer();
    var stderr_capture = std.ArrayList(u8).init(t.alloc);
    var stderr_writer = stderr_capture.writer();
    var success = true;

    const S = struct {
        fn exit(code: u8) void {
            _ = code;
            // Nop.
        }
    };

    var env_ = Environment{
        .main_script_override = env.main_script_override,
        .main_script_origin = "/test.js",
        .err_writer = WriterIface.init(&stderr_writer),
        .out_writer = WriterIface.init(&stdout_writer),
        .on_main_script_done = env.on_main_script_done,
        .on_main_script_done_ctx = env.on_main_script_done_ctx,
        .exit_fn = S.exit,
        .pump_rt_on_graceful_shutdown = true,
    };
    defer env_.deinit(t.alloc);

    main.runMain(t.alloc, cmd, &env_) catch |err| {
        std.debug.print("run error: {}\n", .{err});
        success = false;
    };
    return RunResult{
        .success = success,
        .stdout = stdout_capture.toOwnedSlice(),
        .stderr = stderr_capture.toOwnedSlice(),
    };
}

fn runScript(source: []const u8) RunResult {
    return runCmd(&.{"cosmic", "test.js"}, .{
        .main_script_override = source,
    });
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}

fn extractLine(str: []const u8, idx: u32, out: *[]const u8) []const u8 {
    var iter = std.mem.split(u8, str, "\n");
    var rest = std.ArrayList([]const u8).init(t.alloc);
    defer rest.deinit();
    var i: u32 = 0;
    while (iter.next()) |line| {
        if (i == idx) {
            out.* = t.alloc.dupe(u8, line) catch unreachable;
        } else {
            rest.append(line) catch unreachable;
        }
        i += 1;
    }
    return std.mem.join(t.alloc, "\n", rest.items) catch unreachable;
}