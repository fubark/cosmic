const std = @import("std");
const stdx = @import("stdx");
const uv = @import("uv");
const h2o = @import("h2o");

const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const ThisResource = runtime.ThisResource;
const v8 = @import("v8.zig");
const log = stdx.log.scoped(.server);

pub const HttpServer = struct {
    const Self = @This();

    rt: *RuntimeContext,

    handle: uv.uv_tcp_t,

    config: h2o.h2o_globalconf,
    hostconf: *h2o.h2o_hostconf,
    ctx: h2o.h2o_context,
    accept_ctx: h2o.h2o_accept_ctx,
    generator: h2o.h2o_generator_t,

    // Track active socket handles to make sure we freed all uv handles.
    // This is not always the number of active connections since it's incremented the moment we allocate a uv handle.
    socket_handles: u32,

    requested_shutdown: bool,
    done: bool,

    js_handler: ?v8.Persistent(v8.Function),

    pub fn init(self: *Self, rt: *RuntimeContext) void {
        self.* = .{
            .rt = rt,
            .handle = undefined,
            .config = undefined,
            .hostconf = undefined,
            .ctx = undefined,
            .accept_ctx = undefined,
            .js_handler = null,
            .generator = .{ .proceed = null, .stop = null },
            .requested_shutdown = false,
            .done = false,
            .socket_handles = 0,
        };

        h2o.h2o_config_init(&self.config);
        self.hostconf = h2o.h2o_config_register_host(&self.config, h2o.h2o_iovec_init("default", "default".len), 65535);
        h2o.h2o_context_init(&self.ctx, rt.uv_loop, &self.config);

        self.accept_ctx.ctx = &self.ctx;
        self.accept_ctx.hosts = self.config.hosts;
        self.accept_ctx.ssl_ctx = null;

        _ = uv.uv_tcp_init(rt.uv_loop, &self.handle);
        // Need to callback with handle.
        self.handle.data = self;

        _ = self.registerHandler("/", HttpServer.defaultHandler);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn deinitC(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        log.debug("---DEINIT", .{});
        const uv_tcp = @ptrCast(*uv.uv_tcp_t, ptr);
        const self = stdx.mem.ptrCastAlign(*Self, uv_tcp.data.?);
        self.rt.alloc.destroy(self);
    }

    pub fn start(self: *Self, host: []const u8, port: u16) !void {
        const rt = self.rt;

        var addr: uv.sockaddr_in = undefined;
        var r: c_int = undefined;

        const c_host = std.cstr.addNullByte(rt.alloc, host) catch unreachable;
        defer rt.alloc.free(c_host);
        _ = uv.uv_ip4_addr(c_host, port, &addr);

        r = uv.uv_tcp_bind(&self.handle, @ptrCast(*uv.sockaddr, &addr), 0);
        if (r != 0) {
            log.debug("uv_tcp_bind: {s}", .{uv.uv_strerror(r)});
            uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.handle), HttpServer.deinitC);
            return error.SocketAddrBind;
        }

        r = uv.uv_listen(@ptrCast(*uv.uv_stream_t, &self.handle), 128, HttpServer.onAccept);
        if (r != 0) {
            log.debug("uv_listen: {s}", .{uv.uv_strerror(r)});
            uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.handle), HttpServer.deinitC);
            return error.ListenError;
        }

        rt.num_uv_handles += 1;
    }

    pub fn setHandler(res: ThisResource(*Self), handler: v8.Function) void {
        const self = res.ptr;
        self.js_handler = self.rt.isolate.initPersistent(v8.Function, handler);
    }

    pub fn close(res: ThisResource(*Self)) void {
        const self = res.ptr;
        self.shutdown();
    }

    fn registerHandler(self: *Self, path: [:0]const u8, onRequest: fn (handler: *h2o.h2o_handler, req: *h2o.h2o_req) callconv(.C) c_int) *h2o.h2o_pathconf {
        const pathconf = h2o.h2o_config_register_path(self.hostconf, path, 0);
        var handler = @ptrCast(*H2oServerHandler, h2o.h2o_create_handler(pathconf, @sizeOf(H2oServerHandler)).?);
        handler.super.on_req = onRequest;
        handler.server = self;
        return pathconf;
    }

    fn defaultHandler(ptr: *h2o.h2o_handler, req: *h2o.h2o_req) callconv(.C) c_int {
        const self = @ptrCast(*H2oServerHandler, ptr).server;
        const iso = self.rt.isolate;
        const ctx = self.rt.context;

        if (self.js_handler) |handler| {
            const js_req = self.rt.default_obj_t.initInstance(ctx);
            const method = req.method.base[0..req.method.len];
            _ = js_req.setValue(ctx, iso.initStringUtf8("method"), iso.initStringUtf8(method));
            const path = req.path_normalized.base[0..req.path_normalized.len];
            _ = js_req.setValue(ctx, iso.initStringUtf8("path"), iso.initStringUtf8(path));

            ResponseWriter.cur_req = req;
            ResponseWriter.cur_generator = &self.generator;
            const writer = self.rt.http_response_writer.initInstance(ctx);
            if (handler.inner.call(ctx, self.rt.js_undefined, &.{ js_req.toValue(), writer.toValue() })) |res| {
                if (res.toBool(iso)) {
                    return 0;
                }
            } else {
                // Js exception, start shutdown.
                self.shutdown();
            }
        }

        // Let H2o serve default 404 not found.
        return -1;
    }

    fn onAccept(listener: *uv.uv_stream_t, status: c_int) callconv(.C) void {
        // log.debug("accept", .{});
        if (status != 0) {
            return;
        }

        const self = stdx.mem.ptrCastAlign(*HttpServer, listener.data.?);

        // h2o will set its own data on uv_tcp_t so use a custom struct.
        var conn = self.rt.alloc.create(H2oUvTcp) catch unreachable;
        conn.server = self;
        _ = uv.uv_tcp_init(listener.loop, @ptrCast(*uv.uv_tcp_t, conn));

        self.socket_handles += 1;
        if (uv.uv_accept(listener, @ptrCast(*uv.uv_stream_t, conn)) != 0) {
            conn.super.data = self;
            uv.uv_close(@ptrCast(*uv.uv_handle_t, conn), onCloseH2oSocketHandle);
            return;
        }

        var sock = h2o.h2o_uv_socket_create(@ptrCast(*uv.uv_handle_t, conn), onCloseH2oSocketHandle).?;
        h2o.h2o_accept(&self.accept_ctx, sock);
    }

    // For closing uv handles that have been attached to h2o handles.
    fn onCloseH2oSocketHandle(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const kind = uv.uv_handle_get_type(ptr);
        if (kind == uv.UV_TCP) {
            const handle = @ptrCast(*H2oUvTcp, ptr);
            const self = stdx.mem.ptrCastAlign(*HttpServer, handle.server);
            self.rt.alloc.destroy(handle);

            self.socket_handles -= 1;
            self.updateDone();
        } else {
            unreachable;
        }
    }

    fn updateDone(self: *Self) void {
        if (self.done) {
            return;
        }
        if (self.socket_handles > 0) {
            return;
        }
        self.rt.num_uv_handles -= 1;
        self.done = true;
    }

    fn onUvHandleClose(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const kind = uv.uv_handle_get_type(ptr);
        if (kind == uv.UV_TCP) {
            const handle = @ptrCast(*uv.uv_tcp_t, ptr);
            const self = stdx.mem.ptrCastAlign(*HttpServer, handle.data);
            log.debug("DEINIT {*}", .{ptr});
            self.rt.alloc.destroy(handle);
        } else {
            unreachable;
        }
    }

    pub fn shutdown(self: *Self) void {
        if (self.requested_shutdown) {
            return;
        }
        // Once shutdown is requested, h2o won't be accepting more connections
        // and will start to gracefully shutdown existing connections.
        // After a small delay, a timeout will force any connections to close.
        // We track number of socket handles and once there are no more, we mark this done in updateDone.
        h2o.h2o_context_request_shutdown(&self.ctx);
        self.requested_shutdown = true;

        // TODO: Might want to provide option to wait for all connections to close. See h2o/src/main.c
    }
};

