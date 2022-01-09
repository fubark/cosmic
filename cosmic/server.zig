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

    requested_shutdown: bool,

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
        };

        h2o.h2o_config_init(&self.config);
        self.hostconf = h2o.h2o_config_register_host(&self.config, h2o.h2o_iovec_init("default", "default".len), 65535);
        h2o.h2o_context_init(&self.ctx, rt.uv_loop, &self.config);

        self.accept_ctx.ctx = &self.ctx;
        self.accept_ctx.hosts = self.config.hosts;
        self.accept_ctx.ssl_ctx = null;

        log.debug("init {*}", .{&self.handle});
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
        log.debug("set handler", .{});
        self.js_handler = self.rt.isolate.initPersistent(v8.Function, handler);
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

        _ = req;

        log.debug("default handler", .{});

        const ctx = self.rt.context;
        if (self.js_handler) |handler| {
            if (handler.inner.call(ctx, self.rt.js_undefined, &.{})) |res| {
                _ = res;
            } else {
                // Js exception, start shutdown.
                self.shutdown();
            }
        }

        // if (h2o_memis(req->method.base, req->method.len, H2O_STRLIT("POST")) &&
        //     h2o_memis(req->path_normalized.base, req->path_normalized.len, H2O_STRLIT("/post-test/"))) {
            // req.res.status = 200;
            // req.res.reason = "OK";
            // const str = "text/plain; charset=utf-8";
            // _ = h2o.h2o_add_header(&req.pool, &req.res.headers, h2o.H2O_TOKEN_CONTENT_TYPE, null, str, str.len);
            // h2o.h2o_start_response(req, &generator);
            // h2o.h2o_send(req, &req.entity, 1, 1);
            // return 0;
        // }
        return -1;
    }

    fn onAccept(listener: *uv.uv_stream_t, status: c_int) callconv(.C) void {
        log.debug("accept!", .{});

        if (status != 0) {
            return;
        }

        const self = stdx.mem.ptrCastAlign(*HttpServer, listener.data.?);

        // h2o will set its own data on uv_tcp_t so use a custom struct.
        var conn = self.rt.alloc.create(H2oUvTcp) catch unreachable;
        conn.server = self;
        _ = uv.uv_tcp_init(listener.loop, @ptrCast(*uv.uv_tcp_t, conn));

        if (uv.uv_accept(listener, @ptrCast(*uv.uv_stream_t, conn)) != 0) {
            uv.uv_close(@ptrCast(*uv.uv_handle_t, conn), onH2oUvHandleClose);
            return;
        }

        var sock = h2o.h2o_uv_socket_create(@ptrCast(*uv.uv_handle_t, conn), onH2oUvHandleClose).?;
        sock.data = self;
        h2o.h2o_accept(&self.accept_ctx, sock);
    }

    // For closing uv handles that have been attached to h2o handles.
    fn onH2oUvHandleClose(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const kind = uv.uv_handle_get_type(ptr);
        if (kind == uv.UV_TCP) {
            const handle = @ptrCast(*H2oUvTcp, ptr);
            const self = stdx.mem.ptrCastAlign(*HttpServer, handle.server);
            self.rt.alloc.destroy(handle);
        } else {
            unreachable;
        }
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
        log.debug("before request server shutdown", .{});
        h2o.h2o_context_request_shutdown(&self.ctx);
        self.requested_shutdown = true;
        log.debug("after request server shutdown", .{});

        // TODO: Wait for all connections to close. See h2o/src/main.c
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