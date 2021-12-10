const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("zig-v8");
pub const Platform = v8.Platform;
pub const Isolate = v8.Isolate;
pub const Context = v8.Context;
pub const HandleScope = v8.HandleScope;
const ScriptOrigin = v8.ScriptOrigin;
const TryCatch = v8.TryCatch;
const String = v8.String;
const Value = v8.Value;
const log = stdx.log.scoped(.v8);

pub const initV8Platform = v8.initV8Platform;
pub const deinitV8Platform = v8.deinitV8Platform();
pub const initV8 = v8.initV8;
pub const deinitV8 = v8.deinitV8;

pub const initCreateParams = v8.initCreateParams;
pub const createDefaultArrayBufferAllocator = v8.createDefaultArrayBufferAllocator;
pub const destroyArrayBufferAllocator = v8.destroyArrayBufferAllocator;
pub const createUtf8String = v8.createUtf8String;

pub const ExecuteResult = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    result: ?[]const u8,
    err: ?[]const u8,

    fn deinit(self: Self) void {
        if (self.result) |result| {
            self.alloc.free(result);
        }
        if (self.err) |err| {
            self.alloc.free(err);
        }
    }
};

/// Executes a string within the current v8 context.
pub fn executeString(alloc: std.mem.Allocator, isolate: Isolate, src: *const String, origin_val: *const Value, result: *ExecuteResult) bool {
    var hscope: HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var try_catch: TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    var origin = ScriptOrigin.initDefault(isolate, origin_val);

    var context = isolate.getCurrentContext();

    if (v8.compileScript(context, src, origin)) |script| {
        if (v8.runScript(context, script)) |script_res| {
            result.* = .{
                .alloc = alloc,
                .result = valueToRawUtf8Alloc(alloc, isolate, context, script_res),
                .err = null,
            };
            return true;
        } else {
            setResultError(alloc, isolate, try_catch, result);
            return false;
        }
    } else {
        setResultError(alloc, isolate, try_catch, result);
        return false;
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
        };
        return;
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException();
        const exception_str = valueToRawUtf8Alloc(alloc, isolate, ctx, exception);
        result.* = .{
            .alloc = alloc,
            .result = null,
            .err = exception_str,
        };
        return;
    }
}

pub fn appendValueAsUtf8(arr: *std.ArrayList(u8), isolate: Isolate, ctx: Context, val: *const Value) void {
    const str = v8.valueToString(ctx, val);
    const len = v8.utf8Len(isolate, str);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = v8.writeUtf8String(str, isolate, arr.items[start..arr.items.len]);
}

pub fn valueToRawUtf8Alloc(alloc: std.mem.Allocator, isolate: Isolate, ctx: Context, val: *const Value) []const u8 {
    const str = v8.valueToString(ctx, val);
    const len = v8.utf8Len(isolate, str);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = v8.writeUtf8String(str, isolate, buf);
    return buf;
}