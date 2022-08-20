pub const testing = @import("testing.zig");
pub const debug = @import("debug.zig");
pub const ds = @import("ds/ds.zig");
pub const algo = @import("algo/algo.zig");
pub const log = @import("log.zig");
pub const string = @import("string.zig");
pub const mem = @import("mem.zig");
pub const meta = @import("meta.zig");
pub const heap = @import("heap.zig");
pub const wasm = @import("wasm.zig");
pub const math = @import("math/math.zig");
pub const time = @import("time.zig");
pub const unicode = @import("unicode.zig");
pub const fs = @import("fs.zig");
pub const http = @import("http.zig");
pub const events = @import("events.zig");
pub const net = @import("net.zig");
pub const cstr = @import("cstr.zig");
pub const textbuf = @import("textbuf/textbuf.zig");

const closure = @import("closure.zig");
pub const Closure = closure.Closure;
pub const ClosureIface = closure.ClosureIface;
pub const ClosureSimple = closure.ClosureSimple;
pub const ClosureSimpleIface = closure.ClosureSimpleIface;
const function = @import("function.zig");
pub const Function = function.Function;
pub const FunctionSimple = function.FunctionSimple;
const callback = @import("callback.zig");
pub const Callback = callback.Callback;
pub const IndexSlice = ds.IndexSlice;

// Common utils.
pub const panic = debug.panic;
pub const panicFmt = debug.panicFmt;

pub inline fn unsupported() noreturn {
    panic("unsupported");
}

pub inline fn fatal() noreturn {
    panic("error");
}