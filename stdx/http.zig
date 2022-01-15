const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");
const curl = @import("curl");
const uv = @import("uv");
const Curl = curl.Curl;
const CurlM = curl.CurlM;
const CurlSH = curl.CurlSH;
const log = std.log.scoped(.http);

// NOTES:
// Debugging tls handshake: "openssl s_client -connect 127.0.0.1:3000" Useful options: -prexit -debug -msg 
// Curl also has tracing: "curl --trace /dev/stdout https://127.0.0.1:3000"
// Generating a self-signed localhost certificate: "openssl req -x509 -days 3650 -out localhost.crt -keyout localhost.key -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <( printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")"
// Testing http2 upgrade: "curl http://127.0.0.1:3000/hello -v --http2"
// Testing http2 direct: "curl http://127.0.0.1:3000/hello -v --http2-prior-knowledge"

// Dedicated curl handle for synchronous requests. Reuse for connection pool.
var curl_h: Curl = undefined;

// Async curl handle. curl_multi let's us set up async with uv.
var share: CurlSH = undefined;
var curlm: CurlM = undefined;
var curlm_alloc: std.mem.Allocator = undefined;
pub var curlm_uvloop: *uv.uv_loop_t = undefined; // This is set later when uv loop is available.
// Creating new timers currently does not wake UvPoller. Need to use the interrupt handle.
pub var uv_interrupt: *uv.uv_async_t = undefined;
// Only one timer is needed for the curlm handle.
var timer: uv.uv_timer_t = undefined;
var timer_inited = false;

pub fn init(alloc: std.mem.Allocator) void {
    if (!curl.inited) {
        @panic("expected curl to be inited");
    }
    curl_h = Curl.init();

    // TODO: Look into what scenarios share should be used.
    share = CurlSH.init();
    _ = share.setOption(curl.CURLSHOPT_SHARE, curl.CURL_LOCK_DATA_SSL_SESSION);
    _ = share.setOption(curl.CURLSHOPT_SHARE, curl.CURL_LOCK_DATA_CONNECT);

    curlm = CurlM.init();
    _ = curlm.setOption(curl.CURLMOPT_MAX_TOTAL_CONNECTIONS, @intCast(c_long, 0));
    // Prefer reusing existing http2 connections.
    _ = curlm.setOption(curl.CURLMOPT_PIPELINING, curl.CURLPIPE_MULTIPLEX);
    _ = curlm.setOption(curl.CURLMOPT_MAX_CONCURRENT_STREAMS, @intCast(c_long, 1000));
    _ = curlm.setOption(curl.CURLMOPT_SOCKETFUNCTION, onCurlSocket);
    _ = curlm.setOption(curl.CURLMOPT_TIMERFUNCTION, onCurlSetTimer);
    curlm_alloc = alloc;
}

pub fn deinit() void {
    curl_h.deinit();
    curlm.deinit();
    share.deinit();
}

pub const RequestMethod = enum {
    Head,
    Get,
    Post,
    Put,
    Delete,
};

pub const ContentType = enum {
    Json,
    FormData,
};

pub const RequestOptions = struct {
    method: RequestMethod = .Get,
    keep_connection: bool = false,

    content_type: ?ContentType = null,
    body: ?[]const u8 = null,

    /// In seconds. 0 timeout = no timeout
    timeout: u32 = 30,

    headers: ?std.StringHashMap([]const u8) = null,
};

const IndexSlice = struct {
    start: usize,
    end: usize,
};

pub const Response = struct {
    status_code: u32,

    // Allocated memory.
    headers: []const Header,
    header: []const u8,
    body: []const u8,

    pub fn deinit(self: Response, alloc: std.mem.Allocator) void {
        alloc.free(self.headers);
        alloc.free(self.header);
        alloc.free(self.body);
    }
};

pub const Header = struct {
    key: IndexSlice,
    value: IndexSlice,
};

