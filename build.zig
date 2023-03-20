const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const log = std.log.scoped(.build);

const stdx_lib = @import("stdx/lib.zig");
const platform_lib = @import("platform/lib.zig");
const graphics_lib = @import("graphics/lib.zig");
const ui_lib = @import("ui/lib.zig");
const parser_lib = @import("parser/lib.zig");
const runtime_lib = @import("runtime/lib.zig");

const sdl_lib = @import("lib/sdl/lib.zig");
const ssl_lib = @import("lib/openssl/lib.zig");
const zlib_lib = @import("lib/zlib/lib.zig");
const http2_lib = @import("lib/nghttp2/lib.zig");
const curl_lib = @import("lib/curl/lib.zig");
const uv_lib = @import("lib/uv/lib.zig");
const h2o_lib = @import("lib/h2o/lib.zig");
const stb_lib = @import("lib/stb/lib.zig");
const freetype_lib = @import("lib/freetype2/lib.zig");
const gl_lib = @import("lib/gl/lib.zig");
const vk_lib = @import("lib/vk/lib.zig");
const lyon_lib = @import("lib/clyon/lib.zig");
const tess2_lib = @import("lib/tess2/lib.zig");
const maudio_lib = @import("lib/miniaudio/lib.zig");
const mingw_lib = @import("lib/mingw/lib.zig");
const backend = @import("platform/backend.zig");
const cgltf_lib = @import("lib/cgltf/lib.zig");
const jolt_lib = @import("lib/jolt/lib.zig");
const glslang_lib = @import("lib/glslang/lib.zig");
const mimalloc_lib = @import("lib/mimalloc/lib.zig");

const GitRepoStep = @import("GitRepoStep.zig");

const VersionName = "v0.1";

const EXTRAS_REPO_SHA = "5c31d18797ccb0c71adaf6a31beab53a8c070b5c";
const CYBER_BRANCH = "master";
const CYBER_SHA = "TODO";

// Debugging:
// Set to true to show generated build-lib and other commands created from execFromStep.
const PrintCommands = false;

// Useful in dev to see descrepancies between zig and normal builds.
const LibSdlPath: ?[]const u8 = null;
const LibSslPath: ?[]const u8 = null;
const LibCryptoPath: ?[]const u8 = null;
const LibCurlPath: ?[]const u8 = null;
const LibUvPath: ?[]const u8 = null;
const LibH2oPath: ?[]const u8 = null;

const DefaultGraphicsBackend: backend.GraphicsBackend = .OpenGL;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

var stdx: *std.build.Module = undefined;
var platform: *std.build.Module = undefined;
var ssl: *std.build.Module = undefined;
var mimalloc: *std.build.Module = undefined;
var stbtt: *std.build.Module = undefined;
var stbi: *std.build.Module = undefined;
var stb_perlin: *std.build.Module = undefined;
var sdl: *std.build.Module = undefined;
var uv: *std.build.Module = undefined;
var gl: *std.build.Module = undefined;
var vk: *std.build.Module = undefined;
var jolt: *std.build.Module = undefined;
var maudio: *std.build.Module = undefined;
var freetype: *std.build.Module = undefined;
var ui: *std.build.Module = undefined;
var graphics: *std.build.Module = undefined;
var glslang: *std.build.Module = undefined;
var lyon: *std.build.Module = undefined;
var tess2: *std.build.Module = undefined;
var cgltf: *std.build.Module = undefined;
var runtime: *std.build.Module = undefined;

