const std = @import("std");
const GraphicsBackend = @import("backend.zig").GraphicsBackend;

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    deps: struct {
        sdl: *std.build.Module,
        gl: *std.build.Module,
        stdx: *std.build.Module,
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const bopts = b.addOptions();
    bopts.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    const platform_options = bopts.createModule();

    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/platform.zig" },
        .dependencies = &.{
            .{ .name = "platform_options", .module = platform_options },
            .{ .name = "sdl", .module = opts.deps.sdl },
            .{ .name = "gl", .module = opts.deps.gl },
            .{ .name = "stdx", .module = opts.deps.stdx },
        },
    });
    // vk.pkg,
    return mod;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}
