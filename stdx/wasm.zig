const std = @import("std");
const stdx = @import("stdx.zig");
const ds = stdx.ds;
const builtin = @import("builtin");

const log = stdx.log.scoped(.wasm);

/// A global buffer for wasm that can be used for:
/// Writing to js: In some cases in order to share the same abstraction as desktop code, a growing buffer is useful without needing an allocator. eg. logging.
/// Reading from js: If js needs to return dynamic data, it would need to write to memory which wasm knows about.
pub var js_buffer: WasmJsBuffer = undefined;

var galloc: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    galloc = alloc;
    js_buffer.init(alloc);
    promises = ds.CompactUnorderedList(PromiseId, PromiseInternal).init(alloc);
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
    const Self = @This();

    // Used to write data to js.
    output_buf: std.ArrayList(u8),
    output_writer: std.ArrayList(u8).Writer,

    input_buf: std.ArrayList(u8),

    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .output_buf = std.ArrayList(u8).init(alloc),
            .output_writer = undefined,
            .input_buf = std.ArrayList(u8).init(alloc),
        };
        // Ensure buffers have capacity since we will be returning pointers to js.
        self.output_buf.resize(1) catch unreachable;
        self.input_buf.resize(1) catch unreachable;

        // TODO: also get a writer that does appendSliceAssumeCapacity.
        self.output_writer = self.output_buf.writer();
    }

    pub fn deinit(self: Self) void {
        self.output_buf.deinit();
        self.input_buf.deinit();
    }

    // After wasm execution, write the new input buffer ptr/cap and return the output buffer ptr.
    pub fn writeResult(self: *Self) *const u8 {
        self.output_buf.shrinkRetainingCapacity(0);
        self.output_writer.writeIntLittle(u32, @intCast(u32, @ptrToInt(self.input_buf.items.ptr))) catch unreachable;
        self.output_writer.writeIntLittle(u32, @intCast(u32, self.input_buf.capacity)) catch unreachable;
        return &self.output_buf.items[0];
    }

    pub fn appendInt(self: *Self, comptime T: type, i: T) void {
        self.output_writer.writeIntLittle(T, i) catch unreachable;
    }

    pub fn writeIntAt(self: *Self, comptime T: type, idx: usize, i: T) void {
        std.mem.writeIntLittle(T, @ptrCast(*[@sizeOf(T)]u8, &self.output_buf[idx]), i);
    }

    pub fn appendF32(self: *Self, f: f32) void {
        self.output_writer.writeIntLittle(u32, @bitCast(u32, f)) catch unreachable;
    }

    pub fn writeF32At(self: *Self, idx: usize, f: f32) void {
        std.mem.writeIntLittle(u32, @ptrCast(*[4]u8, &self.output_buf[idx]), @bitCast(u32, f));
    }

    pub fn readIntAt(self: *Self, comptime T: type, idx: usize) T {
        return std.mem.readInt(T, @ptrCast(*[@sizeOf(T)]u8, &self.input_buf.items[idx]));
    }

    pub fn readF32At(self: *Self, idx: usize) f32 {
        return stdx.mem.readFloat32Little(@ptrCast(*[4]u8, &self.input_buf.items[idx]));
    }

    pub fn clearOutputWithSize(self: *Self, size: usize) void {
        self.output_buf.clearRetainingCapacity();
        self.output_buf.resize(size) catch unreachable;
    }

    pub fn clearOutput(self: *Self) void {
        self.output_buf.clearRetainingCapacity();
    }

    pub fn getOutputPtr(self: *Self) [*]const u8 {
        return self.output_buf.items.ptr;
    }
};

pub const PromiseId = u32;
var promises: ds.CompactUnorderedList(PromiseId, PromiseInternal) = undefined;
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
        const p = promises.getPtr(parent_id);
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

export fn wasmEnsureInputCapacity(size: u32) *const u8 {
    // Also set length to capacity so we can read the data in bounds.
    js_buffer.input_buf.resize(size) catch unreachable;
    return js_buffer.writeResult();
}