pub fn build(b: *Builder) !void {
    // Options.
    const path = b.option([]const u8, "path", "Path to main file, for: build, run, test-file") orelse "";
    const vendor_path = b.option([]const u8, "vendor", "Path to vendor.") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const link_graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const link_physics = b.option(bool, "physics", "Link physics libs") orelse false;
    const add_runtime = b.option(bool, "runtime", "Add the runtime package") orelse false;
    const audio = b.option(bool, "audio", "Link audio libs") orelse false;
    const net = b.option(bool, "net", "Link net libs") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};
    const extras_sha = b.option([]const u8, "deps-rev", "Override the extras repo sha.") orelse EXTRAS_REPO_SHA;
    const is_official_build = b.option(bool, "is-official-build", "Whether the build should be an official build.") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wsl = b.option(bool, "wsl", "Whether this running in wsl.") orelse false;
    const link_lyon = b.option(bool, "lyon", "Link lyon graphics for testing.") orelse false;
    const link_tess2 = b.option(bool, "tess2", "Link libtess2 for testing.") orelse false;

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
            // lib.addFrameworkPath("/System/Library/Frameworks");
            // lib.addSystemIncludePath("/usr/include");
            // Don't use zig's libc, since it might not be up to date with the latest SDK which we need for frameworks.
            // lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            if (std.zig.system.darwin.getDarwinSDK(b.allocator, builtin.target)) |sdk| {
                b.sysroot = sdk.path;
            }
        }
    }

    // Default build context.
    var ctx = BuildContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_graphics = link_graphics,
        .graphics_backend = DefaultGraphicsBackend,
        .link_physics = link_physics,
        .link_audio = audio,
        .add_runtime_pkg = add_runtime,
        .link_net = net,
        .link_lyon = link_lyon,
        .link_tess2 = link_tess2,
        .link_mock = false,
        .path = path,
        .filter = filter,
        .optimize = optimize,
        .target = target,
        .wsl = wsl,
    };

    const stdx_opts = stdx_lib.Options{
        .enable_tracy = tracy,
    };
    stdx = stdx_lib.createModule(b, stdx_opts);
    sdl = sdl_lib.createModule(b, stdx);
    gl = gl_lib.createModule(b, .{
        .deps = .{
            .sdl = sdl,
        },
    });
    const platform_opts = platform_lib.Options{
        .graphics_backend = ctx.graphics_backend,
        .deps = .{
            .sdl = sdl,
            .gl = gl,
            .stdx = stdx,
        },
    };
    platform = platform_lib.createModule(b, platform_opts);
    ssl = ssl_lib.createModule(b);
    mimalloc = mimalloc_lib.createModule(b);
    stbtt = stb_lib.createStbttModule(b);
    stbi = stb_lib.createStbiModule(b);
    stb_perlin = stb_lib.createStbPerlinModule(b);
    uv = uv_lib.createModule(b);
    maudio = maudio_lib.createModule(b);
    freetype = freetype_lib.createModule(b);
    vk = vk_lib.createModule(b);
    jolt = jolt_lib.createModule(b);
    glslang = glslang_lib.createModule(b);
    cgltf = cgltf_lib.createModule(b);
    runtime = runtime_lib.createModule(b, .{
        .graphics_backend = ctx.graphics_backend,
        .link_lyon = link_lyon,
        .link_tess2 = link_tess2,
    });
    const graphics_opts = graphics_lib.Options{
        .graphics_backend = ctx.graphics_backend,
        .enable_tracy = ctx.enable_tracy,
        .link_lyon = link_lyon,
        .link_tess2 = link_tess2,
        .sdl_lib_path = LibSdlPath,
        .deps = .{
            .stdx = stdx,
            .gl = gl,
            .freetype = freetype,
            .platform = platform,
            .stbi = stbi,
            .sdl = sdl,
            .stb_perlin = stb_perlin,
        },
    };
    graphics = graphics_lib.createModule(b, graphics_opts);
    const ui_opts = ui_lib.Options{
        .deps = .{
            .graphics = graphics,
            .stdx = stdx,
            .platform = platform,
        },
    };
    ui = ui_lib.createModule(b, ui_opts);
    lyon = lyon_lib.createModule(b, link_lyon);
    tess2 = tess2_lib.createModule(b, link_tess2);

    // Contains optional prebuilt lyon lib as well as windows crypto/ssl prebuilt libs.
    // TODO: Remove this dependency once windows can build crypto/ssl.
    const extras_repo = GitRepoStep.create(b, .{
        .url = "https://github.com/fubark/cosmic-deps",
        .branch = "master",
        .sha = extras_sha,
        .path = thisDir() ++ "/lib/extras",
    });

    {
        // Like extras_repo step but with auto-fetch enabled.
        const extras_repo_fetch = GitRepoStep.create(b, .{
            .url = "https://github.com/fubark/cosmic-deps",
            .branch = "master",
            .sha = extras_sha,
            .path = thisDir() ++ "/lib/extras",
            .fetch_enabled = true,
        });
        b.step("get-extras", "Clone/pull the extras repo.").dependOn(&extras_repo_fetch.step);
    }

    const build_lyon = lyon_lib.BuildStep.create(b, ctx.target);
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
        const step = b.step("test", "Run unit tests");

        // if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
        //     const gen_mac_libc = GenMacLibCStep.create(b, target);
        //     step.step.dependOn(&gen_mac_libc.step);
        // }
        step.dependOn(&stdx_lib.createTestExe(b, target, optimize, stdx_opts).run().step);
        step.dependOn(&platform_lib.createTestExe(b, target, optimize, platform_opts).run().step);
        step.dependOn(&graphics_lib.createTestExe(b, target, optimize, graphics_opts).run().step);

        var test_graphics_opts = graphics_opts;
        test_graphics_opts.graphics_backend = .Test;
        const test_graphics = graphics_lib.createModule(b, test_graphics_opts);
        var test_ui_opts = ui_opts;
        test_ui_opts.deps.graphics = test_graphics;
        step.dependOn(&ui_lib.createTestExe(b, target, optimize, test_ui_opts).run().step);
    }

    {
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        var ctx_ = ctx;

        const build_options = ctx.createDefaultBuildOptions();

        const test_step = ctx_.createTestFileStep("./test/app_test.zig", build_options);
        step.step.dependOn(&test_step.step);
        b.step("test-app", "Run app tests").dependOn(&step.step);
    }

    {
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);

        const build_options = ctx_.createDefaultBuildOptions();
        build_options.addOption([]const u8, "VersionName", VersionName);
        const test_exe = ctx_.createTestFileStep("test/behavior_test.zig", build_options);
        // Set filter so it doesn't run other unit tests (which assume to be linked with lib_mock.zig)
        test_exe.setFilter("behavior:");
        step.step.dependOn(&test_exe.step);
        b.step("test-behavior", "Run behavior tests").dependOn(&step.step);
    }

    const copy_vendor = ctx.createCopyVendorStep(ctx.path, vendor_path);
    b.step("copy-vendor", "Copy vendor source to this repo using vendor_files.txt").dependOn(&copy_vendor.step);

    const test_file = ctx.createTestFileStep(ctx.path, null);
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    const test_jolt = jolt_lib.createTest(b, target, optimize, .{}).run();
    // const test_jolt = jolt.createTest(b, target, mode, .{ .multi_threaded = false, .enable_simd = false }).run();
    // const test_jolt = jolt.createTest(b, target, mode, .{ .multi_threaded = false }).run();
    b.step("test-jolt", "Test jolt library.").dependOn(&test_jolt.step);

    {
        const step = b.addLog("", .{});
        const build_exe = ctx.createBuildExeStep(null);
        step.step.dependOn(&build_exe.step);
        step.step.dependOn(&ctx.addInstallArtifact(build_exe).step);
        b.step("exe", "Build exe with main file at -Dpath").dependOn(&step.step);
    }

    {
        const step = b.addLog("", .{});
        const build_exe = ctx.createBuildExeStep(null);
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
        const crypto = try ssl_lib.createCryptoBuild(b, target, optimize);
        step.dependOn(&ctx.addInstallArtifact(crypto).step);
        const ssl_ = try ssl_lib.createSslBuild(b, target, optimize);
        step.dependOn(&ctx.addInstallArtifact(ssl_).step);
    }

    {
        var ctx_ = ctx;
        ctx_.target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        };
        const build_wasm = ctx_.createBuildWasmBundleStep(ctx_.path, .{});
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
        const counter = ctx_.createBuildWasmBundleStep("ui/examples/counter.zig", .{});
        step.step.dependOn(&counter.step);
        const converter = ctx_.createBuildWasmBundleStep("ui/examples/converter.zig", .{});
        step.step.dependOn(&converter.step);
        const timer = ctx_.createBuildWasmBundleStep("ui/examples/timer.zig", .{});
        step.step.dependOn(&timer.step);
        const crud = ctx_.createBuildWasmBundleStep("ui/examples/crud.zig", .{});
        step.step.dependOn(&crud.step);
        b.step("wasm-examples", "Builds all the wasm examples.").dependOn(&step.step);
    }

    const get_version = b.addLog("{s}", .{getVersionString(is_official_build)});
    b.step("version", "Get the build version.").dependOn(&get_version.step);

    {
        var ctx_ = ctx;
        ctx_.link_net = false;
        ctx_.link_graphics = false;
        ctx_.link_lyon = false;
        ctx_.link_audio = false;
        ctx_.link_mock = true;
        ctx_.path = "tools/gen.zig";

        const build_options = ctx.createDefaultBuildOptions();
        build_options.addOption([]const u8, "VersionName", VersionName);
        build_options.addOption([]const u8, "BuildRoot", b.build_root.path.?);

        const exe = ctx_.createBuildExeStep(build_options);
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
        ctx_.path = "runtime/main.zig";
        const step = b.addLog("", .{});
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);

        const build_options = ctx_.createDefaultBuildOptions();
        build_options.addOption([]const u8, "VersionName", VersionName);
        const run = ctx_.createBuildExeStep(build_options).run();
        run.addArgs(&.{ "test", "test/js/test.js" });
        // run.addArgs(&.{ "test", "test/load-test/cs-https-request-test.js" });
        step.step.dependOn(&run.step);

        b.step("test-cosmic-js", "Test cosmic js").dependOn(&step.step);
    }

    var build_cosmic = b.addLog("", .{});
    {
        const build_options = ctx.createDefaultBuildOptions();
        build_options.addOption([]const u8, "VersionName", getVersionString(is_official_build));
        var ctx_ = ctx;
        ctx_.link_net = true;
        ctx_.link_graphics = true;
        ctx_.link_audio = true;
        ctx_.add_runtime_pkg = true;
        ctx_.path = "runtime/main.zig";
        const step = build_cosmic;
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);
        const exe = ctx_.createBuildExeStep(build_options);
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
        ctx_.path = "runtime/main.zig";
        if (builtin.os.tag == .macos and target.getOsTag() == .macos and !target.isNativeOs()) {
            const gen_mac_libc = GenMacLibCStep.create(b, target);
            step.step.dependOn(&gen_mac_libc.step);
        }
        step.step.dependOn(&extras_repo.step);

        const exe = ctx_.createBuildExeStep(null);
        const exe_install = ctx_.addInstallArtifact(exe);
        step.step.dependOn(&exe_install.step);

        const run = exe.run();
        run.addArgs(&.{"shell"});
        step.step.dependOn(&run.step);
        b.step("cosmic-shell", "Run cosmic in shell mode.").dependOn(&step.step);
    }

    // Whitelist test is useful for running tests that were manually included with an INCLUDE prefix.
    const whitelist_test = ctx.createTestExeStep();
    whitelist_test.setFilter("INCLUDE");
    b.step("whitelist-test", "Tests with INCLUDE in name").dependOn(&whitelist_test.run().step);

    // b.default_step.dependOn(&build_cosmic.step);
}

