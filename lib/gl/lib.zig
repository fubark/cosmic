const std = @import("std");

const sdl = @import("../sdl/lib.zig");
const stdx = @import("../../stdx/lib.zig");

const Options = struct {
    deps: struct {
        sdl: *std.build.Module,
    },
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/gl.zig" },
        .dependencies = &.{
            .{ .name = "sdl", .module = opts.deps.sdl },
        },
    });
    //    .dependencies = &.{ stdx.pkg },
    return mod;
}

pub fn addModule(step: *std.build.CompileStep, name: []const u8, mod: *std.build.Module) void {
    step.addIncludePath(thisDir() ++ "/vendor");
    // step.linkLibC();
    step.addModule(name, mod);
}

pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    switch (target.getOsTag()) {
        .macos => {
            // TODO: Fix this, should be linkFramework instead.

            // TODO: See what this path returns $(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/OpenGL.framework/Headers
            // https://github.com/ziglang/zig/issues/2208
            step.addLibraryPath("/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries");
            step.linkSystemLibrary("GL");
        },
        .windows =>{
            // Link with OpenGL 1.1 API. Higher API functions should be loaded at runtime through vendors.
            step.linkSystemLibrary("opengl32");
        },
        .linux => {
            // Unable to find libraries if linux is provided in triple.
            // https://github.com/ziglang/zig/issues/8103
            step.addLibraryPath("/usr/lib/x86_64-linux-gnu");
            step.linkSystemLibrary("GL");
        },
        else => {
            step.linkSystemLibrary("GL");
        },
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}