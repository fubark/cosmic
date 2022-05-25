const std = @import("std");
const builtin = @import("builtin");

pub const pkg = std.build.Pkg{
    .name = "miniaudio",
    .path = .{ .path = srcPath() ++ "/miniaudio.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/src");
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("miniaudio", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);

    if (builtin.os.tag == .macos and step.target.getOsTag() == .macos) {
        if (!step.target.isNative()) {
            lib.addFrameworkDir("/System/Library/Frameworks");
            lib.addSystemIncludeDir("/usr/include");
            // lib.setLibCFile(std.build.FileSource{ .path = srcPath() ++ "/../macos.libc" });
        }
        lib.linkFramework("CoreAudio");
    }
    // TODO: vorbis has UB when doing seekToPcmFrame.
    lib.disable_sanitize_c = true;

    const c_flags = &[_][]const u8{
    };
    lib.addCSourceFile(srcPath() ++ "/src/miniaudio.c", c_flags);
    lib.linkLibC();
    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}