const BuildContext = struct {
    builder: *std.build.Builder,
    path: []const u8,
    filter: []const u8,
    enable_tracy: bool,
    link_graphics: bool,
    graphics_backend: backend.GraphicsBackend,
    link_physics: bool = false,

    // For testing, benchmarks.
    link_lyon: bool,
    link_tess2: bool = false,

    link_audio: bool,
    add_runtime_pkg: bool = false,
    link_net: bool,
    link_mock: bool,
    link_mimalloc: bool = false,
    optimize: std.builtin.Mode,
    target: std.zig.CrossTarget,
    // This is only used to detect running a linux binary in WSL.
    wsl: bool = false,

    fn fromRoot(self: *BuildContext, path: []const u8) []const u8 {
        return self.builder.pathFromRoot(path);
    }

    fn setOutputDir(self: *BuildContext, obj: *LibExeObjStep, name: []const u8) void {
        const output_dir = self.fromRoot(self.builder.fmt("zig-out/{s}", .{name}));
        obj.setOutputDir(output_dir);
    }

    fn createBuildLibStep(self: *BuildContext) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const step = self.builder.addSharedLibrary(.{
            .name = name,
            .target = self.target,
            .optimize = self.optimize,
            .root_source_file = .{ .path = self.path },
        });
        self.setOutputDir(step, name);
        self.addDeps(step) catch unreachable;
        return step;
    }

    const WasmBundleOptions = struct {
        name: ?[]const u8 = null,
        output_dir: ?[]const u8 = null,
        index_html: []const u8 = "./lib/wasm/index.html",
    };

    /// Similar to createBuildLibStep except we also copy over index.html and required js libs.
    fn createBuildWasmBundleStep(self: *BuildContext, path: []const u8, opts: WasmBundleOptions) *LibExeObjStep {
        const name = opts.name orelse b: {
            const basename = std.fs.path.basename(path);
            const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
            break :b basename[0..i];
        };

        const wasm = self.builder.addSharedLibrary(.{
            .name = name,
            .target = self.target,
            .optimize = self.optimize,
            .root_source_file = .{ .path = path },
        });
        // const step = self.builder.addStaticLibrary(name, path);
        wasm.setMainPkgPath(".");
        self.setBuildMode(wasm);
        self.setTarget(wasm);

        // Set enough stack size. 128KB.
        wasm.stack_size = 1024 * 128;

        const opts_step = self.createDefaultBuildOptions();
        wasm.addOptions("build_options", opts_step);

        opts_step.addOption(backend.GraphicsBackend, "GraphicsBackend", self.graphics_backend);

        self.addDeps(wasm) catch unreachable;

        _ = self.addInstallArtifact(wasm);
        // This is needed for wasm builds or the main .wasm file won't output to the custom directory.
        const output_dir = opts.output_dir orelse wasm.install_step.?.dest_dir.custom;
        self.setOutputDir(wasm, output_dir);

        self.copyAssets(wasm);

        // Create copy of index.html.
        var cp = CopyFileStep.create(self.builder, self.fromRoot(opts.index_html), self.fromRoot("./lib/wasm/gen-index.html"));
        wasm.step.dependOn(&cp.step);

        // Replace wasm file name in gen-index.html
        const index_path = self.fromRoot("./lib/wasm/gen-index.html");
        const new_str = std.mem.concat(self.builder.allocator, u8, &.{ "wasmFile = '", name, ".wasm'" }) catch unreachable;
        const replace = ReplaceInFileStep.create(self.builder, index_path, "wasmFile = 'demo.wasm'", new_str);
        wasm.step.dependOn(&replace.step);

        // Install gen-index.html
        const install_index = self.addStepInstallFile(wasm, thisDir() ++ "/lib/wasm/gen-index.html", "index.html");
        wasm.step.dependOn(&install_index.step);

        // graphics.js
        // const install_graphics = self.addStepInstallFile(step, thisDir() ++ "/lib/wasm/graphics-canvas.js", "graphics.js");
        const install_graphics = self.addStepInstallFile(wasm, thisDir() ++ "/lib/wasm/graphics-webgl2.js", "graphics.js");
        wasm.step.dependOn(&install_graphics.step);

        // stdx.js
        const install_stdx = self.addStepInstallFile(wasm, thisDir() ++ "/lib/wasm/stdx.js", "stdx.js");
        wasm.step.dependOn(&install_stdx.step);

        return wasm;
    }

    /// dst_rel_path is relative to the step's custom dest directory.
    fn addStepInstallFile(self: *BuildContext, step: *LibExeObjStep, src_path: []const u8, dst_rel_path: []const u8) *std.build.InstallFileStep {
        return self.builder.addInstallFile(.{ .path = src_path }, self.builder.fmt("{s}/{s}", .{ step.install_step.?.dest_dir.custom, dst_rel_path }));
    }

    fn copyAssets(self: *BuildContext, step: *LibExeObjStep) void {
        if (self.path.len == 0) {
            return;
        }
        if (!std.mem.endsWith(u8, self.path, ".zig")) {
            return;
        }

        const assets_file = self.builder.fmt("{s}_assets.txt", .{self.path[0 .. self.path.len - 4]});
        const assets = std.fs.cwd().readFileAlloc(self.builder.allocator, assets_file, 1e12) catch return;

        var iter = std.mem.tokenize(u8, assets, "\n");
        while (iter.next()) |path| {
            const basename = std.fs.path.basename(path);
            const src_path = self.builder.fmt("{s}{s}", .{ thisDir(), path });

            const install_file = self.addStepInstallFile(step, src_path, basename);
            step.step.dependOn(&install_file.step);
        }
    }

    fn joinResolvePath(self: *BuildContext, paths: []const []const u8) []const u8 {
        return std.fs.path.join(self.builder.allocator, paths) catch unreachable;
    }

    fn getSimpleTriple(b: *Builder, target: std.zig.CrossTarget) []const u8 {
        return target.toTarget().linuxTriple(b.allocator) catch unreachable;
    }

    fn addInstallArtifact(self: *BuildContext, artifact: *LibExeObjStep) *std.build.InstallArtifactStep {
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

    fn createBuildExeStep(self: *BuildContext, options_step: ?*std.build.OptionsStep) *LibExeObjStep {
        const basename = std.fs.path.basename(self.path);
        const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
        const name = basename[0..i];

        const exe = self.builder.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = self.path },
            .target = self.target,
            .optimize = self.optimize,
        });
        exe.setMainPkgPath(".");

        const opts_step = options_step orelse self.createDefaultBuildOptions();
        exe.addOptions("build_options", opts_step);

        const graphics_backend = backend.getGraphicsBackend(exe);
        opts_step.addOption(backend.GraphicsBackend, "GraphicsBackend", graphics_backend);

        self.addDeps(exe) catch unreachable;

        if (self.enable_tracy) {
            self.linkTracy(exe);
        }

        _ = self.addInstallArtifact(exe);
        self.copyAssets(exe);
        return exe;
    }

    fn createCopyVendorStep(self: *BuildContext, path: []const u8, vendor_path: []const u8) *CopyVendorStep {
        const b = self.builder;
        const step = CopyVendorStep.create(b, path, vendor_path);
        return step;
    }

    fn createTestFileStep(self: *BuildContext, path: []const u8, build_options: ?*std.build.OptionsStep) *std.build.LibExeObjStep {
        const step = self.builder.addTest(.{
            .root_source_file = .{ .path = path },
            .target = self.target,
            .optimize = self.optimize,
        });
        step.setMainPkgPath(".");

        self.addDeps(step) catch unreachable;
        self.buildLinkMock(step);

        const build_opts = build_options orelse self.createDefaultBuildOptions();
        step.addOptions("build_options", build_opts);

        build_opts.addOption(backend.GraphicsBackend, "GraphicsBackend", .Test);

        self.postStep(step);
        return step;
    }

    fn createTestExeStep(self: *BuildContext) *std.build.CompileStep {
        const step = self.builder.addTest(.{
            .name = "main_test",
            .kind = .test_exe,
            .root_source_file = .{ .path = "./test/main_test.zig" },
            .target = self.target,
            .optimize = self.optimize,
        });
        // This fixes test files that import above, eg. @import("../foo")
        step.setMainPkgPath(".");

        // Add external lib headers but link with mock lib.
        self.addDeps(step) catch unreachable;
        self.buildLinkMock(step);

        // Add build_options at root since the main test file references src paths instead of package names.
        const build_opts = self.createDefaultBuildOptions();
        build_opts.addOption(backend.GraphicsBackend, "GraphicsBackend", .Test);
        build_opts.addOption([]const u8, "VersionName", VersionName);
        step.addOptions("build_options", build_opts);
        self.postStep(step);
        return step;
    }

    fn postStep(self: *BuildContext, step: *std.build.LibExeObjStep) void {
        if (self.enable_tracy) {
            self.linkTracy(step);
        }
        if (self.filter.len > 0) {
            step.setFilter(self.filter);
        }
    }

    fn isWasmTarget(self: BuildContext) bool {
        return self.target.getCpuArch().isWasm();
    }

    fn addDeps(self: *BuildContext, step: *LibExeObjStep) !void {
        step.addModule("stdx", stdx);
        step.addModule("platform", platform);

        // curl.addPackage(step);
        // uv.addPackage(step);
        // h2o.addPackage(step);
        step.addModule("openssl", ssl);
        if (self.link_net) {
            ssl_lib.buildAndLinkCrypto(step, .{ .lib_path = LibCryptoPath });
            ssl_lib.buildAndLinkSsl(step, .{ .lib_path = LibSslPath });
            curl_lib.buildAndLink(step, .{ .lib_path = LibCurlPath });
            http2_lib.buildAndLink(step);
            zlib_lib.buildAndLink(step);
            uv_lib.buildAndLink(step, .{ .lib_path = LibUvPath });
            h2o_lib.buildAndLink(step, .{ .lib_path = LibH2oPath });
        }
        step.addModule("mimalloc", mimalloc);
        if (self.link_mimalloc) {
            mimalloc_lib.buildAndLink(step, .{});
        }
        sdl_lib.addModule(step, "sdl", sdl);
        step.addModule("stbtt", stbtt);
        stb_lib.addStbiModule(step, "stbi", stbi);
        step.addModule("stb_perlin", stb_perlin);
        freetype_lib.addModule(step, "freetype", freetype);
        gl_lib.addModule(step, "gl", gl);
        step.addModule("vk", vk);
        step.addModule("jolt", jolt);
        step.addModule("glslang", glslang);
        maudio_lib.addModule(step, "miniaudio", maudio);
        step.addModule("lyon", lyon);
        step.addModule("tess2", tess2);
        if (self.target.getOsTag() == .macos) {
            self.buildLinkMacSys(step);
        }
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            mingw_lib.buildExtra(step);
            mingw_lib.buildAndLinkWinPosix(step);
            mingw_lib.buildAndLinkWinPthreads(step);
        }
        step.addModule("ui", ui);
        step.addModule("cgltf", cgltf);
        step.addModule("graphics", graphics);
        if (self.link_graphics) {
            if (self.graphics_backend == .Vulkan) {
                glslang_lib.buildAndLink(step);
            }
            freetype_lib.buildAndLink(step);
            stb_lib.buildAndLinkStbi(step);
            sdl_lib.buildAndLink(step, .{ .lib_path = LibSdlPath });
            gl_lib.link(step);
        }
        if (self.link_physics) {
            if (step.target.getCpuArch().isWasm()) {
                jolt_lib.buildAndLink(step, .{ .multi_threaded = false, .enable_simd = false });
            } else {
                // Disable building jolt on windows for now.
                if (!step.target.isWindows()) {
                    jolt_lib.buildAndLink(step, .{});
                }
            }
        }
        if (self.link_audio) {
            maudio_lib.buildAndLink(step);
        }

        // const cyber_repo = GitRepoStep.create(self.builder, .{
        //     .url = "https://github.com/fubark/zig-v8",
        //     .branch = ZIG_V8_BRANCH,
        //     .sha = ZIG_V8_SHA,
        //     .path = thisDir() ++ "/lib/zig-v8",
        // });
        // step.step.dependOn(&cyber_repo.step);

        if (self.add_runtime_pkg) {
            step.addModule("runtime", runtime);
        }
        if (self.link_mock) {
            self.buildLinkMock(step);
        }
    }

    fn setBuildMode(self: *BuildContext, step: *std.build.LibExeObjStep) void {
        step.optimize = self.optimize;
        if (self.optimize == .ReleaseSafe) {
            step.strip = true;
        }
    }

    fn setTarget(self: *BuildContext, step: *std.build.LibExeObjStep) void {
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
        step.target = target;
    }

    fn createDefaultBuildOptions(self: BuildContext) *std.build.OptionsStep {
        const build_options = self.builder.addOptions();
        build_options.addOption(bool, "enable_tracy", self.enable_tracy);
        build_options.addOption(bool, "has_lyon", self.link_lyon);
        build_options.addOption(bool, "has_tess2", self.link_tess2);
        return build_options;
    }

    fn linkTracy(self: *BuildContext, step: *std.build.LibExeObjStep) void {
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

        step.addIncludePath(path);
        step.addCSourceFile(client_cpp, tracy_c_flags);
        step.linkSystemLibraryName("c++");
        step.linkLibC();

        // if (target.isWindows()) {
        //     step.linkSystemLibrary("dbghelp");
        //     step.linkSystemLibrary("ws2_32");
        // }
    }

    fn buildLinkMacSys(self: *BuildContext, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary(.{
            .name = "mac_sys",
            .target = self.target,
            .optimize = self.optimize,
        });

        lib.addCSourceFile("./lib/sys/mac_sys.c", &.{});

        if (self.target.isNativeOs()) {
            // Force using native headers or it'll compile with ___darwin_check_fd_set_overflow references.
            lib.linkFramework("CoreServices");
        } else {
            lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
        }

        step.linkLibrary(lib);
    }

    fn addCSourceFileFmt(self: *BuildContext, lib: *LibExeObjStep, comptime format: []const u8, args: anytype, c_flags: []const []const u8) void {
        const path = std.fmt.allocPrint(self.builder.allocator, format, args) catch unreachable;
        lib.addCSourceFile(self.fromRoot(path), c_flags);
    }

    fn buildLinkMock(self: *BuildContext, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary(.{
            .name = "mock",
            .root_source_file = .{ .path = self.fromRoot("./test/lib_mock.zig") },
            .target = self.target,
            .optimize = self.optimize,
        });
        lib.addModule("stdx", stdx);
        gl_lib.addModule(lib, "gl", gl);
        uv_lib.addModule(lib, "uv", uv);
        maudio_lib.addModule(lib, "miniaudio", maudio);
        step.linkLibrary(lib);
    }
};

