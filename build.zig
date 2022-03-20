const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const log = std.log.scoped(.build);
const sdl = @import("lib/sdl/lib.zig");
const ssl = @import("lib/openssl/lib.zig");
const zlib = @import("lib/zlib/lib.zig");
const http2 = @import("lib/nghttp2/lib.zig");
const curl = @import("lib/curl/lib.zig");
const uv = @import("lib/uv/lib.zig");
const h2o = @import("lib/h2o/lib.zig");

const VersionName = "v0.1";
const DepsRevision = "5c31d18797ccb0c71adaf6a31beab53a8c070b5c";
const V8_Revision = "9.9.115.9";

// Debugging:
// Set to true to show generated build-lib and other commands created from execFromStep.
const PrintCommands = false;

// Useful in dev to see descrepancies between zig and normal builds.
const LibV8Path: ?[]const u8 = null;
const LibSdlPath: ?[]const u8 = null;
const LibSslPath: ?[]const u8 = null;
const LibCryptoPath: ?[]const u8 = null;
const LibCurlPath: ?[]const u8 = null;
const LibUvPath: ?[]const u8 = null;
const LibH2oPath: ?[]const u8 = null;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) !void {
    // Options.
    const path = b.option([]const u8, "path", "Path to main file, for: build, run, test-file") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const audio = b.option(bool, "audio", "Link audio libs") orelse false;
    const v8 = b.option(bool, "v8", "Link v8 lib") orelse false;
    const net = b.option(bool, "net", "Link net libs") orelse false;
    const static_link = b.option(bool, "static", "Statically link deps") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};
    const deps_rev = b.option([]const u8, "deps-rev", "Override the deps revision.") orelse DepsRevision;
    const is_official_build = b.option(bool, "is-official-build", "Whether the build should be an official build.") orelse false;
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const wsl = b.option(bool, "wsl", "Whether this running in wsl.") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);
    build_options.addOption([]const u8, "VersionName", getVersionString(is_official_build));

    b.verbose = PrintCommands;

    if (builtin.os.tag == .macos and target.getOsTag() == .macos) {
        if (target.isNative()) {
            // NOTE: builder.sysroot or --sysroot <path> should not be set for a native build;
            // zig will use getDarwinSDK by default and not use it's own libc headers (meant for cross compilation)
            // with one small caveat: the lib/exe must be linking with system library or framework. See Compilation.zig.
            // There are lib.linkFramework("CoreServices") in places where we want to force it to use native headers.
            // The target must be: <cpu>-native-gnu
        } else {
            // Targeting mac but not native. eg. targeting macos with a minimum version.
            // Set sysroot with sdk path and use these setups as needed for libs:
            // lib.addFrameworkDir("/System/Library/Frameworks");
            // lib.addSystemIncludeDir("/usr/include");
            // Don't use zig's libc, since it might not be up to date with the latest SDK which we need for frameworks.
            // lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            if (std.zig.system.darwin.getDarwinSDK(b.allocator, builtin.target)) |sdk| {
                b.sysroot = sdk.path;
            }
        }
    }

    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_graphics = graphics,
        .link_audio = audio,
        .link_v8 = v8,
        .link_net = net,
        .link_mock = false,
        .static_link = static_link,
        .path = path,
        .filter = filter,
        .mode = mode,
        .target = target,
        .build_options = build_options,
        .wsl = wsl,
    };

    const get_deps = GetDepsStep.create(b, deps_rev);
    b.step("get-deps", "Clone/pull the required external dependencies into deps folder").dependOn(&get_deps.step);

    const get_v8_lib = createGetV8LibStep(b, target);
    b.step("get-v8-lib", "Fetches prebuilt static lib. Use -Dtarget to indicate target platform").dependOn(&get_v8_lib.step);

    const build_lyon = BuildLyonStep.create(b, ctx.target);
    b.step("lyon", "Builds rust lib with cargo and copies to deps/prebuilt").dependOn(&build_lyon.step);

    {
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const test_exe = ctx.createTestExeStep();
        step.step.dependOn(&test_exe.step);
        const test_install = ctx.addInstallArtifact(test_exe);
        step.step.dependOn(&test_install.step);
        b.step("test-exe", "Creates the test exe.").dependOn(&step.step);
    }

    {
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const test_exe = ctx.createTestExeStep();
        const run_test = test_exe.run();
        step.step.dependOn(&run_test.step);
        b.step("test", "Run tests").dependOn(&step.step);
    }

    {
        var ctx_ = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_audio = true,
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
            .wsl = wsl,
        };
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const test_exe = ctx_.createTestFileStep("test/behavior_test.zig");
        // Set filter so it doesn't run other unit tests (which assume to be linked with lib_mock.zig)
        test_exe.setFilter("behavior:");
        step.step.dependOn(&test_exe.step);
        b.step("test-behavior", "Run behavior tests").dependOn(&step.step);
    }

    const test_file = ctx.createTestFileStep(ctx.path);
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    {
        const step = b.addLog("", .{});
        const build_exe = ctx.createBuildExeStep();
        step.step.dependOn(&build_exe.step);
        step.step.dependOn(&ctx.addInstallArtifact(build_exe).step);
        b.step("exe", "Build exe with main file at -Dpath").dependOn(&step.step);
    }

    {
        const step = b.addLog("", .{});
        const build_exe = ctx.createBuildExeStep();
        step.step.dependOn(&build_exe.step);
        step.step.dependOn(&ctx.addInstallArtifact(build_exe).step);
        const run_exe = build_exe.run();
        run_exe.addArgs(args);
        step.step.dependOn(&run_exe.step);
        b.step("run", "Run with main file at -Dpath").dependOn(&step.step);
    }

    const build_lib = ctx.createBuildLibStep();
    b.step("lib", "Build lib with main file at -Dpath").dependOn(&build_lib.step);

    {
        const step = b.step("openssl", "Build openssl.");
        const crypto = try ssl.createCrypto(b, target, mode);
        step.dependOn(&ctx.addInstallArtifact(crypto).step);
        const ssl_ = try ssl.createSsl(b, target, mode);
        step.dependOn(&ctx.addInstallArtifact(ssl_).step);
    }

    const build_wasm = ctx.createBuildWasmBundleStep();
    b.step("wasm", "Build wasm bundle with main file at -Dpath").dependOn(&build_wasm.step);

    const get_version = b.addLog("{s}", .{getVersionString(is_official_build)});
    b.step("version", "Get the build version.").dependOn(&get_version.step);

    {
        const _build_options = b.addOptions();
        _build_options.addOption([]const u8, "VersionName", VersionName);
        _build_options.addOption([]const u8, "BuildRoot", b.build_root);
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = false,
            .link_graphics = false,
            .link_audio = false,
            .link_v8 = false,
            .link_mock = true,
            .static_link = static_link,
            .path = "tools/gen.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = _build_options,
            .wsl = wsl,
        };

        const step = _ctx.createBuildExeStep();
        _ctx.buildLinkMock(step);
        const run = step.run();
        run.addArgs(args);
        b.step("gen", "Generate tool.").dependOn(&run.step);
    }

    {
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_audio = true,
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
            .wsl = wsl,
        };
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const run = _ctx.createBuildExeStep().run();
        run.addArgs(&.{ "test", "test/js/test.js" });
        // run.addArgs(&.{ "test", "test/load-test/cs-https-request-test.js" });
        step.step.dependOn(&run.step);
    
        b.step("test-cosmic-js", "Test cosmic js").dependOn(&step.step);
    }

    var build_cosmic = b.addLog("", .{});
    {
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_audio = true,
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
            .wsl = wsl,
        };
        const step = build_cosmic;
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const exe = _ctx.createBuildExeStep();
        const exe_install = _ctx.addInstallArtifact(exe);
        step.step.dependOn(&exe_install.step);
        b.step("cosmic", "Build cosmic.").dependOn(&step.step);
    }

    {
        var step = b.addLog("", .{});
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_audio = true,
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
            .wsl = wsl,
        };
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        const exe = _ctx.createBuildExeStep();
        const exe_install = _ctx.addInstallArtifact(exe);
        step.step.dependOn(&exe_install.step);

        const run = exe.run();
        run.addArgs(&.{ "shell" });
        step.step.dependOn(&run.step);
        b.step("cosmic-shell", "Run cosmic in shell mode.").dependOn(&step.step);
    }

    // Whitelist test is useful for running tests that were manually included with an INCLUDE prefix.
    const whitelist_test = ctx.createTestExeStep();
    whitelist_test.setFilter("INCLUDE");
    b.step("whitelist-test", "Tests with INCLUDE in name").dependOn(&whitelist_test.run().step);

    // b.default_step.dependOn(&build_cosmic.step);
}

