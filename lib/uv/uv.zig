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

pub const UV_RUN_DEFAULT = c.UV_RUN_DEFAULT;

pub const uv_connection_cb = ?fn (*uv_stream_t, c_int) callconv(.C) void;
pub extern fn uv_loop_init(loop: *uv_loop_t) c_int;
pub extern fn uv_listen(stream: *uv_stream_t, backlog: c_int, cb: uv_connection_cb) c_int;
pub extern fn uv_tcp_init(*uv_loop_t, handle: *uv_tcp_t) c_int;
pub extern fn uv_ip4_addr(ip: [*c]const u8, port: c_int, addr: *c.struct_sockaddr_in) c_int;
pub extern fn uv_tcp_bind(handle: *uv_tcp_t, addr: *const c.struct_sockaddr, flags: c_uint) c_int;
pub extern fn uv_strerror(err: c_int) [*c]const u8;
pub extern fn uv_close(handle: *uv_handle_t, close_cb: uv_close_cb) void;
pub extern fn uv_run(*uv_loop_t, mode: c.uv_run_mode) c_int;
pub extern fn uv_accept(server: *uv_stream_t, client: *uv_stream_t) c_int;
