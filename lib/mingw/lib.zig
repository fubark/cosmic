const std = @import("std");

// Missing sources in zig's mingw distribution.
pub fn buildExtra(step: *std.build.LibExeObjStep) void {
    step.addCSourceFile(srcPath() ++ "/ws2tcpip/gai_strerrorA.c", &.{});
    step.addCSourceFile(srcPath() ++ "/ws2tcpip/gai_strerrorW.c", &.{});
}

pub fn buildAndLinkWinPosix(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("win_posix", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.linkLibC();
    lib.addIncludeDir(srcPath() ++ "/win_posix/include");

    const c_files: []const []const u8 = &.{
        "wincompat.c",
        "mman.c",
    };

    for (c_files) |c_file| {
        const path = b.fmt(srcPath() ++ "/win_posix/{s}", .{c_file});
        lib.addCSourceFile(path, &.{});
    }

    step.linkLibrary(lib);
}

pub fn buildAndLinkWinPthreads(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("winpthreads", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.linkLibC();
    lib.addIncludeDir(srcPath() ++ "/winpthreads/include");

    const c_files: []const []const u8 = &.{
        "mutex.c",
        "thread.c",
        "spinlock.c",
        "rwlock.c",
        "cond.c",
        "misc.c",
        "sched.c",
    };

    for (c_files) |c_file| {
        const path = b.fmt(srcPath() ++ "/winpthreads/{s}", .{c_file});
        lib.addCSourceFile(path, &.{});
    }

    step.linkLibrary(lib);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}