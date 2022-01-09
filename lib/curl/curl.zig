const c = @cImport({
    @cInclude("curl.h");
});

pub usingnamespace c;

pub var inited = false;

pub fn initDefault() c.CURLcode {
    return init(c.CURL_GLOBAL_DEFAULT);
}

pub fn init(flags: c_long) c.CURLcode {
    defer inited = true;
    return c.curl_global_init(flags);
}

pub fn deinit() void {
    c.curl_global_cleanup();
}

pub const CurlM = struct {
    const Self = @This();

    handle: *c.CURLM,

    pub fn init() Self {
        return .{
            .handle = c.curl_multi_init().?,
        };
    }

    pub fn deinit(self: Self) void {
        _ = c.curl_multi_cleanup(self.handle);
    }

    pub fn setOption(self: Self, option: c.CURLMoption, arg: anytype) c.CURLcode {
        return c.curl_multi_setopt(self.handle, option, arg);
    }

    pub fn addHandle(self: Self, curl_h: Curl) c.CURLcode {
        return c.curl_multi_add_handle(self.handle, curl_h.handle);
    }
};

pub const Curl = struct {
    const Self = @This();

    handle: *c.CURL,

    pub fn init() Self {
        return .{
            .handle = c.curl_easy_init().?,
        };
    }

    pub fn deinit(self: Self) void {
        c.curl_easy_cleanup(self.handle);
    }

    pub fn setOption(self: Self, option: c.CURLoption, arg: anytype) c.CURLcode {
        return c.curl_easy_setopt(self.handle, option, arg);
    }

    pub fn perform(self: Self) c.CURLcode {
        return c.curl_easy_perform(self.handle);
    }

    pub fn getInfo(self: Self, option: c.CURLINFO, ptr: anytype) c.CURLcode {
        return c.curl_easy_getinfo(self.handle, option, ptr);
    }

    pub fn getStrError(code: c.CURLcode) [*:0]const u8 {
        return c.curl_easy_strerror(code);
    }
};
