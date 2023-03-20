const std = @import("std");

// Enable different modules in ftmodule.h.
// /include has config overrides.

// Minor changes:
// 1. Added "#include <freetype/internal/ftmmtypes.h>" to ttgxvar.h to fix "unknown type name 'GX_ItemVarStoreRec'"

pub fn createModule(b: *std.build.Builder) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/freetype.zig" },
        .dependencies = &.{},
    });
    return mod;
}

pub fn addModuleIncludes(step: *std.build.CompileStep) void {
    step.addIncludePath(thisDir() ++ "/vendor");
    step.addIncludePath(thisDir() ++ "/include");
    step.addIncludePath(thisDir() ++ "/vendor/include");
    if (step.target.getCpuArch().isWasm()) {
        step.addIncludePath(thisDir() ++ "/../wasm/include");
    }
    // step.linkLibC();
}

pub fn addModule(step: *std.build.CompileStep, name: []const u8, mod: *std.build.Module) void {
    addModuleIncludes(step);
    step.addModule(name, mod);
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    const build_mode = step.optimize;

    const lib = step.builder.addStaticLibrary(.{
        .name = "freetype2",
        .target = step.target,
        .optimize = step.optimize,
    });
    lib.addIncludePath(thisDir() ++ "/include");
    lib.addIncludePath(thisDir() ++ "/vendor/include");
    if (target.getCpuArch().isWasm()) {
        lib.addIncludePath(thisDir() ++ "/../wasm/include");
    }
    lib.linkLibC();

    var c_flags = std.ArrayList([]const u8).init(step.builder.allocator);
    c_flags.append("-DFT2_BUILD_LIBRARY") catch @panic("error");
    if (build_mode == .Debug) {
        c_flags.append("-DFT_DEBUG_LEVEL_ERROR") catch @panic("error");
    }

    const src_files: []const []const u8 = &.{
        thisDir() ++ "/vendor/src/base/ftinit.c",
        thisDir() ++ "/vendor/src/base/ftsystem.c",
        thisDir() ++ "/vendor/src/base/ftobjs.c",
        thisDir() ++ "/vendor/src/base/ftstream.c",
        thisDir() ++ "/vendor/src/base/ftutil.c",
        thisDir() ++ "/vendor/src/base/ftdebug.c",
        thisDir() ++ "/vendor/src/base/ftgloadr.c",
        thisDir() ++ "/vendor/src/base/ftfntfmt.c",
        thisDir() ++ "/vendor/src/base/ftrfork.c",
        thisDir() ++ "/vendor/src/base/ftcalc.c",
        thisDir() ++ "/vendor/src/base/fttrigon.c",
        thisDir() ++ "/vendor/src/base/ftoutln.c",
        thisDir() ++ "/vendor/src/base/ftlcdfil.c",
        thisDir() ++ "/vendor/src/base/fterrors.c",
        thisDir() ++ "/vendor/src/base/ftbitmap.c",

        // ttf driver, depends on sfnt driver.
        thisDir() ++ "/vendor/src/truetype/ttdriver.c",
        thisDir() ++ "/vendor/src/truetype/ttgload.c",
        thisDir() ++ "/vendor/src/truetype/ttgxvar.c",
        thisDir() ++ "/vendor/src/truetype/ttinterp.c",
        thisDir() ++ "/vendor/src/truetype/ttobjs.c",
        thisDir() ++ "/vendor/src/truetype/ttpload.c",

        // sfnt driver.
        thisDir() ++ "/vendor/src/sfnt/sfdriver.c",
        thisDir() ++ "/vendor/src/sfnt/sfobjs.c",
        thisDir() ++ "/vendor/src/sfnt/ttload.c",
        thisDir() ++ "/vendor/src/sfnt/ttmtx.c",
        thisDir() ++ "/vendor/src/sfnt/ttkern.c",
        thisDir() ++ "/vendor/src/sfnt/ttcolr.c",
        thisDir() ++ "/vendor/src/sfnt/ttcmap.c",
        thisDir() ++ "/vendor/src/sfnt/ttcpal.c",
        thisDir() ++ "/vendor/src/sfnt/ttsvg.c",
        thisDir() ++ "/vendor/src/sfnt/ttsbit.c",
        thisDir() ++ "/vendor/src/sfnt/ttpost.c",
        // thisDir() ++ "/vendor/src/sfnt/sfwoff.c",

        // Renderers.
        thisDir() ++ "/vendor/src/smooth/smooth.c",
        thisDir() ++ "/vendor/src/smooth/ftgrays.c",
    };
    lib.addCSourceFiles(src_files, c_flags.items);

    if (target.getOsTag() == .windows) {

    } else {

    }

    step.linkLibrary(lib);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}