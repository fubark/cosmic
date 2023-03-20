const std = @import("std");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const Options = struct {
    enable_tracy: bool = false,
    deps: struct {
        graphics: *std.build.Module,
        stdx: *std.build.Module,
        platform: *std.build.Module,
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/ui.zig" },
        .dependencies = &.{
            .{ .name = "graphics", .module = opts.deps.graphics },
            .{ .name = "stdx", .module = opts.deps.stdx },
            .{ .name = "platform", .module = opts.deps.platform },
        },
    });
    // &.{ platform_pkg };
    return mod;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}