const std = @import("std");
const builtin = @import("builtin");
const curl = @import("curl");
const Curl = curl.Curl;
const CurlM = curl.CurlM;
const log = std.log.scoped(.http);

// NOTES:
// Debugging tls handshake: "openssl s_client -connect 127.0.0.1:3000" Useful options: -prexit -debug -msg 
// Curl also has tracing: "curl --trace /dev/stdout https://127.0.0.1:3000"
// Generating a self-signed localhost certificate: "openssl req -x509 -out localhost.crt -keyout localhost.key -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <( printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")"

// Synchronous curl. Keep curl handle to reuse connection pool.
var curl_h: Curl = undefined;

// Async curl.
var curl_m: CurlM = undefined;

pub fn init() void {
    if (!curl.inited) {
        @panic("expected curl to be inited");
    }
    curl_h = Curl.init();
    curl_m = CurlM.init();
}

pub fn deinit() void {
    curl_h.deinit();
    curl_m.deinit();
}

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

fn handleSocket(c_curl: curl.CURL, socket: curl.curl_socket_t, action: c_int, user_p: *anyopaque, socket_p: *anyopaque) void {
    _ = c_curl;
    _ = socket;
    _ = action;
    _ = user_p;
    _ = socket_p;

    log.debug("curl handle socket", .{});
}

pub fn getAsync(alloc: std.mem.Allocator, url: []const u8) !Response {
    curl_m.setOption(curl.CURLMOPT_SOCKETFUNCTION, handleSocket);

    // CURL *handle = curl_easy_init();
    // curl_easy_setopt(handle, CURLOPT_WRITEDATA, file);
    var c_url = std.cstr.addNullByte(alloc, url) catch unreachable;
    defer alloc.free(c_url);
    
    _ = curl_h.setOption(curl.CURLOPT_URL, c_url.ptr);
    _ = curl_m.addHandle(curl_h);
}

/// 0 timeout = no timeout
pub fn get(alloc: std.mem.Allocator, url: []const u8, timeout_secs: u64, keep_connection_open: bool) !Response {
    const HeaderContext = struct {
        headers_buf: std.ArrayList(Header),
        header_data_buf: std.ArrayList(u8),
    };
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
    
    _ = curl_h.setOption(curl.CURLOPT_SSL_VERIFYPEER, @intCast(c_long, 1));
    _ = curl_h.setOption(curl.CURLOPT_SSL_VERIFYHOST, @intCast(c_long, 1));
    if (builtin.os.tag == .linux) {
        _ = curl_h.setOption(curl.CURLOPT_CAINFO, "/etc/ssl/certs/ca-certificates.crt");
        _ = curl_h.setOption(curl.CURLOPT_CAPATH, "/etc/ssl/certs");
    }

    _ = curl_h.setOption(curl.CURLOPT_URL, c_url.ptr);
    _ = curl_h.setOption(curl.CURLOPT_ACCEPT_ENCODING, "gzip, deflate, br");
    _ = curl_h.setOption(curl.CURLOPT_WRITEFUNCTION, S.writeBody);
    _ = curl_h.setOption(curl.CURLOPT_WRITEDATA, &buf);
    _ = curl_h.setOption(curl.CURLOPT_HEADERFUNCTION, S.writeHeader);
    _ = curl_h.setOption(curl.CURLOPT_HEADERDATA, &header_ctx);
    _ = curl_h.setOption(curl.CURLOPT_TIMEOUT, timeout_secs);
    if (keep_connection_open) {
        _ = curl_h.setOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 0));
    } else {
        _ = curl_h.setOption(curl.CURLOPT_FORBID_REUSE, @intCast(c_long, 1));
    }

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