const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");

const runtime = @import("runtime.zig");

/// Wraps environment ops so they can be overridden for testing.
pub const Environment = struct {
    const Self = @This();

    // Overrides the main script source instead of doing a file read. Used for testing.
    main_script_override: ?[]const u8 = null,

    main_script_origin: ?[]const u8 = null,

    // Writes with custom interface instead of stderr. Used for testing.
    err_writer: ?WriterIfaceWrapper = null,

    // Writes with custom interface instead of stdout. Only available with builtin.is_test.
    out_writer: ?WriterIfaceWrapper = null,

    on_main_script_done: ?fn (ctx: ?*anyopaque, rt: *runtime.RuntimeContext) void = null,

    exit_fn: ?fn (code: u8) void = null,

    pub fn exit(self: Self, code: u8) void {
        if (builtin.is_test) {
            if (self.exit_fn) |func| {
                func(code);
                return;
            }
        }
        std.process.exit(code);
    }

    /// Prints to stderr and exits.
    pub fn abortFmt(self: Self, comptime format: []const u8, args: anytype) void {
        self.errorFmt(format, args);
        self.errorFmt("\n", .{});
        self.exit(1);
    }

    /// Prints to stdout.
    pub fn printFmt(self: Self, comptime format: []const u8, args: anytype) void {
        if (builtin.is_test) {
            if (self.out_writer) |writer| {
                std.fmt.format(writer, format, args) catch unreachable;
            }
        }
        const stdout = std.io.getStdOut().writer();
        stdout.print(format, args) catch unreachable;
    }

    /// Prints to stderr.
    pub fn errorFmt(self: Self, comptime format: []const u8, args: anytype) void {
        if (builtin.is_test) {
            if (self.err_writer) |writer| {
                std.fmt.format(writer, format, args) catch unreachable;
            }
        }
        const stderr = std.io.getStdErr().writer();
        stderr.print(format, args) catch unreachable;
    }
};

const WriterIfaceWrapper = std.io.Writer(WriterIface, anyerror, WriterIface.write);

pub const WriterIface = struct {
    const Self = @This();

    ptr: *anyopaque,
    write_inner: fn(*anyopaque, []const u8) anyerror!usize,

    pub fn init(writer_ptr: anytype) WriterIfaceWrapper {
        const Ptr = @TypeOf(writer_ptr);
        const Gen = struct {
            fn write_(ptr_: *anyopaque, data: []const u8) anyerror!usize {
                const self = stdx.mem.ptrCastAlign(Ptr, ptr_);
                return self.write(data);
            }
        };
        return .{
            .context = .{
                .ptr = writer_ptr,
                .write_inner = Gen.write_,
            },
        };
    }

    fn write(self: Self, data: []const u8) anyerror!usize {
        return try self.write_inner(self.ptr, data);
    }
};