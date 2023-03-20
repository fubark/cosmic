const std = @import("std");

const sdl = @import("../sdl/lib.zig");

pub fn createModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/vk.zig" },
        .dependencies = &.{},
    });
    // new_pkg.dependencies = &.{ sdl.pkg };
    // step.addIncludePath(thisDir() ++ "/vendor/include");
    // step.linkLibC();
    return mod;
}

pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    switch (target.getOsTag()) {
        .windows => {},
        .macos => {},
        .linux => {
            step.addLibraryPath("/usr/lib/x86_64-linux-gnu");
            step.linkSystemLibrary("vulkan");
        },
        else => {
            step.linkSystemLibrary("vulkan");
        },
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}