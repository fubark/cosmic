const std = @import("std");

pub fn createModule(b: *std.build.Builder, link_lyon: bool) *std.build.Module {
    if (link_lyon) {
        const mod = b.createModule(.{
            .source_file = .{ .path = thisDir() ++ "/tess2.zig" },
            .dependencies = &.{},
        });
        // step.addIncludePath(thisDir() ++ "/vendor");
        return mod;
    } else {
        const mod = b.createModule(.{
            .source_file = .{ .path = thisDir() ++ "/tess2_dummy.zig" },
            .dependencies = &.{},
        });
        return mod;
    }
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = step.builder.addStaticLibrary(.{
        .name = "tess2",
        .target = step.target,
        .optimize = step.optimize,
    });

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
        const path = b.fmt("{s}/vendor/Source/{s}", .{ thisDir(), file });
        lib.addCSourceFile(path, c_flags);
    }

    lib.addIncludePath(thisDir() ++ "/vendor/Include");
    lib.linkLibC();
    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}