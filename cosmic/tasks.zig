const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const log = std.log.scoped(.tasks);

/// Task that invokes a function with allocated args.
pub fn ClosureTask(comptime func: anytype) type {
    const Fn = @TypeOf(func);
    const Args = std.meta.ArgsTuple(Fn);
    const ArgFields = std.meta.fields(Args);
    const Output = stdx.meta.FunctionReturnType(Fn);
    return struct {
        const Self = @This();

        // Allocator that owns the individual args, not res.
        alloc: std.mem.Allocator,
        args: Args,

        res: Output = undefined,

        pub fn deinit(self: *Self) void {
            inline for (ArgFields) |field| {
                if (field.field_type == []const u8) {
                    self.alloc.free(@field(self.args, field.name));
                }
            }
            deinitResult(self.res);
        }

        pub fn process(self: *Self) !void {
            self.res = @call(.{ .modifier = .always_inline }, func, self.args);
        }
    };
}

// TODO: Should this be the same as js_env.freeNativeValue ?
fn deinitResult(res: anytype) void {
    const Result = @TypeOf(res);
    switch (Result) {
        ds.Box([]const u8) => res.deinit(),
        else => {
            if (@typeInfo(Result) == .Optional) {
                if (res) |_res| {
                    deinitResult(_res);
                }
            }
        },
    }
}

pub const ReadFileTask = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    path: []const u8,

    res: ?[]const u8 = null,

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.path);
        if (self.res) |res| {
            self.alloc.free(res);
        }
    }

    pub fn process(self: *Self) !void {
        self.res = std.fs.cwd().readFileAlloc(self.alloc, self.path, 1e12) catch |err| switch (err) {
            // Whitelist errors to silence.
            error.FileNotFound => null,
            else => unreachable,
        };
    }
};
