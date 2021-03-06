const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");
const log = stdx.log.scoped(.fs);

extern "stdx" fn jsFetchData(ptr: [*]const u8, len: usize) u32;

// Path can be absolute or relative to the cwd.
pub fn appendFile(path: []const u8, data: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch {
        const new = try std.fs.cwd().createFile(path, .{ .truncate = false });
        defer new.close();
        return try new.writeAll(data);
    };
    defer file.close();
    try file.seekFromEnd(0);
    return try file.writeAll(data);
}

/// Path can be absolute or relative to the cwd.
pub fn readFileWasm(path: []const u8) u32 {
    if (comptime builtin.target.isWasm()) {
        return jsFetchData(path.ptr, path.len);
    } else {
        unreachable;
    }
}

/// Path is relative to exe dir.
pub fn pathFromExeDir(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);
    return std.fs.path.join(alloc, &.{ exe_dir, path });
}

/// Path is relative to exe dir.
pub fn readFileFromExeDir(alloc: std.mem.Allocator, path: []const u8, max_size: usize) ![]const u8 {
    const abs = try pathFromExeDir(alloc, path);
    defer alloc.free(abs);
    const file = try std.fs.openFileAbsolute(abs, .{ .mode = .read_only });
    defer file.close();
    return try file.readToEndAlloc(alloc, max_size);
}

pub fn pathExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

pub fn getFileMd5Hash(alloc: std.mem.Allocator, path: []const u8, out: *[16]u8) !void {
    const content = try std.fs.cwd().readFileAlloc(alloc, path, 1e9);
    defer alloc.free(content);
    std.crypto.hash.Md5.hash(content, out, .{});
}
