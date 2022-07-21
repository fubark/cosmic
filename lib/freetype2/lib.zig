const std = @import("std");

// Enable different modules in ftmodule.h.
// /include has config overrides.

// Minor changes:
// 1. Added "#include <freetype/internal/ftmmtypes.h>" to ttgxvar.h to fix "unknown type name 'GX_ItemVarStoreRec'"

pub const pkg = std.build.Pkg{
    .name = "freetype",
    .source = .{ .path = srcPath() ++ "/freetype.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/include");
    step.addIncludeDir(srcPath() ++ "/vendor/include");
    if (step.target.getCpuArch().isWasm()) {
        step.addIncludeDir(srcPath() ++ "/../wasm/include");
    }
    step.linkLibC();
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    const build_mode = step.build_mode;

    const b = step.builder;
    const lib = b.addStaticLibrary("freetype2", null);
    lib.setTarget(target);
    lib.setBuildMode(build_mode);
    lib.addIncludeDir(srcPath() ++ "/include");
    lib.addIncludeDir(srcPath() ++ "/vendor/include");
    if (target.getCpuArch().isWasm()) {
        lib.addIncludeDir(srcPath() ++ "/../wasm/include");
    }
    lib.linkLibC();

    var c_flags = std.ArrayList([]const u8).init(step.builder.allocator);
    c_flags.append("-DFT2_BUILD_LIBRARY") catch @panic("error");
    if (build_mode == .Debug) {
        c_flags.append("-DFT_DEBUG_LEVEL_ERROR") catch @panic("error");
    }

    const src_files: []const []const u8 = &.{
        srcPath() ++ "/vendor/src/base/ftinit.c",
        srcPath() ++ "/vendor/src/base/ftsystem.c",
        srcPath() ++ "/vendor/src/base/ftobjs.c",
        srcPath() ++ "/vendor/src/base/ftstream.c",
        srcPath() ++ "/vendor/src/base/ftutil.c",
        srcPath() ++ "/vendor/src/base/ftdebug.c",
        srcPath() ++ "/vendor/src/base/ftgloadr.c",
        srcPath() ++ "/vendor/src/base/ftfntfmt.c",
        srcPath() ++ "/vendor/src/base/ftrfork.c",
        srcPath() ++ "/vendor/src/base/ftcalc.c",
        srcPath() ++ "/vendor/src/base/fttrigon.c",
        srcPath() ++ "/vendor/src/base/ftoutln.c",
        srcPath() ++ "/vendor/src/base/ftlcdfil.c",
        srcPath() ++ "/vendor/src/base/fterrors.c",
        srcPath() ++ "/vendor/src/base/ftbitmap.c",

        // ttf driver, depends on sfnt driver.
        srcPath() ++ "/vendor/src/truetype/ttdriver.c",
        srcPath() ++ "/vendor/src/truetype/ttgload.c",
        srcPath() ++ "/vendor/src/truetype/ttgxvar.c",
        srcPath() ++ "/vendor/src/truetype/ttinterp.c",
        srcPath() ++ "/vendor/src/truetype/ttobjs.c",
        srcPath() ++ "/vendor/src/truetype/ttpload.c",

        // sfnt driver.
        srcPath() ++ "/vendor/src/sfnt/sfdriver.c",
        srcPath() ++ "/vendor/src/sfnt/sfobjs.c",
        srcPath() ++ "/vendor/src/sfnt/ttload.c",
        srcPath() ++ "/vendor/src/sfnt/ttmtx.c",
        srcPath() ++ "/vendor/src/sfnt/ttkern.c",
        srcPath() ++ "/vendor/src/sfnt/ttcolr.c",
        srcPath() ++ "/vendor/src/sfnt/ttcmap.c",
        srcPath() ++ "/vendor/src/sfnt/ttcpal.c",
        srcPath() ++ "/vendor/src/sfnt/ttsvg.c",
        srcPath() ++ "/vendor/src/sfnt/ttsbit.c",
        srcPath() ++ "/vendor/src/sfnt/ttpost.c",
        // srcPath() ++ "/vendor/src/sfnt/sfwoff.c",

        // Renderers.
        srcPath() ++ "/vendor/src/smooth/smooth.c",
        srcPath() ++ "/vendor/src/smooth/ftgrays.c",
    };
    lib.addCSourceFiles(src_files, c_flags.items);

    if (target.getOsTag() == .windows) {

    } else {

    }

    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
