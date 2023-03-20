const std = @import("std");

const sdl_lib = @import("../lib/sdl/lib.zig");
const gl_lib = @import("../lib/gl/lib.zig");
const freetype_lib = @import("../lib/freetype2/lib.zig");
const stb_lib = @import("../lib/stb/lib.zig");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    link_lyon: bool = false,
    link_tess2: bool = false,
    link_stbtt: bool = false,
    link_freetype2: bool = true,
    enable_tracy: bool = false,

    /// Override with prebuilt libs.
    sdl_lib_path: ?[]const u8 = null,

    deps: struct {
        stdx: *std.build.Module,
        gl: *std.build.Module,
        freetype: *std.build.Module,
        platform: *std.build.Module,
        stbi: *std.build.Module,
        sdl: *std.build.Module,
        stb_perlin: *std.build.Module,
    },
};

fn createOptions(b: *std.build.Builder, opts: Options) *std.build.Module {
    const bopts = b.addOptions();
    bopts.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    bopts.addOption(bool, "enable_tracy", opts.enable_tracy);
    bopts.addOption(bool, "has_lyon", opts.link_lyon);
    bopts.addOption(bool, "has_tess2", opts.link_tess2);
    return bopts.createModule();
}

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const graphics_options = createOptions(b, opts);

    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/graphics.zig" },
        .dependencies = &.{
            .{ .name = "graphics_options", .module = graphics_options },
            .{ .name = "stdx", .module = opts.deps.stdx },
            .{ .name = "gl", .module = opts.deps.gl },
            .{ .name = "freetype", .module = opts.deps.freetype },
            .{ .name = "platform", .module = opts.deps.platform },
            .{ .name = "stbi", .module = opts.deps.stbi },
            .{ .name = "sdl", .module = opts.deps.sdl },
            .{ .name = "stb_perlin", .module = opts.deps.stb_perlin },
        },
    });
    // vk.pkg, lyon_pkg, tess2_pkg, stb.stbtt_pkg, cgltf.pkg, glslang.pkg, 
    return mod;
}

fn isWasm(target: std.zig.CrossTarget) bool {
    return target.getCpuArch() == .wasm32 or target.getCpuArch() == .wasm64;
}

pub fn createTestExe(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, opts: Options) *std.build.CompileStep {
    const step = b.addTest(.{
        .kind = .test_exe,
        .root_source_file = .{ .path = thisDir() ++ "/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    step.setMainPkgPath("..");
    step.addModule("graphics_options", createOptions(b, opts));
    step.addModule("stdx", opts.deps.stdx);
    step.addModule("platform", opts.deps.platform);
    sdl_lib.addModule(step, "sdl", opts.deps.sdl);
    gl_lib.addModule(step, "gl", opts.deps.gl);
    gl_lib.link(step);
    stb_lib.addStbPerlinModule(step, "stb_perlin", opts.deps.stb_perlin);
    stb_lib.buildAndLinkStbPerlin(step);
    freetype_lib.addModule(step, "freetype", opts.deps.freetype);
    return step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}