fn onUvTimer(ptr: [*c]uv.uv_timer_t) callconv(.C) void {
    // log.debug("on uv timer", .{});
    _ = ptr;

    // socketAction can spend a lot of time doing synchronous ssl handshake. lib/multi.c: protocol_connect -> ossl_connect_nonblocking
    // Curl can optimize by reusing connections and ssl sessions but if a new request handle was started too quickly it will be a
    // cache miss and continue doing a fresh connection. Setting CURLOPT_PIPEWAIT on each request handle addresses this issue.
    var running_handles: c_int = undefined;
    const res = curlm.socketAction(curl.CURL_SOCKET_TIMEOUT, 0, &running_handles);
    if (res != curl.CURLM_OK) {
        log.debug("socketAction: {s}", .{CurlM.strerror(res)});
        unreachable;
    }
    checkDone();
}

fn onCurlSetTimer(cm: *curl.CURLM, timeout_ms: c_long, user_ptr: *anyopaque) callconv(.C) c_int {
    // log.debug("set timer {}", .{timeout_ms});
    _ = user_ptr;
    _ = cm;
    if (timeout_ms == -1) {
        _ = uv.uv_timer_stop(&timer);
    } else {
        _ = uv.uv_timer_start(&timer, onUvTimer, @intCast(u64, timeout_ms), 0);
    }
    return 0;
}

// TODO: deinit handle on error.
const AsyncRequestHandle = struct {
    const Self = @This();

    poll: uv.uv_poll_t,
    polling_readable: bool,
    polling_writable: bool,
    sock_fd: curl.curl_socket_t,
    alloc: std.mem.Allocator,
    ch: Curl,

    // Requests that are reusing the same connection/sock_fd are linked together.
    // When the connection is finally freed, all of the child requests can be cleaned up together.
    next_child_req: ?*AsyncRequestHandle,
    attached_to_parent: bool,

    status_code: u32,
    header_ctx: HeaderContext,
    buf: std.ArrayList(u8),

    // Closure of callback.
    cb_ctx: *anyopaque,
    cb_ctx_size: u32,
    success_cb: fn (ctx: *anyopaque, Response) void,

    fn finish(self: *Self) void {
        const resp = Response{
            .status_code = self.status_code,
            .headers = self.header_ctx.headers_buf.toOwnedSlice(),
            .header = self.header_ctx.header_data_buf.toOwnedSlice(),
            .body = self.buf.toOwnedSlice(),
        };
        self.success_cb(self.cb_ctx, resp);
    }

    fn deinit(self: Self) void {
        _ = curlm.removeHandle(self.ch);
        self.ch.deinit();
        self.alloc.free(@ptrCast([*]u8, self.cb_ctx)[0..self.cb_ctx_size]);
    }

    fn destroyRecurse(self: *Self) void {
        if (self.next_child_req) |next| {
            next.destroyRecurse();
        }
        self.alloc.destroy(self);
    }
};

fn onUvPolled(ptr: [*c]uv.uv_poll_t, status: c_int, events: c_int) callconv(.C) void {
    // log.debug("uv polled {} {}", .{status, events});
    if (status != 0) {
        // flags = CURL_CSELECT_ERR;
        log.debug("uv_poll_cb: {s}", .{uv.uv_strerror(status)});
        unreachable;
    }

    var flags: c_int = 0;
 
    if (events & uv.UV_READABLE > 0) {
        flags |= curl.CURL_CSELECT_IN;
    }
    if (events & uv.UV_WRITABLE > 0) {
        flags |= curl.CURL_CSELECT_OUT;
    }
    if (flags == 0) {
        unreachable;
    }
 
    const req = @ptrCast(*AsyncRequestHandle, ptr);
    var running_handles: c_int = undefined;
    const res = curlm.socketAction(req.sock_fd, flags, &running_handles);
    if (res != curl.CURLM_OK) {
        log.debug("socketAction: {s}", .{CurlM.strerror(res)});
        unreachable;
    }
    checkDone();
}

fn onUvClosePoll(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
    // log.debug("uv close poll", .{});
    // The final destroy on all chained requests.
    const req = @ptrCast(*AsyncRequestHandle, ptr);
    req.destroyRecurse();
}

