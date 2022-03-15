const std = @import("std");
const process = std.process;

const runtime = @import("../cosmic/runtime.zig");
const printFmt = runtime.printFmt;
const doc_gen = @import("../docs/doc_gen.zig");
const js_gen = @import("../cosmic/js_gen.zig");

pub fn main() !void {
    // Fast temporary memory allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    var arg_idx: usize = 1;
    const cmd = nextArg(args, &arg_idx) orelse {
        printFmt(
            \\Provide command.
            \\gen docs <dir-path>
            \\gen api-js <js-file-path>
            \\
        , .{});
        process.exit(0);
    };

    if (std.mem.eql(u8, cmd, "docs"))  {
        const docs_path = nextArg(args, &arg_idx) orelse {
            printFmt("Provide directory path.\n", .{});
            process.exit(0);
        };
        try doc_gen.generate(alloc, docs_path);
    } else if (std.mem.eql(u8, cmd, "api-js")) {
        const path = nextArg(args, &arg_idx) orelse {
            printFmt("Provide js path.\n", .{});
            process.exit(0);
        };
        try js_gen.generate(alloc, path);
    } else {
        printFmt("Unknown command \"{s}\"", .{cmd});
        process.exit(0);
    }
}

fn nextArg(args: []const []const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}
