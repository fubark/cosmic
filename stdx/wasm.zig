const std = @import("std");
const stdx = @import("stdx.zig");
const fatal = stdx.fatal;
const ds = stdx.ds;
const builtin = @import("builtin");

const log = stdx.log.scoped(.wasm);

/// A global buffer for wasm that can be used for:
/// Writing to js: In some cases in order to share the same abstraction as desktop code, a growing buffer is useful without needing an allocator. eg. logging.
/// Reading from js: If js needs to return dynamic data, it would need to write to memory which wasm knows about.
pub var js_buffer: WasmJsBuffer = WasmJsBuffer.init(galloc);

pub const galloc: std.mem.Allocator = std.heap.page_allocator;
var atexits = std.ArrayList(AtExitCallback).init(galloc);

const AtExitCallback = struct {
    func: fn (ctx: ?*anyopaque) void,
    ctx: ?*anyopaque,
};

pub fn init(alloc: std.mem.Allocator) void {
    js_buffer.ensureNotEmpty();
    promises = ds.PooledHandleList(PromiseId, PromiseInternal).init(alloc);
    promise_child_deps = ds.CompactManySinglyLinkedList(PromiseId, PromiseDepId, PromiseId).init(alloc);
}

pub fn deinit() void {
    js_buffer.deinit();
}

pub fn getJsBuffer() *WasmJsBuffer {
    return &js_buffer;
}

// Used to read and write to js.
// We have two buffers since it's common to write output while we are reading input from js.
pub const WasmJsBuffer = struct {
    alloc: std.mem.Allocator,
    /// Used to write data to js.
    output_buf: std.ArrayListUnmanaged(u8),
    /// Used to read data from js.
    input_buf: std.ArrayListUnmanaged(u8),

    pub fn init(alloc: std.mem.Allocator) WasmJsBuffer {
        var new = WasmJsBuffer{
            .alloc = alloc,
            .output_buf = .{},
            .input_buf = .{},
        };
        return new;
    }

    pub fn deinit(self: *WasmJsBuffer) void {
        self.output_buf.deinit(self.alloc);
        self.input_buf.deinit(self.alloc);
    }

    pub fn ensureNotEmpty(self: *WasmJsBuffer) void {
        // Ensure buffers have capacity since we will be returning pointers to js.
        self.output_buf.resize(self.alloc, 1) catch unreachable;
        self.input_buf.resize(self.alloc, 1) catch unreachable;
    }

    pub fn getOutputWriter(self: *WasmJsBuffer) std.ArrayListUnmanaged(u8).Writer {
        return self.output_buf.writer(self.alloc);
    }

    // After wasm execution, write the new input buffer ptr/cap and return the output buffer ptr.
    pub fn writeResult(self: *WasmJsBuffer) [*]const u8 {
        const writer = self.output_buf.writer(self.alloc);
        self.output_buf.shrinkRetainingCapacity(0);
        writer.writeIntLittle(u32, @intCast(u32, @ptrToInt(self.input_buf.items.ptr))) catch unreachable;
        writer.writeIntLittle(u32, @intCast(u32, self.input_buf.capacity)) catch unreachable;
        return self.output_buf.items.ptr;
    }

    pub fn appendInt(self: *WasmJsBuffer, comptime T: type, i: T) void {
        const writer = self.output_buf.writer(self.alloc);
        writer.writeIntLittle(T, i) catch unreachable;
    }

    pub fn writeIntAt(self: *WasmJsBuffer, comptime T: type, idx: usize, i: T) void {
        std.mem.writeIntLittle(T, @ptrCast(*[@sizeOf(T)]u8, &self.output_buf[idx]), i);
    }

    pub fn appendF32(self: *WasmJsBuffer, f: f32) void {
        const writer = self.output_buf.writer(self.alloc);
        writer.writeIntLittle(u32, @bitCast(u32, f)) catch unreachable;
    }

    pub fn writeF32At(self: *WasmJsBuffer, idx: usize, f: f32) void {
        std.mem.writeIntLittle(u32, @ptrCast(*[4]u8, &self.output_buf[idx]), @bitCast(u32, f));
    }

    pub fn readIntAt(self: *WasmJsBuffer, comptime T: type, idx: usize) T {
        return std.mem.readInt(T, @ptrCast(*[@sizeOf(T)]u8, &self.input_buf.items[idx]));
    }

    pub fn readF32At(self: *WasmJsBuffer, idx: usize) f32 {
        return stdx.mem.readFloat32Little(@ptrCast(*[4]u8, &self.input_buf.items[idx]));
    }

    pub fn clearOutputWithSize(self: *WasmJsBuffer, size: usize) void {
        self.output_buf.clearRetainingCapacity();
        self.output_buf.resize(size, self.alloc) catch unreachable;
    }

    pub fn clearOutput(self: *WasmJsBuffer) void {
        self.output_buf.clearRetainingCapacity();
    }

    pub fn getOutputPtr(self: *WasmJsBuffer) [*]const u8 {
        return self.output_buf.items.ptr;
    }
};