const H2oUvTcp = struct {
    super: uv.uv_tcp_t,
    server: *HttpServer,
};

// https://github.com/h2o/h2o/issues/181 
const H2oServerHandler = struct {
    super: h2o.h2o_handler,
    server: *HttpServer,
};

pub const ResponseWriter = struct {

    pub var cur_req: ?*h2o.h2o_req = null;
    pub var cur_generator: *h2o.h2o_generator_t = undefined;

    pub fn setStatus(status_code: u32) void {
        if (cur_req) |req| {
            req.res.status = @intCast(c_int, status_code);
            req.res.reason = getStatusReason(status_code).ptr;
        }
    }

    pub fn setHeader(key: []const u8, value: []const u8) void {
        if (cur_req) |req| {
            _ = h2o.h2o_set_header_by_str(&req.pool, &req.res.headers, key.ptr, key.len, 1, value.ptr, value.len, 1);
        }
    }

    pub fn send(text: []const u8) void {
        if (cur_req) |req| {
            h2o.h2o_start_response(req, cur_generator);
            const slice_ptr = @intToPtr([*c]h2o.h2o_iovec_t, @ptrToInt(&text));
            h2o.h2o_send(req, slice_ptr, 1, h2o.H2O_SEND_STATE_FINAL);
        }
    }
};

fn getStatusReason(code: u32) []const u8 {
    switch (code) {
        200 => return "OK",
        201 => return "Created",
        301 => return "Moved Permanently",
        302 => return "Found",
        303 => return "See Other",
        304 => return "Not Modified",
        400 => return "Bad Request",
        401 => return "Unauthorized",
        402 => return "Payment Required",
        403 => return "Forbidden",
        404 => return "Not Found",
        405 => return "Method Not Allowed",
        500 => return "Internal Server Error",
        501 => return "Not Implemented",
        502 => return "Bad Gateway",
        503 => return "Service Unavailable",
        504 => return "Gateway Timeout",
        else => unreachable,
    }
}