const std = @import("std");

const stdx = @import("../../stdx/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "lyon",
    .source = .{ .path = srcPath() ++ "/lyon.zig" },
};

pub const dummy_pkg = std.build.Pkg{
    .name = "lyon",
    .source = .{ .path = srcPath() ++ "/lyon_dummy.zig" },
    .dependencies = &.{ stdx.pkg },
};

pub fn addPackage(step: *std.build.LibExeObjStep, link_lyon: bool) void {
    step.addIncludeDir(srcPath());
    if (link_lyon) {
        step.addPackage(pkg);
    } else {
        step.addPackage(dummy_pkg);
    }
}

pub const BuildStep = struct {
    const Self = @This();

    step: std.build.Step,
    builder: *std.build.Builder,
    target: std.zig.CrossTarget,

    pub fn create(builder: *std.build.Builder, target: std.zig.CrossTarget) *Self {
        const new = builder.allocator.create(Self) catch unreachable;
        new.* = .{
            .step = std.build.Step.init(.custom, builder.fmt("lyon", .{}), builder.allocator, make),
            .builder = builder,
            .target = target,
        };
        return new;
    }

    fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const toml_path = srcPath() ++ "/Cargo.toml";

        if (self.target.getOsTag() == .linux and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/target/release/libclyon.a";
            const to_path = srcPath() ++ "/../extras/prebuilt/linux64/libclyon.a";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
            _ = try self.builder.exec(&.{ "strip", "--strip-debug", to_path });
        } else if (self.target.getOsTag() == .windows and self.target.getCpuArch() == .x86_64 and self.target.getAbi() == .gnu) {
            var env_map = try self.builder.allocator.create(std.process.EnvMap);
            env_map.* = try std.process.getEnvMap(self.builder.allocator);
            // Attempted to use zig cc like: https://github.com/ziglang/zig/issues/10336
            // But ran into issues linking with -lgcc_eh
            // try env_map.put("RUSTFLAGS", "-C linker=/Users/fubar/dev/cosmic/zig-cc");
            try env_map.put("RUSTFLAGS", "-C linker=/usr/local/Cellar/mingw-w64/9.0.0_2/bin/x86_64-w64-mingw32-gcc");
            try self.builder.spawnChildEnvMap(null, env_map, &.{
                "cargo", "build", "--target=x86_64-pc-windows-gnu", "--release", "--manifest-path", toml_path,
            });
            const out_file = srcPath() ++ "/target/x86_64-pc-windows-gnu/release/libclyon.a";
            const to_path = srcPath() ++ "/../extras/prebuilt/win64/clyon.lib";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .x86_64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=x86_64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/target/x86_64-apple-darwin/release/libclyon.a";
            const to_path = srcPath() ++ "/../extras/prebuilt/mac64/libclyon.a";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
            // This actually corrupts the lib and zig will fail to parse it after linking.
            // _ = try self.builder.exec(&[_][]const u8{ "strip", "-S", to_path });
        } else if (self.target.getOsTag() == .macos and self.target.getCpuArch() == .aarch64) {
            _ = try self.builder.exec(&.{ "cargo", "build", "--target=aarch64-apple-darwin", "--release", "--manifest-path", toml_path });
            const out_file = srcPath() ++ "/target/aarch64-apple-darwin/release/libclyon.a";
            const to_path = srcPath() ++ "/../extras/prebuilt/mac-arm64/libclyon.a";
            _ = try self.builder.exec(&.{ "cp", out_file, to_path });
        }
    }
};


/// Static link prebuilt clyon.
pub fn link(step: *std.build.LibExeObjStep) void {
    const target = step.target;
    if (target.getOsTag() == .linux and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../extras/prebuilt/linux64/libclyon.a");
        // Currently clyon needs unwind.
        step.linkSystemLibrary("unwind");
    } else if (target.getOsTag() == .macos and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../extras/prebuilt/mac64/libclyon.a");
    } else if (target.getOsTag() == .macos and target.getCpuArch() == .aarch64) {
        step.addAssemblyFile(srcPath() ++ "/../extras/prebuilt/mac-arm64/libclyon.a");
    } else if (target.getOsTag() == .windows and target.getCpuArch() == .x86_64) {
        step.addAssemblyFile(srcPath() ++ "/../extras/prebuilt/win64/clyon.lib");
        step.linkSystemLibrary("bcrypt");
        step.linkSystemLibrary("userenv");
    } else {
        step.addLibPath(srcPath() ++ "target/release");
        step.linkSystemLibrary("clyon");
    }
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}