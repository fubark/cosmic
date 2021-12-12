const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("zig-v8");
pub const Platform = v8.Platform;
pub const Isolate = v8.Isolate;
pub const Context = v8.Context;
pub const HandleScope = v8.HandleScope;
pub const ObjectTemplate = v8.ObjectTemplate;
pub const FunctionTemplate = v8.FunctionTemplate;
pub const RawFunctionCallbackInfo = v8.RawFunctionCallbackInfo;
pub const FunctionCallbackInfo = v8.FunctionCallbackInfo;
pub const PropertyAttribute = v8.PropertyAttribute;
const ScriptOrigin = v8.ScriptOrigin;
const TryCatch = v8.TryCatch;
pub const String = v8.String;
const Value = v8.Value;
const log = stdx.log.scoped(.v8);

pub const initV8Platform = v8.initV8Platform;
pub const deinitV8Platform = v8.deinitV8Platform;
pub const initV8 = v8.initV8;
pub const deinitV8 = v8.deinitV8;
pub const getVersion = v8.getVersion;

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
pub fn executeString(alloc: std.mem.Allocator, isolate: Isolate, src: String, src_origin: String, result: *ExecuteResult) void {
    var hscope: HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var try_catch: TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    var origin = ScriptOrigin.initDefault(isolate, src_origin.handle);

    var context = isolate.getCurrentContext();

    if (v8.Script.compile(context, src, origin)) |script| {
        if (script.run(context)) |script_res| {
            result.* = .{
                .alloc = alloc,
                .result = valueToRawUtf8Alloc(alloc, isolate, context, script_res),
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

fn setResultError(alloc: std.mem.Allocator, isolate: Isolate, try_catch: TryCatch, result: *ExecuteResult) void {
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
        appendValueAsUtf8(&buf, isolate, ctx, source_line);
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

        const trace = try_catch.getStackTrace(ctx).?;
        appendValueAsUtf8(&buf, isolate, ctx, trace);

        result.* = .{
            .alloc = alloc,
            .result = null,
            .err = buf.toOwnedSlice(),
            .success = false,
        };
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException();
        const exception_str = valueToRawUtf8Alloc(alloc, isolate, ctx, exception);
        result.* = .{
            .alloc = alloc,
            .result = null,
            .err = exception_str,
            .success = false,
        };
    }
}

pub fn appendValueAsUtf8(arr: *std.ArrayList(u8), isolate: Isolate, ctx: Context, any_value: anytype) void {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
}

pub fn valueToRawUtf8Alloc(alloc: std.mem.Allocator, isolate: Isolate, ctx: Context, val: Value) []const u8 {
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(isolate, buf);
    return buf;
}