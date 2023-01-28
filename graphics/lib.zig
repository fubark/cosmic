const std = @import("std");
const Pkg = std.build.Pkg;

const platform = @import("../platform/lib.zig");
const graphics = @import("../graphics/lib.zig");
const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;
const stdx = @import("../stdx/lib.zig");
const stb = @import("../lib/stb/lib.zig");
const freetype = @import("../lib/freetype2/lib.zig");
const gl = @import("../lib/gl/lib.zig");
const vk = @import("../lib/vk/lib.zig");
const sdl = @import("../lib/sdl/lib.zig");
const lyon = @import("../lib/clyon/lib.zig");
const tess2 = @import("../lib/tess2/lib.zig");
const cgltf = @import("../lib/cgltf/lib.zig");
const glslang = @import("../lib/glslang/lib.zig");

pub const pkg = Pkg{
    .name = "graphics",
    .source = .{ .path = srcPath() ++ "/src/graphics.zig" },
};

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    link_lyon: bool = false,
    link_tess2: bool = false,
    link_stbtt: bool = false,
    link_freetype2: bool = true,
    enable_tracy: bool = false,
    add_dep_pkgs: bool = true,

    /// Override with prebuilt libs.
    sdl_lib_path: ?[]const u8 = null,
};

pub fn getPackage(b: *std.build.Builder, opts: Options) std.build.Pkg {
    var ret = pkg;

    var lyon_pkg: Pkg = undefined;
    if (opts.link_lyon) {
        lyon_pkg = lyon.pkg;
        // lyon_pkg.dependencies = &.{ stdx.pkg };
    } else {
        lyon_pkg = lyon.dummy_pkg;
        // lyon_pkg.dependencies = &.{ stdx.pkg };
    }

    var tess2_pkg: Pkg = undefined;
    if (opts.link_tess2) {
        tess2_pkg = tess2.pkg;
    } else {
        tess2_pkg = tess2.dummy_pkg;
    }

    const stdx_pkg = stdx.getPackage(b, .{
        .enable_tracy = opts.enable_tracy,
    });

    const build_options = b.addOptions();
    build_options.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    build_options.addOption(bool, "enable_tracy", opts.enable_tracy);
    build_options.addOption(bool, "has_lyon", opts.link_lyon);
    build_options.addOption(bool, "has_tess2", opts.link_tess2);
    const build_options_pkg = build_options.getPackage("build_options");

    const platform_opts: platform.Options = .{
        .graphics_backend = opts.graphics_backend,
        .add_dep_pkgs = opts.add_dep_pkgs,
    };
    const platform_pkg = platform.getPackage(b, platform_opts);

    ret.dependencies = b.allocator.dupe(std.build.Pkg, &.{
        gl.pkg, vk.pkg, stdx_pkg, build_options_pkg, platform_pkg, freetype.pkg, lyon_pkg, tess2_pkg, sdl.pkg, stb.stbi_pkg, stb.stbtt_pkg, stb.stb_perlin_pkg, cgltf.pkg, glslang.pkg, 
    }) catch @panic("error");
    return ret;
}

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;
    var new_pkg = getPackage(b, opts);
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        stdx.addPackage(step, .{
            .enable_tracy = opts.enable_tracy,
        });
        const platform_opts: platform.Options = .{
            .graphics_backend = opts.graphics_backend,
            .add_dep_pkgs = opts.add_dep_pkgs,
        };
        platform.addPackage(step, platform_opts);
        gl.addPackage(step);
        stb.addStbttPackage(step);
        if (opts.link_freetype2) {
            freetype.addPackage(step);
        }
    }
}

fn isWasm(target: std.zig.CrossTarget) bool {
    return target.getCpuArch() == .wasm32 or target.getCpuArch() == .wasm64;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    if (!isWasm(step.target)) {
        gl.link(step);
        vk.link(step);
        sdl.buildAndLink(step, .{
            .lib_path = opts.sdl_lib_path,
        });
    }
    if (opts.link_stbtt) {
        stb.buildAndLinkStbtt(step);
    }
    stb.buildAndLinkStbi(step);
    stb.buildAndLinkStbPerlin(step);
    if (opts.link_freetype2) {
        freetype.buildAndLink(step);
    }
    if (opts.link_lyon) {
        lyon.link(step);
    }
    if (opts.link_tess2) {
        tess2.buildAndLink(step);
    }
    cgltf.buildAndLink(step);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}