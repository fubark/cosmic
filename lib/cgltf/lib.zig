const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "cgltf",
    .source = .{ .path = srcPath() ++ "/cgltf.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludePath(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("cgltf", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludePath(srcPath() ++ "/vendor");
    lib.linkLibC();

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.appendSlice(&.{ "-DCGLTF_IMPLEMENTATION=1" }) catch @panic("error");
    lib.addCSourceFile(srcPath() ++ "/cgltf.c", c_flags.items);
    step.linkLibrary(lib);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}