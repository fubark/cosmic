const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const openssl = @import("lib/openssl/build.zig");
const Pkg = std.build.Pkg;
const log = std.log.scoped(.build);

const VersionName = "v0.1";
const DepsRevision = "9f28b91ed214d1839a3ee23ac2c2b11fdd4c79b3";
const V8_Revision = "9.9.115";

// Debugging:
// Set to true to show generated build-lib and other commands created from execFromStep.
const PrintCommands = false;

// Useful in dev to see descrepancies between zig and normal builds.
const UsePrebuiltSDL = false;
const UsePrebuiltCurl: ?[]const u8 = null;
// const UsePrebuiltCurl: ?[]const u8 = "/Users/fubar/dev/curl/lib/.libs/libcurl.a";
// const UsePrebuiltCurl: ?[]const u8 = "/home/fubar/repos/curl/lib/.libs/libcurl.a";
const UsePrebuiltUv: ?[]const u8 = null;
// const UsePrebuiltUv: ?[]const u8 = "/Users/fubar/dev/libuv/build/libuv_a.a";
const UsePrebuiltH2O: ?[]const u8 = null;
// const UsePrebuiltH2O: ?[]const u8 = "/Users/fubar/dev/h2o";

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) !void {
    // Options.
    const path = b.option([]const u8, "path", "Path to main file, for: build, run, test-file") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const v8 = b.option(bool, "v8", "Link v8 lib") orelse false;
    const net = b.option(bool, "net", "Link net libs") orelse false;
    const static_link = b.option(bool, "static", "Statically link deps") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};
    const deps_rev = b.option([]const u8, "deps-rev", "Override the deps revision.") orelse DepsRevision;
    const is_official_build = b.option(bool, "is-official-build", "Whether the build should be an official build.") orelse false;
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

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
        .link_v8 = v8,
        .link_net = net,
        .link_mock = false,
        .static_link = static_link,
        .path = path,
        .filter = filter,
        .mode = mode,
        .target = target,
        .build_options = build_options,
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
        const main_test = ctx.createTestStep();
        step.step.dependOn(&main_test.step);
        b.step("test", "Run tests").dependOn(&step.step);
    }

    const test_file = ctx.createTestFileStep();
    b.step("test-file", "Test file with -Dpath").dependOn(&test_file.step);

    const build_exe = ctx.createBuildExeStep();
    b.step("exe", "Build exe with main file at -Dpath").dependOn(&build_exe.step);

    const run_exe = build_exe.run();
    run_exe.addArgs(args);
    b.step("run", "Run with main file at -Dpath").dependOn(&run_exe.step);

    const build_lib = ctx.createBuildLibStep();
    b.step("lib", "Build lib with main file at -Dpath").dependOn(&build_lib.step);

    {
        const step = b.step("openssl", "Build openssl.");
        const crypto = try openssl.buildCrypto(b, target, mode);
        step.dependOn(&b.addInstallArtifact(crypto).step);
        const ssl = try openssl.buildSsl(b, target, mode);
        step.dependOn(&b.addInstallArtifact(ssl).step);
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
            .link_v8 = false,
            .link_mock = true,
            .static_link = static_link,
            .path = "cosmic/doc_gen.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = _build_options,
        };

        const step = _ctx.createBuildExeStep();
        _ctx.buildLinkMock(step);
        const run = step.run();
        run.addArgs(args);
        b.step("gen-docs", "Generate docs").dependOn(&run.step);
    }

    {
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
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
            .link_v8 = true,
            .link_mock = false,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = mode,
            .target = target,
            .build_options = build_options,
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

    // Whitelist test is useful for running tests that were manually included with an INCLUDE prefix.
    const whitelist_test = ctx.createTestStep();
    whitelist_test.setFilter("INCLUDE");
    b.step("whitelist-test", "Tests with INCLUDE in name").dependOn(&whitelist_test.step);

    // b.default_step.dependOn(&build_cosmic.step);
}

