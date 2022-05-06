const std = @import("std");

const platform = @import("../platform/lib.zig");
const stdx = @import("../stdx/lib.zig");
const graphics = @import("../graphics/lib.zig");

const sdl = @import("../lib/sdl/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "ui",
    .path = .{ .path = srcPath() ++ "/ui.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;

    var platform_pkg = platform.pkg;
    platform_pkg.dependencies = &.{ sdl.pkg, stdx.pkg };

    new_pkg.dependencies = &.{ stdx.pkg, graphics.pkg, platform_pkg };
    step.addPackage(new_pkg);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}