const std = @import("std");

pub fn createModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/mimalloc.zig" },
        .dependencies = &.{},
    });
    // step.addIncludePath(thisDir() ++ "/vendor/include");
    return mod;
}

const BuildOptions = struct {
};

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: BuildOptions) void {
    _ = opts;
    const b = step.builder;
    const lib = step.builder.addStaticLibrary(.{
        .name = "mimalloc",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/vendor/include");
    lib.linkLibC();
    // lib.disable_sanitize_c = true;

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    // c_flags.append("-D_GNU_SOURCE=1") catch @panic("error");
    if (step.target.getOsTag() == .windows) {
    }
    if (step.optimize == .Debug) {
        // For debugging:
        // c_flags.append("-O0") catch @panic("error");
        // if (step.target.getCpuArch().isWasm()) {
        //     // Compile with some optimization or number of function locals will exceed max limit in browsers.
        //     c_flags.append("-O1") catch @panic("error");
        // }
    }

    var sources = std.ArrayList([]const u8).init(b.allocator);
    sources.appendSlice(&.{
        "/vendor/src/alloc.c",
        "/vendor/src/alloc-aligned.c",
        "/vendor/src/page.c",
        "/vendor/src/heap.c",
        "/vendor/src/random.c",
        "/vendor/src/segment-cache.c",
        "/vendor/src/options.c",
        "/vendor/src/bitmap.c",
        "/vendor/src/os.c",
        "/vendor/src/init.c",
        "/vendor/src/segment.c",
        "/vendor/src/arena.c",
        "/vendor/src/stats.c",
    }) catch @panic("error");
    for (sources.items) |src| {
        lib.addCSourceFile(b.fmt("{s}{s}", .{thisDir(), src}), c_flags.items);
    }
    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}