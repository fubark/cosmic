const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("zig-v8");
pub const Platform = v8.Platform;
pub const Isolate = v8.Isolate;
pub const Context = v8.Context;
pub const HandleScope = v8.HandleScope;
pub const ObjectTemplate = v8.ObjectTemplate;
pub const FunctionTemplate = v8.FunctionTemplate;
pub const PromiseResolver = v8.PromiseResolver;
pub const Promise = v8.Promise;
pub const C_FunctionCallbackInfo = v8.C_FunctionCallbackInfo;
pub const FunctionCallbackInfo = v8.FunctionCallbackInfo;
pub const C_PropertyCallbackInfo = v8.C_PropertyCallbackInfo;
pub const PropertyCallbackInfo = v8.PropertyCallbackInfo;
pub const C_WeakCallbackInfo = v8.C_WeakCallbackInfo;
pub const WeakCallbackType = v8.WeakCallbackType;
pub const WeakCallbackInfo = v8.WeakCallbackInfo;
pub const AccessorNameGetterCallback = v8.AccessorNameGetterCallback;
pub const AccessorNameSetterCallback = v8.AccessorNameSetterCallback;
pub const FunctionCallback = v8.FunctionCallback;
pub const Name = v8.Name;
pub const Primitive = v8.Primitive;
pub const PropertyAttribute = v8.PropertyAttribute;
const ScriptOrigin = v8.ScriptOrigin;
pub const TryCatch = v8.TryCatch;
pub const String = v8.String;
pub const Boolean = v8.Boolean;
pub const Value = v8.Value;
pub const Object = v8.Object;
pub const Persistent = v8.Persistent;
pub const PersistentHandle = v8.PersistentHandle;
pub const Function = v8.Function;
pub const Integer = v8.Integer;
pub const Number = v8.Number;
pub const Exception = v8.Exception;
const log = stdx.log.scoped(.v8);

pub const initV8Platform = v8.initV8Platform;
pub const deinitV8Platform = v8.deinitV8Platform;
pub const initV8 = v8.initV8;
pub const deinitV8 = v8.deinitV8;
pub const getVersion = v8.getVersion;
pub const initUndefined = v8.initUndefined;
pub const initTrue = v8.initTrue;
pub const initFalse = v8.initFalse;

pub const initCreateParams = v8.initCreateParams;
pub const createDefaultArrayBufferAllocator = v8.createDefaultArrayBufferAllocator;
pub const destroyArrayBufferAllocator = v8.destroyArrayBufferAllocator;

pub const ExecuteResult = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    result: ?[]const u8,
    err: ?[]const u8,
    success: bool,

    pub fn deinit(self: Self) void {
        if (self.result) |result| {
            self.alloc.free(result);
        }
        if (self.err) |err| {
            self.alloc.free(err);
        }
    }
};

/// Executes a string within the current v8 context.
pub fn executeString(alloc: std.mem.Allocator, isolate: Isolate, src: []const u8, src_origin: String, result: *ExecuteResult) void {
    var hscope: HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var try_catch: TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    var origin = ScriptOrigin.initDefault(isolate, src_origin.handle);

    var context = isolate.getCurrentContext();

    // Since es modules are in strict mode it makes sense that everything else should also be in strict mode.
    // Append 'use strict'; There isn't an internal api to enable it.
    // Append void 0 so empty source still evaluates to undefined.
    const final_src = stdx.string.concat(alloc, &[_][]const u8{ "'use strict';void 0;\n", src }) catch unreachable;
    defer alloc.free(final_src);

    const js_src = v8.String.initUtf8(isolate, final_src);

    if (v8.Script.compile(context, js_src, origin)) |script| {
        if (script.run(context)) |script_res| {
            result.* = .{
                .alloc = alloc,
                .result = valueToUtf8Alloc(alloc, isolate, context, script_res),
                .err = null,
                .success = true,
            };
        } else {
            setResultError(alloc, isolate, try_catch, result);
        }
    } else {
        setResultError(alloc, isolate, try_catch, result);
    }
}

pub fn getTryCatchErrorString(alloc: std.mem.Allocator, isolate: Isolate, try_catch: TryCatch) []const u8 {
    var hscope: HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const ctx = isolate.getCurrentContext();

    if (try_catch.getMessage()) |message| {
        var buf = std.ArrayList(u8).init(alloc);
        const writer = buf.writer();

        // Get (filename):(line number): (message).
        // const filename = message.getScriptResourceName();
        // appendValueAsUtf8(&buf, isolate, ctx, filename);

        // const line_num = message.getLineNumber(ctx) orelse 0;
        // writer.print(":{} ", .{line_num}) catch unreachable;

        // const exception = try_catch.getException();
        // appendValueAsUtf8(&buf, isolate, ctx, exception);
        // writer.writeAll("\n") catch unreachable;

        // Append source line.
        const source_line = message.getSourceLine(ctx).?;
        _ = appendValueAsUtf8(&buf, isolate, ctx, source_line);
        writer.writeAll("\n") catch unreachable;

        // Print wavy underline.
        const col_start = message.getStartColumn();
        const col_end = message.getEndColumn();

        var i: u32 = 0;
        while (i < col_start) : (i += 1) {
            writer.writeByte(' ') catch unreachable;
        }
        while (i < col_end) : (i += 1) {
            writer.writeByte('^') catch unreachable;
        }
        writer.writeByte('\n') catch unreachable;

        if (try_catch.getStackTrace(ctx)) |trace| {
            _ = appendValueAsUtf8(&buf, isolate, ctx, trace);
            writer.writeByte('\n') catch unreachable;
        }

        return buf.toOwnedSlice();
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException();
        return valueToUtf8Alloc(alloc, isolate, ctx, exception);
    }
}

fn setResultError(alloc: std.mem.Allocator, isolate: Isolate, try_catch: TryCatch, result: *ExecuteResult) void {
    result.* = .{
        .alloc = alloc,
        .result = null,
        .err = getTryCatchErrorString(alloc, isolate, try_catch),
        .success = false,
    };
}

pub fn appendValueAsUtf8(arr: *std.ArrayList(u8), isolate: Isolate, ctx: Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return arr.items[start..];
}

pub fn valueToUtf8Alloc(alloc: std.mem.Allocator, isolate: Isolate, ctx: Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(isolate, buf);
    return buf;
}

/// Throws an exception with a stack trace.
pub fn throwErrorException(isolate: Isolate, msg: []const u8) void {
    _ = isolate.throwException(v8.Exception.initError(v8.String.initUtf8(isolate, msg)));
}

pub fn throwErrorExceptionFmt(alloc: std.mem.Allocator, isolate: Isolate, comptime format: []const u8, args: anytype) void {
    const str = std.fmt.allocPrint(alloc, format, args) catch unreachable;
    defer alloc.free(str);
    throwErrorException(isolate, str);
}
