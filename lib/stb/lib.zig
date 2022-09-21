const std = @import("std");

pub const stbtt_pkg = std.build.Pkg{
    .name = "stbtt",
    .source = .{ .path = srcPath() ++ "/stbtt.zig" },
};

pub const stbi_pkg = std.build.Pkg{
    .name = "stbi",
    .source = .{ .path = srcPath() ++ "/stbi.zig" },
};

pub const stb_perlin_pkg = std.build.Pkg{
    .name = "stb_perlin",
    .source = .{ .path = srcPath() ++ "/stb_perlin.zig" },
};

pub fn addStbPerlinPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(stb_perlin_pkg);
    step.addIncludePath(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn addStbttPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbtt_pkg);
    step.addIncludePath(srcPath() ++ "/vendor");
    step.linkLibC();
}

pub fn addStbiPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbi_pkg);
    step.addIncludePath(srcPath() ++ "/vendor");
}

pub fn buildAndLinkStbtt(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("stbtt", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludePath(srcPath() ++ "/vendor");
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
    lib.addIncludePath(srcPath() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
    const src_files: []const []const u8 = &.{
        srcPath() ++ "/stb_image.c",
        srcPath() ++ "/stb_image_write.c",
    };
    lib.addCSourceFiles(src_files, c_flags);
    step.linkLibrary(lib);
}

pub fn buildAndLinkStbPerlin(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("stb_perlin", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludePath(srcPath() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_PERLIN_IMPLEMENTATION" };
    const src_files: []const []const u8 = &.{
        srcPath() ++ "/stb_perlin.c",
    };
    lib.addCSourceFiles(src_files, c_flags);
    step.linkLibrary(lib);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}