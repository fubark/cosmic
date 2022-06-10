const std = @import("std");

const platform = @import("../platform/lib.zig");
const stdx = @import("../stdx/lib.zig");
const graphics = @import("../graphics/lib.zig");

const sdl = @import("../lib/sdl/lib.zig");
const gl = @import("../lib/gl/lib.zig");
const vk = @import("../lib/vk/lib.zig");
const freetype = @import("../lib/freetype2/lib.zig");
const stb = @import("../lib/stb/lib.zig");
const root = @import("../build.zig");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const pkg = std.build.Pkg{
    .name = "ui",
    .source = .{ .path = srcPath() ++ "/src/ui.zig" },
};

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    add_dep_pkgs: bool = true,
    link_lyon: bool = false,
    link_tess2: bool = false,
    enable_tracy: bool = false,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;

    var new_pkg = pkg;

    const platform_opts: platform.Options = .{
        .graphics_backend = opts.graphics_backend,
        .add_dep_pkgs = opts.add_dep_pkgs,
    };
    const platform_pkg = platform.getPackage(b, platform_opts);

    const graphics_opts: graphics.Options = .{
        .graphics_backend = opts.graphics_backend,
        .add_dep_pkgs = opts.add_dep_pkgs,
    };
    const graphics_pkg = graphics.getPackage(b, graphics_opts);

    new_pkg.dependencies = &.{ stdx.pkg, graphics_pkg, platform_pkg };
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        graphics.addPackage(step, graphics_opts);
    }
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    _ = opts;
    graphics.buildAndLink(step, .{});
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}