const CopyVendorStep = struct {
    step: std.build.Step,
    b: *Builder,
    path: []const u8,
    vendor_path: []const u8,

    fn create(b: *Builder, path: []const u8, vendor_path: []const u8) *CopyVendorStep {
        const new = b.allocator.create(CopyVendorStep) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, b.fmt("copy-vendor", .{}), b.allocator, make),
            .b = b,
            .path = b.dupe(path),
            .vendor_path = b.dupe(vendor_path),
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(CopyVendorStep, "step", step);

        const vendor_files_txt = self.b.fmt("{s}/vendor_files.txt", .{self.path});
        const f = try std.fs.cwd().openFile(vendor_files_txt, .{ .mode = .read_only });
        defer f.close();
        const content = try f.readToEndAlloc(self.b.allocator, 1e12);
        var iter = std.mem.tokenize(u8, content, "\n\r");
        while (iter.next()) |line| {
            const src_path = self.b.pathJoin(&.{ self.vendor_path, line });
            const dst_path = self.b.pathJoin(&.{ self.path, "vendor", line });
            const stat = try std.fs.cwd().statFile(src_path);
            if (stat.kind == .Directory) {
                var src_dir = try std.fs.cwd().openIterableDir(src_path, .{});
                defer src_dir.close();
                std.fs.cwd().access(dst_path, .{}) catch |e| {
                    if (e == error.FileNotFound) {
                        try std.fs.cwd().makePath(dst_path);
                    } else return e;
                };
                var dst_dir = try std.fs.cwd().openDir(dst_path, .{});
                defer dst_dir.close();
                try copyDir(src_dir, dst_dir);
            } else {
                const filename = std.fs.path.basename(src_path);
                var src_dir = try std.fs.cwd().openDir(std.fs.path.dirname(src_path).?, .{});
                defer src_dir.close();
                try std.fs.cwd().makePath(std.fs.path.dirname(dst_path).?);
                var dst_dir = try std.fs.cwd().openDir(std.fs.path.dirname(dst_path).?, .{});
                defer dst_dir.close();
                try src_dir.copyFile(filename, dst_dir, filename, .{});
            }
            log.debug("copied {s}", .{line});
        }
    }
};

