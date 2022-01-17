const std = @import("std");
const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const LibExeObjStep = std.build.LibExeObjStep;
const print = std.debug.print;
const builtin = @import("builtin");
const openssl = @import("lib/openssl/build.zig");
const Pkg = std.build.Pkg;

const VersionName = "v0.1 Alpha";

// During development you might want zls to see all the lib packages, remember to reset to false.
const IncludeAllLibs = false;

const UsePrebuiltCurl = false;

// To enable tracy profiling, append -Dtracy and ./lib/tracy must point to their main src tree.

pub fn build(b: *Builder) void {
    // Options.
    const path = b.option([]const u8, "path", "Path to main file, for: build, run, test-file") orelse "";
    const filter = b.option([]const u8, "filter", "For tests") orelse "";
    const tracy = b.option(bool, "tracy", "Enable tracy profiling.") orelse false;
    const graphics = b.option(bool, "graphics", "Link graphics libs") orelse false;
    const v8 = b.option(bool, "v8", "Link v8 lib") orelse false;
    const net = b.option(bool, "net", "Link net libs") orelse false;
    const static_link = b.option(bool, "static", "Statically link deps") orelse false;
    const args = b.option([]const []const u8, "arg", "Append an arg into run step.") orelse &[_][]const u8{};

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", tracy);
    build_options.addOption([]const u8, "VersionName", VersionName);

    const target = b.standardTargetOptions(.{});

    var ctx = BuilderContext{
        .builder = b,
        .enable_tracy = tracy,
        .link_graphics = graphics,
        .link_v8 = v8,
        .link_net = net,
        .static_link = static_link,
        .path = path,
        .filter = filter,
        .mode = b.standardReleaseOptions(),
        .target = target,
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

    {
        const _build_options = b.addOptions();
        _build_options.addOption([]const u8, "VersionName", VersionName);
        _build_options.addOption([]const u8, "BuildRoot", b.build_root);
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_v8 = true,
            .static_link = static_link,
            .path = "cosmic/doc_gen.zig",
            .filter = filter,
            .mode = b.standardReleaseOptions(),
            .target = target,
            .build_options = _build_options,
        };
        const step = _ctx.createBuildExeStep().run();
        step.addArgs(args);
        b.step("gen-docs", "Generate docs").dependOn(&step.step);
    }

    {
        var _ctx = BuilderContext{
            .builder = b,
            .enable_tracy = tracy,
            .link_net = true,
            .link_graphics = true,
            .link_v8 = true,
            .static_link = static_link,
            .path = "cosmic/main.zig",
            .filter = filter,
            .mode = b.standardReleaseOptions(),
            .target = target,
            .build_options = build_options,
        };
        const step = _ctx.createBuildExeStep().run();
        step.addArgs(&.{ "test", "test/js/test.js" });
        // test_cosmic_js.addArgs(&.{ "test", "test/load-test/cs-https-request-test.js" });
        b.step("test-cosmic-js", "Test cosmic js").dependOn(&step.step);
    }

    // Whitelist test is useful for running tests that were manually included with an INCLUDE prefix.
    const whitelist_test = ctx.createTestStep();
    whitelist_test.setFilter("INCLUDE");
    b.step("whitelist-test", "Tests with INCLUDE in name").dependOn(&whitelist_test.step);

    b.default_step.dependOn(&main_test.step);
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
    static_link: bool,
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

        const output_dir_rel = std.mem.concat(self.builder.allocator, u8, &.{ "zig-out/", name }) catch unreachable;
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

        step.addPackage(build_options);
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
        if (self.link_net or IncludeAllLibs) {
            addCurl(step);
            addUv(step);
            addH2O(step);
            addOpenSSL(step);
        }
        if (self.link_net) {
            openssl.buildLinkCrypto(self.builder, step) catch unreachable;
            openssl.buildLinkSsl(self.builder, step);
            self.buildLinkCurl(step);
            self.buildLinkNghttp2(step);
            self.buildLinkZlib(step);
            self.buildLinkUv(step) catch unreachable;
            self.buildLinkH2O(step);
        }
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

    fn buildLinkH2O(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("zlib", null);
        lib.c_std = .C99;
        // Unused defines:
        // -DH2O_ROOT="/usr/local" -DH2O_CONFIG_PATH="/usr/local/etc/h2o.conf" -DH2O_HAS_PTHREAD_SETAFFINITY_NP 
        const c_flags = &[_][]const u8{
            "-Wall",
            "-Wno-unused-value",
            "-Wno-nullability-completeness",
            "-Werror=implicit-function-declaration",
            "-Werror=incompatible-pointer-types",
            "-Wno-unused-but-set-variable",
            "-Wno-unused-result",
            "-pthread",
            "-O3",
            "-D_GNU_SOURCE", // This lets it find in6_pktinfo for some reason.
            "-g3",
            "-DH2O_USE_LIBUV",
            "-DH2O_USE_ALPN",
        };

        const c_files = &[_][]const u8{
            // deps
            "deps/picohttpparser/picohttpparser.c",
            "deps/cloexec/cloexec.c",
            "deps/hiredis/async.c",
            "deps/hiredis/hiredis.c",
            "deps/hiredis/net.c",
            "deps/hiredis/read.c",
            "deps/hiredis/sds.c",
            "deps/libgkc/gkc.c",
            "deps/libyrmcds/close.c",
            "deps/libyrmcds/connect.c",
            "deps/libyrmcds/recv.c",
            "deps/libyrmcds/send.c",
            "deps/libyrmcds/send_text.c",
            "deps/libyrmcds/socket.c",
            "deps/libyrmcds/strerror.c",
            "deps/libyrmcds/text_mode.c",
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
            "deps/quicly/lib/cc-cubic.c",
            "deps/quicly/lib/cc-pico.c",
            "deps/quicly/lib/cc-reno.c",
            "deps/quicly/lib/defaults.c",
            "deps/quicly/lib/frame.c",
            "deps/quicly/lib/local_cid.c",
            "deps/quicly/lib/loss.c",
            "deps/quicly/lib/quicly.c",
            "deps/quicly/lib/ranges.c",
            "deps/quicly/lib/rate.c",
            "deps/quicly/lib/recvstate.c",
            "deps/quicly/lib/remote_cid.c",
            "deps/quicly/lib/retire_cid.c",
            "deps/quicly/lib/sendstate.c",
            "deps/quicly/lib/sentmap.c",
            "deps/quicly/lib/streambuf.c",

            // common
            "lib/common/cache.c",
            "lib/common/file.c",
            "lib/common/filecache.c",
            "lib/common/hostinfo.c",
            "lib/common/http1client.c",
            "lib/common/http2client.c",
            "lib/common/http3client.c",
            "lib/common/httpclient.c",
            "lib/common/memcached.c",
            "lib/common/memory.c",
            "lib/common/multithread.c",
            "lib/common/redis.c",
            "lib/common/serverutil.c",
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
            "lib/core/logconf.c",
            "lib/core/proxy.c",
            "lib/core/request.c",
            "lib/core/util.c",

            "lib/handler/access_log.c",
            "lib/handler/compress.c",
            "lib/handler/compress/gzip.c",
            "lib/handler/errordoc.c",
            "lib/handler/expires.c",
            "lib/handler/fastcgi.c",
            "lib/handler/file.c",
            "lib/handler/headers.c",
            "lib/handler/mimemap.c",
            "lib/handler/proxy.c",
            "lib/handler/connect.c",
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
            "lib/handler/configurator/access_log.c",
            "lib/handler/configurator/compress.c",
            "lib/handler/configurator/errordoc.c",
            "lib/handler/configurator/expires.c",
            "lib/handler/configurator/fastcgi.c",
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

            "lib/http3/frame.c",
            "lib/http3/qpack.c",
            "lib/http3/common.c",
            "lib/http3/server.c",
        };

        for (c_files) |file| {
            self.addCSourceFileFmt(lib, "./vendor/h2o/{s}", .{file}, c_flags);
        }

        lib.addCSourceFile("./lib/h2o/utils.c", c_flags);

        // picohttpparser has intentional UB code in
        // findchar_fast when SSE4_2 is enabled: _mm_loadu_si128 can be given ranges pointer with less than 16 bytes.
        // Can't seem to turn off sanitize for just the one source file. Tried to separate picohttpparser into it's own lib too.
        // For now, disable sanitize c for entire h2o lib.
        lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./vendor/openssl/include");
        lib.addIncludeDir("./vendor/libuv/include");
        lib.addIncludeDir("./vendor/h2o/include");
        lib.addIncludeDir("./vendor/zlib");
        lib.addIncludeDir("./vendor/h2o/deps/quicly/include");
        lib.addIncludeDir("./vendor/h2o/deps/picohttpparser");
        lib.addIncludeDir("./vendor/h2o/deps/picotls/include");
        lib.addIncludeDir("./vendor/h2o/deps/klib");
        lib.addIncludeDir("./vendor/h2o/deps/cloexec");
        lib.addIncludeDir("./vendor/h2o/deps/brotli/c/include");
        lib.addIncludeDir("./vendor/h2o/deps/yoml");
        lib.addIncludeDir("./vendor/h2o/deps/hiredis");
        lib.addIncludeDir("./vendor/h2o/deps/golombset");
        lib.addIncludeDir("./vendor/h2o/deps/libgkc");
        lib.addIncludeDir("./vendor/h2o/deps/libyrmcds");
        lib.addIncludeDir("./vendor/h2o/deps/picotls/deps/cifra/src/ext");
        lib.addIncludeDir("./vendor/h2o/deps/picotls/deps/cifra/src");
        step.linkLibrary(lib);
    }

    fn buildLinkUv(self: *Self, step: *LibExeObjStep) !void {
        const lib = self.builder.addStaticLibrary("zlib", null);

        var c_flags = std.ArrayList([]const u8).init(self.builder.allocator);
        if (step.target.getOsTag() == .linux) {
            try c_flags.appendSlice(&.{
                "-D_GNU_SOURCE",
                "-D_POSIX_C_SOURCE=200112",
            });
        }

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
        if (step.target.getOsTag() == .linux) {
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

                // sys
                "src/unix/linux-core.c",
                "src/unix/linux-inotify.c",
                "src/unix/linux-syscalls.c",
                "src/unix/procfs-exepath.c",
                "src/unix/random-getrandom.c",
                "src/unix/random-sysctl-linux.c",
                "src/unix/epoll.c",
                "src/unix/proctitle.c",
            });
        }

        for (c_files.items) |file| {
            self.addCSourceFileFmt(lib, "./vendor/libuv/{s}", .{file}, c_flags.items);
        }

        // libuv has UB in uv__write_req_update when the last buf->base has a null ptr.
        lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./vendor/libuv/include");
        lib.addIncludeDir("./vendor/libuv/src");
        step.linkLibrary(lib);
    }

    fn buildLinkZlib(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("zlib", null);
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
            self.addCSourceFileFmt(lib, "./vendor/zlib/{s}", .{file}, c_flags);
        }

        lib.linkLibC();
        step.linkLibrary(lib);
    }

    fn buildLinkNghttp2(self: *Self, step: *LibExeObjStep) void {
        const lib = self.builder.addStaticLibrary("nghttp2", null);

        const c_flags = &[_][]const u8{
            "-g",
            "-O2",
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
            self.addCSourceFileFmt(lib, "./vendor/nghttp2/lib/{s}", .{file}, c_flags);
        }

        // lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./vendor/nghttp2/lib/includes");
        step.linkLibrary(lib);
    }

    fn buildLinkCurl(self: *Self, step: *LibExeObjStep) void {
        if (UsePrebuiltCurl) {
            step.addAssemblyFile("/home/fubar/repos/curl/lib/.libs/libcurl.a");
            return;
        }

        // TODO: Currently seeing BADF panics when doing fs syscalls when building/linking libcurl dynamically.
        // Similar to this issue: https://github.com/ziglang/zig/issues/10375
        // For now, just build a static lib.
        // const lib = self.builder.addSharedLibrary("curl", null, .unversioned);

        const lib = self.builder.addStaticLibrary("curl", null);

        // cpu-machine-OS
        // eg. x86_64-pc-linux-gnu
        const os_flag = std.fmt.allocPrint(self.builder.allocator, "-DOS=\"{s}-pc-{s}-{s}\"", .{
            @tagName(self.target.getCpuArch()),
            @tagName(self.target.getOsTag()),
            @tagName(self.target.getAbi()),
        }) catch unreachable;

        // See config.status or lib/curl_config.h for generated defines from configure.
        const c_flags = &[_][]const u8{
            // Will make sources include curl_config.h in ./lib/curl
            "-DHAVE_CONFIG_H",

            // Indicates that we're building the lib not the tools.
            "-DBUILDING_LIBCURL",

            // Hides libcurl internal symbols (hide all symbols that aren't officially external).
            "-DCURL_HIDDEN_SYMBOLS",

            os_flag,

            // Optimize.
            "-O2",

            "-DCURL_STATICLIB",

            "-pthread",
            "-Wno-system-headers",
            "-Werror-implicit-function-declaration",
            "-fvisibility=hidden",
        };

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
            self.addCSourceFileFmt(lib, "./vendor/curl/lib/{s}", .{file}, c_flags);
        }

        // lib.disable_sanitize_c = true;

        lib.linkLibC();
        lib.addIncludeDir("./vendor/curl/include");
        lib.addIncludeDir("./vendor/curl/lib");
        lib.addIncludeDir("./lib/curl");
        lib.addIncludeDir("./vendor/openssl/include");
        lib.addIncludeDir("./vendor/nghttp2/lib/includes");
        lib.addIncludeDir("./vendor/zlib");
        step.linkLibrary(lib);
    }

    fn addCSourceFileFmt(self: *Self, lib: *LibExeObjStep, comptime format: []const u8, args: anytype, c_flags: []const []const u8) void {
        const path = std.fmt.allocPrint(self.builder.allocator, format, args) catch unreachable;
        lib.addCSourceFile(self.fromRoot(path), c_flags);
    }

    fn buildLinkStbtt(self: *Self, step: *LibExeObjStep) void {
        var lib: *LibExeObjStep = undefined;
        // For windows-gnu adding a shared library would result in an almost empty stbtt.lib file leading to undefined symbols during linking.
        // As a workaround we always static link for windows.
        if (self.mode == .ReleaseSafe or self.static_link or self.target.getOsTag() == .windows) {
            lib = self.builder.addStaticLibrary("stbtt", self.fromRoot("./lib/stbtt/stbtt.zig"));
        } else {
            lib = self.builder.addSharedLibrary("stbtt", null, .unversioned);
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
            lib = self.builder.addSharedLibrary("stbi", null, .unversioned);
        }
        lib.addIncludeDir(self.fromRoot("./vendor/stb"));
        lib.linkLibC();

        const c_flags = [_][]const u8{ "-O3", "-DSTB_IMAGE_WRITE_IMPLEMENTATION" };
        lib.addCSourceFiles(&.{ self.fromRoot("./lib/stbi/stb_image.c"), self.fromRoot("./lib/stbi/stb_image_write.c") }, &c_flags);
        step.linkLibrary(lib);
    }

    fn linkZigV8(self: *Self, step: *LibExeObjStep) void {
        const mode_str: []const u8 = if (self.mode == .Debug) "debug" else "release";
        const path = std.fmt.allocPrint(self.builder.allocator, "lib/zig-v8/v8-out/{s}-{s}/{s}/ninja/obj/zig/libc_v8.a", .{
            @tagName(self.target.getCpuArch()),
            @tagName(self.target.getOsTag()),
            mode_str,
        }) catch unreachable;
        if (self.target.getOsTag() == .linux) {
            step.addAssemblyFile(path);
            step.linkLibCpp();
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
    step.addIncludeDir("./vendor");
}

const openssl_pkg = Pkg{
    .name = "openssl",
    .path = FileSource.relative("./lib/openssl/openssl.zig"),
};

fn addOpenSSL(step: *LibExeObjStep) void {
    step.addPackage(openssl_pkg);
    step.addIncludeDir("./vendor/openssl/include");
}

const h2o_pkg = Pkg{
    .name = "h2o",
    .path = FileSource.relative("./lib/h2o/h2o.zig"),
};

fn addH2O(step: *LibExeObjStep) void {
    var pkg = h2o_pkg;
    pkg.dependencies = &.{uv_pkg, openssl_pkg};
    step.addPackage(pkg);
    step.addIncludeDir("./vendor/h2o/include");
    step.addIncludeDir("./vendor/h2o/deps/picotls/include");
    step.addIncludeDir("./vendor/h2o/deps/quicly/include");
    step.addIncludeDir("./vendor/openssl/include");
}

const uv_pkg = Pkg{
    .name = "uv",
    .path = FileSource.relative("./lib/uv/uv.zig"),
};

fn addUv(step: *LibExeObjStep) void {
    step.addPackage(uv_pkg);
    step.addIncludeDir("./vendor/libuv/include");
}

const curl_pkg = Pkg{
    .name = "curl",
    .path = FileSource.relative("./lib/curl/curl.zig"),
};

fn addCurl(step: *LibExeObjStep) void {
    step.addPackage(curl_pkg);
    step.addIncludeDir("./vendor/curl/include/curl");
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
        // TODO: See what this path returns $(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/OpenGL.framework/Headers
        // https://github.com/ziglang/zig/issues/2208
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
    pkg.dependencies = &.{build_options, curl_pkg, uv_pkg};
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
