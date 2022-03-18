const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");
const curl = @import("curl");
const uv = @import("uv");
const Curl = curl.Curl;
const CurlM = curl.CurlM;
const CurlSH = curl.CurlSH;
const log = stdx.log.scoped(.http);
const EventDispatcher = @import("events.zig").EventDispatcher;

// NOTES:
// Debugging tls handshake: "openssl s_client -connect 127.0.0.1:3000" Useful options: -prexit -debug -msg 
// Curl also has tracing: "curl --trace /dev/stdout https://127.0.0.1:3000"
// Generating a self-signed localhost certificate: "openssl req -x509 -days 3650 -out localhost.crt -keyout localhost.key -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <( printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")"
// Testing http2 upgrade: "curl http://127.0.0.1:3000/hello -v --http2"
// Testing http2 direct: "curl http://127.0.0.1:3000/hello -v --http2-prior-knowledge"
// It's useful to turn on CURLOPT_VERBOSE to see request/response along with log statements in this file.

// Dedicated curl handle for synchronous requests. Reuse for connection pool.
var curl_h: Curl = undefined;

// Async curl handle. curl_multi_socket let's us set up async with uv.
var share: CurlSH = undefined;
var curlm: CurlM = undefined;
pub var curlm_uvloop: *uv.uv_loop_t = undefined; // This is set later when uv loop is available.
pub var dispatcher: EventDispatcher = undefined;

// Only one timer is needed for the curlm handle.
var timer: uv.uv_timer_t = undefined;
var timer_inited = false;

// Use heap for handles since hashmap can grow.
var galloc: std.mem.Allocator = undefined;
var sock_handles: std.AutoHashMap(std.os.socket_t, *SockHandle) = undefined;

const SockHandle = struct {
    const Self = @This();

    // First field on purpose so we can pass into uv and cast back.
    poll: uv.uv_poll_t,
    polling_readable: bool,
    polling_writable: bool,

    sockfd: std.os.socket_t,

    // There is a bug (first noticed in MacOS) where CURL will call socketfunction
    // before opensocketfunction for internal use: https://github.com/curl/curl/issues/5747
    // Those onSocket callbacks should not affect perform logic on the user request,
    // but we should go through the motions of handling POLL_IN and then POLL_REMOVE in handleInternalSocket.
    // The "ready" field tells us when a sockfd is ready to perform logic on the user request.
    // onOpenSocket will set to ready to true and onCloseSocket will set it to false.
    ready: bool,

    // Whether the sockfd is closed and waiting to be cleaned up.
    sockfd_closed: bool,

    // Number of active requests using this sock fd.
    // This is heavily used by HTTP2 requests.
    // Once this becomes 0, start to close this handle.
    num_active_reqs: u32,

    /// During the uv closing state, onOpenSocket may request to reuse the same sockfd again.
    /// This flag will skip destroying the handle on uv closed callback.
    skip_destroy_on_uv_close: bool,

    pub fn init(self: *Self, sockfd: std.os.socket_t) void {
        self.* = .{
            .poll = undefined,
            .polling_readable = false,
            .polling_writable = false,
            .sockfd = sockfd,
            .ready = false,
            .num_active_reqs = 0,
            .sockfd_closed = false,
            .skip_destroy_on_uv_close = false,
        };
        const c_sockfd = if (builtin.os.tag == .windows) @ptrToInt(sockfd) else sockfd;
        const res = uv.uv_poll_init_socket(curlm_uvloop, &self.poll, c_sockfd);
        uv.assertNoError(res);
    }

    fn checkToDeinit(self: *Self) void {
        // Only start cleanup if sockfd was closed and there are no more active reqs.
        // Otherwise, let the last req trigger the cleanup.
        if (self.sockfd_closed and self.num_active_reqs == 0) {
            uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.poll), onUvClosePoll);
        }
    }
};

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
    _ = curlm.setOption(curl.CURLMOPT_SOCKETFUNCTION, onSocket);
    _ = curlm.setOption(curl.CURLMOPT_TIMERFUNCTION, onCurlSetTimer);
    // _ = curlm.setOption(curl.CURLMOPT_PUSHFUNCTION, onCurlPush);

    sock_handles = std.AutoHashMap(std.os.socket_t, *SockHandle).init(alloc);
    galloc = alloc;
}