// Called from js to resolve a promise.
export fn wasmResolvePromise(id: PromiseId, data_size: u32) void {
    const p = promises.getPtrNoCheck(id);

    if (p.dynamic_size) {
        // We have to allocate heap memory for variable sized values.
        const copy = stdx.heap.getDefaultAllocator().alloc(u8, data_size) catch unreachable;
        js_buffer.input_buf.resize(data_size) catch unreachable;
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
            promises.getPtr(self.id).then_copy_to = ptr;
            return self;
        }

        pub fn autoFree(self: Self) Self {
            promises.getPtr(self.id).auto_free = true;
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
        @export(malloc, .{ .name = "malloc", .linkage = .Strong });
        @export(free, .{ .name = "free", .linkage = .Strong });
        @export(realloc, .{ .name = "realloc", .linkage = .Strong });
        @export(fabs, .{ .name = "fabs", .linkage = .Strong });
        @export(sqrt, .{ .name = "sqrt", .linkage = .Strong });
        @export(ldexp, .{ .name = "ldexp", .linkage = .Strong });
        @export(pow, .{ .name = "pow", .linkage = .Strong });
        @export(abs, .{ .name = "abs", .linkage = .Strong });
        @export(memset, .{ .name = "memset", .linkage = .Strong });
        @export(memcpy, .{ .name = "memcpy", .linkage = .Strong });
    }
}

/// libc malloc.
fn malloc(size: usize) callconv(.C) *anyopaque {
    // Allocates a block that is a multiple of usize that fits the header and the user allocation.
    const eff_size = 1 + (size + usize_len - 1) / usize_len;
    const block = galloc.alloc(usize, eff_size) catch unreachable;
    // Header stores the length.
    block[0] = eff_size;
    // Return the user allocation.
    return &block[1];
}

/// libc fabs.
fn fabs(x: f64) callconv(.C) f64 {
    return std.math.fabs(x);
}

/// libc free.
fn free(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) {
        return;
    }
    const addr = @ptrToInt(ptr) - usize_len;
    const block = @intToPtr([*]const usize, addr);
    const len = block[0];
    galloc.free(block[0..len]);
}

/// libc realloc.
fn realloc(ptr: *anyopaque, size: usize) callconv(.C) *anyopaque {
    const eff_size = 1 + (size + usize_len - 1) / usize_len;
    const addr = @ptrToInt(ptr) - usize_len;
    const block = @intToPtr([*]usize, addr);
    const len = block[0];
    const slice: []usize = block[0..len];
    const new_slice = galloc.realloc(slice, eff_size) catch unreachable;
    new_slice[0] = eff_size;
    return &new_slice[1];
}

/// libc sqrt.
fn sqrt(x: f64) callconv(.C) f64 {
    return std.math.sqrt(x);
}

/// libc ldexp.
fn ldexp(x: f64, n: i32) callconv(.C) f64 {
    return std.math.ldexp(x, n);
}

/// libc pow.
fn pow(x: f64, y: f64) callconv(.C) f64 {
    return std.math.pow(f64, x, y);
}

/// libc abs.
fn abs(x: i32) callconv(.C) i32 {
    return std.math.absInt(x) catch unreachable;
}

/// libc memset.
fn memset(s: ?*anyopaque, val: i32, n: usize) callconv(.C) ?*anyopaque {
    // Some user code may try to write to a bad location in wasm with n=0. Wasm doesn't allow that.
    if (n > 0) {
        const slice = @ptrCast([*]u8, s)[0..n];
        std.mem.set(u8, slice, @intCast(u8, val));
    }
    return s;
}

/// libc memcpy.
fn memcpy(dst: ?*anyopaque, src: ?*anyopaque, n: usize) callconv(.C) ?*anyopaque {
    const dst_slice = @ptrCast([*]u8, dst)[0..n];
    const src_slice = @ptrCast([*]u8, src)[0..n];
    std.mem.copy(u8, dst_slice, src_slice);
    return dst;
}