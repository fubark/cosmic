const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const qjs = @import("qjs");

extern "app" fn jsGetValueType(id: usize) usize;
extern "app" fn jsGetValueString(val_id: usize, ptr: [*]const u8, len: usize) usize;
extern "app" fn jsGetInt32(id: usize) i32;

pub const JsEngine = struct {
    alloc: std.mem.Allocator,
    inner: if (IsWasm) struct {
        buf: std.ArrayListUnmanaged(u8),
    } else struct {
        rt: *qjs.JSRuntime,
        ctx: *qjs.JSContext,
    },

    pub fn init(alloc: std.mem.Allocator) JsEngine {
        if (IsWasm) {
            return .{
                .buf = .{},
            };
        } else {
            const rt = qjs.JS_NewRuntime().?;
            return .{
                .alloc = alloc,
                .inner = .{
                    .rt = rt,
                    .ctx = qjs.JS_NewContext(rt).?,
                },
            };
        }
    }

    pub fn deinit(self: JsEngine) void {
        if (IsWasm) {
            self.buf.deinit(self.alloc);
        } else {
            qjs.JS_FreeContext(self.inner.ctx);
            qjs.JS_FreeRuntime(self.inner.rt);
        }
    }

    pub fn deinitValue(self: JsEngine, val: JsValue) void {
        if (IsWasm) {
            stdx.unsupported();
        } else {
            qjs.JS_FreeValue(self.inner.ctx, val.inner);
        }
    }

    pub fn eval(self: JsEngine, src: [:0]const u8) JsValue {
        if (IsWasm) {
            stdx.unsupported();
        } else {
            // Even though JS_Eval takes src length, it still needs to be null terminated.
            const val = qjs.JS_Eval(self.inner.ctx, src.ptr, src.len, "eval", qjs.JS_EVAL_TYPE_GLOBAL);
            return .{
                .inner = val,
            };
        }
    }

    pub fn getValueTag(self: JsEngine, val: JsValue) JsValueType {
        if (IsWasm) {
            return @intToEnum(JsValueType, jsGetValueType(val.inner.id));
        } else {
            return QJS.getTag(self.inner.ctx, val.inner);
        }
    }

    pub fn valueToString(self: *JsEngine, val: JsValue) ![]const u8 {
        if (IsWasm) {
            self.buf.clearRetainingCapacity();
            var len = jsGetValueString(val.inner.id, self.buf.items.ptr, self.js_rt.buf.capacity);
            if (len > self.js_rt.buf.capacity) {
                try self.js_rt.buf.ensureTotalCapacity(self.alloc, len);
                len = jsGetValueString(val.inner.id, self.buf.items.ptr, self.js_rt.buf.capacity);
            }
            self.buf.items.len = len;
            return try self.alloc.dupe(u8, self.buf.items[0..len]);
        } else {
            const str = qjs.JS_ToCString(self.inner.ctx, val.inner);
            defer qjs.JS_FreeCString(self.inner.ctx, str);
            return try self.alloc.dupe(u8, stdx.cstr.spanOrEmpty(str));
        }
    }
};

pub const JsValue = struct {
    inner: if (IsWasm) WebJsValue else qjs.JSValue,

    const NanBoxing = @sizeOf(?*anyopaque) == 4;

    inline fn getValuePtr(self: JsValue) ?*anyopaque {
        if (NanBoxing) {
            return @intToPtr(?*anyopaque, self.inner);
        } else return @intToPtr(?*anyopaque, self.inner.u.ptr);
    }

    pub fn getTag(self: JsValue, engine: JsEngine) JsValueType {
        return engine.getValueTag(self);
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

    pub fn getBool(val: qjs.JSValue) bool {
        return val.u.int32 == 1;
    }

    pub fn getTag(ctx: *qjs.JSContext, val: qjs.JSValue) JsValueType {
        const tag = if (NanBoxing) b: {
            // Nan Boxing.
            break :b val >> 32;
        } else val.tag;
        return switch (tag) {
            qjs.JS_TAG_BOOL => .boolean,
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