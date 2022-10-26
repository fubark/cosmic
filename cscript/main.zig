const std = @import("std");
const stdx = @import("stdx");
const mi = @import("mimalloc");
const cs = @import("cscript.zig");
const log = stdx.log.scoped(.main);

pub fn main() !void {
    // var miAlloc: mi.Allocator = undefined;
    // miAlloc.init();
    // defer miAlloc.deinit();
    // const alloc = miAlloc.allocator();

    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    // var traceAlloc: stdx.heap.TraceAllocator = undefined;
    // traceAlloc.init(miAlloc.allocator());
    // traceAlloc.init(child);
    // const alloc = traceAlloc.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len > 1) {
        const path = args[1];
        const src = try std.fs.cwd().readFileAlloc(alloc, path, 1e10);
        defer alloc.free(src);

        var vm: cs.VM = undefined;
        try vm.init(alloc);
        defer vm.deinit();

        const res = try vm.eval(src, false);

        if (cs.Value.floatCanBeInteger(res.asF64())) {
            log.info("{d:.0}", .{@floatToInt(u64, res.asF64())});
        } else {
            log.info("{d:.10}", .{res.asF64()});
        }
    }
    // traceAlloc.dump();
}