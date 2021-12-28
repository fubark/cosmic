const std = @import("std");
const log = std.log.scoped(.tasks);

pub const ReadFileTask = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    path: []const u8,

    res: ?[]const u8 = null,

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.path);
        if (self.res) |res| {
            self.alloc.free(res);
        }
    }

    pub fn process(self: *Self) !void {
        self.res = std.fs.cwd().readFileAlloc(self.alloc, self.path, 1e12) catch |err| switch (err) {
            // Whitelist errors to silence.
            error.FileNotFound => null,
            else => unreachable,
        };
    }
};
