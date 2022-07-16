const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");

const IsWasm = builtin.target.cpu.arch == .wasm32;

const MeasureMemory = false;
var gpa: ?std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = MeasureMemory }) = null;

pub fn getDefaultAllocator() std.mem.Allocator {
    if (IsWasm) {
        return std.heap.page_allocator;
    } else {
        if (gpa == null) {
            gpa = .{};
        }
        return gpa.?.allocator();
    }
}

pub fn deinitDefaultAllocator() void {
    if (!IsWasm) {
        // This will report memory leaks in debug mode.
        _ = gpa.?.deinit();
        gpa = null;
    }
}

pub fn getTotalRequestedMemory() usize {
    if (IsWasm or !MeasureMemory) {
        stdx.panic("unsupported");
    } else {
        return gpa.?.total_requested_bytes;
    }
}