pub fn deinit() void {
    curl_h.deinit();
    curlm.deinit();
    share.deinit();

    // Sock Handles that were only used for internal curl ops will still remain since
    // they wouldn't be picked up by closesocketfunction.
    var iter = sock_handles.valueIterator();
    while (iter.next()) |it| {
        if (!it.*.ready) {
            galloc.destroy(it.*);
        } else {
            @panic("Did not expect a user socket handle.");
        }
    }
    sock_handles.deinit();

    timer_inited = false;
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

    // If cert file is not provided, the default for the operating system will be used.
    cert_file: ?[]const u8 = null,
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

fn onOpenSocket(client_ptr: ?*anyopaque, purpose: curl.curlsocktype, addr: *curl.curl_sockaddr) callconv(.C) curl.curl_socket_t {
    _ = client_ptr;
    _ = purpose;
    // log.debug("onOpenSocket", .{});

    // This is what curl does by default.
    const sockfd = std.os.socket(@intCast(u32, addr.family), @intCast(u32, addr.socktype), @intCast(u32, addr.protocol)) catch {
        return curl.CURL_SOCKET_BAD;
    };
    // Get or create a new SockHandle.
    const entry = sock_handles.getOrPut(sockfd) catch unreachable;
    if (!entry.found_existing) {
        entry.value_ptr.* = galloc.create(SockHandle) catch unreachable;
        entry.value_ptr.*.init(sockfd);
    } else {
        if (entry.value_ptr.*.sockfd_closed) {
            // Since the handle still exists and the sockfd is in a closed state,
            // it means the uv_close on the poll hasn't finished yet. Finish the closing with a uv_run.
            // Set skip_destroy_on_uv_close so the uv_close callback doesn't remove the handle.
            entry.value_ptr.*.skip_destroy_on_uv_close = true;
            _ = uv.uv_run(curlm_uvloop, uv.UV_RUN_NOWAIT);
            // Reinit a closed sockfd handle.
            entry.value_ptr.*.init(sockfd);
        }
    }
    // Mark as ready, any onSocket callback from now on is related to the request.
    entry.value_ptr.*.ready = true;

    const c_sockfd = if (builtin.os.tag == .windows) @ptrToInt(sockfd) else sockfd;
    return c_sockfd;
}

fn onCloseSocket(client_ptr: ?*anyopaque, sockfd: curl.curl_socket_t) callconv(.C) c_int  {
    _ = client_ptr;
    // log.debug("onCloseSocket", .{});

    // Close the sockfd.
    const cross_sockfd = if (builtin.os.tag == .windows) @intToPtr(std.os.socket_t, sockfd) else sockfd;
    std.os.closeSocket(cross_sockfd);
    const sock_h = sock_handles.get(cross_sockfd).?;
    sock_h.sockfd_closed = true;
    sock_h.checkToDeinit();
    return 0;
}

fn onUvTimer(ptr: [*c]uv.uv_timer_t) callconv(.C) void {
    // log.debug("on uv timer", .{});
    _ = ptr;

    // socketAction can spend a lot of time doing synchronous ssl handshake. lib/multi.c: protocol_connect -> ossl_connect_nonblocking
    // Curl can optimize by reusing connections and ssl sessions but if a new request handle was started too quickly it will be a
    // cache miss and continue doing a fresh connection. Setting CURLOPT_PIPEWAIT on each request handle addresses this issue.
    var running_handles: c_int = undefined;
    const res = curlm.socketAction(curl.CURL_SOCKET_TIMEOUT, 0, &running_handles);
    CurlM.assertNoError(res);
    checkDone();
}

fn onCurlSetTimer(cm: *curl.CURLM, timeout_ms: c_long, user_ptr: *anyopaque) callconv(.C) c_int {
    // log.debug("set timer {}", .{timeout_ms});
    _ = user_ptr;
    _ = cm;
    if (timeout_ms == -1) {
        const res = uv.uv_timer_stop(&timer);
        uv.assertNoError(res);
    } else {
        dispatcher.startTimer(&timer, @intCast(u32, timeout_ms), onUvTimer);
    }
    return 0;
}

const AsyncRequestHandle = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    ch: Curl,

    attached_to_sockfd: bool,
    sock_fd: std.os.socket_t,

    status_code: u32,
    header_ctx: HeaderContext,
    buf: std.ArrayList(u8),

    // Closure of callback.
    // TODO: Don't own the callback context.
    cb_ctx: *anyopaque,
    cb_ctx_size: u32,
    success_cb: fn (ctx: *anyopaque, Response) void,
    failure_cb: fn (ctx: *anyopaque, err_code: u32) void,

    fn success(self: *Self) void {
        const resp = Response{
            .status_code = self.status_code,
            .headers = self.header_ctx.headers_buf.toOwnedSlice(),
            .header = self.header_ctx.header_data_buf.toOwnedSlice(),
            .body = self.buf.toOwnedSlice(),
        };
        self.success_cb(self.cb_ctx, resp);
    }

    fn fail(self: *Self, err_code: u32) void {
        self.failure_cb(self.cb_ctx, err_code);
    }

    fn deinit(self: Self) void {
        const res = curlm.removeHandle(self.ch);
        CurlM.assertNoError(res);
        self.ch.deinit();
        self.alloc.free(@ptrCast([*]u8, self.cb_ctx)[0..self.cb_ctx_size]);
        self.header_ctx.headers_buf.deinit();
        self.header_ctx.header_data_buf.deinit();
        self.buf.deinit();
    }

    fn destroy(self: *Self) void {
        self.deinit();
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
 
    const sock_h = @ptrCast(*SockHandle, ptr);
    var running_handles: c_int = undefined;
    const c_sockfd = if (builtin.os.tag == .windows) @ptrToInt(sock_h.sockfd) else sock_h.sockfd;
    const res = curlm.socketAction(c_sockfd, flags, &running_handles);
    CurlM.assertNoError(res);
    checkDone();
}

fn onUvClosePoll(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
    // log.debug("uv close poll", .{});
    const sock_h = @ptrCast(*SockHandle, ptr);
    if (!sock_h.skip_destroy_on_uv_close) {
        _ = sock_handles.remove(sock_h.sockfd);
        galloc.destroy(sock_h);
    }
}

fn onCurlPush(parent: *curl.CURL, h: *curl.CURL, num_headers: usize, headers: *curl.curl_pushheaders, userp: ?*anyopaque) callconv(.C) c_int {
    _ = parent;
    _ = h;
    _ = num_headers;
    _ = headers;
    _ = userp;
    return curl.CURL_PUSH_OK;
}

fn handleInternalSocket(sock_h: *SockHandle, action: c_int) void {
    // log.debug("internal curl socket {} {*}", .{action, sock_h});
    _ = sock_h;
    // Nop for now.
    switch (action) {
        curl.CURL_POLL_IN => {
        },
        curl.CURL_POLL_REMOVE => {
        },
        else => unreachable,
    }
}

fn onSocket(_h: *curl.CURL, sock_fd: curl.curl_socket_t, action: c_int, user_ptr: *anyopaque, socket_ptr: ?*anyopaque) callconv(.C) c_int {
    // log.debug("curl socket {} {} {*}", .{sock_fd, action, socket_ptr});
    _ = user_ptr;
    _ = socket_ptr;

    const cross_sockfd = if (builtin.os.tag == .windows) @intToPtr(std.os.socket_t, sock_fd) else sock_fd;
    const entry = sock_handles.getOrPut(cross_sockfd) catch unreachable;
    if (!entry.found_existing) {
        entry.value_ptr.* = galloc.create(SockHandle) catch unreachable;
        entry.value_ptr.*.init(cross_sockfd);
    } else {
        if (entry.value_ptr.*.sockfd_closed) {
            @panic("Did not expect to reuse closed sockfd");
        }
    }
    const sock_h = entry.value_ptr.*;

    // Check if this callback is for an internal Curl io.
    const for_internal_use = !sock_h.ready;
    if (for_internal_use) {
        handleInternalSocket(sock_h, action);
        return 0;
    }

    const h = Curl{ .handle = _h };
    var ptr: *anyopaque = undefined;

    var cres = h.getInfo(curl.CURLINFO_PRIVATE, &ptr);
    Curl.assertNoError(cres);
    const req = stdx.mem.ptrCastAlign(*AsyncRequestHandle, ptr);

    const S = struct {
        // Attaches a sock to a request only once.
        fn attachSock(sock_h_: *SockHandle, req_: *AsyncRequestHandle) void {
            if (!req_.attached_to_sockfd) {
                req_.sock_fd = sock_h_.sockfd;
                req_.attached_to_sockfd = true;
                sock_h_.num_active_reqs += 1;
            }
        }
    };
    switch (action) {
        curl.CURL_POLL_IN => {
            S.attachSock(sock_h, req);
            if (!sock_h.polling_readable) {
                const res = uv.uv_poll_start(&sock_h.poll, uv.UV_READABLE, onUvPolled);
                uv.assertNoError(res);
                sock_h.polling_readable = true;
            }
        },
        curl.CURL_POLL_OUT => {
            S.attachSock(sock_h, req);
            if (!sock_h.polling_writable) {
                const res = uv.uv_poll_start(&sock_h.poll, uv.UV_WRITABLE, onUvPolled);
                uv.assertNoError(res);
                sock_h.polling_writable = true;
            }
        },
        curl.CURL_POLL_INOUT => {
            S.attachSock(sock_h, req);
            if (!sock_h.polling_readable or !sock_h.polling_writable) {
                const res = uv.uv_poll_start(&sock_h.poll, uv.UV_WRITABLE | uv.UV_READABLE, onUvPolled);
                uv.assertNoError(res);
                sock_h.polling_readable = true;
                sock_h.polling_writable = true;
            }
        },
        curl.CURL_POLL_REMOVE => {
            // log.debug("request poll remove {}", .{sock_fd});

            // This does not mean that curl wants to close the connection,
            // It could mean it wants to just reset the polling state.
            const res = uv.uv_poll_stop(&sock_h.poll);
            sock_h.polling_readable = false;
            sock_h.polling_writable = false;
            uv.assertNoError(res);
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

                    // The request might not have received an onSocket callback so it has no attachment to a sockfd.
                    // eg. Can't connect to host.
                    if (req.attached_to_sockfd) {
                        const sock_h = sock_handles.get(req.sock_fd).?;
                        sock_h.num_active_reqs -= 1;
                        sock_h.checkToDeinit();
                    }

                    // Once checkDone reports a request is done,
                    // invoke the success/failure cb and destroy the request.
                    if (info.data.result == curl.CURLE_OK) {
                        req.success();
                    } else {
                        req.fail(info.data.result);
                    }
                    req.destroy();
                },
                else => {
                    unreachable;
                }
            }
        }
    }
}

