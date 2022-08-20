const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "tess2",
    .source = .{ .path = srcPath() ++ "/tess2.zig" },
};

pub const dummy_pkg = std.build.Pkg{
    .name = "tess2",
    .source = .{ .path = srcPath() ++ "/tess2_dummy.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep, link_tess2: bool) void {
    if (link_tess2) {
        step.addIncludeDir(srcPath() ++ "/vendor");
        step.addPackage(pkg);
    } else {
        step.addPackage(dummy_pkg);
    }
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("tess2", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);

    const c_flags = &[_][]const u8{
    };

    const c_files = &[_][]const u8{
        "bucketalloc.c",
        "dict.c",
        "geom.c",
        "mesh.c",
        "priorityq.c",
        "sweep.c",
        "tess.c",
    };

    for (c_files) |file| {
        const path = b.fmt("{s}/vendor/Source/{s}", .{ srcPath(), file });
        lib.addCSourceFile(path, c_flags);
    }

    lib.addIncludeDir(srcPath() ++ "/vendor/Include");
    lib.linkLibC();
    step.linkLibrary(lib);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}