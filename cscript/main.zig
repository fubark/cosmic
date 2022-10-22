const std = @import("std");
const stdx = @import("stdx");
const cs = @import("cscript.zig");
const log = stdx.log.scoped(.main);

pub fn main() !void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

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
        log.info("{}", .{res.asF64()});
    }
}