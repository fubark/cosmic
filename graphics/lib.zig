const std = @import("std");
const Pkg = std.build.Pkg;

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
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const bopts = b.addOptions();
    bopts.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    bopts.addOption(bool, "enable_tracy", opts.enable_tracy);
    bopts.addOption(bool, "has_lyon", opts.link_lyon);
    bopts.addOption(bool, "has_tess2", opts.link_tess2);
    const graphics_options = bopts.createModule();

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
        },
    });
    // vk.pkg, lyon_pkg, tess2_pkg, sdl.pkg, stb.stbtt_pkg, stb.stb_perlin_pkg, cgltf.pkg, glslang.pkg, 
    return mod;
}

fn isWasm(target: std.zig.CrossTarget) bool {
    return target.getCpuArch() == .wasm32 or target.getCpuArch() == .wasm64;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}