pub const PromiseId = u32;
var promises: ds.PooledHandleList(PromiseId, PromiseInternal) = undefined;
const PromiseDepId = u32;
var promise_child_deps: ds.CompactManySinglyLinkedList(PromiseId, PromiseDepId, PromiseId) = undefined;
pub const NullId = ds.CompactNull(u32);

pub fn createPromise(comptime T: type) Promise(T) {
    const id = promises.add(.{
        .num_deps = 0,
        .cur_resolved_deps = 0,
        .child_deps_list_id = null,
        .then_copy_to = null,
        .data_ptr = undefined,
        .auto_free = false,
        .resolved = false,
        .dynamic_size = std.meta.trait.isSlice(T),
    }) catch unreachable;
    return .{
        .id = id,
    };
}

pub fn createAndPromise(ids: []const PromiseId) Promise(void) {
    const id = promises.add(.{
        .num_deps = ids.len,
        .cur_resolved_deps = 0,
        .child_deps_list_id = null,
        .then_copy_to = null,
        .data_ptr = undefined,
        .auto_free = false,
        .resolved = false,
        .dynamic_size = false,
    }) catch unreachable;

    for (ids) |parent_id| {
        const p = promises.getPtrNoCheck(parent_id);
        if (p.child_deps_list_id == null) {
            p.child_deps_list_id = promise_child_deps.addListWithHead(id) catch unreachable;
        } else {
            const last = promise_child_deps.getListHead(p.child_deps_list_id.?).?;
            _ = promise_child_deps.insertAfter(last, id) catch unreachable;
        }
    }

    return .{
        .id = id,
    };
}

export fn wasmEnsureFreeCapacity(size: u32, cur_input_len: u32) [*]const u8 {
    // Must sync over the current input length or a realloc wouldn't know about the new data.
    js_buffer.input_buf.items.len = cur_input_len;
    js_buffer.input_buf.ensureUnusedCapacity(js_buffer.alloc, size) catch unreachable;
    return js_buffer.writeResult();
}

