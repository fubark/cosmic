const std = @import("std");
const builtin = @import("builtin");

const IsWasm = builtin.target.cpu.arch == .wasm32;

var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

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
        _ = gpa.?.deinit();
        gpa = null;
    }
}
