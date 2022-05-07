const std = @import("std");
const builtin = @import("builtin");

pub const pkg = std.build.Pkg{
    .name = "uv",
    .path = .{ .path = srcPath() ++ "/uv.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/vendor/include");
}

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
) !*std.build.LibExeObjStep {

    const lib = b.addStaticLibrary("uv", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

    const alloc = b.allocator;
    var c_flags = std.ArrayList([]const u8).init(alloc);

    // From CMakeLists.txt
    var c_files = std.ArrayList([]const u8).init(alloc);
    try c_files.appendSlice(&.{
        // common
        "src/fs-poll.c",
        "src/idna.c",
        "src/inet.c",
        "src/random.c",
        "src/strscpy.c",
        "src/threadpool.c",
        "src/timer.c",
        "src/uv-common.c",
        "src/uv-data-getter-setters.c",
        "src/version.c",
    });
    if (target.getOsTag() == .linux or target.getOsTag() == .macos) {
        try c_files.appendSlice(&.{
            "src/unix/async.c",
            "src/unix/core.c",
            "src/unix/dl.c",
            "src/unix/fs.c",
            "src/unix/getaddrinfo.c",
            "src/unix/getnameinfo.c",
            "src/unix/loop-watcher.c",
            "src/unix/loop.c",
            "src/unix/pipe.c",
            "src/unix/poll.c",
            "src/unix/process.c",
            "src/unix/random-devurandom.c",
            "src/unix/signal.c",
            "src/unix/stream.c",
            "src/unix/tcp.c",
            "src/unix/thread.c",
            "src/unix/tty.c",
            "src/unix/udp.c",
            "src/unix/proctitle.c",
        });
    }
    if (target.getOsTag() == .linux) {
        try c_files.appendSlice(&.{
            // sys
            "src/unix/linux-core.c",
            "src/unix/linux-inotify.c",
            "src/unix/linux-syscalls.c",
            "src/unix/procfs-exepath.c",
            "src/unix/random-getrandom.c",
            "src/unix/random-sysctl-linux.c",
            "src/unix/epoll.c",
        });
        try c_flags.appendSlice(&.{
            "-D_GNU_SOURCE",
            "-D_POSIX_C_SOURCE=200112",
        });
    } else if (target.getOsTag() == .macos) {
        try c_files.appendSlice(&.{
            "src/unix/bsd-ifaddrs.c",
            "src/unix/kqueue.c",
            "src/unix/random-getentropy.c",
            "src/unix/darwin-proctitle.c",
            "src/unix/darwin.c",
            "src/unix/fsevents.c",
        });
        try c_flags.appendSlice(&.{
            "-D_DARWIN_UNLIMITED_SELECT=1",
            "-D_DARWIN_USE_64_BIT_INODE=1",
            "-D_FILE_OFFSET_BITS=64",
            "-D_LARGEFILE_SOURCE",
        });
    } else if (target.getOsTag() == .windows) {
        try c_files.appendSlice(&.{
            "src/win/loop-watcher.c",
            "src/win/tcp.c",
            "src/win/async.c",
            "src/win/core.c",
            "src/win/signal.c",
            "src/win/snprintf.c",
            "src/win/getnameinfo.c",
            "src/win/fs.c",
            "src/win/fs-event.c",
            "src/win/getaddrinfo.c",
            "src/win/handle.c",
            "src/win/dl.c",
            "src/win/udp.c",
            "src/win/util.c",
            "src/win/error.c",
            "src/win/winapi.c",
            "src/win/winsock.c",
            "src/win/detect-wakeup.c",
            "src/win/stream.c",
            "src/win/tty.c",
            "src/win/process-stdio.c",
            "src/win/process.c",
            "src/win/poll.c",
            "src/win/thread.c",
            "src/win/pipe.c",
        });
    }

    for (c_files.items) |file| {
        const path = b.fmt("{s}/vendor/{s}", .{ srcPath(), file });
        lib.addCSourceFile(path, c_flags.items);
    }

    // libuv has UB in uv__write_req_update when the last buf->base has a null ptr.
    lib.disable_sanitize_c = true;

    lib.linkLibC();
    lib.addIncludeDir(fromRoot(b, "vendor/include"));
    lib.addIncludeDir(fromRoot(b, "vendor/src"));
    if (builtin.os.tag == .macos and target.getOsTag() == .macos) {
        if (target.isNativeOs()) {
            // Force using native headers or it'll compile with ___darwin_check_fd_set_overflow calls
            // which doesn't exist in later mac libs.
            lib.linkFramework("CoreServices");
        } else {
            lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
        }
    }

    return lib;
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    linkDeps(step);
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    linkDeps(step);
    step.addAssemblyFile(path);
}

fn linkDeps(step: *std.build.LibExeObjStep) void {
    if (step.target.getOsTag() == .windows and step.target.getAbi() == .gnu) {
        step.linkSystemLibrary("iphlpapi");
        step.linkSystemLibrary("userenv");
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ srcPath(), rel_path }) catch unreachable;
}