// Called from js to resolve a promise.
export fn wasmResolvePromise(id: PromiseId, data_size: u32) void {
    const p = promises.getPtrNoCheck(id);

    if (p.dynamic_size) {
        // We have to allocate heap memory for variable sized values.
        const copy = stdx.heap.getDefaultAllocator().alloc(u8, data_size) catch unreachable;
        js_buffer.input_buf.resize(js_buffer.alloc, data_size) catch unreachable;
        std.mem.copy(u8, copy, js_buffer.input_buf.items[0..data_size]);
        if (p.then_copy_to) |dst| {
            stdx.mem.ptrCastAlign(*[]u8, dst).* = copy;
        }
    } else {
        if (p.then_copy_to) |dst| {
            const dst_slice = stdx.mem.ptrCastAlign([*]u8, dst)[0..data_size];
            std.mem.copy(u8, dst_slice, js_buffer.input_buf.items[0..data_size]);
        }
    }

    p.resolved = true;

    if (p.child_deps_list_id) |list_id| {
        var cur = promise_child_deps.getListHead(list_id).?;
        while (cur != NullId) {
            const child_id = promise_child_deps.getNoCheck(cur);
            const child_p = promises.getPtrNoCheck(child_id);
            child_p.cur_resolved_deps += 1;
            if (child_p.cur_resolved_deps == child_p.num_deps) {
                child_p.resolved = true;
            }
            cur = promise_child_deps.getNextIdNoCheck(cur);
        }
    }

    if (p.auto_free) {
        promises.remove(id);
    }
}

pub fn resolvePromise(id: PromiseId, value: anytype) void {
    const p = promises.getPtrNoCheck(id);

    if (p.then_copy_to) |dst| {
        stdx.mem.ptrCastAlign(*@TypeOf(value), dst).* = value;
    }

    p.resolved = true;

    if (p.child_deps_list_id) |list_id| {
        var cur = promise_child_deps.getListHead(list_id).?;
        while (cur != NullId) {
            const child_id = promise_child_deps.getNoCheck(cur);
            const child_p = promises.getPtrNoCheck(child_id);
            child_p.cur_resolved_deps += 1;
            if (child_p.cur_resolved_deps == child_p.num_deps) {
                child_p.resolved = true;
            }
            cur = promise_child_deps.getNextIdNoCheck(cur);
        }
    }

    if (p.auto_free) {
        promises.remove(id);
    }
}

pub fn Promise(comptime T: type) type {
    _ = T;
    return struct {
        const Self = @This();

        id: PromiseId,

        pub fn isResolved(self: Self) bool {
            return promises.get(self.id).resolved;
        }

        pub fn thenCopyTo(self: Self, ptr: *T) Self {
            promises.getPtrNoCheck(self.id).then_copy_to = ptr;
            return self;
        }

        pub fn autoFree(self: Self) Self {
            promises.getPtrNoCheck(self.id).auto_free = true;
            return self;
        }
    };
}

const PromiseInternal = struct {
    num_deps: u32,
    cur_resolved_deps: u32,
    child_deps_list_id: ?PromiseDepId,
    then_copy_to: ?*anyopaque,
    data_ptr: ds.SizedPtr,
    auto_free: bool,
    resolved: bool,
    dynamic_size: bool,
};

const usize_len = @sizeOf(usize);

