const uv = @import("uv");

/// Wraps around libuv to make it work with embedded libuv event loop.
pub const EventDispatcher = struct {
    const Self = @This();

    interrupt: *uv.uv_async_t,

    pub fn init(interrupt: *uv.uv_async_t) Self {
        return .{
            .interrupt = interrupt,
        };
    }

    pub fn startTimer(self: Self, timer: *uv.uv_timer_t, timeout_ms: u32, on_timeout: uv.uv_timer_cb) void {
        var res = uv.uv_timer_start(timer, on_timeout, timeout_ms, 0);
        uv.assertNoError(res);
        // The poller thread may already be blocking indefinitely.
        // Wake it up to make sure it gets the right uv_backend_timeout.
        res = uv.uv_async_send(self.interrupt);
        uv.assertNoError(res);
    }
};