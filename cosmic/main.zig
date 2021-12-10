const std = @import("std");
const process = std.process;
const stdx = @import("stdx");
const string = stdx.string;

const v8 = @import("v8.zig");
const log = stdx.log;

const VersionText = "0.1 Alpha";

// Cosmic main. Common entry point for cli and gui.
pub fn main() !void {
    // Fast temporary memory allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    if (args.len == 1) {
        repl();
    }

    // Skip exe path arg.
    var arg_idx: usize = 1;

    const cmd = nextArg(args, &arg_idx).?;
    if (string.eq(cmd, "cli")) {
        repl();
    } else {
        usage();
        abortFmt("unsupported command {s}", .{cmd});
    }
}

// Will exit program once done.
fn repl() void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    var input_buf = std.ArrayList(u8).init(alloc);
    defer input_buf.deinit();

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    v8.initV8();
    defer {
        _ = v8.deinitV8();
        v8.deinitV8Platform();
    }

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    isolate.enter();
    defer isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var context = v8.Context.init(isolate, null, null);
    context.enter();
    defer context.exit();

    const origin = v8.createUtf8String(isolate, "(shell)");

    printFmt(
        \\Cosmic ({s})
        \\exit with Ctrl+D or "exit()"
        \\
    , .{VersionText});

    while (true) {
        printFmt("\n> ", .{});
        const input = getInput(&input_buf);
        if (string.eq(input, "exit()")) {
            process.exit(0);
        }

        const js_input = v8.createUtf8String(isolate, input);

        var res: v8.ExecuteResult = undefined;
        if (v8.executeString(alloc, isolate, js_input, origin, &res)) {
            printFmt("{s}", .{res.result.?});
        } else {
            printFmt("{s}", .{res.err.?});
        }

        while (platform.pumpMessageLoop(isolate, false)) {}
        // log.info("input: {s}", .{input});
    }
}

fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}

// TODO: We'll need to support extended key bindings/ncurses (eg. up arrow for last command) per platform.
// (Low priority since there will be a repl in the GUI)
fn getInput(input_buf: *std.ArrayList(u8)) []const u8 {
    input_buf.clearRetainingCapacity();
    std.io.getStdIn().reader().readUntilDelimiterArrayList(input_buf, '\n', 1000 * 1000 * 1000) catch |err| {
        if (err == error.EndOfStream) {
            printFmt("\n", .{});
            process.exit(0);
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
    \\  cli              Starts a REPL session.
    \\  run              Runs a Javascript or Typescript source file.
    \\  test             Runs tests in source files.
    \\  exe              Packages source files into a single binary executable.
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage.
    \\
;

const Context = struct {
    const Self = @This();
};

fn usage() void {
    printFmt("{s}\n", .{main_usage});
}

pub fn abortFmt(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    process.exit(1);
}

fn nextArg(args: [][]const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}