const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const log = std.log.scoped(.build);

const stdx = @import("stdx/lib.zig");
const platform = @import("platform/lib.zig");
const graphics = @import("graphics/lib.zig");
const ui = @import("ui/lib.zig");
const parser = @import("parser/lib.zig");

const sdl = @import("lib/sdl/lib.zig");
const ssl = @import("lib/openssl/lib.zig");
const zlib = @import("lib/zlib/lib.zig");
const http2 = @import("lib/nghttp2/lib.zig");
const curl = @import("lib/curl/lib.zig");
const uv = @import("lib/uv/lib.zig");
const h2o = @import("lib/h2o/lib.zig");
const stb = @import("lib/stb/lib.zig");
const gl = @import("lib/gl/lib.zig");
const lyon = @import("lib/clyon/lib.zig");
const tess2 = @import("lib/tess2/lib.zig");
const maudio = @import("lib/miniaudio/lib.zig");

const GitRepoStep = @import("GitRepoStep.zig");

const VersionName = "v0.1";

const EXTRAS_REPO_SHA = "5c31d18797ccb0c71adaf6a31beab53a8c070b5c";
const ZIG_V8_BRANCH = "9.9.115.9";
const ZIG_V8_SHA = "8e6837d6d517134fcef0527ed7e933efeb1ee9db";

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
    const link_graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const audio = b.option(bool, "audio", "Link audio libs") orelse false;
    const v8 = b.option(bool, "v8", "Link v8 lib") orelse false;
    const net = b.option(bool, "net", "Link net libs") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};
    const extras_sha = b.option([]const u8, "deps-rev", "Override the extras repo sha.") orelse EXTRAS_REPO_SHA;
    const is_official_build = b.option(bool, "is-official-build", "Whether the build should be an official build.") orelse false;
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const wsl = b.option(bool, "wsl", "Whether this running in wsl.") orelse false;
    const link_lyon = b.option(bool, "lyon", "Link lyon graphics for testing.") orelse false;
    const link_tess2 = b.option(bool, "tess2", "Link libtess2 for testing.") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);
    build_options.addOption([]const u8, "VersionName", getVersionString(is_official_build));
    build_options.addOption(bool, "has_lyon", link_lyon);
    build_options.addOption(bool, "has_tess2", link_tess2);

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

    // Default build context.
    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_graphics = link_graphics,
        .link_audio = audio,
        .add_v8_pkg = v8,
        .link_v8 = v8,
        .link_net = net,
        .link_lyon = link_lyon,
        .link_tess2 = link_tess2,
        .link_mock = false,
        .path = path,
        .filter = filter,
        .mode = mode,
        .target = target,
        .build_options = build_options,
        .wsl = wsl,
    };

    // Contains optional prebuilt lyon lib as well as windows crypto/ssl prebuilt libs.
    // TODO: Remove this dependency once windows can build crypto/ssl.
    const extras_repo = GitRepoStep.create(b, .{
        .url = "https://github.com/fubark/cosmic-deps",
        .branch = "master",
        .sha = extras_sha,
        .path = srcPath() ++ "/lib/extras",
    });

    {
        // Like extras_repo step but with auto-fetch enabled.
        const extras_repo_fetch = GitRepoStep.create(b, .{
            .url = "https://github.com/fubark/cosmic-deps",
            .branch = "master",
            .sha = extras_sha,
            .path = srcPath() ++ "/lib/extras",
            .fetch_enabled = true,
        });
        b.step("get-extras", "Clone/pull the extras repo.").dependOn(&extras_repo_fetch.step);
    }

    const get_v8_lib = createGetV8LibStep(b, target);
    b.step("get-v8-lib", "Fetches prebuilt static lib. Use -Dtarget to indicate target platform").dependOn(&get_v8_lib.step);

    const build_lyon = BuildLyonStep.create(b, ctx.target);
    b.step("lyon", "Builds rust lib with cargo and copies to lib/extras/prebuilt").dependOn(&build_lyon.step);

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
        var ctx_ = ctx;
        ctx_.add_v8_pkg = true;
        const test_exe = ctx_.createTestExeStep();
        const run_test = test_exe.run();
        step.step.dependOn(&run_test.step);
        b.step("test", "Run tests").dependOn(&step.step);
    }

    {
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        ctx_.link_v8 = true;
        ctx_.path = "runtime/main.zig";
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);
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

    {
        var ctx_ = ctx;
        ctx_.target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        };
        const build_wasm = ctx_.createBuildWasmBundleStep(ctx_.path);
        b.step("wasm", "Build wasm bundle with main file at -Dpath").dependOn(&build_wasm.step);
    }

    {
        const step = b.addLog("", .{});
        var ctx_ = ctx;
        ctx_.target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        };
        const counter = ctx_.createBuildWasmBundleStep("ui/examples/counter.zig");
        step.step.dependOn(&counter.step);
        const converter = ctx_.createBuildWasmBundleStep("ui/examples/converter.zig");
        step.step.dependOn(&converter.step);
        const timer = ctx_.createBuildWasmBundleStep("ui/examples/timer.zig");
        step.step.dependOn(&timer.step);
        const crud = ctx_.createBuildWasmBundleStep("ui/examples/crud.zig");
        step.step.dependOn(&crud.step);
        b.step("wasm-examples", "Builds all the wasm examples.").dependOn(&step.step);
    }

    const get_version = b.addLog("{s}", .{getVersionString(is_official_build)});
    b.step("version", "Get the build version.").dependOn(&get_version.step);

    {
        const build_options_ = b.addOptions();
        build_options_.addOption([]const u8, "VersionName", VersionName);
        build_options_.addOption([]const u8, "BuildRoot", b.build_root);
        build_options_.addOption(bool, "enable_tracy", tracy);
        var ctx_ = ctx;
        ctx_.link_net = false;
        ctx_.link_graphics = false;
        ctx_.link_lyon = false;
        ctx_.link_audio = false;
        ctx_.add_v8_pkg = true;
        ctx_.link_v8 = false;
        ctx_.link_mock = true;
        ctx_.path = "tools/gen.zig";
        ctx_.build_options = build_options_;

        const exe = ctx_.createBuildExeStep();
        ctx_.buildLinkMock(exe);
        const run = exe.run();
        run.addArgs(args);
        b.step("gen", "Generate tool.").dependOn(&run.step);
    }

    {
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        ctx_.link_v8 = true;
        ctx_.path = "runtime/main.zig";
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);
        const run = ctx_.createBuildExeStep().run();
        run.addArgs(&.{ "test", "test/js/test.js" });
        // run.addArgs(&.{ "test", "test/load-test/cs-https-request-test.js" });
        step.step.dependOn(&run.step);
    
        b.step("test-cosmic-js", "Test cosmic js").dependOn(&step.step);
    }

    var build_cosmic = b.addLog("", .{});
    {
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        ctx_.link_v8 = true;
        ctx_.path = "runtime/main.zig";
        const step = build_cosmic;
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);
        const exe = ctx_.createBuildExeStep();
        const exe_install = ctx_.addInstallArtifact(exe);
        step.step.dependOn(&exe_install.step);
        b.step("cosmic", "Build cosmic.").dependOn(&step.step);
    }

    {
        var step = b.addLog("", .{});
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        ctx_.link_v8 = true;
        ctx_.path = "runtime/main.zig";
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);

        const exe = ctx_.createBuildExeStep();
        const exe_install = ctx_.addInstallArtifact(exe);
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

    // For testing, benchmarks.
    link_lyon: bool,
    link_tess2: bool = false,

    link_audio: bool,
    add_v8_pkg: bool = false,
    link_v8: bool,
    link_net: bool,
    link_mock: bool,
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

        const step = self.builder.addSharedLibrary(name, self.path, .unversioned);
        self.setBuildMode(step);
        self.setTarget(step);
        self.setOutputDir(step, name);
        self.addDeps(step) catch unreachable;
        return step;
    }

    /// Similar to createBuildLibStep except we also copy over index.html and required js libs.
    fn createBuildWasmBundleStep(self: *Self, path: []const u8) *LibExeObjStep {
        const basename = std.fs.path.basename(path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const step = self.builder.addSharedLibrary(name, path, .unversioned);
        // const step = self.builder.addStaticLibrary(name, path);
        self.setBuildMode(step);
        self.setTarget(step);

        self.addDeps(step) catch unreachable;

        _ = self.addInstallArtifact(step);
        // This is needed for wasm builds or the main .wasm file won't output to the custom directory. 
        self.setOutputDir(step, step.install_step.?.dest_dir.custom);

        self.copyAssets(step);

        // Create copy of index.html.
        var cp = CopyFileStep.create(self.builder, self.fromRoot("./lib/wasm-js/index.html"), self.fromRoot("./lib/wasm-js/gen-index.html"));
        step.step.dependOn(&cp.step);

        // Replace wasm file name in gen-index.html
        const index_path = self.fromRoot("./lib/wasm-js/gen-index.html");
        const new_str = std.mem.concat(self.builder.allocator, u8, &.{ "wasmFile = '", name, ".wasm'" }) catch unreachable;
        const replace = ReplaceInFileStep.create(self.builder, index_path, "wasmFile = 'demo.wasm'", new_str);
        step.step.dependOn(&replace.step);

        // Install gen-index.html
        const install_index = self.addStepInstallFile(step, srcPath() ++ "/lib/wasm-js/gen-index.html", "index.html");
        step.step.dependOn(&install_index.step);

        // graphics.js
        // const install_graphics = self.addStepInstallFile(step, srcPath() ++ "/lib/wasm-js/graphics-canvas.js", "graphics.js");
        const install_graphics = self.addStepInstallFile(step, srcPath() ++ "/lib/wasm-js/graphics-webgl2.js", "graphics.js");
        step.step.dependOn(&install_graphics.step);

        // stdx.js
        const install_stdx = self.addStepInstallFile(step, srcPath() ++ "/lib/wasm-js/stdx.js", "stdx.js");
        step.step.dependOn(&install_stdx.step);

        return step;
    }

    /// dst_rel_path is relative to the step's custom dest directory.
    fn addStepInstallFile(self: *Self, step: *LibExeObjStep, src_path: []const u8, dst_rel_path: []const u8) *std.build.InstallFileStep {
        return self.builder.addInstallFile(.{ .path = src_path }, self.builder.fmt("{s}/{s}", .{step.install_step.?.dest_dir.custom, dst_rel_path}));
    }

    fn copyAssets(self: *Self, step: *LibExeObjStep) void {
        if (self.path.len == 0) {
            return;
        }
        if (!std.mem.endsWith(u8, self.path, ".zig")) {
            return;
        }

        const assets_file = self.builder.fmt("{s}_assets.txt", .{self.path[0..self.path.len-4]});
        const assets = std.fs.cwd().readFileAlloc(self.builder.allocator, assets_file, 1e12) catch return;

        var iter = std.mem.tokenize(u8, assets, "\n");
        while (iter.next()) |path| {
            const basename = std.fs.path.basename(path);
            const src_path = self.builder.fmt("{s}{s}", .{srcPath(), path});

            const install_file = self.addStepInstallFile(step, src_path, basename);
            step.step.dependOn(&install_file.step);
        }
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
            const path = self.builder.fmt("{s}/{s}", .{ triple, artifact.name });
            artifact.override_dest_dir = .{ .custom = path };
        }
        return self.builder.addInstallArtifact(artifact);
    }

    fn createBuildExeStep(self: *Self) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const exe = self.builder.addExecutable(name, self.path);
        self.setBuildMode(exe);
        self.setTarget(exe);
        exe.setMainPkgPath(".");

        exe.addPackage(self.buildOptionsPkg());
        self.addDeps(exe) catch unreachable;

        if (self.enable_tracy) {
            self.linkTracy(exe);
        }

        _ = self.addInstallArtifact(exe);
        self.copyAssets(exe);
        return exe;
    }

    fn createTestFileStep(self: *Self, path: []const u8) *std.build.LibExeObjStep {
        const step = self.builder.addTest(path);
        self.setBuildMode(step);
        self.setTarget(step);
        step.setMainPkgPath(".");

        self.addDeps(step) catch unreachable;

        step.addPackage(self.buildOptionsPkg());
        self.postStep(step);
        return step;
    }

    fn createTestExeStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTestExe("main_test", "./test/main_test.zig");
        self.setBuildMode(step);
        self.setTarget(step);
        // This fixes test files that import above, eg. @import("../foo")
        step.setMainPkgPath(".");

        // Add external lib headers but link with mock lib.
        self.addDeps(step) catch unreachable;
        self.buildLinkMock(step);

        step.addPackage(self.buildOptionsPkg());
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

    fn isWasmTarget(self: Self) bool {
        return self.target.getCpuArch() == .wasm32 or self.target.getCpuArch() == .wasm64;
    }

    fn addDeps(self: *Self, step: *LibExeObjStep) !void {
        stdx.addPackage(step, .{
            .enable_tracy = self.enable_tracy,
        });
        platform.addPackage(step, .{ .add_dep_pkgs = false });
        curl.addPackage(step);
        uv.addPackage(step);
        h2o.addPackage(step);
        ssl.addPackage(step);
        if (self.link_net) {
            buildLinkCrypto(step);
            buildLinkSsl(step);
            buildLinkCurl(step);
            buildLinkNghttp2(step);
            buildLinkZlib(step);
            buildLinkUv(step);
            buildLinkH2O(step);
        }
        sdl.addPackage(step);
        stb.addStbttPackage(step);
        stb.addStbiPackage(step);
        gl.addPackage(step);
        maudio.addPackage(step);
        lyon.addPackage(step, self.link_lyon);
        tess2.addPackage(step, self.link_tess2);
        if (self.target.getOsTag() == .macos) {
            self.buildLinkMacSys(step);
        }
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            self.buildMingwExtra(step);
            self.buildLinkWinPosix(step);
            self.buildLinkWinPthreads(step);
        }
        ui.addPackage(step, .{
            .add_dep_pkgs = false,
        });

        const graphics_opts = graphics.Options{
            .enable_tracy = self.enable_tracy,
            .link_lyon = self.link_lyon,
            .link_tess2 = self.link_tess2,
            .sdl_lib_path = LibSdlPath,
            .add_dep_pkgs = false,
        };
        graphics.addPackage(step, graphics_opts);
        if (self.link_graphics) {
            graphics.buildAndLink(step, graphics_opts);
        }
        if (self.link_audio) {
            maudio.buildAndLink(step);
        }

        if (self.add_v8_pkg or self.link_v8) {
            // Only add zig-v8 package when this flag is set to let unrelated builds continue. eg. graphics/ui examples.
            // Must dependOn before adding the zig-v8 package.
            const zig_v8_repo = GitRepoStep.create(self.builder, .{
                .url = "https://github.com/fubark/zig-v8",
                .branch = ZIG_V8_BRANCH,
                .sha = ZIG_V8_SHA,
                .path = srcPath() ++ "/lib/zig-v8",
            });
            step.step.dependOn(&zig_v8_repo.step);
            addZigV8(step);
        }
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

    fn buildOptionsPkg(self: Self) std.build.Pkg {
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

    fn buildLinkMock(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("mock", self.fromRoot("./test/lib_mock.zig"));
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);
        stdx.addPackage(lib, .{
            .enable_tracy = self.enable_tracy,
        });
        gl.addPackage(lib);
        uv.addPackage(lib);
        addZigV8(lib);
        maudio.addPackage(lib);
        step.linkLibrary(lib);
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

        const toml_path = srcPath() ++ "/lib/clyon/Cargo.toml";

        if (self.target.getOsTag() == .linux and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/lib/clyon/target/release/libclyon.a";
            const to_path = srcPath() ++ "/lib/extras/prebuilt/linux64/libclyon.a";
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
            const out_file = srcPath() ++ "/lib/clyon/target/x86_64-pc-windows-gnu/release/libclyon.a";
            const to_path = srcPath() ++ "/lib/extras/prebuilt/win64/clyon.lib";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=x86_64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/lib/clyon/target/x86_64-apple-darwin/release/libclyon.a";
            const to_path = srcPath() ++ "/lib/extras/prebuilt/mac64/libclyon.a";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
            // This actually corrupts the lib and zig will fail to parse it after linking.
            // _ = try self.builder.exec(&[_][]const u8{ "strip", "-S", to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .aarch64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=aarch64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/lib/clyon/target/aarch64-apple-darwin/release/libclyon.a";
            const to_path = srcPath() ++ "/lib/extras/prebuilt/mac-arm64/libclyon.a";
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
        std.fs.cwd().access(self.path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => {
                try self.b.makePath(self.path);
            },
            else => {},
        };
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

        const file = std.fs.openFileAbsolute(self.path, .{ .mode = .read_only }) catch unreachable;
        errdefer file.close();
        const source = file.readToEndAllocOptions(self.b.allocator, 1024 * 1000 * 10, null, @alignOf(u8), 0) catch unreachable;
        defer self.b.allocator.free(source);

        const new_source = std.mem.replaceOwned(u8, self.b.allocator, source, self.old_str, self.new_str) catch unreachable;
        file.close();

        const write = std.fs.openFileAbsolute(self.path, .{ .mode = .write_only }) catch unreachable;
        defer write.close();
        write.writeAll(new_source) catch unreachable;
    }
};

fn createGetV8LibStep(b: *Builder, target: std.zig.CrossTarget) *std.build.LogStep {
    const step = b.addLog("Get V8 Lib\n", .{});

    const url = getV8_StaticLibGithubUrl(b.allocator, ZIG_V8_BRANCH, target);
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
    const path = std.fmt.allocPrint(b.allocator, "./lib/{s}-{s}.{s}", .{ lib_name, triple, lib_ext }) catch unreachable;
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
        if (cur_revision.len < revision.len or !std.mem.eql(u8, cur_revision[0..revision.len], revision)) {
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
    const file = std.fs.openFileAbsolute(path_abs, .{ .mode = .read_only }) catch |err| {
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

fn buildLinkSsl(step: *LibExeObjStep) void {
    if (LibSslPath) |path| {
        ssl.linkLibSslPath(step, path);
    } else {
        if (builtin.os.tag == .windows) {
            step.addAssemblyFile(srcPath() ++ "/lib/extras/prebuilt/win64/ssl.lib");
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
            step.addAssemblyFile(srcPath() ++ "/lib/extras/prebuilt/win64/crypto.lib");
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

fn srcPath() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ srcPath(), rel_path }) catch unreachable;
}