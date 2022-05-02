const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.closure);

pub fn Closure(comptime Capture: type, comptime Param: type) type {
    if (@sizeOf(Capture) == 0) {
        @compileError("Captured type has no size: " ++ @typeName(Capture));
    }
    return struct {
        const Self = @This();

        capture: *Capture,
        user_fn: UserClosureFn(Capture, Param),

        pub fn init(alloc: std.mem.Allocator, capture: Capture, user_fn: UserClosureFn(Capture, Param)) Self {
            const dupe = alloc.create(Capture) catch unreachable;
            dupe.* = capture;
            return .{
                .capture = dupe,
                .user_fn = user_fn,
            };
        }

        pub fn iface(self: Self) ClosureIface(Param) {
            return ClosureIface(Param).init(self);
        }

        pub fn call(self: *Self, arg: Param) void {
            if (Param == void) {
                self.user_fn(self.capture.*);
            } else {
                self.user_fn(self.capture.*, arg);
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

        capture_ptr: *anyopaque,
        call_fn: fn (*const anyopaque, *anyopaque, Param) void,
        deinit_fn: fn (std.mem.Allocator, *anyopaque) void,

        // Also useful for equality comparison.
        user_fn: *const anyopaque,

        pub fn init(closure: anytype) Self {
            const CapturePtr = @TypeOf(closure.capture);
            const UserFn = @TypeOf(closure.user_fn);
            const gen = struct {
                fn call(user_fn_ptr: *const anyopaque, ptr: *anyopaque, arg: Param) void {
                    const user_fn = @ptrCast(UserFn, user_fn_ptr);
                    const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                    if (Param == void) {
                        user_fn(capture.*);
                    } else {
                        user_fn(capture.*, arg);
                    }
                }
                fn deinit(alloc: std.mem.Allocator, ptr: *anyopaque) void {
                    const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                    alloc.destroy(capture);
                }
            };
            return .{
                .capture_ptr = @ptrCast(*anyopaque, closure.capture),
                .user_fn = closure.user_fn,
                .call_fn = gen.call,
                .deinit_fn = gen.deinit,
            };
        }

        pub fn call(self: Self, arg: Param) void {
            self.call_fn(self.user_fn, self.capture_ptr, arg);
        }

        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.deinit_fn(alloc, self.capture_ptr);
        }
    };
}

pub fn UserClosureFn(comptime Capture: type, comptime Param: type) type {
    return if (Param == void) fn (Capture) void else fn (Capture, Param) void;
}

/// An interface for a free function or a closure.
pub fn Function(comptime Param: type) type {
    return struct {
        const Self = @This();

        ctx: *anyopaque,
        call_fn: fn (*const anyopaque, *anyopaque, Param) void,

        // For closures.
        user_fn: *const anyopaque,

        pub fn initClosure(closure: anytype) Self {
            return initClosureIface(closure.iface());
        }

        pub fn initClosureIface(iface: ClosureIface(Param)) Self {
            return .{
                .ctx = iface.capture_ptr,
                .call_fn = iface.call_fn,
                .user_fn = iface.user_fn,
            };
        }

        pub fn initContext(ctx_ptr: anytype, comptime func: anytype) Self {
            const ContextPtr = @TypeOf(ctx_ptr);
            if (@typeInfo(ContextPtr) != .Pointer) {
                @compileError("Context must be a pointer.");
            }
            const gen = struct {
                fn call(_: *const anyopaque, ptr: *anyopaque, arg: Param) void {
                    const ctx = stdx.mem.ptrCastAlign(ContextPtr, ptr);
                    func(ctx, arg);
                }
            };
            return .{
                .ctx = ctx_ptr,
                .call_fn = gen.call,
                .user_fn = undefined,
            };
        }

        pub fn init(comptime func: anytype) Self {
            const gen = struct {
                fn call(_: *const anyopaque, _: *anyopaque, arg: Param) void {
                    func(arg);
                }
            };
            return .{
                .ctx = undefined,
                .call_fn = gen.call,
                .user_fn = undefined,
            };
        }

        pub fn call(self: Self, arg: Param) void {
            self.call_fn(self.user_fn, self.ctx, arg);
        }
    };
}

test "Function" {
    const S = struct {
        fn inc(res: *u32) void {
            res.* += 1;
        }
        fn closureInc(ctx: u32, res: *u32) void {
            res.* += ctx;
        }
    };
    const f = Function(*u32).init(S.inc);
    var res: u32 = 10;
    f.call(&res);
    try t.eq(res, 11);

    const c = Closure(u32, *u32).init(t.alloc, 20, S.closureInc);
    defer c.deinit(t.alloc);
    const fc1 = Function(*u32).initClosure(c);
    fc1.call(&res);
    try t.eq(res, 31);
    const fc2 = Function(*u32).initClosureIface(c.iface());
    fc2.call(&res);
    try t.eq(res, 51);
}