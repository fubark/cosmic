const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) void {
    // Options.
    const path = b.option([]const u8, "path", "Path to file, for: test-file, run") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const link_stbtt = b.option(bool, "stbtt", "Link stbtt") orelse false;
    const graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);

    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_stbtt = link_stbtt,
        .link_sdl = false,
        .link_gl = false,
        .link_stbi = false,
        .link_lyon = false,
        .path = path,
        .filter = filter,
        .mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
        .build_options = build_options,
    };
    if (graphics) {
        ctx.link_sdl = true;
        ctx.link_stbtt = true;
        ctx.link_stbi = true;
        ctx.link_gl = true;
        ctx.link_lyon = true;
    }

    const get_deps = GetDepsStep.create(b);
    b.step("get-deps", "Clone/pull the required external dependencies into vendor folder").dependOn(&get_deps.step);

    const build_lyon = BuildLyonStep.create(b, ctx.target);
    b.step("build-lyon", "Builds rust lib with cargo and copies to vendor/prebuilt").dependOn(&build_lyon.step);

    const main_test = ctx.createTestStep();
    b.step("test", "Run tests").dependOn(&main_test.step);

    const test_file = ctx.createTestFileStep();
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    const run = ctx.createRunStep();
    b.step("run", "Run with main file defined by -Dpath").dependOn(&run.run().step);

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
    link_stbtt: bool,
    link_stbi: bool,
    link_sdl: bool,
    link_gl: bool,
    link_lyon: bool,
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    build_options: *std.build.OptionsStep,

    fn fromRoot(self: *Self, path: []const u8) []const u8 {
        return self.builder.pathFromRoot(path);
    }

    fn createRunStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addExecutable("run", self.path);
        step.setBuildMode(self.mode);
        self.setTarget(step);

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        if (self.link_sdl) {
            addSDL(step);
            linkSDL(step);
        }
        if (self.link_stbtt) {
            addStbtt(step);
            self.buildLinkStbtt(step);
        }
        if (self.link_gl) {
            addGL(step);
            linkGL(step);
        }
        if (self.link_stbi) {
            addStbi(step);
            self.buildLinkStbi(step);
        }
        if (self.link_lyon) {
            addLyon(step);
            linkLyon(step, self.target);
        }
        addGraphics(step);

        return step;
    }

    fn createTestFileStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest(self.path);
        step.setBuildMode(self.mode);
        self.setTarget(step);
        step.setMainPkgPath(".");
        step.setFilter(self.filter);

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);
        if (self.link_stbtt) {
            addStbtt(step);
            self.buildLinkStbtt(step);
        }

        step.addPackage(build_options);
        self.postStep(step);
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
        addGraphics(step);

        // Add external lib headers but link with mock lib.
        addStbtt(step);
        addGL(step);
        addLyon(step);
        addSDL(step);
        self.buildLinkMock(step);

        step.addPackage(build_options);
        self.postStep(step);
        return step;
    }

    fn postStep(self: *Self, step: *std.build.LibExeObjStep) void {
        if (self.enable_tracy) {
            self.linkTracy(step);
        }
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

    fn buildLinkStbtt(self: *BuilderContext, step: *LibExeObjStep) void {
        const lib = self.builder.addSharedLibrary("stbtt", self.fromRoot("./lib/stbtt/stbtt.zig"), .unversioned);
        lib.addIncludeDir(self.fromRoot("./vendor/stb"));
        lib.linkLibC();
        const c_flags = [_][]const u8{ "-O3", "-DSTB_TRUETYPE_IMPLEMENTATION" };
        lib.addCSourceFile(self.fromRoot("./lib/stbtt/stb_truetype.c"), &c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkStbi(self: *BuilderContext, step: *std.build.LibExeObjStep) void {
        const lib = self.builder.addSharedLibrary("stbi", self.fromRoot("./lib/stbi/stbi.zig"), .unversioned);
        lib.addIncludeDir(self.fromRoot("./vendor/stb"));
        lib.linkLibC();

        const c_flags = [_][]const u8{ "-O3", "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
        lib.addCSourceFiles(&.{ self.fromRoot("./lib/stbi/stb_image.c"), self.fromRoot("./lib/stbi/stb_image_write.c") }, &c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkMock(self: *BuilderContext, step: *LibExeObjStep) void {
        const lib = self.builder.addSharedLibrary("mock", self.fromRoot("./test/lib_mock.zig"), .unversioned);
        addGL(lib);
        step.linkLibrary(lib);
    }
};

const sdl_pkg = Pkg{
    .name = "sdl",
    .path = FileSource.relative("./lib/sdl/sdl.zig"),
};

fn addSDL(step: *LibExeObjStep) void {
    step.addPackage(sdl_pkg);
    step.linkLibC();
    step.addIncludeDir("./vendor");
}

fn linkSDL(step: *LibExeObjStep) void {
    step.linkSystemLibrary("SDL2");
}

const lyon_pkg = Pkg{
    .name = "lyon",
    .path = FileSource.relative("./lib/clyon/lyon.zig"),
};

fn addLyon(step: *LibExeObjStep) void {
    step.addPackage(lyon_pkg);
    step.addIncludeDir("./lib/clyon");
}

fn linkLyon(step: *LibExeObjStep, target: std.zig.CrossTarget) void {
    if (target.getOsTag() == .linux and target.getCpuArch() == .x86_64) {
        step.addLibPath("./vendor/prebuilt/linux64");
    } else {
        step.addLibPath("./lib/clyon/target/release");
    }
    step.linkSystemLibrary("clyon");
}

const gl_pkg = Pkg{
    .name = "gl",
    .path = FileSource.relative("./lib/gl/gl.zig"),
};

fn addGL(step: *LibExeObjStep) void {
    step.addPackage(gl_pkg);
    step.addIncludeDir("./vendor");
    step.linkLibC();
}

fn linkGL(step: *LibExeObjStep) void {
    step.linkSystemLibrary("GL");
}

const stbi_pkg = Pkg{
    .name = "stbi",
    .path = FileSource.relative("./lib/stbi/stbi.zig"),
};

fn addStbi(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbi_pkg);
    step.addIncludeDir("./vendor/stb");
}

const stbtt_pkg = Pkg{
    .name = "stbtt",
    .path = FileSource.relative("./lib/stbtt/stbtt.zig"),
};

fn addStbtt(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbtt_pkg);
    step.addIncludeDir("./vendor/stb");
    step.linkLibC();
}

const stdx_pkg = Pkg{
    .name = "stdx",
    .path = FileSource.relative("./stdx/stdx.zig"),
};

fn addStdx(step: *std.build.LibExeObjStep, build_options: Pkg) void {
    var pkg = stdx_pkg;
    pkg.dependencies = &.{build_options};
    step.addPackage(pkg);
}

const graphics_pkg = Pkg{
    .name = "graphics",
    .path = FileSource.relative("./graphics/src/graphics.zig"),
};

fn addGraphics(step: *std.build.LibExeObjStep) void {
    var pkg = graphics_pkg;

    var lyon = lyon_pkg;
    lyon.dependencies = &.{stdx_pkg};

    pkg.dependencies = &.{ stbi_pkg, stbtt_pkg, gl_pkg, sdl_pkg, stdx_pkg, lyon };
    step.addPackage(pkg);
}

const common_pkg = Pkg{
    .name = "common",
    .path = FileSource.relative("./common/common.zig"),
};

fn addCommon(step: *std.build.LibExeObjStep) void {
    var pkg = common_pkg;
    pkg.dependencies = &.{stdx_pkg};
    step.addPackage(pkg);
}

const parser_pkg = Pkg{
    .name = "parser",
    .path = FileSource.relative("./parser/parser.zig"),
};

fn addParser(step: *std.build.LibExeObjStep) void {
    var pkg = parser_pkg;
    pkg.dependencies = &.{common_pkg};
    step.addPackage(pkg);
}

const BuildLyonStep = struct {
    const Self = @This();

    step: std.build.Step,
    builder: *Builder,
    target: std.zig.CrossTarget,

    fn create(builder: *Builder, target: std.zig.CrossTarget) *Self {
        const new = builder.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, builder.fmt("build_lyon", .{}), builder.allocator, make),
            .builder = builder,
            .target = target,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const toml_path = self.builder.pathFromRoot("./lib/clyon/Cargo.toml");
        _ = try self.builder.exec(&[_][]const u8{ "cargo", "build", "--release", "--manifest-path", toml_path });

        if (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64) {
            const out_file = self.builder.pathFromRoot("./lib/clyon/target/release/libclyon.so");
            const to_path = self.builder.pathFromRoot("./vendor/prebuilt/linux64/libclyon.so");
            _ = try self.builder.exec(&[_][]const u8{ "cp", out_file, to_path });
            _ = try self.builder.exec(&[_][]const u8{ "strip", to_path });
        }
    }
};

const GetDepsStep = struct {
    const Self = @This();

    step: std.build.Step,
    builder: *Builder,

    fn create(builder: *Builder) *Self {
        const new = builder.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, builder.fmt("get_deps", .{}), builder.allocator, make),
            .builder = builder,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);
        var exists = true;
        const path = self.builder.pathFromRoot("./vendor");
        std.fs.accessAbsolute(path, .{}) catch {
            exists = false;
        };
        if (exists) {
            const alloc = self.builder.allocator;
            const res = try std.ChildProcess.exec(.{
                .allocator = alloc,
                .argv = &[_][]const u8{ "git", "pull" },
                .cwd = path,
                .max_output_bytes = 50 * 1024,
            });
            defer {
                alloc.free(res.stdout);
                alloc.free(res.stderr);
            }
            std.debug.print("{s}{s}", .{ res.stdout, res.stderr });
            switch (res.term) {
                .Exited => |code| {
                    if (code != 0) {
                        return error.ExitCodeFailure;
                    }
                },
                .Signal, .Stopped, .Unknown => {
                    return error.ProcessTerminated;
                },
            }
        } else {
            _ = try self.builder.exec(&[_][]const u8{ "git", "clone", "--depth=1", "https://github.com/fubark/cosmic-vendor", path });
        }
    }
};