fn copyDir(src_dir: std.fs.IterableDir, dest_dir: std.fs.Dir) anyerror!void {
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .File => try src_dir.dir.copyFile(entry.name, dest_dir, entry.name, .{}),
            .Directory => {
                // log.debug("{s}", .{entry.name});
                // Create destination directory
                dest_dir.makeDir(entry.name) catch |e| {
                    switch (e) {
                        std.os.MakeDirError.PathAlreadyExists => {},
                        else => return e,
                    }
                };
                // Open destination directory
                var dest_entry_dir = try dest_dir.openDir(entry.name, .{ .access_sub_paths = true, .no_follow = true });
                defer dest_entry_dir.close();
                // Open directory we're copying files from
                var src_entry_dir = try src_dir.dir.openIterableDir(entry.name, .{ .access_sub_paths = true, .no_follow = true });
                defer src_entry_dir.close();
                // Begin the recursive descent!
                try copyDir(src_entry_dir, dest_entry_dir);
            },
            else => {},
        }
    }
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

        const path = try std.fs.path.resolve(self.b.allocator, &.{ self.b.sysroot.?, "usr/include" });
        const libc_file = self.b.fmt(
            \\include_dir={s}
            \\sys_include_dir={s}
            \\crt_dir=
            \\msvc_lib_dir=
            \\kernel32_lib_dir=
            \\gcc_dir=
        ,
            .{ path, path },
        );
        try std.fs.cwd().writeFile("./lib/macos.libc", libc_file);
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

fn getVersionString(is_official_build: bool) []const u8 {
    if (is_official_build) {
        return VersionName;
    } else {
        return VersionName ++ "-Dev";
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ thisDir(), rel_path }) catch unreachable;
}
