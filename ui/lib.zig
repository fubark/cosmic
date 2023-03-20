const std = @import("std");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    link_lyon: bool = false,
    link_tess2: bool = false,
    enable_tracy: bool = false,
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    _ = opts;
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/ui.zig" },
        .dependencies = &.{},
    });
    // &.{ stdx.pkg, graphics_pkg, platform_pkg };
    return mod;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}