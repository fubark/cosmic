const std = @import("std");
const stdx = @import("stdx");
const uv = @import("uv");
const h2o = @import("h2o");
const ssl = @import("openssl");

const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const ThisResource = runtime.ThisResource;
const PromiseId = runtime.PromiseId;
const ResourceId = runtime.ResourceId;
const v8 = @import("v8.zig");
const log = stdx.log.scoped(.server);

pub const HttpServer = struct {
    const Self = @This();

    rt: *RuntimeContext,

    listen_handle: uv.uv_tcp_t,

    h2o_started: bool,
    config: h2o.h2o_globalconf,
    hostconf: *h2o.h2o_hostconf,
    ctx: h2o.h2o_context,
    accept_ctx: h2o.h2o_accept_ctx,
    generator: h2o.h2o_generator_t,

    // Track active socket handles to make sure we freed all uv handles.
    // This is not always the number of active connections since it's incremented the moment we allocate a uv handle.
    socket_handles: u32,

    closing: bool,
    closed_listen_handle: bool,

    // When true, it means there are no handles to be cleaned up. The initial state is true.
    // If we end up owning additional memory in the future, we'd still need to deinit those.
    closed: bool,

    js_handler: ?v8.Persistent(v8.Function),

    https: bool,

    // The initial state is closed and nothing happens until we do startHttp/startHttps.
    pub fn init(self: *Self, rt: *RuntimeContext) void {
        self.* = .{
            .rt = rt,
            .listen_handle = undefined,
            .h2o_started = false,
            .config = undefined,
            .hostconf = undefined,
            .ctx = undefined,
            .accept_ctx = undefined,
            .js_handler = null,
            .generator = .{ .proceed = null, .stop = null },
            .closing = false,
            .closed = true,
            .socket_handles = 0,
            .closed_listen_handle = true,
            .https = false,
        };
    }

    // Deinit before entering closing phase.
    pub fn deinitPreClosing(self: *Self) void {
        _ = self;
    }

    /// This is just setting up the uv socket listener. Does not set up for http or https.
    fn startListener(self: *Self, host: []const u8, port: u16) !void {
        const rt = self.rt;

        self.closed = false;

        _ = uv.uv_tcp_init(rt.uv_loop, &self.listen_handle);
        // Need to callback with handle.
        self.listen_handle.data = self;
        self.closed_listen_handle = false;

        errdefer self.requestShutdown();

        var addr: uv.sockaddr_in = undefined;
        var r: c_int = undefined;

        const c_host = std.cstr.addNullByte(rt.alloc, host) catch unreachable;
        defer rt.alloc.free(c_host);
        _ = uv.uv_ip4_addr(c_host, port, &addr);

        r = uv.uv_tcp_bind(&self.listen_handle, @ptrCast(*uv.sockaddr, &addr), 0);
        if (r != 0) {
            log.debug("uv_tcp_bind: {s}", .{uv.uv_strerror(r)});
            return error.SocketAddrBind;
        }

        r = uv.uv_listen(@ptrCast(*uv.uv_stream_t, &self.listen_handle), 128, HttpServer.onAccept);
        if (r != 0) {
            log.debug("uv_listen: {s}", .{uv.uv_strerror(r)});
            return error.ListenError;
        }

        rt.num_uv_handles += 1;
    }

    /// Default H2O startup for both HTTP/HTTPS
    fn startH2O(self: *Self) void {
        h2o.h2o_config_init(&self.config);
        // H2O already has proper behavior for resending GOAWAY after 1 second.
        // If this is greater than 0 it will be an additional timeout to force close remaining connections.
        // Have not seen any need for this yet, so turn it off.
        self.config.http2.graceful_shutdown_timeout = 0;

        self.hostconf = h2o.h2o_config_register_host(&self.config, h2o.h2o_iovec_init("default", "default".len), 65535);
        h2o.h2o_context_init(&self.ctx, self.rt.uv_loop, &self.config);

        self.accept_ctx = .{
            .ctx = &self.ctx,
            .hosts = self.config.hosts,
            .ssl_ctx = null,
            .http2_origin_frame = null,
            .expect_proxy_line = 0,
            .libmemcached_receiver = null,
        };

        _ = self.registerHandler("/", HttpServer.defaultHandler);

        self.h2o_started = true;
    }

    /// If an error occurs during startup, the server will request shutdown and be in a closing state.
    /// "closed" should be checked later on to ensure everything was cleaned up.
    pub fn startHttp(self: *Self, host: []const u8, port: u16) !void {
        try self.startListener(host, port);
        self.startH2O();
    }

    pub fn startHttps(self: *Self, host: []const u8, port: u16, cert_path: []const u8, key_path: []const u8) !void {
        try self.startListener(host, port);
        self.startH2O();

        self.https = true;
        self.accept_ctx.ssl_ctx = ssl.SSL_CTX_new(ssl.TLS_server_method());

        _ = ssl.initLibrary();
        _ = ssl.addAllAlgorithms();

        // Disable deprecated or vulnerable protocols.
        _ = ssl.SSL_CTX_set_options(self.accept_ctx.ssl_ctx, ssl.SSL_OP_NO_SSLv2);
        _ = ssl.SSL_CTX_set_options(self.accept_ctx.ssl_ctx, ssl.SSL_OP_NO_SSLv3);
        _ = ssl.SSL_CTX_set_options(self.accept_ctx.ssl_ctx, ssl.SSL_OP_NO_TLSv1);
        _ = ssl.SSL_CTX_set_options(self.accept_ctx.ssl_ctx, ssl.SSL_OP_NO_DTLSv1);
        _ = ssl.SSL_CTX_set_options(self.accept_ctx.ssl_ctx, ssl.SSL_OP_NO_TLSv1_1);

        errdefer self.requestShutdown();

        const rt = self.rt;
        const c_cert = std.cstr.addNullByte(rt.alloc, cert_path) catch unreachable;
        defer rt.alloc.free(c_cert);
        const c_key = std.cstr.addNullByte(rt.alloc, key_path) catch unreachable;
        defer rt.alloc.free(c_key);

        if (ssl.SSL_CTX_use_certificate_chain_file(self.accept_ctx.ssl_ctx, c_cert) != 1) {
            log.debug("Failed to load server certificate file: {s}", .{cert_path});
            return error.UseCertificate;
        }

        if (ssl.SSL_CTX_use_PrivateKey_file(self.accept_ctx.ssl_ctx, c_key, ssl.SSL_FILETYPE_PEM) != 1) {
            log.debug("Failed to load private key file: {s}", .{key_path});
            return error.UsePrivateKey;
        }

        // Ciphers for TLS 1.2 and below.
        {
            const ciphers = "DEFAULT:!MD5:!DSS:!DES:!RC4:!RC2:!SEED:!IDEA:!NULL:!ADH:!EXP:!SRP:!PSK";
            if (ssl.SSL_CTX_set_cipher_list(self.accept_ctx.ssl_ctx, ciphers) != 1) {
                log.debug("Failed to set ciphers: {s}\n", .{ciphers});
                return error.UseCiphers;
            }
        }

        // Ciphers for TLS 1.3
        {
            const ciphers = "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256";
            if (ssl.SSL_CTX_set_ciphersuites(self.accept_ctx.ssl_ctx, ciphers) != 1) {
                log.debug("Failed to set ciphers: {s}\n", .{ciphers});
                return error.UseCiphers;
            }
        }

        // Accept requests using ALPN.
        h2o.h2o_ssl_register_alpn_protocols(self.accept_ctx.ssl_ctx.?, h2o.h2o_get_alpn_protocols());
    }

    fn onCloseListenHandle(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const handle = @ptrCast(*uv.uv_tcp_t, ptr);
        const self = stdx.mem.ptrCastAlign(*Self, handle.data.?);
        // We don't need to free the handle since it's embedded into server struct.
        self.closed_listen_handle = true;
        self.updateClosed();
    }

    pub fn setHandler(res: ThisResource(*Self), handler: v8.Function) void {
        const self = res.ptr;
        self.js_handler = self.rt.isolate.initPersistent(v8.Function, handler);
    }

    pub fn requestClose(res: ThisResource(*Self)) void {
        const self = res.ptr;
        self.requestShutdown();
    }

    // The aim is to provide a clean way to shutdown in a promise which resolves when closed and freed.
    // Requests shutdown and adds a task that continually watches the closed variable.
    pub fn closeAsync(res: ThisResource(*Self)) v8.Promise {
        const self = res.ptr;
        self.requestShutdown();

        const rt = self.rt;
        const iso = rt.isolate;

        const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));
        const promise = resolver.inner.getPromise();
        const promise_id = rt.promises.add(resolver) catch unreachable;

        const S = struct {
            const ServerCloseTimer = struct {
                super: uv.uv_timer_t,
                promise_id: PromiseId,
                resource_id: ResourceId,
            };

            fn onCheckServerClose(ptr: [*c]uv.uv_timer_t) callconv(.C) void {
                const timer = @ptrCast(*ServerCloseTimer, ptr);
                const server = stdx.mem.ptrCastAlign(*Self, timer.super.data.?);
                if (!server.closed) {
                    return;
                }
                uv.uv_close(@ptrCast(*uv.uv_handle_t, ptr), onCloseTimer);
            }

            fn onCloseTimer(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
                const timer = @ptrCast(*ServerCloseTimer, ptr);
                const server = stdx.mem.ptrCastAlign(*Self, timer.super.data);

                // Save rt before we free server.
                const _rt = server.rt;

                // At this point there should be nothing that references HttpServer, so destroy the resource.
                _rt.destroyResource(_rt.generic_resource_list, timer.resource_id);

                runtime.resolvePromise(_rt, timer.promise_id, _rt.js_true);

                _rt.alloc.destroy(timer);
            }
        };

        const timer = rt.alloc.create(S.ServerCloseTimer) catch unreachable;
        timer.super.data = self;
        timer.promise_id = promise_id;
        _ = uv.uv_timer_init(self.rt.uv_loop, &timer.super);
        // Check every 200ms.
        _ = uv.uv_timer_start(&timer.super, S.onCheckServerClose, 200, 200);

        return promise;
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
            if (req.proceed_req == null) {
                // Already received request body.
                if (req.entity.len > 0) {
                const backing_store = v8.BackingStore.init(iso, req.entity.len);
                if (backing_store.getData()) |data| {
                    const buf = @ptrCast([*]u8, data);
                    std.mem.copy(u8, buf[0..req.entity.len], req.entity.base[0..req.entity.len]);
                }
                const shared = backing_store.toSharedPtr();
                const array_buffer = v8.ArrayBuffer.initWithBackingStore(iso, &shared);
                const uint8_arr = v8.Uint8Array.init(array_buffer, 0, req.entity.len);
                _ = js_req.setValue(ctx, iso.initStringUtf8("body"), uint8_arr);
                }
            } else unreachable;

            ResponseWriter.cur_req = req;
            ResponseWriter.called_send = false;
            ResponseWriter.cur_generator = &self.generator;

            const writer = self.rt.http_response_writer.initInstance(ctx);
            if (handler.inner.call(ctx, self.rt.js_undefined, &.{ js_req.toValue(), writer.toValue() })) |res| {
                // If user code returned true or called send, report as handled.
                if (res.toBool(iso) or ResponseWriter.called_send) {
                    return 0;
                }
            } else {
                // Js exception, start shutdown.
                self.requestShutdown();
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
            self.updateClosed();
        } else {
            unreachable;
        }
    }

    fn updateClosed(self: *Self) void {
        if (self.closed) {
            return;
        }
        if (self.socket_handles > 0) {
            return;
        }
        if (!self.closed_listen_handle) {
            return;
        }
        self.rt.num_uv_handles -= 1;
        self.closed = true;
    }

    fn onUvHandleClose(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const kind = uv.uv_handle_get_type(ptr);
        if (kind == uv.UV_TCP) {
            const handle = @ptrCast(*uv.uv_tcp_t, ptr);
            const self = stdx.mem.ptrCastAlign(*HttpServer, handle.data);
            self.rt.alloc.destroy(handle);
        } else {
            unreachable;
        }
    }

    pub fn requestShutdown(self: *Self) void {
        if (self.closing) {
            return;
        }
        if (self.h2o_started) {
            // Once shutdown is requested, h2o won't be accepting more connections
            // and will start to gracefully shutdown existing connections.
            // After a small delay, a timeout will force any connections to close.
            // We track number of socket handles and once there are no more, we mark this done in updateClosed.
            h2o.h2o_context_request_shutdown(&self.ctx);

            // Interrupt uv poller to consider any graceful shutdown timeouts set by h2o. eg. http2 resend GOAWAY
            _ = uv.uv_async_send(self.rt.uv_dummy_async);
        }

        if (!self.closed_listen_handle) {
            uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.listen_handle), HttpServer.onCloseListenHandle);
        }

        self.closing = true;
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
    pub var called_send: bool = false;

    pub fn setStatus(status_code: u32) void {
        if (cur_req) |req| {
            req.res.status = @intCast(c_int, status_code);
            req.res.reason = getStatusReason(status_code).ptr;
        }
    }

    pub fn setHeader(key: []const u8, value: []const u8) void {
        if (cur_req) |req| {
            // h2o doesn't dupe the value by default.
            var value_slice = h2o.h2o_strdup(&req.pool, value.ptr, value.len);
            _ = h2o.h2o_set_header_by_str(&req.pool, &req.res.headers, key.ptr, key.len, 1, value_slice.base, value_slice.len, 1);
        }
    }

    pub fn send(text: []const u8) void {
        if (called_send) return;
        if (cur_req) |req| {
            h2o.h2o_start_response(req, cur_generator);

            // Send can be async so dupe.
            var slice = h2o.h2o_strdup(&req.pool, text.ptr, text.len);
            h2o.h2o_send(req, &slice, 1, h2o.H2O_SEND_STATE_FINAL);
            called_send = true;
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