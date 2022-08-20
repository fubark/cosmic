const stdx = @import("stdx");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const qjs = @import("qjs");

extern "app" fn jsGetValueType(id: usize) usize;
extern "app" fn jsGetInt32(id: usize) i32;

pub const JsValue = struct {
    inner: if (IsWasm) WebJsValue else qjs.JSValue,

    const NanBoxing = @sizeOf(?*anyopaque) == 4;

    inline fn getValuePtr(self: JsValue) ?*anyopaque {
        if (NanBoxing) {
            return @intToPtr(?*anyopaque, self.inner);
        } else return @intToPtr(?*anyopaque, self.inner.u.ptr);
    }

    pub fn getTag(self: JsValue, ctx: *JsContext) JsValueType {
        if (IsWasm) {
            return @intToEnum(JsValueType, jsGetValueType(self.inner.id));
        } else {
            return QJS.getTag(ctx, self.inner);
        }
    }

    pub fn getInt32(self: JsValue) i32 {
        if (IsWasm) {
            return jsGetInt32(self.inner.id);
        } else {
            return QJS.getInt32(self.inner);
        }
    }

    pub fn getInt32Err(self: JsValue) !i32 {
        if (self.getTag() != .int32) {
            return error.BadType;
        }
        return QJS.getInt32(self.inner);
    }

    pub fn getFloat64(self: JsValue) f64 {
        return QJS.getFloat64(self.inner);
    }
};

pub const JsContext = if (IsWasm) void else qjs.JSContext;

pub const QJS = struct {
    const NanBoxing = @sizeOf(?*anyopaque) == 4;

    pub fn getInt32(val: qjs.JSValue) i32 {
        return val.u.int32;
    }

    pub fn getFloat64(val: qjs.JSValue) f64 {
        return val.u.float64;
    }

    pub fn getTag(ctx: *qjs.JSContext, val: qjs.JSValue) JsValueType {
        const tag = if (NanBoxing) b: {
            // Nan Boxing.
            break :b val >> 32;
        } else val.tag;
        return switch (tag) {
            qjs.JS_TAG_STRING => .string,
            qjs.JS_TAG_EXCEPTION => .exception,
            qjs.JS_TAG_FLOAT64 => .float64,
            qjs.JS_TAG_OBJECT => {
                if (qjs.JS_IsFunction(ctx, val) == 1) {
                    return .function;
                } else {
                    return .object;
                }
            },
            qjs.JS_TAG_UNDEFINED => .undef,
            qjs.JS_TAG_INT => .int32,
            else => {
                if (@sizeOf(?*anyopaque) == 4) {
                    if (tag - qjs.JS_TAG_FIRST >= qjs.JS_TAG_FLOAT64 - qjs.JS_TAG_FIRST) {
                        return .float64;
                    }
                }
                stdx.panicFmt("unknown tag: {}", .{tag});
            }
        };
    }
};

pub const WebJsValue = struct {
    id: u32,
};

pub const JsValueType = enum(u3) {
    string = 0,
    exception = 1,
    float64 = 2,
    object = 3,
    undef = 4,
    int32 = 5,
    function = 6,
    boolean = 7,
};