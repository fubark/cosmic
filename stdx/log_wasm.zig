const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx.zig");

extern "stdx" fn jsWarn(ptr: [*]const u8, len: usize) void;
extern "stdx" fn jsLog(ptr: [*]const u8, len: usize) void;
extern "stdx" fn jsErr(ptr: [*]const u8, len: usize) void;

const js_buf = stdx.wasm.getJsBuffer();

pub fn scoped(comptime Scope: @Type(.EnumLiteral)) type {
    return struct {

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (builtin.mode == .Debug) {
                const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
                js_buf.output_buf.clearRetainingCapacity();
                std.fmt.format(js_buf.output_writer, "debug" ++ prefix ++ format, args) catch unreachable;
                jsLog(js_buf.output_buf.items.ptr, js_buf.output_buf.items.len);
            }
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            js_buf.output_buf.clearRetainingCapacity();
            std.fmt.format(js_buf.output_writer, prefix ++ format, args) catch unreachable;
            jsLog(js_buf.output_buf.items.ptr, js_buf.output_buf.items.len);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            js_buf.output_buf.clearRetainingCapacity();
            std.fmt.format(js_buf.output_writer, prefix ++ format, args) catch unreachable;
            jsWarn(js_buf.output_buf.items.ptr, js_buf.output_buf.items.len);
        }

        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = if (Scope == .default) ": " else "(" ++ @tagName(Scope) ++ "): ";
            js_buf.output_buf.clearRetainingCapacity();
            std.fmt.format(js_buf.output_writer, prefix ++ format, args) catch unreachable;
            jsErr(js_buf.output_buf.items.ptr, js_buf.output_buf.items.len);
        }
    };
}