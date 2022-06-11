const std = @import("std");

const curl = @import("../lib/curl/lib.zig");
const uv = @import("../lib/uv/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "stdx",
    .source = .{ .path = srcPath() ++ "/stdx.zig" },
};

pub const Options = struct {
    enable_tracy: bool = false,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const b = step.builder;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", opts.enable_tracy);
    const build_options_pkg = build_options.getPackage("build_options");

    var new_pkg = pkg;
    new_pkg.dependencies = &.{ curl.pkg, uv.pkg, build_options_pkg };
    step.addPackage(new_pkg);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}

