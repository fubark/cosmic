const std = @import("std");
const curl = @import("curl");
const Curl = curl.Curl;
const log = std.log.scoped(.http);

// Need to reuse the curl handle to reuse connection pool.
// curl.CURL is synchronous. For async, look at curl.CURLM.
var curl_h: Curl = undefined;

pub fn init() void {
    if (!curl.inited) {
        @panic("expected curl to be inited");
    }
    curl_h = Curl.init();
}

pub fn deinit() void {
    curl_h.deinit();
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

    pub fn deinit(self: *Response, alloc: std.mem.Allocator) void {
        alloc.free(self.headers);
        alloc.free(self.header);
        alloc.free(self.body);
    }
};

pub const Header = struct {
    key: IndexSlice,
    value: IndexSlice,
};

pub fn get(alloc: std.mem.Allocator, url: []const u8) !Response {
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

    _ = curl_h.setOption(curl.CURLOPT_URL, c_url.ptr);
    _ = curl_h.setOption(curl.CURLOPT_ACCEPT_ENCODING, "gzip, deflate, br");
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