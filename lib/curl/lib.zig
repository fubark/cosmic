const std = @import("std");
const builtin = @import("builtin");

pub const pkg = std.build.Pkg{
    .name = "curl",
    .path = .{ .path = srcPath() ++ "/curl.zig" },
};

const Options = struct {
    openssl_includes: []const []const u8,
    nghttp2_includes: []const []const u8,
    zlib_includes: []const []const u8,
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.addIncludeDir(srcPath() ++ "/vendor/include/curl");
}

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    opts: Options,
) !*std.build.LibExeObjStep {

    const lib = b.addStaticLibrary("curl", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

    const alloc = b.allocator;

    // See config.status or lib/curl_config.h for generated defines from configure.
    var c_flags = std.ArrayList([]const u8).init(alloc);
    try c_flags.appendSlice(&.{
        // Indicates that we're building the lib not the tools.
        "-DBUILDING_LIBCURL",

        // Hides libcurl internal symbols (hide all symbols that aren't officially external).
        "-DCURL_HIDDEN_SYMBOLS",

        "-DCURL_STATICLIB",

        "-DNGHTTP2_STATICLIB=1",

        "-Wno-system-headers",
    });

    if (target.getOsTag() == .linux or target.getOsTag() == .macos or target.getOsTag() == .windows) {
        // Will make sources include curl_config.h in ./lib/curl
        try c_flags.append("-DHAVE_CONFIG_H");
    }

    if (target.getOsTag() == .linux) {
        // cpu-machine-OS
        // eg. x86_64-pc-linux-gnu
        const os_flag = try std.fmt.allocPrint(alloc, "-DOS={s}-pc-{s}-{s}", .{
            @tagName(target.getCpuArch()),
            @tagName(target.getOsTag()),
            @tagName(target.getAbi()),
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
        const path = b.fmt("{s}/vendor/lib/{s}", .{ srcPath(), file });
        lib.addCSourceFile(path, c_flags.items);
    }

    // lib.disable_sanitize_c = true;

    lib.linkLibC();

    if (target.getOsTag() == .linux) {
        lib.addIncludeDir(fromRoot(b, "linux"));
    } else if (target.getOsTag() == .macos) {
        lib.addIncludeDir(fromRoot(b, "macos"));
    } else if (target.getOsTag() == .windows) {
        lib.addIncludeDir(fromRoot(b, "windows"));
    }

    lib.addIncludeDir(fromRoot(b, "vendor/include"));
    lib.addIncludeDir(fromRoot(b, "vendor/lib"));

    for (opts.openssl_includes) |path| {
        lib.addIncludeDir(path);
    }
    for (opts.nghttp2_includes) |path| {
        lib.addIncludeDir(path);
    }
    for (opts.zlib_includes) |path| {
        lib.addIncludeDir(path);
    }

    if (builtin.os.tag == .macos and target.getOsTag() == .macos) {
        if (!target.isNativeOs()) {
            lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
            lib.addFrameworkDir("/System/Library/Frameworks");
        } 
        lib.linkFramework("SystemConfiguration");
    }

    return lib;
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    linkDeps(step);
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    linkDeps(step);
    step.addAssemblyFile(path);
}

fn linkDeps(step: *std.build.LibExeObjStep) void {
    if (builtin.os.tag == .macos and step.target.isNativeOs()) {
        step.linkFramework("SystemConfiguration");
    } else if (step.target.getOsTag() == .windows and step.target.getAbi() == .gnu) {
        step.linkSystemLibrary("crypt32");
    }
}

fn srcPath() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ srcPath(), rel_path }) catch unreachable;
}