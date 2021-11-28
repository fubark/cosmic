const std = @import("std");

pub fn pathFromExeDir(alloc: *std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);
    return std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, path });
}

pub fn readFileFromExeDir(alloc: *std.mem.Allocator, path: []const u8, max_size: usize) ![]const u8 {
    const abs_path = try pathFromExeDir(alloc, path);
    defer alloc.free(abs_path);
    const file = try std.fs.openFileAbsolute(abs_path, .{ .read = true, .write = false });
    defer file.close();
    return try file.readToEndAlloc(alloc, max_size);
}