fn onCurlSocket(_h: *curl.CURL, sock_fd: curl.curl_socket_t, action: c_int, user_ptr: *anyopaque, socket_ptr: ?*anyopaque) callconv(.C) c_int {
    // log.debug("curl socket {} {} {*}", .{sock_fd, action, socket_ptr});
    _ = user_ptr;

    const h = Curl{ .handle = _h };
    var ptr: *anyopaque = undefined;

    _ = h.getInfo(curl.CURLINFO_PRIVATE, &ptr);
    const req = stdx.mem.ptrCastAlign(*AsyncRequestHandle, ptr);

    const S = struct {
        fn updateRequest(_sock_fd: curl.curl_socket_t, _req: *AsyncRequestHandle, _socket_ptr: ?*anyopaque) *AsyncRequestHandle {
            if (_socket_ptr == null) {
                _req.sock_fd = _sock_fd;
                const res = uv.uv_poll_init_socket(curlm_uvloop, &_req.poll, _sock_fd);
                if (res != 0) {
                    log.debug("uv_poll_init_socket: {s}", .{uv.uv_strerror(res)});
                    unreachable;
                }
                // We use socket_ptr to associate a sock_fd to the first request that started it.
                // This indicates whether we need to initialize a uv poll handle.
                // It's also needed for HTTP2 requests that are piggy backing off of the same connection from another request.
                // In those cases, we don't want to start the in/out polls again.
                _ = curlm.assign(_sock_fd, _req);
                return _req;
            } else {
                const orig_req = stdx.mem.ptrCastAlign(*AsyncRequestHandle, _socket_ptr.?);
                // Attach request to first req.
                if (!_req.attached_to_parent and _req != orig_req) {
                    const next = orig_req.next_child_req;
                    orig_req.next_child_req = _req;
                    _req.next_child_req = next;
                    _req.attached_to_parent = true;
                }
                return orig_req;
            }
        }
    };
    switch (action) {
        curl.CURL_POLL_IN => {
            const orig_req = S.updateRequest(sock_fd, req, socket_ptr);
            if (!orig_req.polling_readable) {
                const res = uv.uv_poll_start(&req.poll, uv.UV_READABLE, onUvPolled);
                if (res != 0) {
                    log.debug("uv_poll_start: {s}", .{uv.uv_strerror(res)});
                    unreachable;
                }
                orig_req.polling_readable = true;
            }
        },
        curl.CURL_POLL_OUT => {
            const orig_req = S.updateRequest(sock_fd, req, socket_ptr);
            if (orig_req.polling_writable) {
                const res = uv.uv_poll_start(&req.poll, uv.UV_WRITABLE, onUvPolled);
                if (res != 0) {
                    log.debug("uv_poll_start: {s}", .{uv.uv_strerror(res)});
                    unreachable;
                }
                orig_req.polling_writable = true;
            }
        },
        curl.CURL_POLL_INOUT => {
            const orig_req = S.updateRequest(sock_fd, req, socket_ptr);
            if (!orig_req.polling_readable or !orig_req.polling_writable) {
                // Update event mask.
                const res = uv.uv_poll_start(&req.poll, uv.UV_WRITABLE | uv.UV_READABLE, onUvPolled);
                if (res != 0) {
                    log.debug("uv_poll_start: {s}", .{uv.uv_strerror(res)});
                    unreachable;
                }
                orig_req.polling_readable = true;
                orig_req.polling_writable = true;
            }
        },
        curl.CURL_POLL_REMOVE => {
            // log.debug("closing {}", .{sock_fd});

            if (socket_ptr) |_ptr| {
                const orig_req = stdx.mem.ptrCastAlign(*AsyncRequestHandle, _ptr);

                const res = uv.uv_poll_stop(&orig_req.poll);
                if (res != 0) {
                    log.debug("uv_poll_stop: {s}", .{uv.uv_strerror(res)});
                    unreachable;
                }

                uv.uv_close(@ptrCast(*uv.uv_handle_t, &orig_req.poll), onUvClosePoll);
                _ = curlm.assign(sock_fd, null);
            } else unreachable;
        },
        else => unreachable,
    }
    return 0;
}

