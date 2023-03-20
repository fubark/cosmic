const std = @import("std");

const stdx = @import("../stdx/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "parser",
    .path = .{ .path = thisDir() ++ "/parser.zig" },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    new_pkg.dependencies = &.{stdx.pkg};
    step.addPackage(new_pkg);
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}