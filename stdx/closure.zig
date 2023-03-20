const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.closure);

pub fn Closure(comptime Capture: type, comptime Fn: type) type {
    stdx.meta.assertFunctionType(Fn);

    const NewFn = stdx.meta.FnWithPrefixParam(Fn, Capture);

    // The compiler crashes when a created @Type is not used. Declaring a dummy var somehow makes the compiler aware of it.
    var dummy: stdx.meta.FnParamsTuple(Fn) = undefined;
    _ = dummy;
    return struct {
        const Self = @This();

        capture: *Capture,
        user_fn: *const NewFn,

        pub fn init(alloc: std.mem.Allocator, capture: Capture, user_fn: *const NewFn) Self {
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

    const Params = stdx.meta.FnParamsTuple(Fn);
    const Return = stdx.meta.FnReturn(Fn);

    // The compiler crashes when a created @Type is not used. Declaring a dummy var somehow makes the compiler aware of it.
    var dummy: stdx.meta.FnParamsTuple(Fn) = undefined;
    _ = dummy;
    return struct {
        capturePtr: *anyopaque,
        /// Also useful for equality comparison.
        userFnPtr: *const anyopaque,
        vtable: *const VTable,

        const VTable = struct {
            call: *const fn (capturePtr: *anyopaque, userFnPtr: *const anyopaque, args: Params) Return,
            deinit: *const fn (capturePtr: *anyopaque, std.mem.Allocator) void,
        };

        const ClosureIfaceT = @This();

        pub fn init(closure: anytype) ClosureIfaceT {
            const CapturePtr = @TypeOf(closure.capture);
            const UserFn = @TypeOf(closure.user_fn);

            const gen = struct {
                fn call(capturePtr: *anyopaque, userFnPtr: *const anyopaque, args: Params) Return {
                    const userFn = stdx.ptrAlignCast(UserFn, userFnPtr);
                    if (@sizeOf(CapturePtr) == 0) {
                        // *void
                        return @call(.auto, userFn, .{{}} ++ args);
                    } else {
                        const captured = stdx.ptrCastAlign(CapturePtr, capturePtr);
                        return @call(.auto, userFn, .{captured.*} ++ args);
                    }
                }
                fn deinit(capturePtr: *anyopaque, alloc: std.mem.Allocator) void {
                    if (@sizeOf(CapturePtr) > 0) {
                        const captured = stdx.ptrCastAlign(CapturePtr, capturePtr);
                        // not *void
                        alloc.destroy(captured);
                    }
                }
            };
            const vtable = VTable{
                .call = gen.call,
                .deinit = gen.deinit,
            };
            return ClosureIfaceT{
                // Check for *void.
                .capturePtr = if (@sizeOf(CapturePtr) == 0) undefined else @ptrCast(*anyopaque, closure.capture),
                .userFnPtr = closure.user_fn,
                .vtable = &vtable,
            };
        }

        pub fn call(self: ClosureIfaceT, args: Params) Return {
            return self.vtable.call(self.capturePtr, self.userFnPtr, args);
        }

        pub fn deinit(self: ClosureIfaceT, alloc: std.mem.Allocator) void {
            self.vtable.deinit(self.capturePtr, alloc);
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
                        const capture = stdx.ptrCastAlign(CapturePtr, ptr);
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
                        const capture = stdx.ptrCastAlign(CapturePtr, ptr);
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
