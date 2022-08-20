const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "qjs",
    .source = .{ .path = srcPath() ++ "/qjs.zig" },
    .dependencies = &.{},
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    step.addPackage(new_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
}

const BuildOptions = struct {
};

// pub fn createTest(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode, opts: BuildOptions) *std.build.LibExeObjStep {
//     const exe = b.addExecutable("test-qjs", null);
//     exe.setBuildMode(mode);
//     exe.setTarget(target);
//     exe.addIncludeDir(srcPath() ++ "/vendor");
//     buildAndLink(exe, opts);

//     var c_flags = std.ArrayList([]const u8).init(b.allocator);
//     var sources = std.ArrayList([]const u8).init(b.allocator);
//     sources.appendSlice(&.{
//     }) catch @panic("error");
//     for (sources.items) |src| {
//         exe.addCSourceFile(b.fmt("{s}{s}", .{srcPath(), src}), c_flags.items);
//     }
//     return exe;
// }

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: BuildOptions) void {
    _ = opts;
    const b = step.builder;
    const lib = b.addStaticLibrary("qjs", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/");
    lib.linkLibC();
    lib.disable_sanitize_c = true;

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.append("-DCONFIG_BIGNUM=1") catch @panic("error");
    c_flags.append("-DCONFIG_VERSION=\"2021-03-27\"") catch @panic("error");
    c_flags.append("-D_GNU_SOURCE=1") catch @panic("error");
    if (step.target.getOsTag() == .windows) {
        c_flags.append("-D_WIN32=1") catch @panic("error");
    }
    if (step.build_mode == .Debug) {
        // For debugging:
        // c_flags.append("-O0") catch @panic("error");
        if (step.target.getCpuArch().isWasm()) {
            // Compile with some optimization or number of function locals will exceed max limit in browsers.
            c_flags.append("-O1") catch @panic("error");
        }
    }

    var sources = std.ArrayList([]const u8).init(b.allocator);
    sources.appendSlice(&.{
        "/vendor/quickjs.c",
        "/vendor/quickjs-libc.c",
        "/vendor/libbf.c",
        "/vendor/libregexp.c",
        "/vendor/libunicode.c",
        "/vendor/cutils.c",
    }) catch @panic("error");
    for (sources.items) |src| {
        lib.addCSourceFile(b.fmt("{s}{s}", .{srcPath(), src}), c_flags.items);
    }
    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}