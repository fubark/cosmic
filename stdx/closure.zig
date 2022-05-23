const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.closure);

pub fn Closure(comptime Capture: type, comptime Fn: type) type {
    stdx.meta.assertFunctionType(Fn);

    // The compiler crashes when a created @Type is not used. Declaring a dummy var somehow makes the compiler aware of it.
    var dummy: stdx.meta.FnParamsTuple(Fn) = undefined;
    _ = dummy;
    return struct {
        const Self = @This();

        capture: *Capture,
        user_fn: stdx.meta.FnWithPrefixParam(Fn, Capture),

        pub fn init(alloc: std.mem.Allocator, capture: Capture, user_fn: stdx.meta.FnWithPrefixParam(Fn, Capture)) Self {
            if (@sizeOf(Capture) == 0) {
                return .{
                    .capture = undefined,
                    .user_fn = user_fn,
                };
            } else {
                const dupe = alloc.create(Capture) catch unreachable;
                dupe.* = capture;
                return .{
                    .capture = dupe,
                    .user_fn = user_fn,
                };
            }
        }

        pub fn iface(self: Self) ClosureIface(Fn) {
            return ClosureIface(Fn).init(self);
        }

        pub fn call(self: *Self, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
            if (@sizeOf(Capture) == 0) {
                // *void
                return @call(.{}, self.user_fn, .{{}} ++ args);
            } else {
                return @call(.{}, self.user_fn, .{self.capture.*} ++ args);
            }
        }

        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            if (@sizeOf(Capture) > 0) {
                alloc.destroy(self.capture);
            }
        }
    };
}

test "Closure" {
    // No params.
    const S = struct {
        fn foo(ctx: u32) void {
            _ = ctx;
        }
    };
    var c = Closure(u32, fn () void).init(t.alloc, 20, S.foo);
    defer c.deinit(t.alloc);
    c.call(.{});
}

pub fn ClosureIface(comptime Fn: type) type {
    stdx.meta.assertFunctionType(Fn);

    // The compiler crashes when a created @Type is not used. Declaring a dummy var somehow makes the compiler aware of it.
    var dummy: stdx.meta.FnParamsTuple(Fn) = undefined;
    _ = dummy;
    return struct {
        const Self = @This();

        capture_ptr: *anyopaque,
        call_fn: fn (user_fn: *const anyopaque, capture: *anyopaque, stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn),
        deinit_fn: fn (std.mem.Allocator, *anyopaque) void,

        // Also useful for equality comparison.
        user_fn: *const anyopaque,

        pub fn init(closure: anytype) Self {
            const CapturePtr = @TypeOf(closure.capture);
            const UserFn = @TypeOf(closure.user_fn);
            const gen = struct {
                fn call(user_fn_ptr: *const anyopaque, ptr: *anyopaque, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
                    const user_fn = @ptrCast(UserFn, user_fn_ptr);
                    if (@sizeOf(CapturePtr) == 0) {
                        // *void
                        return @call(.{}, user_fn, .{{}} ++ args);
                    } else {
                        const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                        return @call(.{}, user_fn, .{capture.*} ++ args);
                    }
                }
                fn deinit(alloc: std.mem.Allocator, ptr: *anyopaque) void {
                    if (@sizeOf(CapturePtr) > 0) {
                        // not *void
                        const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                        alloc.destroy(capture);
                    }
                }
            };
            return .{
                // Check for *void.
                .capture_ptr = if (@sizeOf(CapturePtr) == 0) undefined else @ptrCast(*anyopaque, closure.capture),
                .user_fn = closure.user_fn,
                .call_fn = gen.call,
                .deinit_fn = gen.deinit,
            };
        }

        pub fn call(self: Self, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
            self.call_fn(self.user_fn, self.capture_ptr, args);
        }

        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            self.deinit_fn(alloc, self.capture_ptr);
        }
    };
}

test "ClosureIface" {
    // No params.
    const S = struct {
        fn foo(ctx: u32) void {
            _ = ctx;
        }
    };
    var c = Closure(u32, fn () void).init(t.alloc, 20, S.foo).iface();
    defer c.deinit(t.alloc);
    c.call(.{});
}

pub fn UserClosureFn(comptime Capture: type, comptime Param: type) type {
    return if (Param == void) fn (Capture) void else fn (Capture, Param) void;
}

/// Prefer Closure, keeping this in case using the FnParamsTuple method breaks.
pub fn ClosureSimple(comptime Capture: type, comptime Param: type) type {
    return struct {
        const Self = @This();

        capture: *Capture,
        user_fn: UserClosureFn(Capture, Param),

        pub fn init(alloc: std.mem.Allocator, capture: Capture, user_fn: UserClosureFn(Capture, Param)) Self {
            if (@sizeOf(Capture) == 0) {
                return .{
                    .capture = undefined,
                    .user_fn = user_fn,
                };
            } else {
                const dupe = alloc.create(Capture) catch unreachable;
                dupe.* = capture;
                return .{
                    .capture = dupe,
                    .user_fn = user_fn,
                };
            }
        }

        pub fn iface(self: Self) ClosureSimpleIface(Param) {
            return ClosureSimpleIface(Param).init(self);
        }

        pub fn call(self: *Self, arg: Param) void {
            if (@sizeOf(Capture) == 0) {
                if (Param == void) {
                    self.user_fn({});
                } else {
                    self.user_fn({}, arg);
                }
            } else {
                if (Param == void) {
                    self.user_fn(self.capture.*);
                } else {
                    self.user_fn(self.capture.*, arg);
                }
            }
        }

        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            if (@sizeOf(Capture) > 0) {
                alloc.destroy(self.capture);
            }
        }
    };
}


/// Prefer ClosureIface, keeping this in case using the FnParamsTuple method breaks.
pub fn ClosureSimpleIface(comptime Param: type) type {
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
                    if (@sizeOf(CapturePtr) == 0) {
                        // *void
                        if (Param == void) {
                            user_fn({});
                        } else {
                            user_fn({}, arg);
                        }
                    } else {
                        const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                        if (Param == void) {
                            user_fn(capture.*);
                        } else {
                            user_fn(capture.*, arg);
                        }
                    }
                }
                fn deinit(alloc: std.mem.Allocator, ptr: *anyopaque) void {
                    if (@sizeOf(CapturePtr) > 0) {
                        // not *void
                        const capture = stdx.mem.ptrCastAlign(CapturePtr, ptr);
                        alloc.destroy(capture);
                    }
                }
            };
            return .{
                // Check for *void.
                .capture_ptr = if (@sizeOf(CapturePtr) == 0) undefined else @ptrCast(*anyopaque, closure.capture),
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
