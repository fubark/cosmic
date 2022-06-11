const std = @import("std");
const GraphicsBackend = @import("backend.zig").GraphicsBackend;

const stdx = @import("../stdx/lib.zig");
const sdl = @import("../lib/sdl/lib.zig");
const gl = @import("../lib/gl/lib.zig");
const vk = @import("../lib/vk/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "platform",
    .source = .{ .path = srcPath() ++ "/platform.zig" },
};

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    add_dep_pkgs: bool = true,
};

pub fn getPackage(b: *std.build.Builder, opts: Options) std.build.Pkg {
    var ret = pkg;
    const build_options = b.addOptions();
    build_options.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    ret.dependencies = b.allocator.dupe(std.build.Pkg, &.{
        sdl.pkg, stdx.pkg, gl.pkg, vk.pkg,
        build_options.getPackage("build_options"),
    }) catch @panic("error");
    return ret;
}

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const gen_pkg = getPackage(step.builder, opts);
    step.addPackage(gen_pkg);
    if (opts.add_dep_pkgs) {
        sdl.addPackage(step);
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
