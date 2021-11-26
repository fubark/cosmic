const std = @import("std");
const builtin = @import("builtin");

extern fn jsWarn(ptr: [*]const u8, len: usize) void;
extern fn jsLog(ptr: [*]const u8, len: usize) void;
extern fn jsErr(ptr: [*]const u8, len: usize) void;

var buffer: *std.ArrayList(u8) = undefined;
var buffer_writer: std.ArrayList(u8).Writer = undefined;

pub fn setBuffer(_buffer: *std.ArrayList(u8)) void {
    buffer = _buffer;
    buffer_writer = buffer.writer();
}

pub fn scoped(comptime Scope: @Type(.EnumLiteral)) type {
    return struct {

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (builtin.mode == .Debug) {
                const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
                buffer.shrinkRetainingCapacity(0);
                std.fmt.format(buffer_writer, "debug" ++ prefix ++ format, args) catch unreachable;
                jsLog(buffer.items.ptr, buffer.items.len);
            }
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buffer.shrinkRetainingCapacity(0);
            std.fmt.format(buffer_writer, prefix ++ format, args) catch unreachable;
            jsLog(buffer.items.ptr, buffer.items.len);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buffer.shrinkRetainingCapacity(0);
            std.fmt.format(buffer_writer, prefix ++ format, args) catch unreachable;
            jsWarn(buffer.items.ptr, buffer.items.len);
        }

        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            buffer.shrinkRetainingCapacity(0);
            std.fmt.format(buffer_writer, prefix ++ format, args) catch unreachable;
            jsErr(buffer.items.ptr, buffer.items.len);
        }
    };
}