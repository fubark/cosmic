const std = @import("std");

const curl = @import("../lib/curl/lib.zig");
const uv = @import("../lib/uv/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "stdx",
    .source = .{ .path = thisDir() ++ "/stdx.zig" },
};

pub const Options = struct {
    enable_tracy: bool = false,
};

pub fn createModule(b: *std.build.Builder, opts: Options) *std.build.Module {
    const bopts = b.addOptions();
    bopts.addOption(bool, "enable_tracy", opts.enable_tracy);
    const stdx_options = bopts.createModule();

    const mod = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/stdx.zig" },
        .dependencies = &.{
            .{ .name = "stdx_options", .module = stdx_options },
        },
    });
    // curl.pkg, uv.pkg, 
    // step.linkLibC();
    return mod;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse unreachable;
}