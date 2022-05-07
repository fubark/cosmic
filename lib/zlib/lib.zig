const std = @import("std");

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("zlib", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

    const c_flags = &[_][]const u8{
    };

    const c_files = &[_][]const u8{
        "inftrees.c",
        "inflate.c",
        "adler32.c",
        "zutil.c",
        "trees.c",
        "gzclose.c",
        "gzwrite.c",
        "gzread.c",
        "deflate.c",
        "compress.c",
        "crc32.c",
        "infback.c",
        "gzlib.c",
        "uncompr.c",
        "inffast.c",
    };

    for (c_files) |file| {
        const path = b.fmt("{s}/vendor/{s}", .{ root(), file });
        lib.addCSourceFile(path, c_flags);
    }

    lib.linkLibC();
    return lib;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const lib = create(step.builder, step.target, step.build_mode) catch unreachable;
    linkLib(step, lib);
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    step.addAssemblyFile(path);
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}