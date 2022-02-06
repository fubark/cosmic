const std = @import("std");
const stdx = @import("stdx");

pub fn Closure(comptime Capture: type, comptime Param: type) type {
    return struct {
        const Self = @This();

        user_fn: UserClosureFn(Capture, Param),
        capture: *Capture,

        pub fn init(alloc: std.mem.Allocator, capture: Capture, user_fn: UserClosureFn(Capture, Param)) Self {
            const dupe = alloc.create(Capture) catch unreachable;
            dupe.* = capture;
            return .{
                .user_fn = user_fn,
                .capture = dupe,
            };
        }

        /// The iface points to the Closure in memory.
        pub fn iface(self: *Self) ClosureIface(Param) {
            return ClosureIface(Param).init(self);
        }

        pub fn call(self: *Self, arg: Param) void {
            if (Param == void) {
                self.user_fn(self.capture);
            } else {
                self.user_fn(self.capture, arg);
            }
        }

        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            alloc.destroy(self.capture);
        }
    };
}

pub fn ClosureIface(comptime Param: type) type {
    return struct {
        const Self = @This();

        capture: *anyopaque,
        call_fn: fn (*anyopaque, Param) void,

        // Used for comparing two ifaces.
        user_fn: *anyopaque,

        pub fn init(closure: anytype) Self {
            const CapturePtr = @TypeOf(closure.capture);
            const gen = struct {
                fn call(ptr: *anyopaque, arg: Param) void {
                    const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                    closure.user_fn(capture, arg);
                }
            };
            return .{
                .capture = closure.capture,
                .call_fn = gen.call,
                .user_fn = closure.user_fn,
            };
        }

        pub fn call(self: Self, arg: Param) void {
            self.call_fn(self, arg);
        }
    };
}

pub fn UserClosureFn(comptime Capture: type, comptime Param: type) type {
    return if (Param == void) fn (Capture) void else fn (Capture, Param) void;
}