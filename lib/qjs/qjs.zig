const c = @cImport({
    @cInclude("quickjs.h");
    @cInclude("quickjs-libc.h");
});

pub usingnamespace c;

pub const Undefined = c.JSValue{
    .tag = c.JS_TAG_UNDEFINED,
    .u = .{
        .int32 = 0,
    },
};

pub const Null = c.JSValue{
    .tag = c.JS_TAG_NULL,
    .u = .{
        .int32 = 0,
    },
};