pub fn requestAsync(
    alloc: std.mem.Allocator,
    url: []const u8,
    opts: RequestOptions,
    _ctx: anytype,
    success_cb: fn (*anyopaque, Response) void,
    failure_cb: fn (*anyopaque, err_code: u32) void,
) !void {
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

    ch.mustSetOption(curl.CURLOPT_WRITEFUNCTION, S.writeBody);
    ch.mustSetOption(curl.CURLOPT_HEADERFUNCTION, S.writeHeader);

    const ctx = alloc.create(@TypeOf(_ctx)) catch unreachable;
    ctx.* = _ctx;

    var req = alloc.create(AsyncRequestHandle) catch unreachable;
    req.* = .{
        .alloc = alloc,
        .ch = ch,

        .attached_to_sockfd = false,
        .sock_fd = undefined,

        .cb_ctx = ctx,
        .cb_ctx_size = @sizeOf(@TypeOf(_ctx)),
        .success_cb = success_cb,
        .failure_cb = failure_cb,

        .status_code = undefined,
        .header_ctx = .{
            .headers_buf = std.ArrayList(Header).initCapacity(alloc, 10) catch unreachable,
            .header_data_buf = std.ArrayList(u8).initCapacity(alloc, 5e2) catch unreachable,
        },
        .buf = std.ArrayList(u8).initCapacity(alloc, 4e3) catch unreachable,
    };
    ch.mustSetOption(curl.CURLOPT_PRIVATE, req);
    ch.mustSetOption(curl.CURLOPT_WRITEDATA, &req.buf);
    ch.mustSetOption(curl.CURLOPT_HEADERDATA, &req.header_ctx);
    ch.mustSetOption(curl.CURLOPT_OPENSOCKETFUNCTION, onOpenSocket);
    ch.mustSetOption(curl.CURLOPT_OPENSOCKETDATA, req);
    ch.mustSetOption(curl.CURLOPT_CLOSESOCKETFUNCTION, onCloseSocket);

    // If two requests start concurrently, prefer waiting for one to finish connecting to reuse the same connection. For HTTP2.
    ch.mustSetOption(curl.CURLOPT_PIPEWAIT, @intCast(c_long, 1));

    // ch.mustSetOption(curl.CURLOPT_SHARE, &share);
    // ch.mustsetOption(curl.CURLOPT_NOSIGNAL, @intCast(c_long, 1));

    // Loads the timer on demand.
    // Only one timer is needed for all requests.
    if (!timer_inited) {
        var res = uv.uv_timer_init(curlm_uvloop, &timer);
        uv.assertNoError(res);
        timer_inited = true;
    }

    // Add handle starts the request and triggers onCurlSetTimer synchronously.
    // Subsequent socketAction calls also synchronously call onCurlSetTimer and onSocket, however if two sockets are ready
    // onSocket will be called twice so the only way to attach a ctx is through the CURL handle's private opt.
    const res = curlm.addHandle(req.ch);
    if (res != curl.CURLM_OK) {
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

    curl_h.mustSetOption(curl.CURLOPT_WRITEFUNCTION, S.writeBody);
    curl_h.mustSetOption(curl.CURLOPT_WRITEDATA, &buf);
    curl_h.mustSetOption(curl.CURLOPT_HEADERFUNCTION, S.writeHeader);
    curl_h.mustSetOption(curl.CURLOPT_HEADERDATA, &header_ctx);
    
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
    // ch.mustSetOption(curl.CURLOPT_VERBOSE, @intCast(c_int, 1));
    ch.mustSetOption(curl.CURLOPT_URL, url.ptr);
    ch.mustSetOption(curl.CURLOPT_SSL_VERIFYPEER, @intCast(c_long, 1));
    ch.mustSetOption(curl.CURLOPT_SSL_VERIFYHOST, @intCast(c_long, 1));
    if (opts.cert_file) |cert_file| {
        const c_str = try std.fmt.allocPrint(alloc, "{s}\u{0}", .{ cert_file });
        defer alloc.free(c_str);
        ch.mustSetOption(curl.CURLOPT_CAINFO, c_str.ptr);
    } else {
        switch (builtin.os.tag) {
            .linux => {
                ch.mustSetOption(curl.CURLOPT_CAINFO, "/etc/ssl/certs/ca-certificates.crt");
            },
            .macos => {
                ch.mustSetOption(curl.CURLOPT_CAINFO, "/etc/ssl/cert.pem");
            },
            .windows => {
                const mask: c_long = curl.CURLSSLOPT_NATIVE_CA;
                ch.mustSetOption(curl.CURLOPT_SSL_OPTIONS, mask);
            },
            else => {},
        }
    }
    switch (builtin.os.tag) {
        .linux,
        .macos => {
            ch.mustSetOption(curl.CURLOPT_CAPATH, "/etc/ssl/certs");
        },
        else => {},
    }
    // TODO: Expose timeout as ms and use CURLOPT_TIMEOUT_MS
    ch.mustSetOption(curl.CURLOPT_TIMEOUT, @intCast(c_long, opts.timeout));
    ch.mustSetOption(curl.CURLOPT_ACCEPT_ENCODING, "gzip, deflate, br");
    if (opts.keep_connection) {
        ch.mustSetOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 0));
    } else {
        ch.mustSetOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 1));
    }
    // HTTP2 is far more efficient since curl deprecated HTTP1 pipelining. (Must have built curl with nghttp2)
    ch.mustSetOption(curl.CURLOPT_HTTP_VERSION, curl.CURL_HTTP_VERSION_2_0);
    switch (opts.method) {
        .Get => ch.mustSetOption(curl.CURLOPT_CUSTOMREQUEST, "GET"),
        .Post => ch.mustSetOption(curl.CURLOPT_CUSTOMREQUEST, "POST"),
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
            const c_str = try std.fmt.allocPrint(alloc, "{s}: {s}\u{0}", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer alloc.free(c_str);
            header_list.* = curl.curl_slist_append(header_list.*, c_str.ptr);
        }
    }

    ch.mustSetOption(curl.CURLOPT_HTTPHEADER, header_list.*);

    if (opts.body) |body| {
        ch.mustSetOption(curl.CURLOPT_POSTFIELDSIZE, @intCast(c_long, body.len));
        ch.mustSetOption(curl.CURLOPT_POSTFIELDS, body.ptr);
    }
}
