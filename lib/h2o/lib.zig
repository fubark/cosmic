const std = @import("std");
const builtin = @import("builtin");

const uv = @import("../uv/lib.zig");
const ssl = @import("../openssl/lib.zig");

const Options = struct {
    openssl_includes: []const []const u8,
    libuv_includes: []const []const u8,
    zlib_includes: []const []const u8,
};

pub const pkg = std.build.Pkg{
    .name = "h2o",
    .source = .{ .path = srcPath() ++ "/h2o.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    new_pkg.dependencies = &.{ uv.pkg, ssl.pkg };
    step.addPackage(new_pkg);
    step.addIncludeDir(srcPath() ++ "/");
    step.addIncludeDir(srcPath() ++ "/vendor/include");
    step.addIncludeDir(srcPath() ++ "/vendor/deps/picotls/include");
    step.addIncludeDir(srcPath() ++ "/vendor/deps/quicly/include");
    step.addIncludeDir(srcPath() ++ "/../openssl/vendor/include");
    if (step.target.getOsTag() == .windows) {
        step.addIncludeDir(srcPath() ++ "/../mingw/win_posix/include");
        step.addIncludeDir(srcPath() ++ "/../mingw/winpthreads/include");
    }
}

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    opts: Options,
) !*std.build.LibExeObjStep {

    const lib = b.addStaticLibrary("h2o", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    // lib.c_std = .C99;

    const alloc = b.allocator;

    // Unused defines:
    // -DH2O_ROOT="/usr/local" -DH2O_CONFIG_PATH="/usr/local/etc/h2o.conf" -DH2O_HAS_PTHREAD_SETAFFINITY_NP 
    var c_flags = std.ArrayList([]const u8).init(alloc);

    // Move args into response file to avoid cli limit.
    try c_flags.appendSlice(&.{
        "@lib/h2o/cflags",
    });
    if (target.getOsTag() == .linux) {
        try c_flags.appendSlice(&.{
            "-D_GNU_SOURCE", // This lets it find in6_pktinfo for some reason.
        });
    } else if (target.getOsTag() == .windows) {
        try c_flags.appendSlice(&.{
            "-D_WINDOWS=1",
            // Need this when using C99.
            "-D_POSIX_C_SOURCE=200809L",
            "-D_POSIX",
        });
    }

    var c_files = std.ArrayList([]const u8).init(alloc);
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
        const path = b.fmt("{s}/vendor/{s}", .{ srcPath(), file });
        lib.addCSourceFile(path, c_flags.items);
    }

    lib.addCSourceFile(fromRoot(b, "utils.c"), c_flags.items);

    // picohttpparser has intentional UB code in
    // findchar_fast when SSE4_2 is enabled: _mm_loadu_si128 can be given ranges pointer with less than 16 bytes.
    // Can't seem to turn off sanitize for just the one source file. Tried to separate picohttpparser into it's own lib too.
    // For now, disable sanitize c for entire h2o lib.
    lib.disable_sanitize_c = true;

    if (builtin.os.tag == .macos and target.getOsTag() == .macos) {
        if (target.isNativeOs()) {
            // Force using native headers or it won't find netinet/udp.h
            lib.linkFramework("CoreServices");
        } else {
            lib.addSystemIncludeDir("/usr/include");
        }
    } 

    lib.linkLibC();

    // Load user_config.h here. include/h2o.h was patched to include user_config.h
    lib.addIncludeDir(srcPath());

    for (opts.openssl_includes) |path| {
        lib.addIncludeDir(path);
    }
    for (opts.libuv_includes) |path| {
        lib.addIncludeDir(path);
    }
    lib.addIncludeDir(fromRoot(b, "vendor/include"));
    for (opts.zlib_includes) |path| {
        lib.addIncludeDir(path);
    }
    lib.addIncludeDir(fromRoot(b, "vendor/deps/quicly/include"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/picohttpparser"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/picotls/include"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/klib"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/cloexec"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/brotli/c/include"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/yoml"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/hiredis"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/golombset"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/libgkc"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/libyrmcds"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/picotls/deps/cifra/src/ext"));
    lib.addIncludeDir(fromRoot(b, "vendor/deps/picotls/deps/cifra/src"));

    if (target.getOsTag() == .windows and target.getAbi() == .gnu) {
        // Since H2O source relies on posix only, provide an interface to windows API.
        lib.addSystemIncludeDir("./lib/mingw/win_posix/include");
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            lib.addSystemIncludeDir("./lib/mingw/win_posix/include-posix");
        }
        lib.addSystemIncludeDir("./lib/mingw/winpthreads/include");
    } 

    return lib;
}

pub const LinkOptions = struct {
    lib_path: ?[]const u8 = null,
};

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: LinkOptions) void {
    if (opts.lib_path) |path| {
        linkLibPath(step, path);
    } else {
        const b = step.builder;
        const lib = create(b, step.target, step.build_mode, .{
            .openssl_includes = &.{
                srcPath() ++ "/../openssl/vendor/include",
            },
            .libuv_includes = &.{
                srcPath() ++ "/../uv/vendor/include",
            },
            .zlib_includes = &.{
                srcPath() ++ "/../zlib/vendor",
            },
        }) catch unreachable;
        linkLib(step, lib);
    }
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    step.addAssemblyFile(path);
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ srcPath(), rel_path }) catch unreachable;
}