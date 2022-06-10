const std = @import("std");

const sdl = @import("../sdl/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "vk",
    .source = .{ .path = srcPath() ++ "/vk.zig" },
    .dependencies = &.{ sdl.pkg },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    new_pkg.dependencies = &.{ sdl.pkg };
    step.addPackage(new_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor/include");
    step.linkLibC();
}

pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    switch (target.getOsTag()) {
        .linux => {
            step.addLibPath("/usr/lib/x86_64-linux-gnu");
            step.linkSystemLibrary("vulkan");
        },
        else => {
            step.linkSystemLibrary("vulkan");
        },
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}