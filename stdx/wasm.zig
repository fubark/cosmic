const std = @import("std");
const stdx = @import("stdx.zig");
const ds = stdx.ds;

const log_wasm = @import("log_wasm.zig");
const log = stdx.log.scoped(.wasm);

var js_buffer: WasmJsBuffer = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    js_buffer.init(alloc);
    log_wasm.js_buf = &js_buffer;
    promises = ds.CompactUnorderedList(PromiseId, PromiseInternal).init(alloc);
    promise_child_deps = ds.CompactManySinglyLinkedList(PromiseId, PromiseDepId, PromiseId).init(alloc);
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
    const p = promises.getPtrAssumeExists(id);

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
        var mb_cur = promise_child_deps.getListHead(list_id);
        while (mb_cur) |cur| {
            const child_id = promise_child_deps.getAssumeExists(cur);
            const child_p = promises.getPtrAssumeExists(child_id);
            child_p.cur_resolved_deps += 1;
            if (child_p.cur_resolved_deps == child_p.num_deps) {
                child_p.resolved = true;
            }
            mb_cur = promise_child_deps.getNext(cur);
        }
    }

    if (p.auto_free) {
        promises.remove(id);
    }
}

pub fn resolvePromise(id: PromiseId, value: anytype) void {
    const p = promises.getPtrAssumeExists(id);

    if (p.then_copy_to) |dst| {
        stdx.mem.ptrCastAlign(*@TypeOf(value), dst).* = value;
    }

    p.resolved = true;

    if (p.child_deps_list_id) |list_id| {
        var mb_cur = promise_child_deps.getListHead(list_id);
        while (mb_cur) |cur| {
            const child_id = promise_child_deps.getAssumeExists(cur);
            const child_p = promises.getPtrAssumeExists(child_id);
            child_p.cur_resolved_deps += 1;
            if (child_p.cur_resolved_deps == child_p.num_deps) {
                child_p.resolved = true;
            }
            mb_cur = promise_child_deps.getNext(cur);
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
