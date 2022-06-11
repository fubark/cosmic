const std = @import("std");

pub const stbtt_pkg = std.build.Pkg{
    .name = "stbtt",
    .source = .{ .path = srcPath() ++ "/stbtt.zig" },
};

pub const stbi_pkg = std.build.Pkg{
    .name = "stbi",
    .source = .{ .path = srcPath() ++ "/stbi.zig" },
};

pub fn addStbttPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbtt_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn addStbiPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbi_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
}

pub fn buildAndLinkStbtt(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("stbtt", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_TRUETYPE_IMPLEMENTATION" };
    lib.addCSourceFile(srcPath() ++ "/stb_truetype.c", c_flags);
    step.linkLibrary(lib);
}

pub fn buildAndLinkStbi(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("stbi", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
    const src_files: []const []const u8 = &.{
        srcPath() ++ "/stb_image.c",
        srcPath() ++ "/stb_image_write.c",
    };
    lib.addCSourceFiles(src_files, c_flags);
    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
