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

pub fn get(alloc: std.mem.Allocator, url: []const u8) ![]const u8 {
    const S = struct {
        fn write(read_buf: [*]u8, size: usize, nmemb: usize, user_data: *std.ArrayList(u8)) usize {
            // log.debug("writing {}", .{nmemb});
            // const write_buf = @ptrCast(*std.ArrayList(u8), user_data);
            const write_buf = user_data;
            const read_size = size * nmemb;
            write_buf.appendSlice(read_buf[0..read_size]) catch unreachable;
            return read_size;
        }
    };
    
    var buf = std.ArrayList(u8).initCapacity(alloc, 4e3) catch unreachable;
    defer buf.deinit();

    var c_url = std.cstr.addNullByte(alloc, url) catch unreachable;
    defer alloc.free(c_url);
    
    _ = curl_h.setOption(curl.CURLOPT_SSL_VERIFYPEER, @intCast(c_long, 1));
    _ = curl_h.setOption(curl.CURLOPT_SSL_VERIFYHOST, @intCast(c_long, 1));

    _ = curl_h.setOption(curl.CURLOPT_URL, c_url.ptr);
    _ = curl_h.setOption(curl.CURLOPT_ACCEPT_ENCODING, "gzip, deflate, br");
    _ = curl_h.setOption(curl.CURLOPT_WRITEFUNCTION, S.write);
    _ = curl_h.setOption(curl.CURLOPT_WRITEDATA, &buf);

    // _ = curl_h.setOption(curl.CURLOPT_VERBOSE, @intCast(c_int, 1));
    
    const res = curl_h.perform();
    if (res != curl.CURLE_OK) {
        // log.debug("Request failed: {s}", .{Curl.getStrError(res)});
        return error.RequestFailed;
    }
    
    return buf.toOwnedSlice();
}