comptime {
    // Conditionally export, or desktop builds will have the wrong malloc.
    if (builtin.target.isWasm()) {
        @export(c_malloc, .{ .name = "malloc", .linkage = .Strong });
        @export(c_free, .{ .name = "free", .linkage = .Strong });
        @export(c_realloc, .{ .name = "realloc", .linkage = .Strong });
        @export(c_fabs, .{ .name = "fabs", .linkage = .Strong });
        @export(c_sqrt, .{ .name = "sqrt", .linkage = .Strong });
        @export(c_ldexp, .{ .name = "ldexp", .linkage = .Strong });
        @export(c_pow, .{ .name = "pow", .linkage = .Strong });
        @export(c_abs, .{ .name = "abs", .linkage = .Strong });
        @export(c_memmove, .{ .name = "memmove", .linkage = .Strong });
        @export(c_memset, .{ .name = "memset", .linkage = .Strong });
        @export(c_memcpy, .{ .name = "memcpy", .linkage = .Strong });
        @export(c_strlen, .{ .name = "strlen", .linkage = .Strong });
        @export(c_strchr, .{ .name = "strchr", .linkage = .Strong });
        @export(c_strncpy, .{ .name = "strncpy", .linkage = .Strong });
        @export(c_atof, .{ .name = "atof", .linkage = .Strong });
        @export(c_atoi, .{ .name = "atoi", .linkage = .Strong });
        @export(c_atoll, .{ .name = "atoll", .linkage = .Strong });
        @export(c_strcmp, .{ .name = "strcmp", .linkage = .Strong });
        @export(c_strncmp, .{ .name = "strncmp", .linkage = .Strong });
        @export(c_strtol, .{ .name = "strtol", .linkage = .Strong });
        @export(c_longjmp, .{ .name = "longjmp", .linkage = .Strong });
        @export(c_setjmp, .{ .name = "setjmp", .linkage = .Strong });
        @export(c_getenv, .{ .name = "getenv", .linkage = .Strong });
        @export(c_strstr, .{ .name = "strstr", .linkage = .Strong });
        @export(c_qsort, .{ .name = "qsort", .linkage = .Strong });
        @export(c_aligned_alloc, .{ .name = "aligned_alloc", .linkage = .Strong });
        @export(c_memcmp, .{ .name = "memcmp", .linkage = .Strong });
        @export(c_vsnprintf, .{ .name = "vsnprintf", .linkage = .Strong });
        @export(c_exit, .{ .name = "exit", .linkage = .Strong });
        @export(panic, .{ .name = "panic", .linkage = .Strong });
        @export(cxa_allocate_exception, .{ .name ="__cxa_allocate_exception", .linkage = .Strong });
        @export(cxa_pure_virtual, .{ .name ="__cxa_pure_virtual", .linkage = .Strong });
        @export(cxa_atexit, .{ .name ="__cxa_atexit", .linkage = .Strong });
        @export(cxa_throw, .{ .name = "__cxa_throw", .linkage = .Strong });
        @export(cxa_guard_acquire, .{ .name = "__cxa_guard_acquire", .linkage = .Strong });
        @export(cxa_guard_release, .{ .name = "__cxa_guard_release", .linkage = .Strong });
        @export(cpp_next_prime, .{ .name = "_ZNSt3__112__next_primeEm", .linkage = .Strong });
        @export(cpp_out_of_range, .{ .name = "_ZNSt12out_of_rangeD1Ev", .linkage = .Strong });
        @export(cpp_bad_array_new_length2, .{ .name = "_ZNSt20bad_array_new_lengthC1Ev", .linkage = .Strong });
        @export(cpp_bad_array_new_length, .{ .name = "_ZNSt20bad_array_new_lengthD1Ev", .linkage = .Strong });
        @export(cpp_basic_string_throw_length_error, .{ .name = "_ZNKSt3__121__basic_string_commonILb1EE20__throw_length_errorEv", .linkage = .Strong });
        @export(cpp_vector_base_throw_length_error, .{ .name = "_ZNKSt3__120__vector_base_commonILb1EE20__throw_length_errorEv", .linkage = .Strong });
        @export(cpp_vector_base_throw_out_of_range_error, .{ .name = "_ZNKSt3__120__vector_base_commonILb1EE20__throw_out_of_rangeEv", .linkage = .Strong });
        @export(cpp_condvar_wait_unique_lock, .{ .name = "_ZN18condition_variable4waitER11unique_lockI5mutexE", .linkage = .Strong });
        @export(cpp_exception, .{ .name = "_ZNSt9exceptionD2Ev", .linkage = .Strong });
        @export(cpp_exception_what, .{ .name = "_ZNKSt9exception4whatEv", .linkage = .Strong });
        @export(cpp_system_category, .{ .name = "_ZNSt3__115system_categoryEv", .linkage = .Strong });
        @export(cpp_system_category_error, .{ .name = "_ZNSt3__112system_errorC1EiRKNS_14error_categoryE", .linkage = .Strong });
        @export(cpp_system_error, .{ .name = "_ZNSt3__112system_errorD1Ev", .linkage = .Strong });
        @export(cpp_operator_delete, .{ .name ="_ZdlPv", .linkage = .Strong });
        @export(cpp_operator_new, .{ .name ="_Znwm", .linkage = .Strong });
        @export(cpp_length_error, .{ .name = "_ZNSt12length_errorD1Ev", .linkage = .Strong });
        @export(cpp_logic_error, .{ .name = "_ZNSt11logic_errorC2EPKc", .linkage = .Strong });
        @export(cpp_operator_new_1, .{ .name = "_ZnwmSt11align_val_t", .linkage = .Strong });
        @export(cpp_operator_delete_1, .{ .name = "_ZdlPvSt11align_val_t", .linkage = .Strong });
        @export(cpp_vfprintf, .{ .name = "vfprintf", .linkage = .Strong });
        @export(cpp_fopen, .{ .name = "fopen", .linkage = .Strong });
        @export(cpp_fseek, .{ .name = "fseek", .linkage = .Strong });
        @export(cpp_ftell, .{ .name = "ftell", .linkage = .Strong });
        @export(cpp_fclose, .{ .name = "fclose", .linkage = .Strong });
        @export(cpp_fread, .{ .name = "fread", .linkage = .Strong });
        @export(cpp_strrchr, .{ .name = "strrchr", .linkage = .Strong });
        @export(cpp_strcat, .{ .name = "strcat", .linkage = .Strong });
        @export(cpp_strcpy, .{ .name = "strcpy", .linkage = .Strong });
        @export(cpp_fwrite, .{ .name = "fwrite", .linkage = .Strong });
    }
}

