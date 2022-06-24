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

pub fn getPackage(b: *std.build.Builder, opts: Options) std.build.Pkg {
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", opts.enable_tracy);
    const build_options_pkg = build_options.getPackage("build_options");

    var ret = pkg;
    ret.dependencies = b.allocator.dupe(std.build.Pkg, &.{
        curl.pkg, uv.pkg, build_options_pkg,
    }) catch @panic("error");
    return ret;
}

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const final_pkg = getPackage(step.builder, opts);
    step.addPackage(final_pkg);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}

