const std = @import("std");

const gl_lib = @import("../lib/gl/lib.zig");
const sdl_lib = @import("../lib/sdl/lib.zig");
const freetype_lib = @import("../lib/freetype2/lib.zig");
const stb_lib = @import("../lib/stb/lib.zig");

const GraphicsBackend = @import("../platform/backend.zig").GraphicsBackend;

pub const Options = struct {
    enable_tracy: bool = false,
    deps: struct {
        graphics: *std.build.Module,
        stdx: *std.build.Module,
        platform: *std.build.Module,
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/ui.zig" },
        .dependencies = &.{
            .{ .name = "graphics", .module = opts.deps.graphics },
            .{ .name = "stdx", .module = opts.deps.stdx },
            .{ .name = "platform", .module = opts.deps.platform },
        },
    });
    return mod;
}

pub fn createTestExe(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, opts: Options) *std.build.CompileStep {
    const step = b.addTest(.{
        .kind = .test_exe,
        .root_source_file = .{ .path = thisDir() ++ "/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    step.addModule("stdx", opts.deps.stdx);
    step.addModule("platform", opts.deps.platform);
    step.addModule("graphics", opts.deps.graphics);
    gl_lib.addModuleIncludes(step);
    freetype_lib.addModuleIncludes(step);
    freetype_lib.buildAndLink(step);
    return step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}