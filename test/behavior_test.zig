const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const runtime = @import("../cosmic/runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const main = @import("../cosmic/main.zig");
const env_ns = @import("../cosmic/env.zig");
const Environment = env_ns.Environment;
const WriterIface = env_ns.WriterIface;
const log = stdx.log.scoped(.behavior_test);

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
        .exit_fn = S.exit,
    };

    main.runMain(cmd, &env_) catch {
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