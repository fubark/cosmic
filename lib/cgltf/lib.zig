const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "cgltf",
    .path = .{ .path = srcPath() ++ "/cgltf.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("cgltf", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DCGLTF_IMPLEMENTATION=1" };
    lib.addCSourceFile(srcPath() ++ "/cgltf.c", c_flags);
    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
