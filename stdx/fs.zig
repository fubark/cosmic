const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");

extern "stdx" fn jsFetchData(promise_id: u32, ptr: [*]const u8, len: usize) void;

/// Path can be absolute or relative to the cwd.
pub fn readFileFromPathAlloc(alloc: std.mem.Allocator, path: []const u8, max_size: usize) ![]const u8 {
    const abs = try std.fs.path.resolve(alloc, &.{ path });
    defer alloc.free(abs);
    const file = try std.fs.openFileAbsolute(abs, .{ .read = true, .write = false });
    defer file.close();
    return try file.readToEndAlloc(alloc, max_size);
}

/// Path can be absolute or relative to the cwd.
pub fn readFileFromPathPromise(alloc: std.mem.Allocator, path: []const u8, max_size: usize) stdx.wasm.Promise([]const u8) {
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

/// Path is relative to exe dir.
pub fn pathFromExeDir(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);
    return std.fs.path.join(alloc, &.{ exe_dir, path });
}

/// Path is relative to exe dir.
pub fn readFileFromExeDirAlloc(alloc: std.mem.Allocator, path: []const u8, max_size: usize) ![]const u8 {
    const abs = try pathFromExeDir(alloc, path);
    defer alloc.free(abs);
    const file = try std.fs.openFileAbsolute(abs, .{ .read = true, .write = false });
    defer file.close();
    return try file.readToEndAlloc(alloc, max_size);
}