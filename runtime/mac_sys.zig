const c = @cImport(
    @cInclude("sys/select.h"),
);

pub const timeval = c.timeval;
pub const fd_set = c.fd_set;
pub const select = c.select;

pub extern fn sys_FD_SET(n: c_int, p: *c.fd_set) void;
pub extern fn sys_FD_ZERO(p: *c.fd_set) void;