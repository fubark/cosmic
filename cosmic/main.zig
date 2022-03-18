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
    defer env.deinit(alloc);
    try runMain(alloc, args, &env);
}

const Flags = struct {
    help: bool = false,
};

fn parseFlags(alloc: std.mem.Allocator, args: []const []const u8, flags: *Flags) []const []const u8 {
    var rest_args = std.ArrayList([]const u8).init(alloc);
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-h")) {
                flags.help = true;
            } else if (std.mem.eql(u8, arg, "--help")) {
                flags.help = true;
            }
        } else {
            const arg_dupe = alloc.dupe(u8, arg) catch unreachable;
            rest_args.append(arg_dupe) catch unreachable;
        }
    }
    return rest_args.toOwnedSlice();
}

// main is extracted with cli args and options to facilitate testing.
pub fn runMain(alloc: std.mem.Allocator, orig_args: []const []const u8, env: *Environment) !void {
    var flags = Flags{};
    const args = parseFlags(alloc, orig_args, &flags);
    defer {
        for (args) |arg| {
            alloc.free(arg);
        }
        alloc.free(args);
    }

    if (args.len == 1) {
        printUsage(env, main_usage);
        env.exit(0);
        return;
    }

    // Skip exe path arg.
    var arg_idx: usize = 1;

    const cmd = nextArg(args, &arg_idx).?;
    if (string.eq(cmd, "dev")) {
        if (flags.help) {
            printUsage(env, dev_usage);
            env.exit(0);
        } else {
            const src_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected path to main source file.", .{});
                return;
            };
            try runAndExit(src_path, true, env);
        }
    } else if (string.eq(cmd, "run")) {
        if (flags.help) {
            printUsage(env, run_usage);
            env.exit(0);
        } else {
            const src_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected path to main source file.", .{});
                return;
            };
            try runAndExit(src_path, false, env);
        }
    } else if (string.eq(cmd, "test")) {
        if (flags.help) {
            printUsage(env, test_usage);
            env.exit(0);
        } else {
            const src_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected path to main source file.", .{});
                return;
            };
            try testAndExit(src_path, env);
        }
    } else if (string.eq(cmd, "http")) {
        if (flags.help) {
            printUsage(env, http_usage);
            env.exit(0);
        } else {
            const public_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected public directory path.", .{});
                return;
            };
            const abs_path = try std.fs.path.resolve(alloc, &.{ public_path });
            defer alloc.free(abs_path);
            try std.os.chdir(abs_path);

            const port_str = nextArg(args, &arg_idx) orelse "8081";
            const port = try std.fmt.parseInt(u32, port_str, 10);

            env.main_script_origin = "(in-memory: http-main.js)";
            env.main_script_override = http_main;
            env.user_ctx_json = try std.fmt.allocPrint(alloc, 
                \\{{ "port": {}, "https": false }}
                , .{ port });
            try runAndExit("http-main.js", false, env);
        }
    } else if (string.eq(cmd, "https")) {
        if (flags.help) {
            printUsage(env, https_usage);
            env.exit(0);
        } else {
            const public_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected public directory path.", .{});
                return;
            };
            const public_key_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected public key path.", .{});
                return;
            };
            const private_key_path = nextArg(args, &arg_idx) orelse {
                env.abortFmt("Expected private key path.", .{});
                return;
            };

            const abs_path = try std.fs.path.resolve(alloc, &.{ public_path });
            defer alloc.free(abs_path);
            try std.os.chdir(abs_path);

            const port_str = nextArg(args, &arg_idx) orelse "8081";
            const port = try std.fmt.parseInt(u32, port_str, 10);

            env.main_script_origin = "(in-memory: http-main.js)";
            env.main_script_override = http_main;
            env.user_ctx_json = try std.fmt.allocPrint(alloc, 
                \\{{ "port": {}, "https": true, "certPath": "{s}", "keyPath": "{s}" }}
                , .{ port, public_key_path, private_key_path });
            try runAndExit("http-main.js", false, env);
        }
    } else if (string.eq(cmd, "help")) {
        printUsage(env, main_usage);
        env.exit(0);
    } else if (string.eq(cmd, "version")) {
        version(env);
        env.exit(0);
    } else if (string.eq(cmd, "shell")) {
        if (flags.help) {
            printUsage(env, shell_usage);
            env.exit(0);
        } else {
            repl(env);
            env.exit(0);
        }
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

    const platform = runtime.ensureV8Platform();

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

fn printUsage(env: *Environment, usage: []const u8) void {
    env.printFmt("{s}", .{usage});
}

fn version(env: *Environment) void {
    env.printFmt("cosmic {s}\nv8 {s}\n", .{ build_options.VersionName, v8.getVersion() });
}

fn nextArg(args: []const []const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}

const main_usage =
    \\Usage: cosmic [command] [options]
    \\
    \\Main:
    \\
    \\  dev              Runs a JS source file in dev mode.
    \\  run              Runs a JS source file.
    \\  test             Runs a JS source file with the test runner.
    \\  shell            Starts a shell session.
    \\  exe              TODO: Packages source files into a single binary executable.
    \\
    \\Tools:
    \\
    \\  http             Starts an HTTP server over a directory.
    \\  https            Starts an HTTPS server over a directory.
    \\
    \\Help:
    \\
    \\  help             Print main usage.
    \\  version          Print version.
    \\  [command] -h     Print command-specific usage.
    \\  [command] --help 
    \\
    ;

const run_usage = 
    \\Usage: cosmic run [src-path]
    \\       cosmic [src-path]
    \\
    \\Run a js file.
    \\
    ;

const dev_usage = 
    \\Usage: cosmic dev [src-path]
    \\
    \\Run a js file in dev mode.
    \\Dev mode enables hot reloading of your scripts whenever they are modified.
    \\It also includes a HUD for viewing debug output and running commands.
    \\
    ;

const test_usage = 
    \\Usage: cosmic test [src-path]
    \\
    \\Run a js file with the test runner.
    \\Test runner also includes an additional API module `cs.test`
    \\which is not available during normal execution with `cosmic run`.
    \\A short test report will be printed at the end.
    \\Any test failure will result in a non 0 exit code.
    \\
    ;

const shell_usage =
    \\Usage: cosmic shell
    \\
    \\Starts a limited shell for experimenting.
    \\TODO: Run the shell over the cosmic runtime.
    \\
    ;

const http_usage = 
    \\Usage: cosmic http [dir-path] [port=8081]
    \\
    \\Starts an HTTP server over a public folder at [dir-path].
    \\Default port is 8081.
    \\
    ;

const https_usage = 
    \\Usage: cosmic https [dir-path] [public-key-path] [private-key-path] [port=8081]
    \\
    \\Starts an HTTPS server over a public folder at [dir-path].
    \\Paths to public and private keys must be absolute or relative to the public folder path.
    \\Default port is 8081.
    \\
    ;

const http_main = 
    \\let s
    \\if (user.https) {
    \\    s = cs.http.serveHttps('127.0.0.1', user.port, user.certPath, user.keyPath)
    \\    puts(`HTTPS server started on port ${user.port}.`)
    \\} else {
    \\    s = cs.http.serveHttp('127.0.0.1', user.port)
    \\    puts(`HTTP server started on port ${user.port}.`)
    \\}
    \\s.setHandler((req, resp) => {
    \\    if (req.method != 'GET') {
    \\        return false
    \\    }
    \\    const path = req.path.substring(1)
    \\    const content = cs.files.read(path)
    \\    if (content != null) {
    \\        resp.setStatus(200)
    \\        if (path.endsWith('.html')) {
    \\            resp.setHeader('content-type', 'text/html; charset=utf-8')
    \\        } else {
    \\            resp.setHeader('content-type', 'text/plain; charset=utf-8')
    \\        }
    \\        resp.sendBytes(content)
    \\        puts(`GET ${req.path} [200]`)
    \\        return true
    \\    } else {
    \\        puts(`GET ${req.path} [404]`)
    \\        return false
    \\    }
    \\})
    ;