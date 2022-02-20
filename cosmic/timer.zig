const std = @import("std");
const stdx = @import("stdx");
const uv = @import("uv");
const v8 = @import("v8");
const t = stdx.testing;
const Null = stdx.ds.CompactNull(u32);
const RuntimeContext = @import("runtime.zig").RuntimeContext;
const EventDispatcher = stdx.events.EventDispatcher;

const log = stdx.log.scoped(.timer);

/// High performance timer to handle large amounts of timers and callbacks.
/// A binary min-heap is used to track the next closest timeout.
/// A hashmap is used to lookup group nodes by timeout value.
/// Each group node has timeouts clamped to the same millisecond with a singly linked list.
pub const Timer = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    timer: *uv.uv_timer_t,
    watch: std.time.Timer,
    heap: std.PriorityQueue(u32, void, compare),

    // Keys are in milliseconds relative to the watch start time. (This avoids having to update the timeout.)
    map: std.AutoHashMap(u32, GroupNode),

    ll_buf: stdx.ds.CompactSinglyLinkedListBuffer(u32, Node),

    // Relative timeout in ms from watch start time that is currently set for the uv timer.
    // If a new timeout is set at or past this value, we don't need to reset the timer.
    // If a new timeout is set before this value, we do need to invoke uv_timer_start again.
    // The initial state is at max(u32) so the first timeout should set the uv timer.
    active_timeout: u32,

    ctx: v8.Persistent(v8.Context),
    receiver: v8.Value,
    dispatcher: EventDispatcher,

    /// RuntimeContext must already have inited uv_loop.
    pub fn init(self: *Self, rt: *RuntimeContext) !void {
        const alloc = rt.alloc;
        const timer = alloc.create(uv.uv_timer_t) catch unreachable;
        var res = uv.uv_timer_init(rt.uv_loop, timer);
        uv.assertNoError(res);
        timer.data = self;
        self.* = .{
            .alloc = alloc,
            .timer = timer,
            .heap = std.PriorityQueue(u32, void, compare).init(alloc, {}),
            .watch = try std.time.Timer.start(),
            .map = std.AutoHashMap(u32, GroupNode).init(alloc),
            .ll_buf = stdx.ds.CompactSinglyLinkedListBuffer(u32, Node).init(alloc),
            .active_timeout = std.math.maxInt(u32),
            .ctx = rt.context,
            .receiver = rt.global.toValue(),
            .dispatcher = rt.event_dispatcher,
        };
    }

    pub fn close(self: Self) void {
        const res = uv.uv_timer_stop(self.timer);
        uv.assertNoError(res);
        uv.uv_close(@ptrCast(*uv.uv_handle_t, self.timer), null);
    }

    /// Should be called after close and closing uv events have been processed.
    pub fn deinit(self: *Self) void {
        self.alloc.destroy(self.timer);
        self.heap.deinit();
        self.map.deinit();
        self.ll_buf.deinit();
    }

    fn onTimeout(ptr: [*c]uv.uv_timer_t) callconv(.C) void {
        const timer = @ptrCast(*uv.uv_timer_t, ptr);
        const self = stdx.mem.ptrCastAlign(*Self, timer.data);
        self.processNext(self.ctx.inner);
    }

    pub fn setTimeout(self: *Self, timeout_ms: u32, cb: v8.Persistent(v8.Function), cb_arg: ?v8.Persistent(v8.Value)) !u32 {
        const now = @floatToInt(u32, @intToFloat(f32, self.watch.read()) / 1e6);
        const abs_ms = now + timeout_ms;

        const entry = try self.map.getOrPut(abs_ms);
        if (!entry.found_existing) {
            const head = try self.ll_buf.add(.{
                .cb = cb,
                .cb_arg = cb_arg,
            });
            entry.value_ptr.* = .{
                .timeout = abs_ms,
                .head = head,
                .last = head,
            };
            try self.heap.add(abs_ms);

            // Check if we need to start the uv timer.
            if (abs_ms < self.active_timeout) {
                self.dispatcher.startTimer(self.timer, timeout_ms, onTimeout);
                self.active_timeout = abs_ms;
            }

            return head;
        } else {
            // Append to the last node in the list.
            const new = try self.ll_buf.insertAfter(entry.value_ptr.last, .{
                .cb = cb,
                .cb_arg = cb_arg,
            });
            entry.value_ptr.last = new;
            return new;
        }
    }

    pub fn peekNext(self: *Self) ?u32 {
        return self.heap.peek();
    }

    pub fn processNext(self: *Self, _: v8.Context) void {
        // Pop the next timeout.
        const timeout = self.heap.remove();
        const group = self.map.get(timeout).?;

        const ctx = self.ctx.inner;

        // Invoke each callback in order and deinit them.
        var cur = group.head;
        while (cur != Null) {
            var node = self.ll_buf.getNodeAssumeExists(cur);
            if (node.data.cb_arg) |*cb_arg| {
                _ = node.data.cb.inner.call(ctx, self.receiver, &.{ cb_arg.inner });
                cb_arg.deinit();
            } else {
                _ = node.data.cb.inner.call(ctx, self.receiver, &.{});
            }
            node.data.cb.deinit();
            self.ll_buf.removeAssumeNoPrev(cur) catch unreachable;
            cur = node.next;
        }

        // Remove this GroupNode.
        if (!self.map.remove(timeout)) unreachable;

        // TODO: Consider processing next timeouts that have already expired.

        // Schedule the next timeout.
        if (self.heap.len > 0) {
            const next_timeout = self.peekNext().?;
            const now = @floatToInt(u32, @intToFloat(f32, self.watch.read()) / 1e6);
            var rel_timeout: u32 = undefined;
            if (next_timeout < now) {
                rel_timeout = 0;
            } else {
                rel_timeout = next_timeout - now;
            }

            self.dispatcher.startTimer(self.timer, rel_timeout, onTimeout);
            self.active_timeout = next_timeout;
        } else {
            self.active_timeout = std.math.maxInt(u32);
        }
    }
};

// This does not test the libuv mechanism.
test "Timer" {
    // t.setLogLevel(.debug);
    var rt: RuntimeContext = undefined;
    rt.alloc = t.alloc;

    var timer: Timer = undefined;
    try timer.init(&rt);
    defer timer.deinit();

    const cb: v8.Persistent(v8.Function) = undefined;
    _ = try timer.setTimeout(100, cb, null);
    _ = try timer.setTimeout(200, cb, null);
    _ = try timer.setTimeout(0, cb, null);
    _ = try timer.setTimeout(0, cb, null);
    _ = try timer.setTimeout(300, cb, null);
    _ = try timer.setTimeout(300, cb, null);

    const ctx: v8.Context = undefined;

    const timeout = timer.peekNext().?;
    try t.eq(timeout, 0);
    timer.processNext(ctx);
    try t.eq(timer.peekNext().?, 100);
    timer.processNext(ctx);
    try t.eq(timer.peekNext().?, 200);
    timer.processNext(ctx);
    try t.eq(timer.peekNext().?, 300);
    timer.processNext(ctx);
    try t.eq(timer.peekNext(), null);
}

// Assume no duplicate nodes since timeouts will be grouped together.
fn compare(_: void, a: u32, b: u32) std.math.Order {
    if (a < b) {
        return .lt;
    } else {
        return .gt;
    }
}

const GroupNode = struct {
    // In milliseconds relative to the watch's start time.
    timeout: u32,
    head: u32,
    last: u32,
};

const Node = struct {
    cb: v8.Persistent(v8.Function),
    cb_arg: ?v8.Persistent(v8.Value),
};