fn cxa_guard_acquire(guard: *anyopaque) callconv(.C) i32 {
    log.debug("guard_acquire", .{});
    _ = guard;
    return 1;
}

fn cxa_guard_release(guard: *anyopaque) callconv(.C) void {
    log.debug("guard_release", .{});
    _ = guard;
}

fn c_aligned_alloc(alignment: usize, size: usize) callconv(.C) *anyopaque {
    if (alignment <= @sizeOf(*anyopaque)) {
        return c_malloc(size);
    } else {
        const ptr = c_malloc(size + alignment - @sizeOf(*anyopaque));
        const rem = @ptrToInt(ptr) % alignment;
        if (rem == 0) {
            return ptr;
        } else {
            return @intToPtr(*anyopaque, @ptrToInt(ptr) + alignment - rem);
        }
    }
}

/// Since this is often 16 for the new operator in C++, malloc should also mimic that.
const DefaultMallocAlignment = 16;

const PointerSize = @sizeOf(*anyopaque);
const BlocksPerAlignment = DefaultMallocAlignment / PointerSize;

fn c_malloc(size: usize) callconv(.C) *anyopaque {
    // Allocates blocks of PointerSize sized items that fits the header and the user memory using the default alignment.
    const blocks = (1 + (size + DefaultMallocAlignment - 1) / DefaultMallocAlignment) * BlocksPerAlignment;
    const buf = galloc.alignedAlloc(usize, DefaultMallocAlignment, blocks) catch fatal();
    // Header stores the length.
    buf[0] = blocks;
    // Return the user pointer.
    return &buf[BlocksPerAlignment];
}

fn c_realloc(ptr: ?*anyopaque, size: usize) callconv(.C) *anyopaque {
    if (ptr == null) {
        return c_malloc(size);
    }
    // Get current block size and slice.
    const addr = @ptrToInt(ptr.?) - DefaultMallocAlignment;
    const block = @intToPtr([*]usize, addr);
    const len = block[0];
    const slice: []usize = block[0..len];

    // Reallocate.
    const blocks = (1 + (size + DefaultMallocAlignment - 1) / DefaultMallocAlignment) * BlocksPerAlignment;
    const new_slice = galloc.reallocAdvanced(slice, DefaultMallocAlignment, blocks, .exact) catch fatal();
    new_slice[0] = blocks;
    return @ptrCast(*anyopaque, &new_slice[BlocksPerAlignment]);
}