const HeaderContext = struct {
    headers_buf: std.ArrayList(Header),
    header_data_buf: std.ArrayList(u8),
};

fn checkDone() void {
    var num_remaining_msgs: c_int = 1;
    while (num_remaining_msgs > 0) {
        var mb_msg = curlm.infoRead(&num_remaining_msgs);
        if (mb_msg) |info| {
            switch (info.msg) {
                curl.CURLMSG_DONE => {
                    // [curl] WARNING: The data the returned pointer points to will not survive calling
                    // curl_multi_cleanup, curl_multi_remove_handle or curl_easy_cleanup.
                    const ch = Curl{ .handle = info.easy_handle.? };

                    var ptr: *anyopaque = undefined;
                    _ = ch.getInfo(curl.CURLINFO_PRIVATE, &ptr);
                    const req = stdx.mem.ptrCastAlign(*AsyncRequestHandle, ptr);

                    // Get status code.
                    var http_code: u64 = 0;
                    _ = ch.getInfo(curl.CURLINFO_RESPONSE_CODE, &http_code);
                    req.status_code = @intCast(u32, http_code);

                    // Once checkDone reports a request is done,
                    // invoke the success cb and free just the curl resources for the request.
                    // The final uv close callback will free all the chained AsyncRequestHandles.
                    req.finish();
                    req.deinit();
                },
                else => {
                    unreachable;
                }
            }
        }
    }
}

pub fn requestAsync(alloc: std.mem.Allocator, url: []const u8, opts: RequestOptions, _ctx: anytype, success_cb: fn (ptr: *anyopaque, Response) void) !void {
    const S = struct {
        fn writeBody(read_buf: [*]u8, item_size: usize, nitems: usize, user_data: *std.ArrayList(u8)) callconv(.C) usize {
            const write_buf = user_data;
            const read_size = item_size * nitems;
            write_buf.appendSlice(read_buf[0..read_size]) catch unreachable;
            return read_size;
        }

        fn writeHeader(read_buf: [*]u8, item_size: usize, nitems: usize, ctx: *HeaderContext) usize {
            const read_size = item_size * nitems;
            const header = read_buf[0..read_size];
            const start = ctx.header_data_buf.items.len;
            ctx.header_data_buf.appendSlice(header) catch unreachable;
            if (std.mem.indexOfScalar(u8, header, ':')) |idx| {
                const val = std.mem.trim(u8, ctx.header_data_buf.items[start+idx+1..], " \r\n");
                const val_start = @ptrToInt(val.ptr) - @ptrToInt(ctx.header_data_buf.items.ptr);
                ctx.headers_buf.append(.{
                    .key = .{ .start = start, .end = start + idx },
                    .value = .{ .start = val_start, .end = val_start + val.len },
                }) catch unreachable;
            }
            return read_size;
        }
    };

    var c_url = std.cstr.addNullByte(alloc, url) catch unreachable;
    defer alloc.free(c_url);
    
    // Currently we create a new CURL handle per request.
    const ch = Curl.init();

    var header_list: ?*curl.curl_slist = null;
    defer curl.curl_slist_free_all(header_list);

    try setCurlOptions(alloc, ch, c_url, &header_list, opts);

    _ = ch.setOption(curl.CURLOPT_WRITEFUNCTION, S.writeBody);
    _ = ch.setOption(curl.CURLOPT_HEADERFUNCTION, S.writeHeader);

    const ctx = alloc.create(@TypeOf(_ctx)) catch unreachable;
    ctx.* = _ctx;

    var req = alloc.create(AsyncRequestHandle) catch unreachable;
    req.* = .{
        .poll = undefined,
        .alloc = alloc,
        .polling_readable = false,
        .polling_writable = false,
        .ch = ch,
        .sock_fd = undefined,

        .next_child_req = null,
        .attached_to_parent = false,

        .cb_ctx = ctx,
        .cb_ctx_size = @sizeOf(@TypeOf(_ctx)),
        .success_cb = success_cb,

        .status_code = undefined,
        .header_ctx = .{
            .headers_buf = std.ArrayList(Header).initCapacity(alloc, 10) catch unreachable,
            .header_data_buf = std.ArrayList(u8).initCapacity(alloc, 5e2) catch unreachable,
        },
        .buf = std.ArrayList(u8).initCapacity(alloc, 4e3) catch unreachable,
    };
    _ = ch.setOption(curl.CURLOPT_PRIVATE, req);
    _ = ch.setOption(curl.CURLOPT_WRITEDATA, &req.buf);
    _ = ch.setOption(curl.CURLOPT_HEADERDATA, &req.header_ctx);

    // If two requests start concurrently, prefer waiting for one to finish connecting to reuse the same connection. For HTTP2.
    _ = ch.setOption(curl.CURLOPT_PIPEWAIT, @intCast(c_long, 1));
    // _ = ch.setOption(curl.CURLOPT_SHARE, &share);
    // _ = ch.setOption(curl.CURLOPT_NOSIGNAL, @intCast(c_long, 1));

    // _ = ch.setOption(curl.CURLOPT_VERBOSE, @intCast(c_int, 1));

    // Only one timer is needed for all requests.
    if (!timer_inited) {
        _ = uv.uv_timer_init(curlm_uvloop, &timer);
        _ = uv.uv_async_send(uv_interrupt);
        timer_inited = true;
    }

    // Add handle starts the request and triggers onCurlSetTimer synchronously.
    // Subsequent socketAction calls also synchronously call onCurlSetTimer and onCurlSocket, however if two sockets are ready
    // onCurlSocket will be called twice so the only way to attach a ctx is through the CURL handle's private opt.
    const res = curlm.addHandle(req.ch);
    if (res != curl.CURLE_OK) {
        return error.RequestFailed;
    }
    // log.debug("added request handle", .{});

    // For debugging with no uv poller thread:
    // _ = uv.uv_run(curlm_uvloop, uv.UV_RUN_DEFAULT);

    var http_code: u64 = 0;
    _ = ch.getInfo(curl.CURLINFO_RESPONSE_CODE, &http_code);
}