const BuilderContext = struct {
    const Self = @This();

    builder: *std.build.Builder,
    path: []const u8,
    filter: []const u8,
    enable_tracy: bool,
    link_graphics: bool,
    link_audio: bool,
    link_v8: bool,
    link_net: bool,
    link_mock: bool,
    static_link: bool,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    build_options: *std.build.OptionsStep,
    // This is only used to detect running a linux binary in WSL.
    wsl: bool = false,

    fn fromRoot(self: *Self, path: []const u8) []const u8 {
        return self.builder.pathFromRoot(path);
    }

    fn setOutputDir(self: *Self, obj: *LibExeObjStep, name: []const u8) void {
        const output_dir = self.fromRoot(self.builder.fmt("zig-out/{s}", .{ name }));
        obj.setOutputDir(output_dir);
    }

    fn createBuildLibStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const build_options = self.buildOptionsPkg();
        const step = self.builder.addSharedLibrary(name, self.path, .unversioned);
        self.setBuildMode(step);
        self.setTarget(step);
        self.setOutputDir(step, name);

        addStdx(step, build_options);
        addInput(step);
        addGraphics(step);
        self.addDeps(step) catch unreachable;

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

        const output_dir_rel = std.mem.concat(self.builder.allocator, u8, &.{ "zig-out/", name }) catch unreachable;
        const output_dir = self.fromRoot(output_dir_rel);
        step.setOutputDir(output_dir);

        addStdx(step, build_options);
        addGraphics(step);
        self.addDeps(step) catch unreachable;
        self.copyAssets(step, output_dir_rel);

        // index.html
        var cp = CopyFileStep.create(self.builder, self.fromRoot("./lib/wasm-js/index.html"), self.joinResolvePath(&.{ output_dir, "index.html" }));
        step.step.dependOn(&cp.step);

        // Replace wasm file name in index.html
        const index_path = self.joinResolvePath(&[_][]const u8{ output_dir, "index.html" });
        const new_str = std.mem.concat(self.builder.allocator, u8, &.{ "wasmFile = '", name, ".wasm'" }) catch unreachable;
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

    fn getSimpleTriple(b: *Builder, target: std.zig.CrossTarget) []const u8 {
        return target.toTarget().linuxTriple(b.allocator) catch unreachable;
    }

    fn addInstallArtifact(self: *Self, artifact: *LibExeObjStep) *std.build.InstallArtifactStep {
        const triple = getSimpleTriple(self.builder, artifact.target);
        if (artifact.kind == .exe or artifact.kind == .test_exe) {
            const basename = std.fs.path.basename(artifact.root_src.?.path);
            const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
            const name = basename[0..i];
            const path = self.builder.fmt("{s}/{s}", .{ triple, name });
            artifact.override_dest_dir = .{ .custom = path };
        } else if (artifact.kind == .lib) {
            const path = self.builder.fmt("{s}/lib", .{ triple });
            artifact.override_dest_dir = .{ .custom = path };
        }
        return self.builder.addInstallArtifact(artifact);
    }

    fn createBuildExeStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const build_options = self.buildOptionsPkg();
        const exe = self.builder.addExecutable(name, self.path);
        self.setBuildMode(exe);
        self.setTarget(exe);
        exe.setMainPkgPath(".");

        exe.addPackage(build_options);
        addStdx(exe, build_options);
        addInput(exe);
        addGraphics(exe);
        self.addDeps(exe) catch unreachable;

        _ = self.addInstallArtifact(exe);
        const install_dir = self.builder.fmt("zig-out/{s}", .{exe.install_step.?.dest_dir.custom });
        self.copyAssets(exe, install_dir);
        return exe;
    }

    fn createTestFileStep(self: *Self, path: []const u8) *std.build.LibExeObjStep {
        const step = self.builder.addTest(path);
        self.setBuildMode(step);
        self.setTarget(step);
        step.setMainPkgPath(".");

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);
        addGraphics(step);
        addInput(step);
        self.addDeps(step) catch unreachable;

        step.addPackage(build_options);
        self.postStep(step);
        return step;
    }

    fn createTestExeStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTestExe("main_test", "./test/main_test.zig");
        self.setBuildMode(step);
        self.setTarget(step);
        // This fixes test files that import above, eg. @import("../foo")
        step.setMainPkgPath(".");

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);
        addGraphics(step);
        addInput(step);

        // Add external lib headers but link with mock lib.
        self.addDeps(step) catch unreachable;
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

    fn addDeps(self: *Self, step: *LibExeObjStep) !void {
        addCurl(step);
        addUv(step);
        addH2O(step);
        addOpenSSL(step);
        if (self.link_net) {
            buildLinkCrypto(step);
            buildLinkSsl(step);
            buildLinkCurl(step);
            buildLinkNghttp2(step);
            buildLinkZlib(step);
            buildLinkUv(step);
            buildLinkH2O(step);
        }
        addSDL(step);
        addStbtt(step);
        addGL(step);
        addMiniaudio(step);
        addLyon(step);
        addStbi(step);
        if (self.target.getOsTag() == .macos) {
            self.buildLinkMacSys(step);
        }
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            self.buildMingwExtra(step);
            self.buildLinkWinPosix(step);
            self.buildLinkWinPthreads(step);
        }
        if (self.link_graphics) {
            buildLinkSDL2(step);
            self.buildLinkStbtt(step);
            linkGL(step, self.target);
            self.linkLyon(step, self.target);
            self.buildLinkStbi(step);
        }
        if (self.link_audio) {
            self.buildLinkMiniaudio(step);
        }
        addZigV8(step);
        if (self.link_v8) {
            self.linkZigV8(step);
        }
        if (self.link_mock) {
            self.buildLinkMock(step);
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

    fn buildLinkWinPthreads(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("winpthreads", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);
        lib.linkLibC();
        lib.addIncludeDir("./lib/mingw/winpthreads/include");

        const c_files: []const []const u8 = &.{
            "mutex.c",
            "thread.c",
            "spinlock.c",
            "rwlock.c",
            "cond.c",
            "misc.c",
            "sched.c",
        };

        for (c_files) |c_file| {
            const path = self.builder.fmt("./lib/mingw/winpthreads/{s}", .{c_file});
            lib.addCSourceFile(path, &.{});
        }

        step.linkLibrary(lib);
    }

    fn buildLinkWinPosix(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("win_posix", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);
        lib.linkLibC();
        lib.addIncludeDir("./lib/mingw/win_posix/include");

        const c_files: []const []const u8 = &.{
            "wincompat.c",
            "mman.c",
        };

        for (c_files) |c_file| {
            const path = self.builder.fmt("./lib/mingw/win_posix/{s}", .{c_file});
            lib.addCSourceFile(path, &.{});
        }

        step.linkLibrary(lib);
    }

    fn buildLinkMacSys(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("mac_sys", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        lib.addCSourceFile("./lib/sys/mac_sys.c", &.{});

        if (self.target.isNativeOs()) {
            // Force using native headers or it'll compile with ___darwin_check_fd_set_overflow references.
            lib.linkFramework("CoreServices");
        } else {
            lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
        }

        step.linkLibrary(lib);
    }

    // Missing sources in zig's mingw distribution.
    fn buildMingwExtra(self: *Self, step: *LibExeObjStep) void {
        _ = self;
        step.addCSourceFile("./lib/mingw/ws2tcpip/gai_strerrorA.c", &.{});
        step.addCSourceFile("./lib/mingw/ws2tcpip/gai_strerrorW.c", &.{});
    }

    fn addCSourceFileFmt(self: *Self, lib: *LibExeObjStep, comptime format: []const u8, args: anytype, c_flags: []const []const u8) void {
        const path = std.fmt.allocPrint(self.builder.allocator, format, args) catch unreachable;
        lib.addCSourceFile(self.fromRoot(path), c_flags);
    }

    fn buildLinkStbtt(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("stbtt", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        lib.addIncludeDir(self.fromRoot("./lib/stb/vendor"));
        lib.linkLibC();
        const c_flags = &[_][]const u8{ "-DSTB_TRUETYPE_IMPLEMENTATION" };
        lib.addCSourceFile(self.fromRoot("./lib/stb/stb_truetype.c"), c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkStbi(self: *Self, step: *std.build.LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("stbi", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        lib.addIncludeDir(self.fromRoot("./lib/stb/vendor"));
        lib.linkLibC();

        const c_flags = &[_][]const u8{ "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
        const src_files: []const []const u8 = &.{
            self.fromRoot("./lib/stb/stb_image.c"),
            self.fromRoot("./lib/stb/stb_image_write.c")
        };
        lib.addCSourceFiles(src_files, c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkMiniaudio(self: *Self, step: *std.build.LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("miniaudio", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            if (!self.target.isNative()) {
                lib.addFrameworkDir("/System/Library/Frameworks");
                lib.addSystemIncludeDir("/usr/include");
                lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            }
            lib.linkFramework("CoreAudio");
        }
        // TODO: vorbis has UB when doing seekToPcmFrame.
        lib.disable_sanitize_c = true;

        const c_flags = &[_][]const u8{
        };
        lib.addCSourceFile(self.fromRoot("./lib/miniaudio/src/miniaudio.c"), c_flags);
        lib.linkLibC();
        step.linkLibrary(lib);
    }

    fn linkZigV8(self: *Self, step: *LibExeObjStep) void {
        const path = getV8_StaticLibPath(self.builder, step.target);
        step.addAssemblyFile(path);
        step.linkLibCpp();
        step.linkLibC();
        if (self.target.getOsTag() == .linux) {
            step.linkSystemLibrary("unwind");
        } else if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            step.linkSystemLibrary("winmm");
            step.linkSystemLibrary("dbghelp");
        }
    }

    /// Static link clyon.
    fn linkLyon(self: *Self, step: *LibExeObjStep, target: std.zig.CrossTarget) void {
        if (target.getOsTag() == .linux and target.getCpuArch() == .x86_64) {
            step.addAssemblyFile(self.fromRoot("./deps/prebuilt/linux64/libclyon.a"));
            // Currently clyon needs unwind. How to remove?
            step.linkSystemLibrary("unwind");
        } else if (target.getOsTag() == .macos and target.getCpuArch() == .x86_64) {
            step.addAssemblyFile(self.fromRoot("./deps/prebuilt/mac64/libclyon.a"));
        } else if (target.getOsTag() == .macos and target.getCpuArch() == .aarch64) {
            step.addAssemblyFile(self.fromRoot("./deps/prebuilt/mac-arm64/libclyon.a"));
        } else if (target.getOsTag() == .windows and target.getCpuArch() == .x86_64) {
            step.addAssemblyFile(self.fromRoot("./deps/prebuilt/win64/clyon.lib"));
            step.linkSystemLibrary("bcrypt");
            step.linkSystemLibrary("userenv");
        } else {
            step.addLibPath("./lib/clyon/target/release");
            step.linkSystemLibrary("clyon");
        }
    }

    fn buildLinkMock(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("mock", self.fromRoot("./test/lib_mock.zig"));
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);
        addStdx(lib, self.buildOptionsPkg());
        addGL(lib);
        addUv(lib);
        addZigV8(lib);
        addMiniaudio(lib);
        step.linkLibrary(lib);
    }

    fn copyAssets(self: *Self, step: *LibExeObjStep, output_dir_rel: []const u8) void {
        if (self.path.len == 0) {
            return;
        }
        if (!std.mem.endsWith(u8, self.path, ".zig")) {
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
    .name = "v8",
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
    var pkg = sdl_pkg;
    pkg.dependencies = &.{ stdx_pkg };
    step.addPackage(pkg);
    step.linkLibC();
    step.addIncludeDir("./lib/sdl/vendor/include");
}

const openssl_pkg = Pkg{
    .name = "openssl",
    .path = FileSource.relative("./lib/openssl/openssl.zig"),
};

fn addOpenSSL(step: *LibExeObjStep) void {
    step.addPackage(openssl_pkg);
    step.addIncludeDir("./deps/openssl/include");
}

const h2o_pkg = Pkg{
    .name = "h2o",
    .path = FileSource.relative("./lib/h2o/h2o.zig"),
};

fn addH2O(step: *LibExeObjStep) void {
    var pkg = h2o_pkg;
    pkg.dependencies = &.{uv_pkg, openssl_pkg};
    step.addPackage(pkg);
    step.addIncludeDir("./lib/h2o");
    step.addIncludeDir("./lib/h2o/vendor/include");
    step.addIncludeDir("./lib/h2o/vendor/deps/picotls/include");
    step.addIncludeDir("./lib/h2o/vendor/deps/quicly/include");
    step.addIncludeDir("./lib/openssl/vendor/include");
    if (step.target.getOsTag() == .windows) {
        step.addIncludeDir("./lib/mingw/win_posix/include");
        step.addIncludeDir("./lib/mingw/winpthreads/include");
    }
}

const uv_pkg = Pkg{
    .name = "uv",
    .path = FileSource.relative("./lib/uv/uv.zig"),
};

fn addUv(step: *LibExeObjStep) void {
    step.addPackage(uv_pkg);
    step.addIncludeDir("./lib/uv/vendor/include");
}

const curl_pkg = Pkg{
    .name = "curl",
    .path = FileSource.relative("./lib/curl/curl.zig"),
};

fn addCurl(step: *LibExeObjStep) void {
    step.addPackage(curl_pkg);
    step.addIncludeDir("./lib/curl/vendor/include/curl");
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
    step.addIncludeDir("./lib/gl/vendor");
    step.linkLibC();
}

fn linkGL(step: *LibExeObjStep, target: std.zig.CrossTarget) void {
    switch (target.getOsTag()) {
        .macos => {
            // TODO: Fix this, should be linkFramework instead.

            // TODO: See what this path returns $(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/OpenGL.framework/Headers
            // https://github.com/ziglang/zig/issues/2208
            step.addLibPath("/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries");
            step.linkSystemLibrary("GL");
        },
        .windows =>{
            // Link with OpenGL 1.1 API. Higher API functions should be loaded at runtime through vendors.
            step.linkSystemLibrary("opengl32");
        },
        .linux => {
            // Unable to find libraries if linux is provided in triple.
            // https://github.com/ziglang/zig/issues/8103
            step.addLibPath("/usr/lib/x86_64-linux-gnu");
            step.linkSystemLibrary("GL");
        },
        else => {
            step.linkSystemLibrary("GL");
        },
    }
}

const stbi_pkg = Pkg{
    .name = "stbi",
    .path = FileSource.relative("./lib/stb/stbi.zig"),
};

fn addStbi(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbi_pkg);
    step.addIncludeDir("./lib/stb/vendor");
}

const stbtt_pkg = Pkg{
    .name = "stbtt",
    .path = FileSource.relative("./lib/stb/stbtt.zig"),
};

fn addStbtt(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbtt_pkg);
    step.addIncludeDir("./lib/stb/vendor");
    step.linkLibC();
}

const miniaudio_pkg = Pkg{
    .name = "miniaudio",
    .path = FileSource.relative("./lib/miniaudio/miniaudio.zig"),
};

fn addMiniaudio(step: *std.build.LibExeObjStep) void {
    step.addPackage(miniaudio_pkg);
    step.addIncludeDir("./lib/miniaudio/src");
}

const stdx_pkg = Pkg{
    .name = "stdx",
    .path = FileSource.relative("./stdx/stdx.zig"),
};

fn addStdx(step: *std.build.LibExeObjStep, build_options: Pkg) void {
    var pkg = stdx_pkg;
    pkg.dependencies = &.{build_options, curl_pkg, uv_pkg};
    step.addPackage(pkg);
}

const input_pkg = Pkg{
    .name = "input",
    .path = FileSource.relative("./input/input.zig"),
};

fn addInput(step: *std.build.LibExeObjStep) void {
    var pkg = input_pkg;
    pkg.dependencies = &.{ sdl_pkg, stdx_pkg };
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

    var sdl_ = sdl_pkg;
    sdl_.dependencies = &.{stdx_pkg};

    var gl = gl_pkg;
    gl.dependencies = &.{ sdl_pkg, stdx_pkg };

    pkg.dependencies = &.{ stbi_pkg, stbtt_pkg, gl, sdl_, stdx_pkg, lyon };
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

const GenMacLibCStep = struct {
    const Self = @This();

    step: std.build.Step,
    b: *Builder,
    target: std.zig.CrossTarget,

    fn create(b: *Builder, target: std.zig.CrossTarget) *Self {
        const new = b.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("gen-mac-libc", .{}), b.allocator, make),
            .b = b,
            .target = target,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const path = try std.fs.path.resolve(self.b.allocator, &.{ self.b.sysroot.?, "usr/include"});
        const libc_file = self.b.fmt(
            \\include_dir={s}
            \\sys_include_dir={s}
            \\crt_dir=
            \\msvc_lib_dir=
            \\kernel32_lib_dir=
            \\gcc_dir=
            , .{ path, path },
        );
        try std.fs.cwd().writeFile("./lib/macos.libc", libc_file);
    }
};

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

        if (self.target.getOsTag() == .linux and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--release", "--manifest-path", toml_path });
            const out_file = self.builder.pathFromRoot("./lib/clyon/target/release/libclyon.a");
            const to_path = self.builder.pathFromRoot("./deps/prebuilt/linux64/libclyon.a");
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
            _ = try self.builder.exec(&.{ "strip", "--strip-debug", to_path });
        } else if (self.target.getOsTag() == .windows and self.target.getCpuArch() == .x86_64 and self.target.getAbi() == .gnu) {
            var env_map = try self.builder.allocator.create(std.BufMap);
            env_map.* = try std.process.getEnvMap(self.builder.allocator);
            // Attempted to use zig cc like: https://github.com/ziglang/zig/issues/10336
            // But ran into issues linking with -lgcc_eh
            // try env_map.put("RUSTFLAGS", "-C linker=/Users/fubar/dev/cosmic/zig-cc");
            try env_map.put("RUSTFLAGS", "-C linker=/usr/local/Cellar/mingw-w64/9.0.0_2/bin/x86_64-w64-mingw32-gcc");
            try self.builder.spawnChildEnvMap(null, env_map, &.{
                "cargo", "build", "--target=x86_64-pc-windows-gnu", "--release", "--manifest-path", toml_path,
            });
            const out_file = self.builder.pathFromRoot("./lib/clyon/target/x86_64-pc-windows-gnu/release/libclyon.a");
            const to_path = self.builder.pathFromRoot("./deps/prebuilt/win64/clyon.lib");
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=x86_64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = self.builder.pathFromRoot("./lib/clyon/target/x86_64-apple-darwin/release/libclyon.a");
            const to_path = self.builder.pathFromRoot("./deps/prebuilt/mac64/libclyon.a");
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
            // This actually corrupts the lib and zig will fail to parse it after linking.
            // _ = try self.builder.exec(&[_][]const u8{ "strip", "-S", to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .aarch64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=aarch64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = self.builder.pathFromRoot("./lib/clyon/target/aarch64-apple-darwin/release/libclyon.a");
            const to_path = self.builder.pathFromRoot("./deps/prebuilt/mac-arm64/libclyon.a");
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
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
    b: *Builder,
    deps_rev: []const u8,

    fn create(b: *Builder, deps_rev: []const u8) *Self {
        const new = b.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("get_deps", .{}), b.allocator, make),
            .deps_rev = deps_rev,
            .b = b,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        try syncRepo(self.b, step, "./deps", "https://github.com/fubark/cosmic-deps", self.deps_rev, false);

        // zig-v8 is still changing frequently so pull the repo.
        try syncRepo(self.b, step, "./lib/zig-v8", "https://github.com/fubark/zig-v8", V8_Revision, true);
    }
};

fn createGetV8LibStep(b: *Builder, target: std.zig.CrossTarget) *std.build.LogStep {
    const step = b.addLog("Get V8 Lib\n", .{});

    const url = getV8_StaticLibGithubUrl(b.allocator, V8_Revision, target);
    // log.debug("Url: {s}", .{url});
    const lib_path = getV8_StaticLibPath(b, target);

    if (builtin.os.tag == .windows) {
        var sub_step = b.addSystemCommand(&.{ "powershell", "Invoke-WebRequest", "-Uri", url, "-OutFile", lib_path });
        step.step.dependOn(&sub_step.step);
    } else {
        var sub_step = b.addSystemCommand(&.{ "curl", "-L", url, "-o", lib_path });
        step.step.dependOn(&sub_step.step);
    }
    return step;
}

fn getV8_StaticLibGithubUrl(alloc: std.mem.Allocator, tag: []const u8, target: std.zig.CrossTarget) []const u8 {
    const lib_name: []const u8 = if (target.getOsTag() == .windows) "c_v8" else "libc_v8";
    const lib_ext: []const u8 = if (target.getOsTag() == .windows) "lib" else "a";
    if (target.getCpuArch() == .aarch64 and target.getOsTag() == .macos) {
        return std.fmt.allocPrint(alloc, "https://github.com/fubark/zig-v8/releases/download/{s}/{s}_{s}-{s}-gnu_{s}_{s}.{s}", .{
            tag, lib_name, @tagName(target.getCpuArch()), @tagName(target.getOsTag()), "release", tag, lib_ext,
        }) catch unreachable;
    } else if (target.getOsTag() == .windows) {
        return std.fmt.allocPrint(alloc, "https://github.com/fubark/zig-v8/releases/download/{s}/{s}_{s}-{s}-gnu_{s}_{s}.{s}", .{
            tag, lib_name, @tagName(target.getCpuArch()), @tagName(target.getOsTag()), "release", tag, lib_ext,
        }) catch unreachable;
    } else {
        return std.fmt.allocPrint(alloc, "https://github.com/fubark/zig-v8/releases/download/{s}/{s}_{s}-{s}-gnu_{s}_{s}.{s}", .{
            tag, lib_name, @tagName(target.getCpuArch()), @tagName(target.getOsTag()), "release", tag, lib_ext,
        }) catch unreachable;
    }
}

fn getV8_StaticLibPath(b: *Builder, target: std.zig.CrossTarget) []const u8 {
    if (LibV8Path) |path| {
        return path;
    }
    const lib_name: []const u8 = if (target.getOsTag() == .windows) "c_v8" else "libc_v8";
    const lib_ext: []const u8 = if (target.getOsTag() == .windows) "lib" else "a";
    const triple = BuilderContext.getSimpleTriple(b, target);
    const path = std.fmt.allocPrint(b.allocator, "./lib/zig-v8/{s}-{s}.{s}", .{ lib_name, triple, lib_ext }) catch unreachable;
    return b.pathFromRoot(path);
}

fn syncRepo(b: *Builder, step: *std.build.Step, rel_path: []const u8, remote_url: []const u8, revision: []const u8, is_tag: bool) !void {
    const repo_path = b.pathFromRoot(rel_path);
    if ((try statPath(repo_path)) == .NotExist) {
        _ = try b.execFromStep(&.{ "git", "clone", remote_url, repo_path }, step);
        _ = try b.execFromStep(&.{ "git", "-C", repo_path, "checkout", revision }, step);
    } else {
        var cur_revision: []const u8 = undefined;
        if (is_tag) {
            cur_revision = try b.execFromStep(&.{ "git", "-C", repo_path, "describe", "--tags" }, step);
        } else {
            cur_revision = try b.execFromStep(&.{ "git", "-C", repo_path, "rev-parse", "HEAD" }, step);
        }
        if (!std.mem.eql(u8, cur_revision[0..revision.len], revision)) {
            // Fetch and checkout.
            // Need -f or it will fail if the remote tag now points to a different revision.
            _ = try b.execFromStep(&.{ "git", "-C", repo_path, "fetch", "--tags", "-f" }, step);
            _ = try b.execFromStep(&.{ "git", "-C", repo_path, "checkout", revision }, step);
        }
    }
}

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
        } else if (err == error.IsDir) {
            return .Directory;
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

fn getVersionString(is_official_build: bool) []const u8 {
    if (is_official_build) {
        return VersionName;
    } else {
        return VersionName ++ "-Dev";
    }
}

fn buildLinkSDL2(step: *LibExeObjStep) void {
    if (LibSdlPath) |path| {
        sdl.linkLibPath(step, path);
    } else {
        const lib = sdl.create(step.builder, step.target, step.build_mode) catch unreachable;
        sdl.linkLib(step, lib);
    }
}

fn buildLinkSsl(step: *LibExeObjStep) void {
    if (LibSslPath) |path| {
        ssl.linkLibSslPath(step, path);
    } else {
        if (builtin.os.tag == .windows) {
            step.addAssemblyFile("./deps/prebuilt/win64/ssl.lib");
            return;
        }
        const lib = ssl.createSsl(step.builder, step.target, step.build_mode) catch unreachable;
        ssl.linkLibSsl(step, lib);
    }
}

fn buildLinkCrypto(step: *LibExeObjStep) void {
    if (LibCryptoPath) |path| {
        ssl.linkLibCryptoPath(step, path);
    } else {
        if (builtin.os.tag == .windows) {
            // Can't build, too many args in build-lib will break zig :)
            step.addAssemblyFile("./deps/prebuilt/win64/crypto.lib");
            return;
        }
        const lib = ssl.createCrypto(step.builder, step.target, step.build_mode) catch unreachable;
        ssl.linkLibCrypto(step, lib);
    }
}

fn buildLinkZlib(step: *LibExeObjStep) void {
    const lib = zlib.create(step.builder, step.target, step.build_mode) catch unreachable;
    zlib.linkLib(step, lib);
}

fn buildLinkNghttp2(step: *LibExeObjStep) void {
    const lib = http2.create(step.builder, step.target, step.build_mode) catch unreachable;
    http2.linkLib(step, lib);
}

fn buildLinkCurl(step: *LibExeObjStep) void {
    const b = step.builder;
    if (LibCurlPath) |path| {
        curl.linkLibPath(step, path);
    } else {
        const lib = curl.create(step.builder, step.target, step.build_mode, .{
            // Use the same openssl config so curl knows what features it has.
            .openssl_includes = &.{
                fromRoot(b, "lib/openssl/include"),
                fromRoot(b, "lib/openssl/vendor/include"),
            },
            .nghttp2_includes = &.{
                fromRoot(b, "lib/nghttp2/vendor/lib/includes"),
            },
            .zlib_includes = &.{
                fromRoot(b, "lib/zlib/vendor"),
            },
        }) catch unreachable;
        curl.linkLib(step, lib);
    }
}

fn buildLinkUv(step: *LibExeObjStep) void {
    if (LibUvPath) |path| {
        uv.linkLibPath(step, path);
    } else {
        const lib = uv.create(step.builder, step.target, step.build_mode) catch unreachable;
        uv.linkLib(step, lib);
    }
}

fn buildLinkH2O(step: *LibExeObjStep) void {
    if (LibH2oPath) |path| {
        h2o.linkLibPath(step, path);
    } else {
        const b = step.builder;
        const lib = h2o.create(step.builder, step.target, step.build_mode, .{
            .openssl_includes = &.{
                fromRoot(b, "lib/openssl/vendor/include"),
            },
            .libuv_includes = &.{
                fromRoot(b, "lib/uv/vendor/include"),
            },
            .zlib_includes = &.{
                fromRoot(b, "lib/zlib/vendor"),
            },
        }) catch unreachable;
        h2o.linkLib(step, lib);
    }
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ root(), rel_path }) catch unreachable;
}