const BuilderContext = struct {
    const Self = @This();

    builder: *std.build.Builder,
    path: []const u8,
    filter: []const u8,
    enable_tracy: bool,
    link_graphics: bool,
    link_v8: bool,
    link_net: bool,
    link_mock: bool,
    static_link: bool,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    build_options: *std.build.OptionsStep,

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
        if (artifact.kind == .exe) {
            const basename = std.fs.path.basename(artifact.root_src.?.path);
            const i = std.mem.indexOf(u8, basename, ".zig") orelse basename.len;
            const name = basename[0..i];
            const path = self.builder.fmt("{s}/{s}", .{ triple, name });
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

    fn createTestFileStep(self: *Self) *std.build.LibExeObjStep {
        const step = self.builder.addTest(self.path);
        self.setBuildMode(step);
        self.setTarget(step);
        step.setMainPkgPath(".");

        const build_options = self.buildOptionsPkg();
        addStdx(step, build_options);
        addCommon(step);
        addGraphics(step);
        addInput(step);
        self.addDeps(step) catch unreachable;
        self.buildLinkMock(step);

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
            try openssl.buildLinkCrypto(self.builder, self.target, self.mode, step);
            try openssl.buildLinkSsl(self.builder, self.target, self.mode, step);
            try self.buildLinkCurl(step);
            self.buildLinkNghttp2(step);
            self.buildLinkZlib(step);
            try self.buildLinkUv(step);
            try self.buildLinkH2O(step);
        }
        addSDL(step);
        addStbtt(step);
        addGL(step);
        addLyon(step);
        addStbi(step);
        if (builtin.os.tag == .macos) {
            self.buildLinkMacSys(step);
        }
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            self.buildMingwExtra(step);
            self.buildLinkWinPosix(step);
            self.buildLinkWinPthreads(step);
        }
        if (self.link_graphics) {
            try self.buildLinkSDL2(step);
            self.buildLinkStbtt(step);
            linkGL(step, self.target);
            self.linkLyon(step, self.target);
            self.buildLinkStbi(step);
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

    fn buildLinkH2O(self: *Self, step: *LibExeObjStep) !void {
        if (UsePrebuiltH2O) |path| {
            step.addAssemblyFile(path);
            return;
        }
        const lib = self.builder.addStaticLibrary("h2o", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);
        // lib.c_std = .C99;

        // Unused defines:
        // -DH2O_ROOT="/usr/local" -DH2O_CONFIG_PATH="/usr/local/etc/h2o.conf" -DH2O_HAS_PTHREAD_SETAFFINITY_NP 
        var c_flags = std.ArrayList([]const u8).init(self.builder.allocator);

        // Move args into response file to avoid cli limit.
        try c_flags.appendSlice(&.{
            "@lib/h2o/cflags",
        });
        if (self.target.getOsTag() == .linux) {
            try c_flags.appendSlice(&.{
                "-D_GNU_SOURCE", // This lets it find in6_pktinfo for some reason.
            });
        } else if (self.target.getOsTag() == .windows) {
            try c_flags.appendSlice(&.{
                "-D_WINDOWS=1",
                // Need this when using C99.
                "-D_POSIX_C_SOURCE=200809L",
                "-D_POSIX",
            });
        }

        var c_files = std.ArrayList([]const u8).init(self.builder.allocator);
        try c_files.appendSlice(&.{
            // deps
            "deps/picohttpparser/picohttpparser.c",
            //"deps/cloexec/cloexec.c",
            //"deps/hiredis/async.c",
            // "deps/hiredis/hiredis.c",
            // "deps/hiredis/net.c",
            // "deps/hiredis/read.c",
            // "deps/hiredis/sds.c",
            "deps/libgkc/gkc.c",
            //"deps/libyrmcds/close.c",
            //"deps/libyrmcds/connect.c",
            //"deps/libyrmcds/recv.c",
            //"deps/libyrmcds/send.c",
            //"deps/libyrmcds/send_text.c",
            //"deps/libyrmcds/socket.c",
            //"deps/libyrmcds/strerror.c",
            //"deps/libyrmcds/text_mode.c",
            "deps/picotls/deps/cifra/src/blockwise.c",
            "deps/picotls/deps/cifra/src/chash.c",
            "deps/picotls/deps/cifra/src/curve25519.c",
            "deps/picotls/deps/cifra/src/drbg.c",
            "deps/picotls/deps/cifra/src/hmac.c",
            "deps/picotls/deps/cifra/src/sha256.c",
            "deps/picotls/lib/certificate_compression.c",
            "deps/picotls/lib/pembase64.c",
            "deps/picotls/lib/picotls.c",
            "deps/picotls/lib/openssl.c",
            "deps/picotls/lib/cifra/random.c",
            "deps/picotls/lib/cifra/x25519.c",
            // "deps/quicly/lib/cc-cubic.c",
            // "deps/quicly/lib/cc-pico.c",
            // "deps/quicly/lib/cc-reno.c",
            // "deps/quicly/lib/defaults.c",
            // "deps/quicly/lib/frame.c",
            // "deps/quicly/lib/local_cid.c",
            // "deps/quicly/lib/loss.c",
            // "deps/quicly/lib/quicly.c",
            // "deps/quicly/lib/ranges.c",
            // "deps/quicly/lib/rate.c",
            // "deps/quicly/lib/recvstate.c",
            // "deps/quicly/lib/remote_cid.c",
            // "deps/quicly/lib/retire_cid.c",
            // "deps/quicly/lib/sendstate.c",
            // "deps/quicly/lib/sentmap.c",
            // "deps/quicly/lib/streambuf.c",

            // common
            "lib/common/cache.c",
            "lib/common/file.c",
            "lib/common/filecache.c",
            "lib/common/hostinfo.c",
            // "lib/common/http1client.c",
            // "lib/common/http2client.c",
            // "lib/common/http3client.c",
            // "lib/common/httpclient.c",
            // "lib/common/memcached.c",
            "lib/common/memory.c",
            "lib/common/multithread.c",
            // "lib/common/redis.c",
            // "lib/common/serverutil.c",
            "lib/common/socket.c",
            "lib/common/socketpool.c",
            "lib/common/string.c",
            "lib/common/rand.c",
            "lib/common/time.c",
            "lib/common/timerwheel.c",
            "lib/common/token.c",
            "lib/common/url.c",
            "lib/common/balancer/roundrobin.c",
            "lib/common/balancer/least_conn.c",
            "lib/common/absprio.c",

            "lib/core/config.c",
            "lib/core/configurator.c",
            "lib/core/context.c",
            "lib/core/headers.c",
            // "lib/core/logconf.c",
            // "lib/core/proxy.c",
            "lib/core/request.c",
            "lib/core/util.c",

            // "lib/handler/access_log.c",
            "lib/handler/compress.c",
            "lib/handler/compress/gzip.c",
            "lib/handler/errordoc.c",
            "lib/handler/expires.c",
            "lib/handler/fastcgi.c",
            // "lib/handler/file.c",
            "lib/handler/headers.c",
            "lib/handler/mimemap.c",
            "lib/handler/proxy.c",
            // "lib/handler/connect.c",
            "lib/handler/redirect.c",
            "lib/handler/reproxy.c",
            "lib/handler/throttle_resp.c",
            "lib/handler/self_trace.c",
            "lib/handler/server_timing.c",
            "lib/handler/status.c",
            "lib/handler/headers_util.c",
            "lib/handler/status/events.c",
            "lib/handler/status/requests.c",
            "lib/handler/status/ssl.c",
            "lib/handler/http2_debug_state.c",
            "lib/handler/status/durations.c",
            // "lib/handler/configurator/access_log.c",
            "lib/handler/configurator/compress.c",
            "lib/handler/configurator/errordoc.c",
            "lib/handler/configurator/expires.c",
            // "lib/handler/configurator/fastcgi.c",
            "lib/handler/configurator/file.c",
            "lib/handler/configurator/headers.c",
            "lib/handler/configurator/proxy.c",
            "lib/handler/configurator/redirect.c",
            "lib/handler/configurator/reproxy.c",
            "lib/handler/configurator/throttle_resp.c",
            "lib/handler/configurator/self_trace.c",
            "lib/handler/configurator/server_timing.c",
            "lib/handler/configurator/status.c",
            "lib/handler/configurator/http2_debug_state.c",
            "lib/handler/configurator/headers_util.c",

            "lib/http1.c",

            "lib/tunnel.c",

            "lib/http2/cache_digests.c",
            "lib/http2/casper.c",
            "lib/http2/connection.c",
            "lib/http2/frame.c",
            "lib/http2/hpack.c",
            "lib/http2/scheduler.c",
            "lib/http2/stream.c",
            "lib/http2/http2_debug_state.c",

            // "lib/http3/frame.c",
            // "lib/http3/qpack.c",
            // "lib/http3/common.c",
            // "lib/http3/server.c",
        });

        for (c_files.items) |file| {
            self.addCSourceFileFmt(lib, "./deps/h2o/{s}", .{file}, c_flags.items);
        }

        lib.addCSourceFile("./lib/h2o/utils.c", c_flags.items);

        // picohttpparser has intentional UB code in
        // findchar_fast when SSE4_2 is enabled: _mm_loadu_si128 can be given ranges pointer with less than 16 bytes.
        // Can't seem to turn off sanitize for just the one source file. Tried to separate picohttpparser into it's own lib too.
        // For now, disable sanitize c for entire h2o lib.
        lib.disable_sanitize_c = true;

        if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            if (self.target.isNativeOs()) {
                // Force using native headers or it won't find netinet/udp.h
                lib.linkFramework("CoreServices");
            } else {
                lib.addSystemIncludeDir("/usr/include");
            }
        } 

        lib.linkLibC();

        // Load user_config.h here. include/h2o.h was patched to include user_config.h
        lib.addIncludeDir("./lib/h2o");

        lib.addIncludeDir("./deps/openssl/include");
        lib.addIncludeDir("./deps/libuv/include");
        lib.addIncludeDir("./deps/h2o/include");
        lib.addIncludeDir("./deps/zlib");
        lib.addIncludeDir("./deps/h2o/deps/quicly/include");
        lib.addIncludeDir("./deps/h2o/deps/picohttpparser");
        lib.addIncludeDir("./deps/h2o/deps/picotls/include");
        lib.addIncludeDir("./deps/h2o/deps/klib");
        lib.addIncludeDir("./deps/h2o/deps/cloexec");
        lib.addIncludeDir("./deps/h2o/deps/brotli/c/include");
        lib.addIncludeDir("./deps/h2o/deps/yoml");
        lib.addIncludeDir("./deps/h2o/deps/hiredis");
        lib.addIncludeDir("./deps/h2o/deps/golombset");
        lib.addIncludeDir("./deps/h2o/deps/libgkc");
        lib.addIncludeDir("./deps/h2o/deps/libyrmcds");
        lib.addIncludeDir("./deps/h2o/deps/picotls/deps/cifra/src/ext");
        lib.addIncludeDir("./deps/h2o/deps/picotls/deps/cifra/src");
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            // Since H2O source relies on posix only, provide an interface to windows API.
            lib.addIncludeDir("./lib/mingw/win_posix/include");
            lib.addIncludeDir("./lib/mingw/winpthreads/include");
        } 
        step.linkLibrary(lib);
    }

    fn buildLinkUv(self: *Self, step: *LibExeObjStep) !void {
        if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            step.linkSystemLibrary("iphlpapi");
        }
        if (UsePrebuiltUv) |path| {
            step.addAssemblyFile(path);
            return;
        }

        const lib = self.builder.addStaticLibrary("uv", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        var c_flags = std.ArrayList([]const u8).init(self.builder.allocator);

        // From CMakeLists.txt
        var c_files = std.ArrayList([]const u8).init(self.builder.allocator);
        try c_files.appendSlice(&.{
            // common
            "src/fs-poll.c",
            "src/idna.c",
            "src/inet.c",
            "src/random.c",
            "src/strscpy.c",
            "src/threadpool.c",
            "src/timer.c",
            "src/uv-common.c",
            "src/uv-data-getter-setters.c",
            "src/version.c",
        });
        if (self.target.getOsTag() == .linux or self.target.getOsTag() == .macos) {
            try c_files.appendSlice(&.{
                "src/unix/async.c",
                "src/unix/core.c",
                "src/unix/dl.c",
                "src/unix/fs.c",
                "src/unix/getaddrinfo.c",
                "src/unix/getnameinfo.c",
                "src/unix/loop-watcher.c",
                "src/unix/loop.c",
                "src/unix/pipe.c",
                "src/unix/poll.c",
                "src/unix/process.c",
                "src/unix/random-devurandom.c",
                "src/unix/signal.c",
                "src/unix/stream.c",
                "src/unix/tcp.c",
                "src/unix/thread.c",
                "src/unix/tty.c",
                "src/unix/udp.c",
                "src/unix/proctitle.c",
            });
        }
        if (self.target.getOsTag() == .linux) {
            try c_files.appendSlice(&.{
                // sys
                "src/unix/linux-core.c",
                "src/unix/linux-inotify.c",
                "src/unix/linux-syscalls.c",
                "src/unix/procfs-exepath.c",
                "src/unix/random-getrandom.c",
                "src/unix/random-sysctl-linux.c",
                "src/unix/epoll.c",
            });
            try c_flags.appendSlice(&.{
                "-D_GNU_SOURCE",
                "-D_POSIX_C_SOURCE=200112",
            });
        } else if (self.target.getOsTag() == .macos) {
            try c_files.appendSlice(&.{
                "src/unix/bsd-ifaddrs.c",
                "src/unix/kqueue.c",
                "src/unix/random-getentropy.c",
                "src/unix/darwin-proctitle.c",
                "src/unix/darwin.c",
                "src/unix/fsevents.c",
            });
            try c_flags.appendSlice(&.{
                "-D_DARWIN_UNLIMITED_SELECT=1",
                "-D_DARWIN_USE_64_BIT_INODE=1",
                "-D_FILE_OFFSET_BITS=64",
                "-D_LARGEFILE_SOURCE",
            });
        } else if (self.target.getOsTag() == .windows) {
            try c_files.appendSlice(&.{
                "src/win/loop-watcher.c",
                "src/win/tcp.c",
                "src/win/async.c",
                "src/win/core.c",
                "src/win/signal.c",
                "src/win/snprintf.c",
                "src/win/getnameinfo.c",
                "src/win/fs.c",
                "src/win/fs-event.c",
                "src/win/getaddrinfo.c",
                "src/win/handle.c",
                "src/win/dl.c",
                "src/win/udp.c",
                "src/win/util.c",
                "src/win/error.c",
                "src/win/winapi.c",
                "src/win/winsock.c",
                "src/win/detect-wakeup.c",
                "src/win/stream.c",
                "src/win/tty.c",
                "src/win/process-stdio.c",
                "src/win/process.c",
                "src/win/poll.c",
                "src/win/thread.c",
                "src/win/pipe.c",
            });
        }

        for (c_files.items) |file| {
            self.addCSourceFileFmt(lib, "./deps/libuv/{s}", .{file}, c_flags.items);
        }

        // libuv has UB in uv__write_req_update when the last buf->base has a null ptr.
        lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./deps/libuv/include");
        lib.addIncludeDir("./deps/libuv/src");
        if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            if (self.target.isNativeOs()) {
                // Force using native headers or it'll compile with ___darwin_check_fd_set_overflow calls
                // which doesn't exist in later mac libs.
                lib.linkFramework("CoreServices");
            } else {
                lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            }
        }
        step.linkLibrary(lib);
    }

    fn buildLinkSDL2(self: *Self, step: *LibExeObjStep) !void {
        if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            // "sdl2_config --static-libs" tells us what we need
            if (!self.target.isNativeOs()) {
                step.addFrameworkDir("/System/Library/Frameworks");
                step.addLibPath("/usr/lib"); // To find libiconv.
            }
            step.linkFramework("Cocoa");
            step.linkFramework("IOKit");
            step.linkFramework("CoreAudio");
            step.linkFramework("CoreVideo");
            step.linkFramework("Carbon");
            step.linkFramework("Metal");
            step.linkFramework("ForceFeedback");
            step.linkFramework("AudioToolbox");
            step.linkFramework("GameController");
            step.linkFramework("CFNetwork");
            step.linkSystemLibrary("iconv");
            step.linkSystemLibrary("m");
            if (UsePrebuiltSDL and self.target.getCpuArch() == .x86_64) {
                step.addAssemblyFile("./deps/prebuilt/mac64/libSDL2.a");
                return;
            }
        } else if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            step.linkSystemLibrary("setupapi");
            step.linkSystemLibrary("ole32");
            step.linkSystemLibrary("oleaut32");
            step.linkSystemLibrary("gdi32");
            step.linkSystemLibrary("imm32");
            step.linkSystemLibrary("version");
        } else if (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64) {
            if (UsePrebuiltSDL) {
                const path = self.fromRoot("./deps/prebuilt/linux64/libSDL2.a");
                step.addAssemblyFile(path);
                return;
            }
        } else {
            if (UsePrebuiltSDL) {
                step.linkSystemLibrary("SDL2");
                return;
            }
        }

        const lib = self.builder.addStaticLibrary("SDL2", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        // Use SDL_config_minimal.h instead of relying on configure or CMake
        // and add defines to make it work for most modern platforms.
        var c_flags = std.ArrayList([]const u8).init(self.builder.allocator);

        if (self.target.getOsTag() == .macos) {
            try c_flags.appendSlice(&.{
                // Silence warnings that are errors by default in objc source files. Noticed this in github ci.
                "-Wno-deprecated-declarations",
                "-Wno-unguarded-availability",
            });
        }

        // Look at CMakeLists.txt.
        var c_files = std.ArrayList([]const u8).init(self.builder.allocator);

        try c_files.appendSlice(&.{
            // General source files.
            "SDL_log.c",
            "SDL_hints.c",
            "SDL_error.c",
            "SDL_dataqueue.c",
            "SDL.c",
            "SDL_assert.c",
            "atomic/SDL_spinlock.c",
            "atomic/SDL_atomic.c",
            "audio/SDL_wave.c",
            "audio/SDL_mixer.c",
            "audio/SDL_audiotypecvt.c",
            "audio/SDL_audiodev.c",
            "audio/SDL_audiocvt.c",
            "audio/SDL_audio.c",
            "audio/disk/SDL_diskaudio.c",
            "audio/dsp/SDL_dspaudio.c",
            "audio/sndio/SDL_sndioaudio.c",
            "cpuinfo/SDL_cpuinfo.c",
            "dynapi/SDL_dynapi.c",
            "events/SDL_windowevents.c",
            "events/SDL_touch.c",
            "events/SDL_quit.c",
            "events/SDL_mouse.c",
            "events/SDL_keyboard.c",
            "events/SDL_gesture.c",
            "events/SDL_events.c",
            "events/SDL_dropevents.c",
            "events/SDL_displayevents.c",
            "events/SDL_clipboardevents.c",
            "events/imKStoUCS.c",
            "file/SDL_rwops.c",
            "haptic/SDL_haptic.c",
            "hidapi/SDL_hidapi.c",
            "libm/s_tan.c",
            "libm/s_sin.c",
            "libm/s_scalbn.c",
            "libm/s_floor.c",
            "libm/s_fabs.c",
            "libm/s_cos.c",
            "libm/s_copysign.c",
            "libm/s_atan.c",
            "libm/k_tan.c",
            "libm/k_rem_pio2.c",
            "libm/k_cos.c",
            "libm/e_sqrt.c",
            "libm/e_rem_pio2.c",
            "libm/e_pow.c",
            "libm/e_log.c",
            "libm/e_log10.c",
            "libm/e_fmod.c",
            "libm/e_exp.c",
            "libm/e_atan2.c",
            "libm/k_sin.c",
            "locale/SDL_locale.c",
            "misc/SDL_url.c",
            "power/SDL_power.c",
            "render/SDL_yuv_sw.c",
            "render/SDL_render.c",
            "render/SDL_d3dmath.c",
            "render/vitagxm/SDL_render_vita_gxm_tools.c",
            "render/vitagxm/SDL_render_vita_gxm_memory.c",
            "render/vitagxm/SDL_render_vita_gxm.c",
            "render/software/SDL_triangle.c",
            "render/software/SDL_rotate.c",
            "render/software/SDL_render_sw.c",
            "render/software/SDL_drawpoint.c",
            "render/software/SDL_drawline.c",
            "render/software/SDL_blendpoint.c",
            "render/software/SDL_blendline.c",
            "render/software/SDL_blendfillrect.c",
            "render/psp/SDL_render_psp.c",
            "render/opengl/SDL_shaders_gl.c",
            "render/opengles/SDL_render_gles.c",
            "render/opengles2/SDL_shaders_gles2.c",
            "render/opengles2/SDL_render_gles2.c",
            "render/opengl/SDL_render_gl.c",
            "render/direct3d/SDL_shaders_d3d.c",
            "render/direct3d/SDL_render_d3d.c",
            "render/direct3d11/SDL_shaders_d3d11.c",
            "render/direct3d11/SDL_render_d3d11.c",
            "sensor/SDL_sensor.c",
            "stdlib/SDL_strtokr.c",
            "stdlib/SDL_stdlib.c",
            "stdlib/SDL_qsort.c",
            "stdlib/SDL_malloc.c",
            "stdlib/SDL_iconv.c",
            "stdlib/SDL_getenv.c",
            "stdlib/SDL_crc32.c",
            "stdlib/SDL_string.c",
            "thread/SDL_thread.c",
            "timer/SDL_timer.c",
            "video/SDL_yuv.c",
            "video/SDL_vulkan_utils.c",
            "video/SDL_surface.c",
            "video/SDL_stretch.c",
            "video/SDL_shape.c",
            "video/SDL_RLEaccel.c",
            "video/SDL_rect.c",
            "video/SDL_pixels.c",
            "video/SDL_video.c",
            "video/SDL_fillrect.c",
            "video/SDL_egl.c",
            "video/SDL_bmp.c",
            "video/SDL_clipboard.c",
            "video/SDL_blit_slow.c",
            "video/SDL_blit_N.c",
            "video/SDL_blit_copy.c",
            "video/SDL_blit_auto.c",
            "video/SDL_blit_A.c",
            "video/SDL_blit.c",
            "video/SDL_blit_0.c",
            "video/SDL_blit_1.c",
            "video/yuv2rgb/yuv_rgb.c",

            // SDL_JOYSTICK
            "joystick/SDL_joystick.c",
            "joystick/SDL_gamecontroller.c",

            // Dummy
            "audio/dummy/SDL_dummyaudio.c",
            "sensor/dummy/SDL_dummysensor.c",
            "haptic/dummy/SDL_syshaptic.c",
            "joystick/dummy/SDL_sysjoystick.c",
            "video/dummy/SDL_nullvideo.c",
            "video/dummy/SDL_nullframebuffer.c",
            "video/dummy/SDL_nullevents.c",

            // Steam
            "joystick/steam/SDL_steamcontroller.c",

            "joystick/hidapi/SDL_hidapi_rumble.c",
            "joystick/hidapi/SDL_hidapijoystick.c",
            "joystick/hidapi/SDL_hidapi_xbox360w.c",
            "joystick/hidapi/SDL_hidapi_switch.c",
            "joystick/hidapi/SDL_hidapi_steam.c",
            "joystick/hidapi/SDL_hidapi_stadia.c",
            "joystick/hidapi/SDL_hidapi_ps4.c",
            "joystick/hidapi/SDL_hidapi_xboxone.c",
            "joystick/hidapi/SDL_hidapi_xbox360.c",
            "joystick/hidapi/SDL_hidapi_gamecube.c",
            "joystick/hidapi/SDL_hidapi_ps5.c",
            "joystick/hidapi/SDL_hidapi_luna.c",

            "joystick/virtual/SDL_virtualjoystick.c",
        });

        if (self.target.getOsTag() == .linux or self.target.getOsTag() == .macos) {
            try c_files.appendSlice(&.{
                // Threads
                "thread/pthread/SDL_systhread.c",
                "thread/pthread/SDL_systls.c",
                "thread/pthread/SDL_syssem.c",
                "thread/pthread/SDL_sysmutex.c",
                "thread/pthread/SDL_syscond.c",
            });
        }

        if (self.target.getOsTag() == .linux) {
            try c_files.appendSlice(&.{
                "core/unix/SDL_poll.c",
                "core/linux/SDL_evdev.c",
                "core/linux/SDL_evdev_kbd.c",
                "core/linux/SDL_dbus.c",
                "core/linux/SDL_ime.c",
                "core/linux/SDL_udev.c",
                "core/linux/SDL_threadprio.c",
                // "core/linux/SDL_fcitx.c",
                "core/linux/SDL_ibus.c",
                "core/linux/SDL_evdev_capabilities.c",

                "power/linux/SDL_syspower.c",
                "haptic/linux/SDL_syshaptic.c",

                "misc/unix/SDL_sysurl.c",
                "timer/unix/SDL_systimer.c",
                "locale/unix/SDL_syslocale.c",

                "loadso/dlopen/SDL_sysloadso.c",

                "filesystem/unix/SDL_sysfilesystem.c",

                "video/x11/SDL_x11opengles.c",
                "video/x11/SDL_x11messagebox.c",
                "video/x11/SDL_x11touch.c",
                "video/x11/SDL_x11mouse.c",
                "video/x11/SDL_x11keyboard.c",
                "video/x11/SDL_x11video.c",
                "video/x11/edid-parse.c",
                "video/x11/SDL_x11dyn.c",
                "video/x11/SDL_x11framebuffer.c",
                "video/x11/SDL_x11opengl.c",
                "video/x11/SDL_x11modes.c",
                "video/x11/SDL_x11shape.c",
                "video/x11/SDL_x11window.c",
                "video/x11/SDL_x11vulkan.c",
                "video/x11/SDL_x11xfixes.c",
                "video/x11/SDL_x11clipboard.c",
                "video/x11/SDL_x11events.c",
                "video/x11/SDL_x11xinput2.c",

                "audio/alsa/SDL_alsa_audio.c",
                "audio/pulseaudio/SDL_pulseaudio.c",
                "joystick/linux/SDL_sysjoystick.c",
            });
        } else if (self.target.getOsTag() == .macos) {
            try c_files.appendSlice(&.{
                "joystick/darwin/SDL_iokitjoystick.c",
                "haptic/darwin/SDL_syshaptic.c",

                "video/cocoa/SDL_cocoametalview.m",
                "video/cocoa/SDL_cocoaclipboard.m",
                "video/cocoa/SDL_cocoashape.m",
                "video/cocoa/SDL_cocoakeyboard.m",
                "video/cocoa/SDL_cocoamessagebox.m",
                "video/cocoa/SDL_cocoaevents.m",
                "video/cocoa/SDL_cocoamouse.m",
                "video/cocoa/SDL_cocoavideo.m",
                "video/cocoa/SDL_cocoawindow.m",
                "video/cocoa/SDL_cocoavulkan.m",
                "video/cocoa/SDL_cocoaopengles.m",
                "video/cocoa/SDL_cocoamodes.m",
                "video/cocoa/SDL_cocoaopengl.m",
                "file/cocoa/SDL_rwopsbundlesupport.m",
                "render/metal/SDL_render_metal.m",
                "filesystem/cocoa/SDL_sysfilesystem.m",
                "audio/coreaudio/SDL_coreaudio.m",
                "locale/macosx/SDL_syslocale.m",

                // Currently, joystick support is disabled in SDL_config.h for macos since there were issues
                // building in github ci and there is no cosmic joystick api atm.
                // Once enabled, SDL_mfijoystick will have a compile error in github ci: cannot create __weak reference in file using manual reference counting
                // This can be resolved by giving it "-fobjc-arc" cflag for just the one file.
                // After that it turns out we'll need CoreHaptics but it's not always available and zig doesn't have a way to set weak frameworks yet:
                // https://github.com/ziglang/zig/issues/10206
                "joystick/iphoneos/SDL_mfijoystick.m",

                "timer/unix/SDL_systimer.c",
                "loadso/dlopen/SDL_sysloadso.c",
                "misc/unix/SDL_sysurl.c",
                "power/macosx/SDL_syspower.c",
            });
        } else if (self.target.getOsTag() == .windows) {
            try c_files.appendSlice(&.{
                "core/windows/SDL_xinput.c",
                "core/windows/SDL_windows.c",
                "core/windows/SDL_hid.c",
                "misc/windows/SDL_sysurl.c",
                "locale/windows/SDL_syslocale.c",
                "sensor/windows/SDL_windowssensor.c",
                "power/windows/SDL_syspower.c",
                "video/windows/SDL_windowsmodes.c",
                "video/windows/SDL_windowsclipboard.c",
                "video/windows/SDL_windowsopengles.c",
                "video/windows/SDL_windowsevents.c",
                "video/windows/SDL_windowsvideo.c",
                "video/windows/SDL_windowskeyboard.c",
                "video/windows/SDL_windowsshape.c",
                "video/windows/SDL_windowswindow.c",
                "video/windows/SDL_windowsvulkan.c",
                "video/windows/SDL_windowsmouse.c",
                "video/windows/SDL_windowsopengl.c",
                "video/windows/SDL_windowsframebuffer.c",
                "video/windows/SDL_windowsmessagebox.c",
                "joystick/windows/SDL_rawinputjoystick.c",
                "joystick/windows/SDL_dinputjoystick.c",
                "joystick/windows/SDL_xinputjoystick.c",
                "joystick/windows/SDL_windows_gaming_input.c",
                "joystick/windows/SDL_windowsjoystick.c",
                "haptic/windows/SDL_windowshaptic.c",
                "haptic/windows/SDL_xinputhaptic.c",
                "haptic/windows/SDL_dinputhaptic.c",
                "audio/winmm/SDL_winmm.c",
                "audio/directsound/SDL_directsound.c",
                "audio/wasapi/SDL_wasapi.c",
                "audio/wasapi/SDL_wasapi_win32.c",
                "timer/windows/SDL_systimer.c",
                "thread/windows/SDL_sysmutex.c",
                "thread/windows/SDL_systhread.c",
                "thread/windows/SDL_syssem.c",
                "thread/windows/SDL_systls.c",
                "thread/windows/SDL_syscond_cv.c",
                "thread/generic/SDL_systls.c",
                "thread/generic/SDL_syssem.c",
                "thread/generic/SDL_sysmutex.c",
                "thread/generic/SDL_systhread.c",
                "thread/generic/SDL_syscond.c",
                "loadso/windows/SDL_sysloadso.c",
                "filesystem/windows/SDL_sysfilesystem.c",
            });
        }

        for (c_files.items) |file| {
            self.addCSourceFileFmt(lib, "./deps/SDL/src/{s}", .{file}, c_flags.items);
        }

        lib.linkLibC();
        // Look for our custom SDL_config.h.
        lib.addIncludeDir("./lib/sdl");
        // For local CMake generated config.
        // lib.addIncludeDir("./deps/SDL/build/include");
        lib.addIncludeDir("./deps/SDL/include");
        if (self.target.getOsTag() == .linux) {
            lib.addIncludeDir("/usr/include");
            lib.addIncludeDir("/usr/include/x86_64-linux-gnu");
            lib.addIncludeDir("/usr/include/dbus-1.0");
            lib.addIncludeDir("/usr/lib/x86_64-linux-gnu/dbus-1.0/include");
        } else if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            if (self.target.isNativeOs()) {
                lib.linkFramework("CoreFoundation");
            } else {
                lib.addFrameworkDir("/System/Library/Frameworks");
                lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            }
        }
        step.linkLibrary(lib);
    }

    fn buildLinkZlib(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("zlib", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        const c_flags = &[_][]const u8{
        };

        const c_files = &[_][]const u8{
            "inftrees.c",
            "inflate.c",
            "adler32.c",
            "zutil.c",
            "trees.c",
            "gzclose.c",
            "gzwrite.c",
            "gzread.c",
            "deflate.c",
            "compress.c",
            "crc32.c",
            "infback.c",
            "gzlib.c",
            "uncompr.c",
            "inffast.c",
        };

        for (c_files) |file| {
            self.addCSourceFileFmt(lib, "./deps/zlib/{s}", .{file}, c_flags);
        }

        lib.linkLibC();
        step.linkLibrary(lib);
    }

    fn buildLinkNghttp2(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("nghttp2", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        const c_flags = &[_][]const u8{
            "-DNGHTTP2_STATICLIB=1",
        };

        const c_files = &[_][]const u8{
            // Copied from nghttp2/lib/CMakeLists.txt 
            "nghttp2_pq.c",
            "nghttp2_map.c",
            "nghttp2_queue.c",
            "nghttp2_frame.c",
            "nghttp2_buf.c",
            "nghttp2_stream.c",
            "nghttp2_outbound_item.c",
            "nghttp2_session.c",
            "nghttp2_submit.c",
            "nghttp2_helper.c",
            "nghttp2_npn.c",
            "nghttp2_hd.c",
            "nghttp2_hd_huffman.c",
            "nghttp2_hd_huffman_data.c",
            "nghttp2_version.c",
            "nghttp2_priority_spec.c",
            "nghttp2_option.c",
            "nghttp2_callbacks.c",
            "nghttp2_mem.c",
            "nghttp2_http.c",
            "nghttp2_rcbuf.c",
            "nghttp2_debug.c",
        };

        for (c_files) |file| {
            self.addCSourceFileFmt(lib, "./deps/nghttp2/lib/{s}", .{file}, c_flags);
        }

        // lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./deps/nghttp2/lib/includes");
        step.linkLibrary(lib);
    }

    fn buildLinkCurl(self: *Self, step: *LibExeObjStep) !void {
        if (builtin.os.tag == .macos and self.target.isNativeOs()) {
            step.linkFramework("SystemConfiguration");
        } else if (self.target.getOsTag() == .windows and self.target.getAbi() == .gnu) {
            step.linkSystemLibrary("crypt32");
        }
        if (UsePrebuiltCurl) |path| {
            step.addAssemblyFile(path);
            return;
        }

        // TODO: Currently seeing BADF panics when doing fs syscalls when building/linking libcurl dynamically.
        // Similar to this issue: https://github.com/ziglang/zig/issues/10375
        // For now, just build a static lib.
        // const lib = self.builder.addSharedLibrary("curl", null, .unversioned);

        const lib = self.builder.addStaticLibrary("curl", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        // See config.status or lib/curl_config.h for generated defines from configure.
        var c_flags = std.ArrayList([]const u8).init(self.builder.allocator);
        try c_flags.appendSlice(&.{
            // Indicates that we're building the lib not the tools.
            "-DBUILDING_LIBCURL",

            // Hides libcurl internal symbols (hide all symbols that aren't officially external).
            "-DCURL_HIDDEN_SYMBOLS",

            "-DCURL_STATICLIB",

            "-DNGHTTP2_STATICLIB=1",

            "-Wno-system-headers",
        });

        // Currently only linux and mac have custom configs.
        if (self.target.getOsTag() == .linux or self.target.getOsTag() == .macos or self.target.getOsTag() == .windows) {
            // Will make sources include curl_config.h in ./lib/curl
            try c_flags.append("-DHAVE_CONFIG_H");
        }

        if (self.target.getOsTag() == .linux) {
            // cpu-machine-OS
            // eg. x86_64-pc-linux-gnu
            const os_flag = try std.fmt.allocPrint(self.builder.allocator, "-DOS=\"{s}-pc-{s}-{s}\"", .{
                @tagName(self.target.getCpuArch()),
                @tagName(self.target.getOsTag()),
                @tagName(self.target.getAbi()),
            });
            try c_flags.appendSlice(&.{
                "-DTARGET_LINUX",
                "-pthread",
                "-Werror-implicit-function-declaration",
                "-fvisibility=hidden",
                // Move to curl_config.
                os_flag,
            });
        }

        const c_files = &[_][]const u8{
            // Copied from curl/lib/Makefile.inc (LIB_CFILES)
            "altsvc.c",
            "amigaos.c",
            "asyn-ares.c",
            "asyn-thread.c",
            "base64.c",
            "bufref.c",
            "c-hyper.c",
            "conncache.c",
            "connect.c",
            "content_encoding.c",
            "cookie.c",
            "curl_addrinfo.c",
            "curl_ctype.c",
            "curl_des.c",
            "curl_endian.c",
            "curl_fnmatch.c",
            "curl_get_line.c",
            "curl_gethostname.c",
            "curl_gssapi.c",
            "curl_memrchr.c",
            "curl_multibyte.c",
            "curl_ntlm_core.c",
            "curl_ntlm_wb.c",
            "curl_path.c",
            "curl_range.c",
            "curl_rtmp.c",
            "curl_sasl.c",
            "curl_sspi.c",
            "curl_threads.c",
            "dict.c",
            "doh.c",
            "dotdot.c",
            "dynbuf.c",
            "easy.c",
            "easygetopt.c",
            "easyoptions.c",
            "escape.c",
            "file.c",
            "fileinfo.c",
            "formdata.c",
            "ftp.c",
            "ftplistparser.c",
            "getenv.c",
            "getinfo.c",
            "gopher.c",
            "hash.c",
            "hmac.c",
            "hostasyn.c",
            "hostcheck.c",
            "hostip.c",
            "hostip4.c",
            "hostip6.c",
            "hostsyn.c",
            "hsts.c",
            "http.c",
            "http2.c",
            "http_chunks.c",
            "http_digest.c",
            "http_negotiate.c",
            "http_ntlm.c",
            "http_proxy.c",
            "http_aws_sigv4.c",
            "idn_win32.c",
            "if2ip.c",
            "imap.c",
            "inet_ntop.c",
            "inet_pton.c",
            "krb5.c",
            "ldap.c",
            "llist.c",
            "md4.c",
            "md5.c",
            "memdebug.c",
            "mime.c",
            "mprintf.c",
            "mqtt.c",
            "multi.c",
            "netrc.c",
            "non-ascii.c",
            "nonblock.c",
            "openldap.c",
            "parsedate.c",
            "pingpong.c",
            "pop3.c",
            "progress.c",
            "psl.c",
            "rand.c",
            "rename.c",
            "rtsp.c",
            "select.c",
            "sendf.c",
            "setopt.c",
            "sha256.c",
            "share.c",
            "slist.c",
            "smb.c",
            "smtp.c",
            "socketpair.c",
            "socks.c",
            "socks_gssapi.c",
            "socks_sspi.c",
            "speedcheck.c",
            "splay.c",
            "strcase.c",
            "strdup.c",
            "strerror.c",
            "strtok.c",
            "strtoofft.c",
            "system_win32.c",
            "telnet.c",
            "tftp.c",
            "timeval.c",
            "transfer.c",
            "url.c",
            "urlapi.c",
            "version.c",
            "version_win32.c",
            "warnless.c",
            "wildcard.c",
            "x509asn1.c",

            // Copied from curl/lib/Makefile.inc (LIB_VAUTH_CFILES)
            "vauth/cleartext.c",
            "vauth/cram.c",
            "vauth/digest.c",
            "vauth/digest_sspi.c",
            "vauth/gsasl.c",
            "vauth/krb5_gssapi.c",
            "vauth/krb5_sspi.c",
            "vauth/ntlm.c",
            "vauth/ntlm_sspi.c",
            "vauth/oauth2.c",
            "vauth/spnego_gssapi.c",
            "vauth/spnego_sspi.c",
            "vauth/vauth.c",

            // Copied from curl/lib/Makefile.inc (LIB_VTLS_CFILES)
            "vtls/bearssl.c",
            "vtls/gskit.c",
            "vtls/gtls.c",
            "vtls/keylog.c",
            "vtls/mbedtls.c",
            "vtls/mbedtls_threadlock.c",
            "vtls/mesalink.c",
            "vtls/nss.c",
            "vtls/openssl.c",
            "vtls/rustls.c",
            "vtls/schannel.c",
            "vtls/schannel_verify.c",
            "vtls/sectransp.c",
            "vtls/vtls.c",
            "vtls/wolfssl.c",
        };
        for (c_files) |file| {
            self.addCSourceFileFmt(lib, "./deps/curl/lib/{s}", .{file}, c_flags.items);
        }

        // lib.disable_sanitize_c = true;

        lib.linkLibC();
        if (self.target.getOsTag() == .linux) {
            lib.addIncludeDir("./lib/curl/linux");
        } else if (self.target.getOsTag() == .macos) {
            lib.addIncludeDir("./lib/curl/macos");
        } else if (self.target.getOsTag() == .windows) {
            lib.addIncludeDir("./lib/curl/windows");
        }
        lib.addIncludeDir("./deps/curl/include");
        lib.addIncludeDir("./deps/curl/lib");
        // Use the same openssl config so curl knows what features it has.
        lib.addIncludeDir("./lib/openssl/include");
        lib.addIncludeDir("./deps/openssl/include");
        lib.addIncludeDir("./deps/nghttp2/lib/includes");
        lib.addIncludeDir("./deps/zlib");
        if (builtin.os.tag == .macos and self.target.getOsTag() == .macos) {
            if (!self.target.isNativeOs()) {
                lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
                lib.addFrameworkDir("/System/Library/Frameworks");
            } 
            lib.linkFramework("SystemConfiguration");
        }
        step.linkLibrary(lib);
    }

    fn addCSourceFileFmt(self: *Self, lib: *LibExeObjStep, comptime format: []const u8, args: anytype, c_flags: []const []const u8) void {
        const path = std.fmt.allocPrint(self.builder.allocator, format, args) catch unreachable;
        lib.addCSourceFile(self.fromRoot(path), c_flags);
    }

    fn buildLinkStbtt(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("stbtt", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        lib.addIncludeDir(self.fromRoot("./deps/stb"));
        lib.linkLibC();
        const c_flags = &[_][]const u8{ "-O3", "-DSTB_TRUETYPE_IMPLEMENTATION" };
        lib.addCSourceFile(self.fromRoot("./lib/stbtt/stb_truetype.c"), c_flags);
        step.linkLibrary(lib);
    }

    fn buildLinkStbi(self: *Self, step: *std.build.LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("stbi", null);
        lib.setTarget(self.target);
        lib.setBuildMode(self.mode);

        lib.addIncludeDir(self.fromRoot("./deps/stb"));
        lib.linkLibC();

        const c_flags = &[_][]const u8{ "-O3", "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
        const src_files: []const []const u8 = &.{
            self.fromRoot("./lib/stbi/stb_image.c"),
            self.fromRoot("./lib/stbi/stb_image_write.c")
        };
        lib.addCSourceFiles(src_files, c_flags);
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
    step.addPackage(sdl_pkg);
    step.linkLibC();
    step.addIncludeDir("./deps/SDL/include");
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
    step.addIncludeDir("./deps/h2o/include");
    step.addIncludeDir("./deps/h2o/deps/picotls/include");
    step.addIncludeDir("./deps/h2o/deps/quicly/include");
    step.addIncludeDir("./deps/openssl/include");
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
    step.addIncludeDir("./deps/libuv/include");
}

const curl_pkg = Pkg{
    .name = "curl",
    .path = FileSource.relative("./lib/curl/curl.zig"),
};

fn addCurl(step: *LibExeObjStep) void {
    step.addPackage(curl_pkg);
    step.addIncludeDir("./deps/curl/include/curl");
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
    step.addIncludeDir("./deps");
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
    .path = FileSource.relative("./lib/stbi/stbi.zig"),
};

fn addStbi(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbi_pkg);
    step.addIncludeDir("./deps/stb");
}

const stbtt_pkg = Pkg{
    .name = "stbtt",
    .path = FileSource.relative("./lib/stbtt/stbtt.zig"),
};

fn addStbtt(step: *std.build.LibExeObjStep) void {
    step.addPackage(stbtt_pkg);
    step.addIncludeDir("./deps/stb");
    step.linkLibC();
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
    // Keep for local dev.
    // const mode_str: []const u8 = if (self.mode == .Debug) "debug" else "release";
    // const path = std.fmt.allocPrint(self.builder.allocator, "lib/zig-v8/v8-out/{s}-{s}/{s}/ninja/obj/zig/libc_v8.a", .{
    //     @tagName(self.target.getCpuArch()),
    //     @tagName(self.target.getOsTag()),
    //     mode_str,
    // }) catch unreachable;
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
