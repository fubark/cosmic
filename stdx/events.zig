const uv = @import("uv");
const stdx = @import("stdx.zig");

const log = stdx.log.scoped(.events);

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
        log.debug("start timer {}", .{timeout_ms});
        var res = uv.uv_timer_start(timer, on_timeout, timeout_ms, 0);
        uv.assertNoError(res);
        // The poller thread may already be blocking indefinitely.
        // Wake it up to make sure it gets the right uv_backend_timeout.
        // TODO: It would be better if we received a callback that the timeout has changed from libuv so this doesn't always have to wake the poller.
        res = uv.uv_async_send(self.interrupt);
        uv.assertNoError(res);
        log.debug("start timer sent", .{});
    }
};
