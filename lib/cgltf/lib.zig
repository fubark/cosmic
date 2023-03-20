const std = @import("std");

pub fn createModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/cgltf.zig" },
        .dependencies = &.{},
    });
    // step.addIncludePath(thisDir() ++ "/vendor");
    // step.linkLibC();
    return mod;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = step.builder.addStaticLibrary(.{
        .name = "cgltf",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/vendor");
    lib.linkLibC();

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.appendSlice(&.{ "-DCGLTF_IMPLEMENTATION=1" }) catch @panic("error");
    lib.addCSourceFile(thisDir() ++ "/cgltf.c", c_flags.items);
    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}