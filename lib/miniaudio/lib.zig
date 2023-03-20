const std = @import("std");
const builtin = @import("builtin");

pub fn createModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/miniaudio.zig" },
        .dependencies = &.{},
    });
    return mod;
}

pub fn addModule(step: *std.build.CompileStep, name: []const u8, mod: *std.build.Module) void {
    step.addIncludePath(thisDir() ++ "/src");
    step.addModule(name, mod);
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary(.{
        .name = "miniaudio",
        .target = step.target,
        .optimize = step.optimize,
    });

    if (builtin.os.tag == .macos and step.target.getOsTag() == .macos) {
        if (!step.target.isNative()) {
            lib.addFrameworkPath("/System/Library/Frameworks");
            lib.addSystemIncludePath("/usr/include");
            lib.setLibCFile(std.build.FileSource{ .path = thisDir() ++ "/../macos.libc" });
        }
        lib.linkFramework("CoreAudio");
    }
    // TODO: vorbis has UB when doing seekToPcmFrame.
    lib.disable_sanitize_c = true;

    const c_flags = &[_][]const u8{
    };
    lib.addCSourceFile(thisDir() ++ "/src/miniaudio.c", c_flags);
    lib.linkLibC();
    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}