fn cpp_operator_new(size: usize) callconv(.C) ?*anyopaque {
    return c_malloc(size);
}

fn c_free(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) {
        return;
    }
    const addr = @ptrToInt(ptr) - DefaultMallocAlignment;
    const block = @intToPtr([*]const usize, addr);
    const len = block[0];
    galloc.free(block[0..len]);
}

fn cpp_operator_delete(ptr: ?*anyopaque) callconv(.C) void {
    c_free(ptr);
}

fn c_fabs(x: f64) callconv(.C) f64 {
    return @fabs(x);
}

fn c_sqrt(x: f64) callconv(.C) f64 {
    return std.math.sqrt(x);
}

fn c_ldexp(x: f64, n: i32) callconv(.C) f64 {
    return std.math.ldexp(x, n);
}

fn c_pow(x: f64, y: f64) callconv(.C) f64 {
    return std.math.pow(f64, x, y);
}

fn c_abs(x: i32) callconv(.C) i32 {
    return std.math.absInt(x) catch unreachable;
}

fn c_memset(s: ?*anyopaque, val: i32, n: usize) callconv(.C) ?*anyopaque {
    // Some user code may try to write to a bad location in wasm with n=0. Wasm doesn't allow that.
    if (n > 0) {
        const slice = @ptrCast([*]u8, s)[0..n];
        std.mem.set(u8, slice, @intCast(u8, val));
    }
    return s;
}

/// From lib/c.zig
fn c_memmove(dest: ?[*]u8, src: ?[*]const u8, n: usize) callconv(.C) ?[*]u8 {
    @setRuntimeSafety(false);
    if (@ptrToInt(dest) < @ptrToInt(src)) {
        var index: usize = 0;
        while (index != n) : (index += 1) {
            dest.?[index] = src.?[index];
        }
    } else {
        var index = n;
        while (index != 0) {
            index -= 1;
            dest.?[index] = src.?[index];
        }
    }
    return dest;
}

fn c_memcpy(dst: ?*anyopaque, src: ?*anyopaque, n: usize) callconv(.C) ?*anyopaque {
    const dst_slice = @ptrCast([*]u8, dst)[0..n];
    const src_slice = @ptrCast([*]u8, src)[0..n];
    std.mem.copy(u8, dst_slice, src_slice);
    return dst;
}

fn c_strstr(c_haystack: [*:0]const u8, c_needle: [*:0]const u8) callconv(.C) ?[*:0]const u8 {
    const haystack = std.mem.sliceTo(c_haystack, 0);
    const needle = std.mem.sliceTo(c_needle, 0);
    if (std.mem.indexOf(u8, haystack, needle)) |idx| {
        return @ptrCast([*:0]const u8, &c_haystack[idx]);
    } else return null;
}

fn c_strlen(s: [*:0]const u8) callconv(.C) usize {
    return std.mem.sliceTo(s, 0).len;
}

fn c_strchr(s: [*:0]const u8, ch: u8) callconv(.C) ?[*:0]const u8 {
    if (std.mem.indexOfScalar(u8, std.mem.sliceTo(s, 0), ch)) |idx| {
        return @ptrCast([*:0]const u8, &s[idx]);
    } else return null;
}

fn c_atof(s: [*:0]const u8) callconv(.C) f64 {
    return std.fmt.parseFloat(f64, std.mem.sliceTo(s, 0)) catch return 0;
}

fn c_atoi(s: [*:0]const u8) callconv(.C) i32 {
    return std.fmt.parseInt(i32, std.mem.sliceTo(s, 0), 10) catch return 0;
}

fn c_atoll(s: [*:0]const u8) callconv(.C) i64 {
    return std.fmt.parseInt(i64, std.mem.sliceTo(s, 0), 10) catch return 0;
}

