const stdx = @import("stdx.zig");
const t = stdx.testing;
const Closure = stdx.Closure;
const ClosureIface = stdx.ClosureIface;
const ClosureSimple = stdx.ClosureSimple;
const ClosureSimpleIface = stdx.ClosureSimpleIface;

/// An interface for a free function or a closure.
pub fn Function(comptime Fn: type) type {
    stdx.meta.assertFunctionType(Fn);

    // The compiler crashes when a created @Type is not used. Declaring a dummy var somehow makes the compiler aware of it.
    var dummy: stdx.meta.FnParamsTuple(Fn) = undefined;
    _ = dummy;
    return struct {
        const Self = @This();

        ctx: *anyopaque,
        call_fn: fn (*const anyopaque, *anyopaque, stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn),

        // For closures.
        user_fn: *const anyopaque,

        pub fn initClosure(closure: anytype) Self {
            return initClosureIface(closure.iface());
        }

        pub fn initClosureIface(iface: ClosureIface(Fn)) Self {
            return .{
                .ctx = iface.capture_ptr,
                .call_fn = iface.call_fn,
                .user_fn = iface.user_fn,
            };
        }

        pub fn initContext(ctx_ptr: anytype, comptime func: anytype) Self {
            const ContextPtr = @TypeOf(ctx_ptr);
            stdx.meta.assertPointerType(ContextPtr);
            const gen = struct {
                fn call(_: *const anyopaque, ptr: *anyopaque, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
                    const ctx = stdx.mem.ptrCastAlign(ContextPtr, ptr);
                    return @call(.{}, func, .{ctx} ++ args);
                }
            };
            return .{
                .ctx = ctx_ptr,
                .call_fn = gen.call,
                .user_fn = func,
            };
        }

        pub fn init(comptime func: anytype) Self {
            const gen = struct {
                fn call(_: *const anyopaque, _: *anyopaque, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
                    return @call(.{}, func, args);
                }
            };
            return .{
                .ctx = undefined,
                .call_fn = gen.call,
                .user_fn = func,
            };
        }

        pub fn call(self: Self, args: stdx.meta.FnParamsTuple(Fn)) stdx.meta.FnReturn(Fn) {
            return self.call_fn(self.user_fn, self.ctx, args);
        }
    };
}

test "Function" {
    var foo: u32 = 123;
    const S = struct {
        fn bar(foo_: *u32, num1: u32, num2: u32) u32 {
            return foo_.* + num1 + num2;
        }
    };
    const func = Function(fn (u32, u32) u32).initContext(&foo, S.bar);
    const res = func.call(.{ 1, 2 });
    try t.eq(res, 126);

    const c = Closure(*u32, fn (u32, u32) u32).init(t.alloc, &foo, S.bar);
    defer c.deinit(t.alloc);
    const fc1 = Function(fn (u32, u32) u32).initClosure(c);
    try t.eq(fc1.call(.{ 1, 2 }), 126);
    const fc2 = Function(fn (u32, u32) u32).initClosureIface(c.iface());
    try t.eq(fc2.call(.{ 1, 2 }), 126);
}

/// Prefer Function, keeping this in case using the FnParamsTuple method breaks.
pub fn FunctionSimple(comptime Param: type) type {
    return struct {
        const Self = @This();

        ctx: *anyopaque,
        call_fn: fn (*const anyopaque, *anyopaque, Param) void,

        // For closures.
        user_fn: *const anyopaque,

        pub fn initClosure(closure: anytype) Self {
            return initClosureIface(closure.iface());
        }

        pub fn initClosureIface(iface: ClosureSimpleIface(Param)) Self {
            return .{
                .ctx = iface.capture_ptr,
                .call_fn = iface.call_fn,
                .user_fn = iface.user_fn,
            };
        }

        pub fn initContext(ctx_ptr: anytype, comptime func: anytype) Self {
            const ContextPtr = @TypeOf(ctx_ptr);
            stdx.meta.assertPointerType(ContextPtr);
            const gen = struct {
                fn call(_: *const anyopaque, ptr: *anyopaque, arg: Param) void {
                    const ctx = stdx.mem.ptrCastAlign(ContextPtr, ptr);
                    func(ctx, arg);
                }
            };
            return .{
                .ctx = ctx_ptr,
                .call_fn = gen.call,
                .user_fn = func,
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
                .user_fn = func,
            };
        }

        pub fn call(self: Self, arg: Param) void {
            self.call_fn(self.user_fn, self.ctx, arg);
        }
    };
}

test "FunctionSimple" {
    const S = struct {
        fn inc(res: *u32) void {
            res.* += 1;
        }
        fn closureInc(ctx: u32, res: *u32) void {
            res.* += ctx;
        }
    };
    const f = FunctionSimple(*u32).init(S.inc);
    var res: u32 = 10;
    f.call(&res);
    try t.eq(res, 11);

    const c = ClosureSimple(u32, *u32).init(t.alloc, 20, S.closureInc);
    defer c.deinit(t.alloc);
    const fc1 = FunctionSimple(*u32).initClosure(c);
    fc1.call(&res);
    try t.eq(res, 31);
    const fc2 = FunctionSimple(*u32).initClosureIface(c.iface());
    fc2.call(&res);
    try t.eq(res, 51);
}