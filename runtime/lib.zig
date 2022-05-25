const std = @import("std");

const stdx = @import("../stdx/lib.zig");
const graphics = @import("../graphics/lib.zig");
const platform = @import("../platform/lib.zig");

const zig_v8_pkg = @import("../build.zig").zig_v8_pkg;
const uv = @import("../lib/uv/lib.zig");
const h2o = @import("../lib/h2o/lib.zig");
const curl = @import("../lib/curl/lib.zig");
const ssl = @import("../lib/openssl/lib.zig");
const maudio = @import("../lib/miniaudio/lib.zig");
const sdl = @import("../lib/sdl/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "runtime",
    .path = .{ .path = srcPath() ++ "/runtime.zig" },
};

pub const Options = struct {
    link_lyon: bool = false,
    link_tess2: bool = false,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;
    _ = opts;
    var new_pkg = pkg;

    const build_options = b.addOptions();
    build_options.addOption(bool, "has_lyon", opts.link_lyon);
    build_options.addOption(bool, "has_tess2", opts.link_tess2);
    const build_options_pkg = build_options.getPackage("build_options");

    var h2o_pkg = h2o.pkg;
    h2o_pkg.dependencies = &.{ uv.pkg, ssl.pkg };

    new_pkg.dependencies = &.{ zig_v8_pkg, stdx.pkg, graphics.pkg, uv.pkg, h2o_pkg, curl.pkg, maudio.pkg, build_options_pkg, ssl.pkg, platform.pkg, sdl.pkg };

    step.addPackage(new_pkg);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}