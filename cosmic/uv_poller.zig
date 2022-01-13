const std = @import("std");
const uv = @import("uv");
const log = std.log.scoped(.uv_poller);

/// A dedicated thread is used to poll libuv's backend fd.
pub const UvPoller = struct {
    const Self = @This();

    uv_loop: *uv.uv_loop_t,
    epfd: i32,
    wakeup: std.Thread.ResetEvent,

    // Must refer to the same address in memory.
    notify: *std.Thread.ResetEvent,

    close_flag: std.atomic.Atomic(bool),

    pub fn init(uv_loop: *uv.uv_loop_t, notify: *std.Thread.ResetEvent) Self {
        var wakeup: std.Thread.ResetEvent = undefined;
        wakeup.init() catch unreachable;

        // Polling should happen before event loop processing so this is set initially to start polling when thread is spawned.
        wakeup.set();

        const backend_fd = uv.uv_backend_fd(uv_loop);

        var evt: std.os.linux.epoll_event = undefined;
        evt.events = std.os.linux.EPOLL.IN;
        evt.data.fd = backend_fd;

        const epfd = std.os.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch unreachable;
        std.os.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_ADD, backend_fd, &evt) catch unreachable;
        return .{
            .uv_loop = uv_loop,
            .epfd = epfd,
            .wakeup = wakeup,
            .notify = notify,
            .close_flag = std.atomic.Atomic(bool).init(false),
        };
    }

    pub fn loop(self: *Self) void {
        while (true) {
            if (self.close_flag.load(.Acquire)) {
                break;
            }

            // Only start polling when uv is done processing.
            self.wakeup.wait();
            self.wakeup.reset();

            const timeout = uv.uv_backend_timeout(self.uv_loop);
            var evts: [1]std.os.linux.epoll_event = undefined;
            // log.debug("uv poller wait", .{});
            _ = std.os.epoll_wait(self.epfd, &evts, timeout);
            // log.debug("uv poller wait return {}", .{uv.uv_loop_alive(self.uv_loop)});

            // Notify that there is new uv work to process.
            self.notify.set();
        }

        // Reuse flag to indicate the thread is done.
        self.close_flag.store(false, .Release);
    }
};