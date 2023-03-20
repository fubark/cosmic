const std = @import("std");
const GraphicsBackend = @import("backend.zig").GraphicsBackend;

const sdl_lib = @import("../lib/sdl/lib.zig");

pub const Options = struct {
    graphics_backend: GraphicsBackend,
    deps: struct {
        sdl: *std.build.Module,
        gl: *std.build.Module,
        stdx: *std.build.Module,
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const platform_options = createOptions(b, opts);

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

fn createOptions(b: *std.build.Builder, opts: Options) *std.build.Module {
    const bopts = b.addOptions();
    bopts.addOption(GraphicsBackend, "GraphicsBackend", opts.graphics_backend);
    return bopts.createModule();
}

pub fn createTestExe(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, opts: Options) *std.build.CompileStep {
    const step = b.addTest(.{
        .kind = .test_exe,
        .root_source_file = .{ .path = thisDir() ++ "/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    step.addModule("stdx", opts.deps.stdx);
    step.addModule("platform_options", createOptions(b, opts));
    sdl_lib.addModule(step, "sdl", opts.deps.sdl);
    sdl_lib.buildAndLink(step, .{
        .lib_path = null,
    });
    return step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}
