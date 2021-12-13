const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;

// During development you might want zls to see all the lib packages, remember to reset to false.
const IncludeAllLibs = false;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) void {
    // Options.
    const path = b.option([]const u8, "path", "Path to file, for: test-file, run") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const v8 = b.option(bool, "v8", "Link v8 lib") orelse false;
    const static_link = b.option(bool, "static", "Statically link deps") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);

    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_graphics = graphics,
        .link_v8 = v8,
        .static_link = static_link,
        .path = path,
        .filter = filter,
        .mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
        .build_options = build_options,
    };

    const get_deps = GetDepsStep.create(b);
    b.step("get-deps", "Clone/pull the required external dependencies into vendor folder").dependOn(&get_deps.step);

    const build_lyon = BuildLyonStep.create(b, ctx.target);
    b.step("lyon", "Builds rust lib with cargo and copies to vendor/prebuilt").dependOn(&build_lyon.step);

    const main_test = ctx.createTestStep();
    b.step("test", "Run tests").dependOn(&main_test.step);

    const test_file = ctx.createTestFileStep();
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    const build_exe = ctx.createBuildExeStep();
    b.step("exe", "Build exe with main file at -Dpath").dependOn(&build_exe.step);

    const run_exe = build_exe.run();
    run_exe.addArgs(args);
    b.step("run", "Run with main file at -Dpath").dependOn(&run_exe.step);

    const build_lib = ctx.createBuildLibStep();
    b.step("lib", "Build lib with main file at -Dpath").dependOn(&build_lib.step);

    const build_wasm = ctx.createBuildWasmBundleStep();
    b.step("wasm", "Build wasm bundle with main file at -Dpath").dependOn(&build_wasm.step);

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
    link_graphics: bool,
    link_v8: bool,
    static_link: bool,
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    build_options: *std.build.OptionsStep,

    fn fromRoot(self: *Self, path: []const u8) []const u8 {
        return self.builder.pathFromRoot(path);
    }

    fn createBuildLibStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const build_options = self.buildOptionsPkg();
        const step = self.builder.addSharedLibrary(name, self.path, .unversioned);
        self.setBuildMode(step);
        self.setTarget(step);

        const output_dir_rel = std.mem.concat(self.builder.allocator, u8, &[_][]const u8{ "zig-out/", name }) catch unreachable;
        const output_dir = self.fromRoot(output_dir_rel);
        step.setOutputDir(output_dir);

        addStdx(step, build_options);
        addGraphics(step);
        self.addDeps(step);

        return step;
    }

    // Similar to createBuildLibStep except we also copy over index.html and required js libs.
    fn createBuildWasmBundleStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const build_options = self.buildOptionsPkg();
        const step = self.builder.addSharedLibrary(name, self.path, .unversioned);
        self.setBuildMode(step);
        step.setTarget(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const output_dir_rel = std.mem.concat(self.builder.allocator, u8, &[_][]const u8{ "zig-out/", name }) catch unreachable;
        const output_dir = self.fromRoot(output_dir_rel);
        step.setOutputDir(output_dir);

        addStdx(step, build_options);
        addGraphics(step);
        self.addDeps(step);
        self.copyAssets(step, output_dir_rel);

        // index.html
        var cp = CopyFileStep.create(self.builder, self.fromRoot("./lib/wasm-js/index.html"), self.joinResolvePath(&.{ output_dir, "index.html" }));
        step.step.dependOn(&cp.step);

        // Replace wasm file name in index.html
        const index_path = self.joinResolvePath(&[_][]const u8{ output_dir, "index.html" });
        const new_str = std.mem.concat(self.builder.allocator, u8, &[_][]const u8{ "wasmFile = '", name, ".wasm'" }) catch unreachable;
        const replace = ReplaceInFileStep.create(self.builder, index_path, "wasmFile = 'demo.wasm'", new_str);
        step.step.dependOn(&replace.step);

        // graphics.js
        cp = CopyFileStep.create(self.builder, self.fromRoot("./lib/wasm-js/graphics.js"), self.joinResolvePath(&.{ output_dir, "graphics.js" }));
        step.step.dependOn(&cp.step);

        // stdx.js
        cp = CopyFileStep.create(self.builder, self.fromRoot("./lib/wasm-js/stdx.js"), self.joinResolvePath(&.{ output_dir, "stdx.js" }));
        step.step.dependOn(&cp.step);

        return step;
    }

    fn joinResolvePath(self: *Self, paths: []const []const u8) []const u8 {
        return std.fs.path.join(self.builder.allocator, paths) catch unreachable;
    }

    fn createBuildExeStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const build_options = self.buildOptionsPkg();
        const step = self.builder.addExecutable(name, self.path);
        self.setBuildMode(step);
        self.setTarget(step);

        const output_dir_rel = std.mem.concat(self.builder.allocator, u8, &[_][]const u8{ "zig-out/", name }) catch unreachable;
        const output_dir = self.fromRoot(output_dir_rel);
        step.setOutputDir(output_dir);

        addStdx(step, build_options);
        addGraphics(step);
        self.addDeps(step);
        self.copyAssets(step, output_dir_rel);
        return step;
    }

    fn createTestFileStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest(self.path);
        self.setBuildMode(step);
        self.setTarget(step);
        step.setMainPkgPath(".");

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);
        if (self.link_graphics) {
            addStbtt(step);
            self.buildLinkStbtt(step);
        }

        step.addPackage(build_options);
        self.postStep(step);
        return step;
    }

    fn createTestStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest("./test/main_test.zig");
        self.setBuildMode(step);
        self.setTarget(step);
        // This fixes test files that import above, eg. @import("../foo")
        step.setMainPkgPath(".");

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
        if (self.filter.len > 0) {
            step.setFilter(self.filter);
        }
    }

    fn addDeps(self: *Self, step: *LibExeObjStep) void {
        if (self.link_graphics or IncludeAllLibs) {
            addSDL(step);
            addStbtt(step);
            addGL(step);
            addLyon(step);
            addStbi(step);
        }
        if (self.link_graphics) {
            self.linkSDL(step);
            self.buildLinkStbtt(step);
            linkGL(step);
            self.linkLyon(step, self.target);
            self.buildLinkStbi(step);
        }

        if (self.link_v8 or IncludeAllLibs) {
            addZigV8(step);
        }
        if (self.link_v8) {
            self.linkZigV8(step);
        }
    }

    fn setBuildMode(self: *Self, step: *std.build.LibExeObjStep) void {
        step.setBuildMode(self.mode);
        if (self.mode == .ReleaseSafe) {
            step.strip = true;
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

    fn buildLinkStbtt(self: *Self, step: *LibExeObjStep) void {
        var lib: *LibExeObjStep = undefined;
        // For windows-gnu adding a shared library would result in an almost empty stbtt.lib file leading to undefined symbols during linking.
        // As a workaround we always static link for windows.
        if (self.mode == .ReleaseSafe or self.static_link or self.target.getOsTag() == .windows) {
            lib = self.builder.addStaticLibrary("stbtt", self.fromRoot("./lib/stbtt/stbtt.zig"));
        } else {
            lib = self.builder.addSharedLibrary("stbtt", self.fromRoot("./lib/stbtt/stbtt.zig"), .unversioned);
        }
        lib.addIncludeDir(self.fromRoot("./vendor/stb"));
        lib.linkLibC();
        const c_flags = [_][]const u8{ "-O3", "-DSTB_TRUETYPE_IMPLEMENTATION" };
        lib.addCSourceFile(self.fromRoot("./lib/stbtt/stb_truetype.c"), &c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkStbi(self: *Self, step: *std.build.LibExeObjStep) void {
        var lib: *LibExeObjStep = undefined;
        if (self.mode == .ReleaseSafe or self.static_link or self.target.getOsTag() == .windows) {
            lib = self.builder.addStaticLibrary("stbi", self.fromRoot("./lib/stbi/stbi.zig"));
        } else {
            lib = self.builder.addSharedLibrary("stbi", self.fromRoot("./lib/stbi/stbi.zig"), .unversioned);
        }
        lib.addIncludeDir(self.fromRoot("./vendor/stb"));
        lib.linkLibC();

        const c_flags = [_][]const u8{ "-O3", "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
        lib.addCSourceFiles(&.{ self.fromRoot("./lib/stbi/stb_image.c"), self.fromRoot("./lib/stbi/stb_image_write.c") }, &c_flags);
        step.linkLibrary(lib);
    }

    fn linkZigV8(self: *Self, step: *LibExeObjStep) void {
        if (self.target.getOsTag() == .linux) {
            step.addAssemblyFile("./lib/zig-v8/v8-out/ninja/obj/zig/libc_v8.a");
            step.linkSystemLibrary("unwind");
        } else {
            @panic("Unsupported");
        }
    }

    // TODO: We should probably build SDL locally instead of using a prebuilt version.
    fn linkSDL(self: *Self, step: *LibExeObjStep) void {
        if (builtin.os.tag == .macos and builtin.cpu.arch == .x86_64) {
            if (self.static_link) {
                // "sdl2_config --static-libs" tells us what we need
                step.addFrameworkDir("/System/Library/Frameworks");
                step.linkFramework("Cocoa");
                step.linkFramework("IOKit");
                step.linkFramework("CoreAudio");
                step.linkFramework("CoreVideo");
                step.linkFramework("Carbon");
                step.linkFramework("Metal");
                step.linkFramework("ForceFeedback");
                step.linkFramework("AudioToolbox");
                step.linkFramework("CFNetwork");
                step.linkSystemLibrary("iconv");
                step.linkSystemLibrary("m");
                step.addAssemblyFile("./vendor/prebuilt/mac64/libSDL2.a");
            } else {
                step.addAssemblyFile("./vendor/prebuilt/mac64/libSDL2-2.0.0.dylib");
            }
        } else if (builtin.os.tag == .windows and builtin.cpu.arch == .x86_64) {
            const path = self.fromRoot("./vendor/prebuilt/win64/SDL2.dll");
            step.addAssemblyFile(path);
            if (step.output_dir) |out_dir| {
                const mkpath = MakePathStep.create(self.builder, out_dir);
                step.step.dependOn(&mkpath.step);

                const dst = self.joinResolvePath(&.{ out_dir, "SDL2.dll" });
                const cp = CopyFileStep.create(self.builder, path, dst);
                step.step.dependOn(&cp.step);
            }
        } else {
            step.linkSystemLibrary("SDL2");
        }
    }

    fn linkLyon(self: *Self, step: *LibExeObjStep, target: std.zig.CrossTarget) void {
        if (self.static_link) {
            // Currently static linking lyon requires you to build it yourself.
            step.addAssemblyFile("./lib/clyon/target/release/libclyon.a");
            // Currently clyon needs unwind. It would be nice to remove this dependency.
            step.linkSystemLibrary("unwind");
        } else {
            if (target.getOsTag() == .linux and target.getCpuArch() == .x86_64) {
                step.addAssemblyFile("./vendor/prebuilt/linux64/libclyon.so");
            } else if (target.getOsTag() == .macos and target.getCpuArch() == .x86_64) {
                step.addAssemblyFile("./vendor/prebuilt/mac64/libclyon.dylib");
            } else if (target.getOsTag() == .windows and target.getCpuArch() == .x86_64) {
                const path = self.fromRoot("./vendor/prebuilt/win64/clyon.dll");
                step.addAssemblyFile(path);
                if (step.output_dir) |out_dir| {
                    const mkpath = MakePathStep.create(self.builder, out_dir);
                    step.step.dependOn(&mkpath.step);

                    const dst = self.joinResolvePath(&.{ out_dir, "clyon.dll" });
                    const cp = CopyFileStep.create(self.builder, path, dst);
                    step.step.dependOn(&cp.step);
                }
            } else {
                step.addLibPath("./lib/clyon/target/release");
                step.linkSystemLibrary("clyon");
            }
        }
    }

    fn buildLinkMock(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addSharedLibrary("mock", self.fromRoot("./test/lib_mock.zig"), .unversioned);
        addGL(lib);
        step.linkLibrary(lib);
    }

    fn copyAssets(self: *Self, step: *LibExeObjStep, output_dir_rel: []const u8) void {
        if (self.path.len == 0) {
            return;
        }
        // Parses the main file for @buildCopy in doc comments
        const main_path = self.fromRoot(self.path);
        const main_dir = std.fs.path.dirname(main_path).?;
        const file = std.fs.openFileAbsolute(main_path, .{ .read = true, .write = false }) catch unreachable;
        defer file.close();
        const source = file.readToEndAllocOptions(self.builder.allocator, 1024 * 1000 * 10, null, @alignOf(u8), 0) catch unreachable;
        defer self.builder.allocator.free(source);

        var tree = std.zig.parse(self.builder.allocator, source) catch unreachable;
        defer tree.deinit(self.builder.allocator);

        const mkpath = MakePathStep.create(self.builder, output_dir_rel);
        step.step.dependOn(&mkpath.step);

        const output_dir_abs = self.fromRoot(output_dir_rel);

        const root_members = tree.rootDecls();
        for (root_members) |member| {
            // Search for doc comments.
            const tok_start = tree.firstToken(member);
            if (tok_start == 0) {
                continue;
            }
            var tok = tok_start - 1;
            while (tok >= 0) {
                if (tree.tokens.items(.tag)[tok] == .doc_comment) {
                    const str = tree.tokenSlice(tok);
                    var i: usize = 0;
                    i = std.mem.indexOfScalarPos(u8, str, i, '@') orelse continue;
                    var end = std.mem.indexOfScalarPos(u8, str, i, ' ') orelse continue;
                    if (!std.mem.eql(u8, str[i..end], "@buildCopy")) continue;
                    i = std.mem.indexOfScalarPos(u8, str, i, '"') orelse continue;
                    end = std.mem.indexOfScalarPos(u8, str, i + 1, '"') orelse continue;
                    const src_path = std.fs.path.resolve(self.builder.allocator, &[_][]const u8{ main_dir, str[i + 1 .. end] }) catch unreachable;
                    i = std.mem.indexOfScalarPos(u8, str, end + 1, '"') orelse continue;
                    end = std.mem.indexOfScalarPos(u8, str, i + 1, '"') orelse continue;
                    const dst_path = std.fs.path.resolve(self.builder.allocator, &[_][]const u8{ output_dir_abs, str[i + 1 .. end] }) catch unreachable;

                    const cp = CopyFileStep.create(self.builder, src_path, dst_path);
                    step.step.dependOn(&cp.step);
                } else {
                    break;
                }
                if (tok > 0) tok -= 1;
            }
        }
    }
};

const zig_v8_pkg = Pkg{
    .name = "zig-v8",
    .path = FileSource.relative("./lib/zig-v8/src/v8.zig"),
};

fn addZigV8(step: *LibExeObjStep) void {
    step.addPackage(zig_v8_pkg);
    step.linkLibC();
    step.addIncludeDir("./lib/zig-v8/src");
}

const sdl_pkg = Pkg{
    .name = "sdl",
    .path = FileSource.relative("./lib/sdl/sdl.zig"),
};

fn addSDL(step: *LibExeObjStep) void {
    step.addPackage(sdl_pkg);
    step.linkLibC();
    step.addIncludeDir("./vendor");
}

const lyon_pkg = Pkg{
    .name = "lyon",
    .path = FileSource.relative("./lib/clyon/lyon.zig"),
};

fn addLyon(step: *LibExeObjStep) void {
    step.addPackage(lyon_pkg);
    step.addIncludeDir("./lib/clyon");
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
    if (builtin.os.tag == .macos) {
        step.addLibPath("/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries");
        step.linkSystemLibrary("GL");
    } else if (builtin.os.tag == .windows) {
        step.linkSystemLibrary("opengl32");
    } else {
        step.linkSystemLibrary("GL");
    }
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

    var gl = gl_pkg;
    gl.dependencies = &.{ sdl_pkg, stdx_pkg };

    pkg.dependencies = &.{ stbi_pkg, stbtt_pkg, gl, sdl_pkg, stdx_pkg, lyon };
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
            .step = std.build.Step.init(.custom, builder.fmt("lyon", .{}), builder.allocator, make),
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

const MakePathStep = struct {
    const Self = @This();

    step: std.build.Step,
    b: *Builder,
    path: []const u8,

    fn create(b: *Builder, root_path: []const u8) *Self {
        const new = b.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("make-path", .{}), b.allocator, make),
            .b = b,
            .path = root_path,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);
        try self.b.makePath(self.path);
    }
};

const CopyFileStep = struct {
    const Self = @This();

    step: std.build.Step,
    b: *Builder,
    src_path: []const u8,
    dst_path: []const u8,

    fn create(b: *Builder, src_path: []const u8, dst_path: []const u8) *Self {
        const new = b.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("cp", .{}), b.allocator, make),
            .b = b,
            .src_path = src_path,
            .dst_path = dst_path,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);
        try std.fs.copyFileAbsolute(self.src_path, self.dst_path, .{});
    }
};

const ReplaceInFileStep = struct {
    const Self = @This();

    step: std.build.Step,
    b: *Builder,
    path: []const u8,
    old_str: []const u8,
    new_str: []const u8,

    fn create(b: *Builder, path: []const u8, old_str: []const u8, new_str: []const u8) *Self {
        const new = b.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("replace_in_file", .{}), b.allocator, make),
            .b = b,
            .path = path,
            .old_str = old_str,
            .new_str = new_str,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const file = std.fs.openFileAbsolute(self.path, .{ .read = true, .write = false }) catch unreachable;
        errdefer file.close();
        const source = file.readToEndAllocOptions(self.b.allocator, 1024 * 1000 * 10, null, @alignOf(u8), 0) catch unreachable;
        defer self.b.allocator.free(source);

        const new_source = std.mem.replaceOwned(u8, self.b.allocator, source, self.old_str, self.new_str) catch unreachable;
        file.close();

        const write = std.fs.openFileAbsolute(self.path, .{ .read = false, .write = true }) catch unreachable;
        defer write.close();
        write.writeAll(new_source) catch unreachable;
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

        var path = self.builder.pathFromRoot("./vendor");
        if ((try statPath(path)) == .NotExist) {
            _ = try self.builder.exec(&[_][]const u8{ "git", "clone", "--depth=1", "https://github.com/fubark/cosmic-vendor", path });
        }

        path = self.builder.pathFromRoot("./lib/zig-v8");
        if ((try statPath(path)) == .NotExist) {
            _ = try self.builder.exec(&[_][]const u8{ "git", "clone", "--depth=1", "https://github.com/fubark/zig-v8", path });
        }
    }
};

const PathStat = enum {
    NotExist,
    Directory,
    File,
    SymLink,
    Unknown,
};

fn statPath(path_abs: []const u8) !PathStat {
    const file = std.fs.openFileAbsolute(path_abs, .{ .read = false, .write = false }) catch |err| {
        if (err == error.FileNotFound) {
            return .NotExist;
        } else {
            return err;
        }
    };
    defer file.close();

    const stat = try file.stat();
    switch (stat.kind) {
        .SymLink => return .SymLink,
        .Directory => return .Directory,
        .File => return .File,
        else => return .Unknown,
    }
}