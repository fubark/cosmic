const std = @import("std");
const stdx = @import("stdx");
const uv = @import("uv");
const builtin = @import("builtin");

const log = stdx.log.scoped(.uv_poller);
const mac_sys = @import("mac_sys.zig");
const runtime = @import("runtime.zig");

/// A dedicated thread is used to poll libuv's backend fd.
pub const UvPoller = struct {
    const Self = @This();

    uv_loop: *uv.uv_loop_t,
    inner: switch (builtin.os.tag) {
        .linux => UvPollerLinux,
        .macos => UvPollerMac,
        .windows => UvPollerWindows,
        else => unreachable,
    },

    // Must refer to the same address in memory.
    notify: *std.Thread.ResetEvent,

    close_flag: std.atomic.Atomic(bool),

    // Currently only used for GetQueuedCompletionStatus (pre windows 10) to make sure there is only one thread polling at any time.
    poll_ready: std.atomic.Atomic(bool),

    pub fn init(uv_loop: *uv.uv_loop_t, notify: *std.Thread.ResetEvent) Self {
        var new = Self{
            .uv_loop = uv_loop,
            .inner = undefined,
            .notify = notify,
            .close_flag = std.atomic.Atomic(bool).init(false),
            .poll_ready = std.atomic.Atomic(bool).init(true),
        };
        new.inner.init(uv_loop);
        return new;
    }

    pub fn setPollReady(self: *Self) void {
        if (builtin.os.tag == .windows) {
            self.poll_ready.store(true, .Release);
        }
    }

    /// Only exposed for testing purposes.
    pub fn poll(self: *Self) void {
        self.inner.poll(self.uv_loop);
    }

    pub fn run(self: *Self) void {
        while (true) {
            if (self.close_flag.load(.Acquire)) {
                break;
            }

            if (builtin.os.tag == .windows) {
                while (!self.poll_ready.load(.Acquire)) {}
            }

            // log.debug("uv poller wait", .{});
            self.inner.poll(self.uv_loop);
            // log.debug("uv poller wait end, alive: {}", .{uv.uv_loop_alive(self.uv_loop) == 1});

            if (builtin.os.tag == .windows) {
                self.poll_ready.store(false, .Release);
            }

            // Notify that there is new uv work to process.
            self.notify.set();
        }

        // Reuse flag to indicate the thread is done.
        self.close_flag.store(false, .Release);
    }
};

const UvPollerLinux = struct {
    const Self = @This();

    epfd: i32,

    fn init(self: *Self, uv_loop: *uv.uv_loop_t) void {
        const backend_fd = uv.uv_backend_fd(uv_loop);

        var evt: std.os.linux.epoll_event = undefined;
        evt.events = std.os.linux.EPOLL.IN;
        evt.data.fd = backend_fd;

        const epfd = std.os.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch unreachable;
        std.os.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_ADD, backend_fd, &evt) catch unreachable;

        self.* = .{
            .epfd = epfd,
        };
    }

    fn poll(self: Self, uv_loop: *uv.uv_loop_t) void {
        const timeout = uv.uv_backend_timeout(uv_loop);
        var evts: [1]std.os.linux.epoll_event = undefined;
        _ = std.os.epoll_wait(self.epfd, &evts, timeout);
    }
};

const UvPollerMac = struct {
    const Self = @This();

    fn init(self: *Self, uv_loop: *uv.uv_loop_t) void {
        _ = self;
        _ = uv_loop;
    }

    fn poll(self: Self, uv_loop: *uv.uv_loop_t) void {
        _ = self;
        var tv: mac_sys.timeval = undefined;
        const timeout = uv.uv_backend_timeout(uv_loop);
        if (timeout != -1) {
            tv.tv_sec = @divTrunc(timeout, 1000);
            tv.tv_usec = @rem(timeout, 1000) * 1000;
        }

        var readset: mac_sys.fd_set = undefined;
        const fd = uv.uv_backend_fd(uv_loop);
        mac_sys.sys_FD_ZERO(&readset);
        mac_sys.sys_FD_SET(fd, &readset);

        var r: c_int = undefined;
        while (true) {
            r = mac_sys.select(fd + 1, &readset, null, null, if (timeout == -1) null else &tv);
            if (r != -1 or std.os.errno(r) != .INTR) {
                break;
            }
        }
    }
};

