const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");
const v8 = @import("v8");
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
            \\Starts a limited shell for experimenting.
            \\TODO: Run the shell over the cosmic runtime.
            \\
        );
    }
    {
        // "cosmic http -h" prints out usage.
        const res = runCmd(&.{"cosmic", "http", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic http [dir-path] [port=8081]
            \\
            \\Starts an HTTP server over a public folder at [dir-path].
            \\Default port is 8081.
            \\
        );
    }
    {
        // "cosmic https -h" prints out usage.
        const res = runCmd(&.{"cosmic", "https", "-h"}, .{});
        defer res.deinit();
        try t.eq(res.success, true);
        try t.eqStr(res.stdout,
            \\Usage: cosmic https [dir-path] [public-key-path] [private-key-path] [port=8081]
            \\
            \\Starts an HTTPS server over a public folder at [dir-path].
            \\Must provide a public key and private key to enable a secure communication.
            \\Default port is 8081.
            \\
        );
    }
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

    main.runMain(t.alloc, cmd, &env_) catch {
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