const std = @import("std");

pub fn createStbPerlinModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/stb_perlin.zig" },
        .dependencies = &.{},
    });
    return mod;
}

pub fn addStbPerlinModule(step: *std.build.CompileStep, name: []const u8, mod: *std.build.Module) void {
    step.addIncludePath(thisDir() ++ "/vendor");
    // step.linkLibC();
    step.addModule(name, mod);
}

pub fn createStbttModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/stbtt.zig" },
        .dependencies = &.{},
    });
    // step.addIncludePath(thisDir() ++ "/vendor");
    // step.linkLibC();
    return mod;
}

pub fn createStbiModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/stbi.zig" },
        .dependencies = &.{},
    });
    return mod;
}

pub fn addStbiModuleIncludes(step: *std.build.CompileStep) void {
    step.addIncludePath(thisDir() ++ "/vendor");
}

pub fn addStbiModule(step: *std.build.CompileStep, name: []const u8, mod: *std.build.Module) void {
    addStbiModuleIncludes(step);
    step.addModule(name, mod);
}

pub fn buildAndLinkStbtt(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    _ = b;
    const lib = step.builder.addStaticLibrary(.{
        .name = "stbtt",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_TRUETYPE_IMPLEMENTATION" };
    lib.addCSourceFile(thisDir() ++ "/stb_truetype.c", c_flags);
    step.linkLibrary(lib);
}

pub fn buildAndLinkStbi(step: *std.build.LibExeObjStep) void {
    const lib = step.builder.addStaticLibrary(.{
        .name = "stbi",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
    const src_files: []const []const u8 = &.{
        thisDir() ++ "/stb_image.c",
        thisDir() ++ "/stb_image_write.c",
    };
    lib.addCSourceFiles(src_files, c_flags);
    step.linkLibrary(lib);
}

pub fn buildAndLinkStbPerlin(step: *std.build.LibExeObjStep) void {
    const lib = step.builder.addStaticLibrary(.{
        .name = "stb_perlin",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/vendor");
    lib.linkLibC();

    const c_flags = &[_][]const u8{ "-DSTB_PERLIN_IMPLEMENTATION" };
    const src_files: []const []const u8 = &.{
        thisDir() ++ "/stb_perlin.c",
    };
    lib.addCSourceFiles(src_files, c_flags);
    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}