pub fn request(alloc: std.mem.Allocator, url: []const u8, opts: RequestOptions) !Response {
    const S = struct {
        fn writeBody(read_buf: [*]u8, item_size: usize, nitems: usize, user_data: *std.ArrayList(u8)) callconv(.C) usize {
            const write_buf = user_data;
            const read_size = item_size * nitems;
            write_buf.appendSlice(read_buf[0..read_size]) catch unreachable;
            return read_size;
        }

        fn writeHeader(read_buf: [*]u8, item_size: usize, nitems: usize, ctx: *HeaderContext) usize {
            const read_size = item_size * nitems;
            const header = read_buf[0..read_size];
            const start = ctx.header_data_buf.items.len;
            ctx.header_data_buf.appendSlice(header) catch unreachable;
            if (std.mem.indexOfScalar(u8, header, ':')) |idx| {
                const val = std.mem.trim(u8, ctx.header_data_buf.items[start+idx+1..], " \r\n");
                const val_start = @ptrToInt(val.ptr) - @ptrToInt(ctx.header_data_buf.items.ptr);
                ctx.headers_buf.append(.{
                    .key = .{ .start = start, .end = start + idx },
                    .value = .{ .start = val_start, .end = val_start + val.len },
                }) catch unreachable;
            }
            return read_size;
        }
    };

    var header_ctx = HeaderContext{
        .headers_buf = std.ArrayList(Header).initCapacity(alloc, 10) catch unreachable,
        .header_data_buf = std.ArrayList(u8).initCapacity(alloc, 5e2) catch unreachable,
    };
    defer {
        header_ctx.headers_buf.deinit();
        header_ctx.header_data_buf.deinit();
    }

    var buf = std.ArrayList(u8).initCapacity(alloc, 4e3) catch unreachable;
    defer buf.deinit();

    var c_url = std.cstr.addNullByte(alloc, url) catch unreachable;
    defer alloc.free(c_url);

    var header_list: ?*curl.curl_slist = null;
    defer curl.curl_slist_free_all(header_list);
    
    try setCurlOptions(alloc, curl_h, c_url, &header_list, opts);

    _ = curl_h.setOption(curl.CURLOPT_WRITEFUNCTION, S.writeBody);
    _ = curl_h.setOption(curl.CURLOPT_WRITEDATA, &buf);
    _ = curl_h.setOption(curl.CURLOPT_HEADERFUNCTION, S.writeHeader);
    _ = curl_h.setOption(curl.CURLOPT_HEADERDATA, &header_ctx);

    // _ = curl_h.setOption(curl.CURLOPT_VERBOSE, @intCast(c_int, 1));
    
    const res = curl_h.perform();
    if (res != curl.CURLE_OK) {
        // log.debug("Request failed: {s}", .{Curl.getStrError(res)});
        return error.RequestFailed;
    }

    var http_code: u64 = 0;
    _ = curl_h.getInfo(curl.CURLINFO_RESPONSE_CODE, &http_code);

    return Response{
        .status_code = @intCast(u32, http_code),
        .headers = header_ctx.headers_buf.toOwnedSlice(),
        .header = header_ctx.header_data_buf.toOwnedSlice(),
        .body = buf.toOwnedSlice(),
    };
}

