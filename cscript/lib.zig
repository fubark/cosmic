const std = @import("std");

const stdx = @import("../stdx/lib.zig");
const qjs = @import("../lib/qjs/lib.zig");
const config = @import("config.zig");

pub const pkg = std.build.Pkg{
    .name = "cscript",
    .source = .{ .path = srcPath() ++ "/cscript.zig" },
};

pub const Options = struct {
    add_dep_pkgs: bool = true,
    engine: config.Engine = .vm,
};

pub fn getPackage(b: *std.build.Builder, opts: Options) std.build.Pkg {
    var ret = pkg;
    const build_options = b.addOptions();
    build_options.addOption(config.Engine, "csEngine", opts.engine);

    ret.dependencies = b.allocator.dupe(std.build.Pkg, &.{
        stdx.pkg, qjs.pkg,
        build_options.getPackage("build_options"),
    }) catch @panic("error");
    return ret;
}

pub fn addPackage(step: *std.build.LibExeObjStep, opts: Options) void {
    const gen_pkg = getPackage(step.builder, opts);
    step.addPackage(gen_pkg);
    if (opts.add_dep_pkgs) {
        stdx.addPackage(step, .{});
        qjs.addPackage(step);
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
