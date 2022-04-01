const std = @import("std");
const log = std.log.scoped(.uv);

const c = @cImport({
    @cInclude("uv.h");
});

pub const sockaddr = c.sockaddr;
pub const sockaddr_in = c.sockaddr_in;

pub const uv_loop_t = c.uv_loop_t;
pub const uv_tcp_t = c.uv_tcp_t;
pub const uv_stream_t = c.uv_stream_t;
pub const uv_handle_t = c.uv_handle_t;
pub const uv_close_cb = c.uv_close_cb;
pub const uv_async_t = c.uv_async_t;
pub const uv_timer_t = c.uv_timer_t;
pub const uv_poll_t = c.uv_poll_t;
pub const uv_timer_cb = c.uv_timer_cb;
pub const uv_fs_event_t = c.uv_fs_event_t;

pub const UV_EBUSY = c.UV_EBUSY;

pub const UV_RUN_DEFAULT = c.UV_RUN_DEFAULT;
pub const UV_RUN_ONCE = c.UV_RUN_ONCE;
pub const UV_RUN_NOWAIT = c.UV_RUN_NOWAIT;

pub const UV_READABLE = c.UV_READABLE;
pub const UV_WRITABLE = c.UV_WRITABLE;

// Handle types
pub const UV_TCP = c.UV_TCP;
pub const UV_TIMER = c.UV_TIMER;

// uv_fs_event enum
pub const UV_RENAME = c.UV_RENAME;
pub const UV_CHANGE = c.UV_CHANGE;

pub const uv_fs_event_cb = ?fn (*uv_fs_event_t, [*c]const u8, c_int, c_int) callconv(.C) void;
pub const uv_connection_cb = ?fn (*uv_stream_t, c_int) callconv(.C) void;
pub extern fn uv_loop_init(loop: *uv_loop_t) c_int;
pub extern fn uv_listen(stream: *uv_stream_t, backlog: c_int, cb: uv_connection_cb) c_int;
pub extern fn uv_tcp_init(*uv_loop_t, handle: *uv_tcp_t) c_int;
pub extern fn uv_ip4_addr(ip: [*c]const u8, port: c_int, addr: *c.struct_sockaddr_in) c_int;
pub extern fn uv_tcp_bind(handle: *uv_tcp_t, addr: *const c.struct_sockaddr, flags: c_uint) c_int;
pub extern fn uv_strerror(err: c_int) [*c]const u8;

/// [uv] Gets the platform dependent file descriptor equivalent.
///      following handles are supported: TCP, pipes, TTY, UDP and poll. Passing any other handle type will fail with UV_EINVAL.
///      If a handle doesn’t have an attached file descriptor yet or the handle itself has been closed, this function will return UV_EBADF.
pub extern fn uv_fileno(handle: *const uv_handle_t, fd: *c.uv_os_fd_t) c_int;

/// [uv] Request handle to be closed. close_cb will be called asynchronously after this call.
///      This MUST be called on each handle before memory is released.
///      Moreover, the memory can only be released in close_cb or after it has returned.
///      Handles that wrap file descriptors are closed immediately but close_cb will still be deferred to the next iteration of the event loop.
///      It gives you a chance to free up any resources associated with the handle.
///      In-progress requests, like uv_connect_t or uv_write_t, are cancelled and have their callbacks called asynchronously with status=UV_ECANCELED.
pub extern fn uv_close(handle: *uv_handle_t, close_cb: uv_close_cb) void;

pub extern fn uv_run(*uv_loop_t, mode: c.uv_run_mode) c_int;
pub extern fn uv_accept(server: *uv_stream_t, client: *uv_stream_t) c_int;
pub extern fn uv_backend_fd(*const uv_loop_t) c_int;
pub extern fn uv_backend_timeout(*const uv_loop_t) c_int;
pub extern fn uv_loop_size() usize;
pub extern fn uv_loop_alive(loop: *const uv_loop_t) c_int;
pub extern fn uv_loop_close(loop: *const uv_loop_t) c_int;
pub extern fn uv_stop(loop: *const uv_loop_t) void;
pub extern fn uv_walk(loop: *const uv_loop_t, cb: c.uv_walk_cb, ctx: ?*anyopaque) void;
pub extern fn uv_async_init(*uv_loop_t, @"async": *uv_async_t, async_cb: c.uv_async_cb) c_int;
pub extern fn uv_async_send(@"async": *uv_async_t) c_int;
pub extern fn uv_handle_get_type(handle: *const uv_handle_t) c.uv_handle_type;
pub extern fn uv_timer_init(*uv_loop_t, handle: *uv_timer_t) c_int;
pub extern fn uv_timer_start(handle: *uv_timer_t, cb: c.uv_timer_cb, timeout: u64, repeat: u64) c_int;
pub extern fn uv_timer_stop(handle: *uv_timer_t) c_int;
pub extern fn uv_poll_init_socket(loop: *uv_loop_t, handle: *uv_poll_t, socket: c.uv_os_sock_t) c_int;
pub extern fn uv_poll_start(handle: *uv_poll_t, events: c_int, cb: c.uv_poll_cb) c_int;
pub extern fn uv_poll_stop(handle: *uv_poll_t) c_int;
pub extern fn uv_is_closing(handle: *const uv_handle_t) c_int;
pub extern fn uv_update_time(*uv_loop_t) void;
pub extern fn uv_fs_event_init(loop: *uv_loop_t, handle: *uv_fs_event_t) c_int;
pub extern fn uv_fs_event_start(handle: *uv_fs_event_t, cb: uv_fs_event_cb, path: [*c]const u8, flags: c_uint) c_int;
pub extern fn uv_fs_event_stop(handle: *uv_fs_event_t) c_int;
pub extern fn uv_tcp_getsockname(handle: *const uv_tcp_t, name: *c.struct_sockaddr, namelen: *c_int) c_int;

pub fn assertNoError(code: c_int) void {
    if (code != 0) {
        log.debug("uv error: [{}] {s}", .{code, uv_strerror(code)});
        unreachable;
    }
}