const std = @import("std");

const sdl = @import("../sdl/lib.zig");
const stdx = @import("../../stdx/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "gl",
    .source = .{ .path = srcPath() ++ "/gl.zig" },
    .dependencies = &.{ sdl.pkg, stdx.pkg },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    switch (target.getOsTag()) {
        .macos => {
            // TODO: Fix this, should be linkFramework instead.

            // TODO: See what this path returns $(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/OpenGL.framework/Headers
            // https://github.com/ziglang/zig/issues/2208
            step.addLibPath("/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries");
            step.linkSystemLibrary("GL");
        },
        .windows =>{
            // Link with OpenGL 1.1 API. Higher API functions should be loaded at runtime through vendors.
            step.linkSystemLibrary("opengl32");
        },
        .linux => {
            // Unable to find libraries if linux is provided in triple.
            // https://github.com/ziglang/zig/issues/8103
            step.addLibPath("/usr/lib/x86_64-linux-gnu");
            step.linkSystemLibrary("GL");
        },
        else => {
            step.linkSystemLibrary("GL");
        },
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}