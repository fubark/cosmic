const std = @import("std");

const sdl = @import("../sdl/lib.zig");

// Generate build_info.h in glslang repo root with: ./build_info.py . -i build_info.h.tmpl -o glslang/build_info.h 

pub const pkg = std.build.Pkg{
    .name = "glslang",
    .source = .{ .path = srcPath() ++ "/glslang.zig" },
    .dependencies = &.{},
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    step.addPackage(new_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("glslang", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/vendor");
    lib.linkLibCpp();

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.appendSlice(&.{ "-std=c++17" }) catch @panic("error");
    if (step.build_mode == .Debug) {
        // c_flags.append("-O0") catch @panic("error");
    }

    var sources = std.ArrayList([]const u8).init(b.allocator);
    sources.appendSlice(&.{
        "/vendor/glslang/CInterface/glslang_c_interface.cpp",
        "/vendor/glslang/GenericCodeGen/Link.cpp",
        "/vendor/glslang/GenericCodeGen/CodeGen.cpp",
        "/vendor/glslang/MachineIndependent/Constant.cpp",
        "/vendor/glslang/MachineIndependent/InfoSink.cpp",
        "/vendor/glslang/MachineIndependent/Initialize.cpp",
        "/vendor/glslang/MachineIndependent/Intermediate.cpp",
        "/vendor/glslang/MachineIndependent/IntermTraverse.cpp",
        "/vendor/glslang/MachineIndependent/ParseContextBase.cpp",
        "/vendor/glslang/MachineIndependent/ParseHelper.cpp",
        "/vendor/glslang/MachineIndependent/PoolAlloc.cpp",
        "/vendor/glslang/MachineIndependent/RemoveTree.cpp",
        "/vendor/glslang/MachineIndependent/Scan.cpp",
        "/vendor/glslang/MachineIndependent/ShaderLang.cpp",
        "/vendor/glslang/MachineIndependent/SpirvIntrinsics.cpp",
        "/vendor/glslang/MachineIndependent/SymbolTable.cpp",
        "/vendor/glslang/MachineIndependent/Versions.cpp",
        "/vendor/glslang/MachineIndependent/attribute.cpp",
        "/vendor/glslang/MachineIndependent/glslang_tab.cpp",
        "/vendor/glslang/MachineIndependent/intermOut.cpp",
        "/vendor/glslang/MachineIndependent/iomapper.cpp",
        "/vendor/glslang/MachineIndependent/limits.cpp",
        "/vendor/glslang/MachineIndependent/linkValidate.cpp",
        "/vendor/glslang/MachineIndependent/parseConst.cpp",
        "/vendor/glslang/MachineIndependent/propagateNoContraction.cpp",
        "/vendor/glslang/MachineIndependent/reflection.cpp",
        "/vendor/glslang/MachineIndependent/preprocessor/Pp.cpp",
        "/vendor/glslang/MachineIndependent/preprocessor/PpAtom.cpp",
        "/vendor/glslang/MachineIndependent/preprocessor/PpContext.cpp",
        "/vendor/glslang/MachineIndependent/preprocessor/PpScanner.cpp",
        "/vendor/glslang/MachineIndependent/preprocessor/PpTokens.cpp",
        "/vendor/SPIRV/CInterface/spirv_c_interface.cpp",
        "/vendor/SPIRV/GlslangToSpv.cpp",
        "/vendor/SPIRV/InReadableOrder.cpp",
        "/vendor/SPIRV/Logger.cpp",
        "/vendor/SPIRV/SpvBuilder.cpp",
        "/vendor/SPIRV/SpvPostProcess.cpp",
        "/vendor/OGLCompilersDLL/InitializeDll.cpp",
        "/vendor/StandAlone/ResourceLimits.cpp",
        "/vendor/StandAlone/resource_limits_c.cpp",
    }) catch @panic("error");
    if (step.target.getOsTag() == .windows) {
        sources.appendSlice(&.{
            "/vendor/glslang/OSDependent/Windows/ossource.cpp",
        }) catch @panic("error");
    } else {
        sources.appendSlice(&.{
            "/vendor/glslang/OSDependent/Unix/ossource.cpp",
        }) catch @panic("error");
    }

    for (sources.items) |src| {
        lib.addCSourceFile(b.fmt("{s}{s}", .{srcPath(), src}), c_flags.items);
    }
    step.linkLibrary(lib);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}