/// From lib/c.zig
fn c_memcmp(vl: ?[*]const u8, vr: ?[*]const u8, n: usize) callconv(.C) c_int {
    @setRuntimeSafety(false);
    var index: usize = 0;
    while (index != n) : (index += 1) {
        const compare_val = @bitCast(i8, vl.?[index] -% vr.?[index]);
        if (compare_val != 0) {
            return compare_val;
        }
    }
    return 0;
}

/// Allow C/C++ to trigger panic.
fn panic() callconv(.C) void {
    stdx.panic("error");
}

// Handles next_prime for n [0, 210)
const low_next_primes = [_]u32{
    0,
    2,
    3,
    5,
    7,
    11,
    13,
    17,
    19,
    23,
    29,
    31,
    37,
    41,
    43,
    47,
    53,
    59,
    61,
    67,
    71,
    73,
    79,
    83,
    89,
    97,
    101,
    103,
    107,
    109,
    113,
    127,
    131,
    137,
    139,
    149,
    151,
    157,
    163,
    167,
    173,
    179,
    181,
    191,
    193,
    197,
    199,
    211
};

/// C++ __next_prime
fn cpp_next_prime(n: usize) callconv(.C) usize {
    if (n < low_next_primes.len) {
        return low_next_primes[n];
    } else {
        stdx.panic("next_prime");
    }
}

fn cpp_out_of_range(_: i32) callconv(.C) i32 {
    stdx.panic("out of range");
}

fn cpp_bad_array_new_length2(_: i32) callconv(.C) i32 {
    stdx.panic("bad array new length");
}

fn cpp_bad_array_new_length(_: i32) callconv(.C) i32 {
    stdx.panic("bad array new length");
}

fn cpp_basic_string_throw_length_error(_: i32) callconv(.C) void {
    stdx.panic("throw_length_error");
}

fn cpp_vector_base_throw_length_error(_: i32) callconv(.C) void {
    stdx.panic("throw_length_error");
}

fn cpp_vector_base_throw_out_of_range_error(_: i32) callconv(.C) void {
    stdx.panic("throw_out_of_range");
}

fn cpp_condvar_wait_unique_lock(_: i32, _: i32) callconv(.C) void {
    stdx.panic("condvar wait");
}

fn cpp_exception(_: i32) callconv(.C) i32 {
    stdx.panic("exception");
}

fn cpp_exception_what(_: i32) callconv(.C) i32 {
    stdx.panic("exception what");
}

fn cpp_system_category() callconv(.C) i32 {
    stdx.panic("system category");
}

fn cpp_system_category_error(_: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("system category error");
}

fn cpp_system_error() callconv(.C) i32 {
    stdx.panic("system error");
}

fn cxa_pure_virtual() callconv(.C) void {
    stdx.panic("cxa_pure_virtual");
}

fn cxa_atexit(func: ?*anyopaque, arg: ?*anyopaque, _: ?*anyopaque) callconv(.C) i32 {
    atexits.append(.{
        .func = @ptrCast(fn (?*anyopaque) void, func),
        .ctx = arg,
    }) catch fatal();
    return 0;
}

fn cxa_allocate_exception(_: i32) callconv(.C) i32 {
    stdx.panic("allocate_exception");
}

fn cpp_length_error(_: i32) callconv(.C) i32 {
    stdx.panic("length_error");
}

fn cxa_throw(_: i32, _: i32, _: i32) callconv(.C) void {
    stdx.panic("cxa_throw");
}

fn cpp_logic_error(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("logic_error");
}

fn cpp_operator_new_1(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("new_1");
}

fn cpp_operator_delete_1(_: i32, _: i32) callconv(.C) void {
    stdx.panic("delete_1");
}

pub fn flushAtExits() void {
    while (atexits.popOrNull()) |atexit| {
        atexit.func(atexit.ctx);
    }
    atexits.clearRetainingCapacity();
}

