const std = @import("std");

const platform = @import("../platform/lib.zig");
const stdx = @import("../stdx/lib.zig");
const graphics = @import("../graphics/lib.zig");

const sdl = @import("../lib/sdl/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "ui",
    .path = .{ .path = srcPath() ++ "/ui.zig" },
};

pub const Options = struct {
    add_dep_pkgs: bool = true,
};

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    var new_pkg = pkg;

    var platform_pkg = platform.pkg;
    platform_pkg.dependencies = &.{ sdl.pkg, stdx.pkg };

    new_pkg.dependencies = &.{ stdx.pkg, graphics.pkg, platform_pkg };
    step.addPackage(new_pkg);

    if (opts.add_dep_pkgs) {
        graphics.addPackage(step, .{
            .add_dep_pkgs = opts.add_dep_pkgs,
        });
    }
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    _ = opts;
    graphics.buildAndLink(step, .{});
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}