fn setCurlOptions(alloc: std.mem.Allocator, ch: Curl, url: [:0]const u8, header_list: *?*curl.curl_slist, opts: RequestOptions) !void {
    _ = ch.setOption(curl.CURLOPT_URL, url.ptr);
    _ = ch.setOption(curl.CURLOPT_SSL_VERIFYPEER, @intCast(c_long, 1));
    _ = ch.setOption(curl.CURLOPT_SSL_VERIFYHOST, @intCast(c_long, 1));
    if (builtin.os.tag == .linux) {
        _ = ch.setOption(curl.CURLOPT_CAINFO, "/etc/ssl/certs/ca-certificates.crt");
        _ = ch.setOption(curl.CURLOPT_CAPATH, "/etc/ssl/certs");
    }
    _ = ch.setOption(curl.CURLOPT_TIMEOUT, opts.timeout);
    _ = ch.setOption(curl.CURLOPT_ACCEPT_ENCODING, "gzip, deflate, br");
    if (opts.keep_connection) {
        _ = ch.setOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 0));
    } else {
        _ = ch.setOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 1));
    }
    // HTTP2 is far more efficient since curl has deprecated HTTP1 pipelining. (Must have built curl with nghttp2)
    _ = ch.setOption(curl.CURLOPT_HTTP_VERSION, curl.CURL_HTTP_VERSION_2_0);
    switch (opts.method) {
        .Get => _ = ch.setOption(curl.CURLOPT_CUSTOMREQUEST, "GET"),
        .Post => _ = ch.setOption(curl.CURLOPT_CUSTOMREQUEST, "POST"),
        else => return error.UnsupportedMethod,
    }

    if (opts.content_type) |content_type| {
        switch (content_type) {
            .Json => header_list.* = curl.curl_slist_append(header_list.*, "content-type: application/json"),
            .FormData => header_list.* = curl.curl_slist_append(header_list.*, "content-type: application/x-www-form-urlencoded"),
        }
    }

    // Custom headers.
    if (opts.headers) |headers| {
        var iter = headers.iterator();
        while (iter.next()) |entry| {
            const c_str = try std.fmt.allocPrint(alloc, "{s}: {s}\\0", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer alloc.free(c_str);
            header_list.* = curl.curl_slist_append(header_list.*, c_str.ptr);
        }
    }

    _ = ch.setOption(curl.CURLOPT_HTTPHEADER, header_list.*);

    if (opts.body) |body| {
        _ = ch.setOption(curl.CURLOPT_POSTFIELDSIZE, @intCast(c_long, body.len));
        _ = ch.setOption(curl.CURLOPT_POSTFIELDS, body.ptr);
    }
}