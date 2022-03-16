const std = @import("std");
const process = std.process;
const stdx = @import("stdx");
const string = stdx.string;
const ds = stdx.ds;
const graphics = @import("graphics");
const Color = graphics.Color;
const sdl = @import("sdl");
const v8 = @import("v8");
const build_options = @import("build_options");

const v8x = @import("v8x.zig");
const js_env = @import("js_env.zig");
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const log = stdx.log.scoped(.main);
const Environment = @import("env.zig").Environment;

// Cosmic main. Common entry point for cli and gui.
pub fn main() !void {
    // Fast temporary memory allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    var env = Environment{};
    try runMain(args, &env);
}

// main is extracted with cli args and options to facilitate testing.
pub fn runMain(args: []const []const u8, env: *Environment) !void {
    if (args.len == 1) {
        repl(env);
        env.exit(0);
        return;
    }

    // Skip exe path arg.
    var arg_idx: usize = 1;

    const cmd = nextArg(args, &arg_idx).?;
    if (string.eq(cmd, "cli")) {
        repl(env);
        env.exit(0);
    } else if (string.eq(cmd, "dev")) {
        const src_path = nextArg(args, &arg_idx) orelse {
            env.abortFmt("Expected path to main source file.", .{});
            return;
        };
        try runAndExit(src_path, true, env);
    } else if (string.eq(cmd, "run")) {
        const src_path = nextArg(args, &arg_idx) orelse {
            env.abortFmt("Expected path to main source file.", .{});
            return;
        };
        try runAndExit(src_path, false, env);
    } else if (string.eq(cmd, "test")) {
        const src_path = nextArg(args, &arg_idx) orelse {
            env.abortFmt("Expected path to main source file.", .{});
            return;
        };
        try testAndExit(src_path, env);
    } else if (string.eq(cmd, "help")) {
        usage(env);
        env.exit(0);
    } else if (string.eq(cmd, "version")) {
        version(env);
        env.exit(0);
    } else if (string.eq(cmd, "shell")) {
        repl(env);
        env.exit(0);
    } else {
        // Assume param is a js file.
        const src_path = cmd;
        try runAndExit(src_path, false, env);
    }
}

fn testAndExit(src_path: []const u8, env: *Environment) !void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    const passed = runtime.runTestMain(alloc, src_path, env) catch |err| {
        stdx.heap.deinitDefaultAllocator();
        if (err == error.FileNotFound) {
            env.abortFmt("File not found: {s}", .{src_path});
        } else {
            env.abortFmt("Encountered error: {}", .{err});
        }
        return;
    };
    stdx.heap.deinitDefaultAllocator();
    if (passed) {
        env.exit(0);
    } else {
        env.exit(1);
    }
}

fn runAndExit(src_path: []const u8, dev_mode: bool, env: *Environment) !void {
    const alloc = stdx.heap.getDefaultAllocator();

    runtime.runUserMain(alloc, src_path, dev_mode, env) catch |err| {
        stdx.heap.deinitDefaultAllocator();
        switch (err) {
            error.FileNotFound => env.abortFmt("File not found: {s}", .{src_path}),
            error.MainScriptError => {},
            else => env.abortFmt("Encountered error: {}", .{err}),
        }
        return err;
    };
    stdx.heap.deinitDefaultAllocator();
    env.exit(0);
}

fn repl(env: *Environment) void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    var input_buf = std.ArrayList(u8).init(alloc);
    defer input_buf.deinit();

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    defer v8.deinitV8Platform();

    v8.initV8();
    defer _ = v8.deinitV8();

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var iso = v8.Isolate.init(&params);
    defer iso.deinit();

    iso.enter();
    defer iso.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var ctx = iso.initContext(null, null);
    ctx.enter();
    defer ctx.exit();

    const origin = iso.initStringUtf8("(shell)");

    env.printFmt(
        \\Cosmic ({s})
        \\exit with Ctrl+D or "exit()"
        \\
    , .{build_options.VersionName});

    while (true) {
        env.printFmt("\n> ", .{});
        if (getInput(&input_buf)) |input| {
            if (string.eq(input, "exit()")) {
                break;
            }

            var res: v8x.ExecuteResult = undefined;
            defer res.deinit();
            v8x.executeString(alloc, iso, ctx, input, origin, &res);
            if (res.success) {
                env.printFmt("{s}", .{res.result.?});
            } else {
                env.printFmt("{s}", .{res.err.?});
            }

            while (platform.pumpMessageLoop(iso, false)) {
                @panic("Did not expect v8 event loop task");
            }
            // log.info("input: {s}", .{input});
        } else {
            env.printFmt("\n", .{});
            return;
        }
    }
}

// TODO: We'll need to support extended key bindings/ncurses (eg. up arrow for last command) per platform.
// (Low priority since there will be a repl in the GUI)
fn getInput(input_buf: *std.ArrayList(u8)) ?[]const u8 {
    input_buf.clearRetainingCapacity();
    std.io.getStdIn().reader().readUntilDelimiterArrayList(input_buf, '\n', 1e9) catch |err| {
        if (err == error.EndOfStream) {
            return null;
        } else {
            unreachable;
        }
    };
    return input_buf.items;
}

const main_usage =
    \\Usage: cosmic [command] [options]
    \\
    \\Commands:
    \\
    \\  dev              Starts dev mode on a JS source file.
    \\  cli              Starts a REPL session.
    \\  run              Runs a JS source file.
    \\  test             Starts the test runner on JS source files.
    \\  exe              TODO: Packages source files into a single binary executable.
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage.
    \\
;

fn usage(env: *Environment) void {
    env.printFmt("{s}\n", .{main_usage});
}

fn version(env: *Environment) void {
    env.printFmt("cosmic {s}\nv8 {s}\n", .{ build_options.VersionName, v8.getVersion() });
}

fn nextArg(args: []const []const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}
