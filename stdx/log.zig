const std = @import("std");
pub const wasm = @import("log_wasm.zig");
const builtin = @import("builtin");

const UseStd = builtin.target.cpu.arch != .wasm32;

pub fn scoped(comptime Scope: @Type(.EnumLiteral)) type {
    return struct {
        pub fn debug(comptime format: []const u8, args: anytype) void {
            if (UseStd) {
                std.log.scoped(Scope).debug(format, args);
            } else {
                wasm.scoped(Scope).debug(format, args);
            }
        }

        pub fn info(comptime format: []const u8, args: anytype) void {
            if (UseStd) {
                std.log.scoped(Scope).info(format, args);
            } else {
                wasm.scoped(Scope).info(format, args);
            }
        }

        pub fn warn(comptime format: []const u8, args: anytype) void {
            if (UseStd) {
                std.log.scoped(Scope).warn(format, args);
            } else {
                wasm.scoped(Scope).warn(format, args);
            }
        }

        pub fn err(comptime format: []const u8, args: anytype) void {
            if (UseStd) {
                std.log.scoped(Scope).err(format, args);
            } else {
                wasm.scoped(Scope).err(format, args);
            }
        }
    };
}

const default = if (UseStd) std.log.default else wasm.scoped(.default);

pub fn info(comptime format: []const u8, args: anytype) void {
    default.info(format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
    default.err(format, args);
}
