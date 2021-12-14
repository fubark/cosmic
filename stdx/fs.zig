const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");

extern "stdx" fn jsFetchData(promise_id: u32, ptr: [*]const u8, len: usize) void;

/// An absolute path will take precedence.
pub fn pathFromExeDir(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);
    // If absolute path is provided resolve will return it.
    return std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, path });
}

pub fn readFileFromExeDir(alloc: std.mem.Allocator, path: []const u8, max_size: usize) ![]const u8 {
    const abs_path = try pathFromExeDir(alloc, path);
    defer alloc.free(abs_path);
    const file = try std.fs.openFileAbsolute(abs_path, .{ .read = true, .write = false });
    defer file.close();
    return try file.readToEndAlloc(alloc, max_size);
}

pub fn readFileFromExeDirPromise(alloc: std.mem.Allocator, path: []const u8, max_size: usize) stdx.wasm.Promise([]const u8) {
    _ = alloc;
    _ = max_size;
    // Currently only supported for web wasm.
    if (builtin.target.cpu.arch == .wasm32) {
        const p = stdx.wasm.createPromise([]const u8);
        jsFetchData(p.id, path.ptr, path.len);
        return p;
    } else {
        @compileError("unsupported");
    }
}