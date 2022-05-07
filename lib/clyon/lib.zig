const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "lyon",
    .path = .{ .path = srcPath() ++ "/lyon.zig" },
};

pub const dummy_pkg = std.build.Pkg{
    .name = "lyon",
    .path = .{ .path = srcPath() ++ "/lyon_dummy.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep, link_lyon: bool) void {
    step.addIncludeDir(srcPath());
    if (link_lyon) {
        step.addPackage(pkg);
    } else {
        step.addPackage(dummy_pkg);
    }
}

/// Static link prebuilt clyon.
pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    if (target.getOsTag() == .linux and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../../lib/extras/prebuilt/linux64/libclyon.a");
        // Currently clyon needs unwind.
        step.linkSystemLibrary("unwind");
    } else if (target.getOsTag() == .macos and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../../lib/extras/prebuilt/mac64/libclyon.a");
    } else if (target.getOsTag() == .macos and target.getCpuArch() == .aarch64) {
        step.addAssemblyFile(srcPath() ++ "/../../lib/extras/prebuilt/mac-arm64/libclyon.a");
    } else if (target.getOsTag() == .windows and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../../lib/extras/prebuilt/win64/clyon.lib");
        step.linkSystemLibrary("bcrypt");
        step.linkSystemLibrary("userenv");
    } else {
        step.addLibPath(srcPath() ++ "target/release");
        step.linkSystemLibrary("clyon");
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}