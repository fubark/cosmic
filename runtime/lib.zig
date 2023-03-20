const std = @import("std");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    link_lyon: bool = false,
    link_tess2: bool = false,
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    _ = opts;
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/runtime.zig" },
        .dependencies = &.{},
    });

    // const build_options = b.addOptions();
    // build_options.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    // build_options.addOption(bool, "has_lyon", opts.link_lyon);
    // build_options.addOption(bool, "has_tess2", opts.link_tess2);
    // const build_options_pkg = build_options.getPackage("build_options");

    //     zig_v8_pkg, build_options_pkg, stdx.pkg, graphics_pkg, uv.pkg, h2o_pkg, curl.pkg, maudio.pkg, ssl.pkg, platform_pkg, sdl.pkg,
    return mod;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}