fn c_exit(_: i32) callconv(.C) void {
    flushAtExits();
}

fn c_vsnprintf(_: i32, _: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("vsnprintf");
}

fn cpp_vfprintf(_: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("vfprintf");
}

fn cpp_fopen(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("fopen");
}

fn cpp_fseek(_: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("fseek");
}

fn cpp_ftell(_: i32) callconv(.C) i32 {
    stdx.panic("ftell");
}

fn cpp_fclose(_: i32) callconv(.C) i32 {
    stdx.panic("fclose");
}

fn cpp_fread(_: i32, _: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("fread");
}

fn c_qsort(base: [*]u8, nmemb: usize, size: usize, c_compare: fn (*anyopaque, *anyopaque) callconv(.C) i32) callconv(.C) void {
    const idxes = galloc.alloc(u32, nmemb) catch fatal();
    defer galloc.free(idxes);

    const Context = struct {
        buf: []u8,
        c_compare: fn (*anyopaque, *anyopaque) callconv(.C) i32,
        size: usize,
    };

    const S = struct {
        fn lessThan(ctx: Context, lhs: u32, rhs: u32) bool {
            return ctx.c_compare(&ctx.buf[lhs * ctx.size], &ctx.buf[rhs * ctx.size]) < 0;
        }
    };
    const ctx = Context{
        .size = size,
        .c_compare = c_compare,
        .buf = base[0..nmemb*size],
    };
    for (idxes) |_, i| {
        idxes[i] = i;
    }
    std.sort.sort(u32, idxes, ctx, S.lessThan);

    // Copy to temporary buffer.
    const temp = galloc.alloc(u8, nmemb * size) catch fatal();
    defer galloc.free(temp);
    for (idxes) |idx, i| {
        std.mem.copy(u8, temp[i*size..i*size+size], ctx.buf[idx*size..idx*size+size]);
    }
    std.mem.copy(u8, ctx.buf, temp);
}

fn cpp_strrchr(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("strrchr");
}

/// From lib/c.zig
fn c_strncpy(dest: [*:0]u8, src: [*:0]const u8, n: usize) callconv(.C) [*:0]u8 {
    var i: usize = 0;
    while (i < n and src[i] != 0) : (i += 1) {
        dest[i] = src[i];
    }
    while (i < n) : (i += 1) {
        dest[i] = 0;
    }
    return dest;
}

fn cpp_strcat(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("strcat");
}

fn c_getenv(name: [*:0]const u8) callconv(.C) ?[*:0]const u8 {
    _ = name;
    return null;
}

fn cpp_strncmp(_: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("strncmp");
}

fn c_strtol(s: [*:0]const u8, _: i32, _: i32) callconv(.C) i32 {
    _ = s;
    stdx.panic("strtol");
}

fn cpp_strcpy(_: i32, _: i32) callconv(.C) i32 {
    stdx.panic("strcpy");
}

fn c_strcmp(a: [*:0]const u8, b: [*:0]const u8) callconv(.C) i32 {
    return std.cstr.cmp(a, b);
}

fn c_strncmp(a: [*:0]const u8, b: [*:0]const u8, size: usize) callconv(.C) i32 {
    if (size == 0) return 0;
    var index: usize = 0;
    while (a[index] == b[index] and a[index] != 0) : (index += 1) {
        if (index == size - 1) {
            return 0;
        }
    }
    if (a[index] > b[index]) {
        return 1;
    } else if (a[index] < b[index]) {
        return -1;
    } else {
        return 0;
    }
}

fn c_setjmp(_: i32) callconv(.C) i32 {
    // Stack unwinding is not supported but continue anyway.
    return 0;
}

fn c_longjmp(_: i32, _: i32) callconv(.C) void {
    stdx.panic("longjmp");
}

fn cpp_fwrite(_: i32, _: i32, _: i32, _: i32) callconv(.C) i32 {
    stdx.panic("fwrite");
}