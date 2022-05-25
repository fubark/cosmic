const std = @import("std");

const platform = @import("../platform/lib.zig");
const stdx = @import("../stdx/lib.zig");
const graphics = @import("../graphics/lib.zig");

const sdl = @import("../lib/sdl/lib.zig");
const gl = @import("../lib/gl/lib.zig");
const freetype = @import("../lib/freetype2/lib.zig");
const stb = @import("../lib/stb/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "ui",
    .path = .{ .path = srcPath() ++ "/src/ui.zig" },
};

pub const Options = struct {
    add_dep_pkgs: bool = true,
    link_lyon: bool = false,
    link_tess2: bool = false,
    enable_tracy: bool = false,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;

    var new_pkg = pkg;

    var platform_pkg = platform.pkg;
    platform_pkg.dependencies = &.{ sdl.pkg, stdx.pkg };

    var sdl_pkg = sdl.pkg;
    sdl_pkg.dependencies = &.{ stdx.pkg };

    var gl_pkg = gl.pkg;
    gl_pkg.dependencies = &.{ sdl_pkg, stdx.pkg };

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", opts.enable_tracy);
    build_options.addOption(bool, "has_lyon", opts.link_lyon);
    build_options.addOption(bool, "has_tess2", opts.link_tess2);
    const build_options_pkg = build_options.getPackage("build_options");

    var graphics_pkg = graphics.pkg;
    graphics_pkg.dependencies = &.{ gl_pkg, stdx.pkg, freetype.pkg, sdl_pkg, platform.pkg, stb.stbi_pkg, stb.stbtt_pkg, build_options_pkg };

    new_pkg.dependencies = &.{ stdx.pkg, graphics_pkg, platform_pkg };
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        graphics.addPackage(step, .{
            .add_dep_pkgs = opts.add_dep_pkgs,
        });
    }
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    _ = opts;
    graphics.buildAndLink(step, .{});
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}