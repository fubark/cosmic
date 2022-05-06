const std = @import("std");

const stdx = @import("../stdx/lib.zig");
const sdl = @import("../lib/sdl/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "platform",
    .path = .{ .path = srcPath() ++ "/platform.zig" },
};

pub const Options = struct {
    add_dep_pkgs: bool = true,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    var new_pkg = pkg;
    new_pkg.dependencies = &.{ sdl.pkg, stdx.pkg };
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        sdl.addPackage(step);
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
