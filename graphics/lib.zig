const std = @import("std");
const Pkg = std.build.Pkg;

const platform = @import("../platform/lib.zig");
const stdx = @import("../stdx/lib.zig");
const stb = @import("../lib/stb/lib.zig");
const freetype = @import("../lib/freetype2/lib.zig");
const gl = @import("../lib/gl/lib.zig");
const sdl = @import("../lib/sdl/lib.zig");
const lyon = @import("../lib/clyon/lib.zig");
const tess2 = @import("../lib/tess2/lib.zig");

pub const pkg = Pkg{
    .name = "graphics",
    .path = .{ .path = srcPath() ++ "/src/graphics.zig" },
};

pub const Options = struct {
    link_lyon: bool = false,
    link_tess2: bool = false,
    link_stbtt: bool = false,
    link_freetype2: bool = true,
    enable_tracy: bool = false,
    add_dep_pkgs: bool = true,

    /// Override with prebuilt libs.
    sdl_lib_path: ?[]const u8 = null,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;

    var lyon_pkg: Pkg = undefined;
    if (opts.link_lyon) {
        lyon_pkg = lyon.pkg;
        lyon_pkg.dependencies = &.{ stdx.pkg };
    } else {
        lyon_pkg = lyon.dummy_pkg;
        lyon_pkg.dependencies = &.{ stdx.pkg };
    }

    var tess2_pkg: Pkg = undefined;
    if (opts.link_tess2) {
        tess2_pkg = tess2.pkg;
        step.addIncludeDir(srcPath() ++ "/../lib/libtess2/Include");
    } else {
        tess2_pkg = tess2.dummy_pkg;
    }

    var sdl_pkg = sdl.pkg;
    sdl_pkg.dependencies = &.{ stdx.pkg };

    var gl_pkg = gl.pkg;
    gl_pkg.dependencies = &.{ sdl_pkg, stdx.pkg };

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", opts.enable_tracy);
    build_options.addOption(bool, "has_lyon", opts.link_lyon);
    build_options.addOption(bool, "has_tess2", opts.link_tess2);
    const build_options_pkg = build_options.getPackage("build_options");

    var new_pkg = pkg;
    new_pkg.dependencies = &.{ stb.stbi_pkg, stb.stbtt_pkg, freetype.pkg, gl_pkg, sdl_pkg, stdx.pkg, lyon_pkg, tess2_pkg, platform.pkg, build_options_pkg };
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        stdx.addPackage(step, .{
            .enable_tracy = opts.enable_tracy,
        });
        platform.addPackage(step, .{ .add_dep_pkgs = opts.add_dep_pkgs });
        gl.addPackage(step);
        stb.addStbttPackage(step);
    }
}

fn isWasm(target: std.zig.CrossTarget) bool {
    return target.getCpuArch() == .wasm32 or target.getCpuArch() == .wasm64;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    if (!isWasm(step.target)) {
        gl.link(step);
        sdl.buildAndLink(step, .{
            .lib_path = opts.sdl_lib_path,
        });
    }
    if (opts.link_stbtt) {
        stb.buildAndLinkStbtt(step);
    }
    stb.buildAndLinkStbi(step);
    if (opts.link_freetype2) {
        freetype.buildAndLink(step);
    }
    if (opts.link_lyon) {
        lyon.link(step);
    }
    if (opts.link_tess2) {
        tess2.buildAndLink(step);
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}