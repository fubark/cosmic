const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const uv = @import("uv");
const h2o = @import("h2o");
const ssl = @import("openssl");
const v8 = @import("v8");

const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const ThisResource = runtime.ThisResource;
const PromiseId = runtime.PromiseId;
const ResourceId = runtime.ResourceId;
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

    on_shutdown_cb: ?stdx.Callback(*anyopaque, *Self),

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
            .on_shutdown_cb = null,
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
    }

    /// Default H2O startup for both HTTP/HTTPS
    fn startH2O(self: *Self) void {
        h2o.h2o_config_init(&self.config);
        // H2O already has proper behavior for resending GOAWAY after 1 second.
        // If this is greater than 0 it will be an additional timeout to force close remaining connections.
        // Have not seen any need for this yet, so turn it off.
        self.config.http2.graceful_shutdown_timeout = 0;

        // Zig in release-safe has trouble with string literals if they aren't used in zig code, eg. if they are just being passed into C functions.
        // First noticed on windows build.
        var buf: [100]u8 = undefined;
        const default = std.fmt.bufPrint(&buf, "default", .{}) catch unreachable;

        self.hostconf = h2o.h2o_config_register_host(&self.config, h2o.h2o_iovec_init(default), 65535);
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
                    const body_buf = runtime.Uint8Array{ .buf = req.entity.base[0..req.entity.len] };
                    const js_val = self.rt.getJsValue(body_buf);
                    _ = js_req.setValue(ctx, iso.initStringUtf8("body"), js_val);
                } else {
                    _ = js_req.setValue(ctx, iso.initStringUtf8("body"), self.rt.js_null);
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
        // log.debug("on accept", .{});
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
        self.closed = true;
        // Even though there aren't any more connections or a listening port,
        // h2o's graceful timeout might still be active.
        // Make sure to close that since being in a closed state means this memory could be freed,
        // and the timeout could fire later and reference undefined memory.
        if (self.ctx.globalconf.http2.callbacks.request_shutdown != null) {
            if (self.ctx.http2._graceful_shutdown_timeout.is_linked == 1) {
                h2o.h2o_timer_unlink(&self.ctx.http2._graceful_shutdown_timeout);
            }
        }
        // h2o context and config also need to be deinited.
        h2o.h2o_context_dispose(&self.ctx);
        h2o.h2o_config_dispose(&self.config);

        if (self.on_shutdown_cb) |cb| {
            cb.call(self);
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
            const res = uv.uv_async_send(self.rt.uv_dummy_async);
            uv.assertNoError(res);
        }

        if (!self.closed_listen_handle) {
            // NOTE: libuv does not start listeners with reuseaddr on windows since it behaves differently and isn't desirable.
            // This means the listening port may still be in a TIME_WAIT state for some time after it was "shutdown". 
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

    pub fn sendBytes(arr: runtime.Uint8Array) void {
        if (called_send) return;
        if (cur_req) |req| {
            h2o.h2o_start_response(req, cur_generator);

            // Send can be async so dupe.
            var slice = h2o.h2o_strdup(&req.pool, arr.buf.ptr, arr.buf.len);
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