/// Since UvPoller runs on a separate thread,
/// and libuv also uses GetQueuedCompletionStatus(Ex),
/// the iocp is assumed to allow 2 concurrent threads.
/// Otherwise, the first thread to call GetQueuedCompletionStatus will bind to iocp
/// preventing the other thread from receiving anything.
const UvPollerWindows = struct {
    const Self = @This();

    fn init(self: *Self, uv_loop: *uv.uv_loop_t) void {
        _ = self;
        _ = uv_loop;
    }

    fn poll(self: Self, uv_loop: *uv.uv_loop_t) void {
        _ = self;

        var bytes: u32 = undefined;
        var key: usize = undefined;
        var overlapped: ?*std.os.windows.OVERLAPPED = null;

        // Wait forever if -1 is returned.
        const timeout = uv.uv_backend_timeout(uv_loop);
        // log.debug("windows poll wait {} {}", .{timeout, uv_loop.iocp.?});
        if (timeout == -1) {
            GetQueuedCompletionStatus(uv_loop.iocp.?, &bytes, &key, &overlapped, std.os.windows.INFINITE);
        } else {
            GetQueuedCompletionStatus(uv_loop.iocp.?, &bytes, &key, &overlapped, @intCast(u32, timeout));
        }

        // Repost so libuv can pick it up during uv_run.
        if (overlapped != null) {
            std.os.windows.PostQueuedCompletionStatus(uv_loop.iocp.?, bytes, key, overlapped) catch |err| {
                log.debug("PostQueuedCompletionStatus error: {}", .{err});
            }; 
        }
    }
};

/// For debugging. Poll immediately to see if there are problems with the windows queue. 
pub export fn cosmic_check_win_queue() void {
    if (builtin.os.tag != .windows) {
        return;
    }
    // log.debug("check win queue", .{});
    var bytes: u32 = undefined;
    var key: usize = undefined;
    var overlapped: ?*std.os.windows.OVERLAPPED = null;
    GetQueuedCompletionStatus(runtime.global.uv_loop.iocp.?, &bytes, &key, &overlapped, 0);
    if (overlapped != null) {
        // Repost so we don't lose any queue items.
        std.os.windows.PostQueuedCompletionStatus(runtime.global.uv_loop.iocp.?, bytes, key, overlapped) catch |err| {
            log.debug("PostQueuedCompletionStatus error: {}", .{err});
        }; 
    }
}

/// Duped from std.os.windows.GetQueuedCompletionStatus in case we need to make changes.
fn GetQueuedCompletionStatus(
    completion_port: std.os.windows.HANDLE,
    bytes_transferred_count: *std.os.windows.DWORD,
    lpCompletionKey: *usize,
    lpOverlapped: *?*std.os.windows.OVERLAPPED,
    dwMilliseconds: std.os.windows.DWORD,
) void {
    if (std.os.windows.kernel32.GetQueuedCompletionStatus(
        completion_port,
        bytes_transferred_count,
        lpCompletionKey,
        lpOverlapped,
        dwMilliseconds,
    ) == std.os.windows.FALSE) {
        switch (std.os.windows.kernel32.GetLastError()) {
            .ABANDONED_WAIT_0 => {
                // Nop, iocp handle was closed.
            },
            .OPERATION_ABORTED => {
                // Nop, event was cancelled.
                log.debug("OPERATION ABORTED", .{});
                unreachable;
            },
            .IMEOUT => {
                // Nop, timeout reached.
            },
            //.HANDLE_EOF => return GetQueuedCompletionStatusResult.EOF,
            else => |err| {
                log.debug("GetQueuedCompletionStatus error: {}", .{err});
                unreachable;
            },
        }
    }
}

