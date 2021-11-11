const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) void {
    // Options.
    const path = b.option([]const u8, "path", "For single-test") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);

    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .path = path,
        .filter = filter,
        .mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
        .build_options = build_options,
    };

    const main_test = ctx.createTestStep();
    b.step("test", "Run tests").dependOn(&main_test.step);

    const test_file = ctx.createTestFileStep();
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    // Whitelist test is useful for running tests that were manually included with an INCLUDE prefix.
    const whitelist_test = ctx.createTestStep();
    whitelist_test.setFilter("INCLUDE");
    b.step("whitelist-test", "Tests with INCLUDE in name").dependOn(&whitelist_test.step);

    b.default_step.dependOn(&main_test.step);
}

const BuilderContext = struct {
    const Self = @This();

    path: []const u8,
    filter: []const u8,
    enable_tracy: bool,
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    build_options: *std.build.OptionsStep,

    fn createTestFileStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest(self.path);
        step.setBuildMode(self.mode);
        self.setTarget(step);
        step.setMainPkgPath(".");
        step.setFilter(self.filter);

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);

        self.linkTracy(step);
        step.addPackage(build_options);
        return step;
    }

    fn createTestStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest("./test/main_test.zig");
        step.setBuildMode(self.mode);
        self.setTarget(step);
        // This fixes test files that import above, eg. @import("../foo")
        step.setMainPkgPath(".");
        step.setFilter(self.filter);

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);

        self.linkTracy(step);
        step.addPackage(build_options);
        return step;
    }

    fn setTarget(self: *Self, step: *std.build.LibExeObjStep) void {
        var target = self.target;
        if (target.os_tag == null) {
            // Native
            if (builtin.target.os.tag == .linux and self.enable_tracy) {
                // tracy seems to require glibc 2.18, only override if less.
                target = std.zig.CrossTarget.fromTarget(builtin.target);
                const min_ver = std.zig.CrossTarget.SemVer.parse("2.18") catch unreachable;
                if (std.zig.CrossTarget.SemVer.order(target.glibc_version.?, min_ver) == .lt) {
                    target.glibc_version = min_ver;
                }
            }
        }
        step.setTarget(target);
    }

    fn buildOptionsPkg(self: *Self) std.build.Pkg {
        return self.build_options.getPackage("build_options");
    }

    fn linkTracy(self: *Self, step: *std.build.LibExeObjStep) void {
        if (self.enable_tracy) {
            const path = "lib/tracy";
            const client_cpp = std.fs.path.join(
                self.builder.allocator,
                &[_][]const u8{ path, "TracyClient.cpp" },
            ) catch unreachable;

            const tracy_c_flags: []const []const u8 = &[_][]const u8{
                "-DTRACY_ENABLE=1",
                "-fno-sanitize=undefined",
                // "-DTRACY_NO_EXIT=1"
            };

            step.addIncludeDir(path);
            step.addCSourceFile(client_cpp, tracy_c_flags);
            step.linkSystemLibraryName("c++");
            step.linkLibC();

            // if (target.isWindows()) {
            //     step.linkSystemLibrary("dbghelp");
            //     step.linkSystemLibrary("ws2_32");
            // }
        }
    }
};

const stdx_pkg = Pkg{
    .name = "stdx",
    .path = FileSource.relative("./stdx/stdx.zig"),
};

fn addStdx(step: *std.build.LibExeObjStep, build_options: Pkg) void {
    var pkg = stdx_pkg;
    pkg.dependencies = &.{ build_options };
    step.addPackage(pkg);
}

const common_pkg = Pkg{
    .name = "common",
    .path = FileSource.relative("./common/common.zig"),
};

fn addCommon(step: *std.build.LibExeObjStep) void {
    var pkg = common_pkg;
    pkg.dependencies = &.{ stdx_pkg };
    step.addPackage(pkg);
}

const parser_pkg = Pkg{
    .name = "parser",
    .path = FileSource.relative("./parser/parser.zig"),
};

fn addParser(step: *std.build.LibExeObjStep) void {
    var pkg = parser_pkg;
    pkg.dependencies = &.{ common_pkg };
    step.addPackage(pkg);
}