const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx.zig");

extern "stdx" fn jsWarn(ptr: [*]const u8, len: usize) void;
pub extern "stdx" fn jsLog(ptr: [*]const u8, len: usize) void;
extern "stdx" fn jsErr(ptr: [*]const u8, len: usize) void;

const DebugLog = builtin.mode == .Debug and true;

/// A seperate buffer is used for logging since it can be cleared after passing to js.
var buf = std.ArrayList(u8).init(stdx.wasm.galloc);

pub fn scoped(comptime Scope: @Type(.EnumLiteral)) type {
    return struct {
        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (DebugLog) {
                const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
                buf.clearRetainingCapacity();
                const writer = buf.writer();
                std.fmt.format(writer, "debug" ++ prefix ++ format, args) catch unreachable;
                jsLog(buf.items.ptr, buf.items.len);
            }
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buf.clearRetainingCapacity();
            const writer = buf.writer();
            std.fmt.format(writer, prefix ++ format, args) catch unreachable;
            jsLog(buf.items.ptr, buf.items.len);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buf.clearRetainingCapacity();
            const writer = buf.writer();
            std.fmt.format(writer, prefix ++ format, args) catch unreachable;
            jsWarn(buf.items.ptr, buf.items.len);
        }

        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buf.clearRetainingCapacity();
            const writer = buf.writer();
            std.fmt.format(writer, prefix ++ format, args) catch unreachable;
            jsErr(buf.items.ptr, buf.items.len);
        }
    };
}
