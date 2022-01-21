const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("v8");

const log = stdx.log.scoped(.v8_util);

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
pub fn executeString(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, src: []const u8, src_origin: v8.String, result: *ExecuteResult) void {
    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    defer try_catch.deinit();

    var origin = v8.ScriptOrigin.initDefault(iso, src_origin.handle);

    var context = iso.getCurrentContext();

    // Since es modules are in strict mode it makes sense that everything else should also be in strict mode.
    // Append 'use strict'; There isn't an internal api to enable it.
    // Append void 0 so empty source still evaluates to undefined.
    const final_src = stdx.string.concat(alloc, &[_][]const u8{ "'use strict';void 0;\n", src }) catch unreachable;
    defer alloc.free(final_src);

    const js_src = v8.String.initUtf8(iso, final_src);

    if (v8.Script.compile(context, js_src, origin)) |script| {
        if (script.run(context)) |script_res| {
            result.* = .{
                .alloc = alloc,
                .result = allocPrintValueAsUtf8(alloc, iso, context, script_res),
                .err = null,
                .success = true,
            };
        } else {
            setResultError(alloc, iso, ctx, try_catch, result);
        }
    } else {
        setResultError(alloc, iso, ctx, try_catch, result);
    }
}

pub fn allocPrintMessageStackTrace(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, message: v8.Message, exception_msg: []const u8) []const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    const writer = buf.writer();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    // Append source line.
    const source_line = message.getSourceLine(ctx).?;
    _ = appendValueAsUtf8(&buf, iso, ctx, source_line);
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

    // Exception message.
    writer.writeAll("\n") catch unreachable;
    writer.writeAll(exception_msg) catch unreachable;
    writer.writeAll("\n") catch unreachable;

    if (message.getStackTrace()) |trace| {
        const num_frames = trace.getFrameCount();
        i = 0;
        while (i < num_frames) : (i += 1) {
            const frame = trace.getFrame(iso, i);
            writer.writeAll("    at ") catch unreachable;
            if (frame.getFunctionName()) |name| {
                appendStringAsUtf8(&buf, iso, name);
                writer.writeAll(" ") catch unreachable;
            }
            appendStringAsUtf8(&buf, iso, frame.getScriptNameOrSourceUrl());
            writer.print(":{}:{}", .{frame.getLineNumber(), frame.getColumn()}) catch unreachable;
            writer.writeAll("\n") catch unreachable;
        }
    }
    return buf.toOwnedSlice();
}

pub fn allocPrintTryCatchStackTrace(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, try_catch: v8.TryCatch) ?[]const u8 {
    if (!try_catch.hasCaught()) {
        return null;
    }

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    if (try_catch.getMessage()) |message| {
        const exception = try_catch.getException().?;
        const exception_str = allocPrintValueAsUtf8(alloc, iso, ctx, exception);
        defer alloc.free(exception_str);
        return allocPrintMessageStackTrace(alloc, iso, ctx, message, exception_str);
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException().?;
        return allocPrintValueAsUtf8(alloc, iso, ctx, exception);
    }
}

fn setResultError(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, try_catch: v8.TryCatch, result: *ExecuteResult) void {
    result.* = .{
        .alloc = alloc,
        .result = null,
        .err = allocPrintTryCatchStackTrace(alloc, iso, ctx, try_catch),
        .success = false,
    };
}

fn appendStringAsUtf8(arr: *std.ArrayList(u8), iso: v8.Isolate, str: v8.String) void {
    const len = str.lenUtf8(iso);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(iso, arr.items[start..arr.items.len]);
}

pub fn appendValueAsUtf8Lower(arr: *std.ArrayList(u8), isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return std.ascii.lowerString(arr.items[start..], arr.items[start..]);
}

pub fn appendValueAsUtf8(arr: *std.ArrayList(u8), isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return arr.items[start..];
}

pub fn allocPrintValueAsUtf8(alloc: std.mem.Allocator, isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx);
    const len = str.lenUtf8(isolate);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(isolate, buf);
    return buf;
}

/// Throws an exception with a stack trace.
pub fn throwErrorException(iso: v8.Isolate, msg: []const u8) void {
    _ = iso.throwException(v8.Exception.initError(iso.initStringUtf8(msg)));
}

pub fn throwErrorExceptionFmt(alloc: std.mem.Allocator, isolate: v8.Isolate, comptime format: []const u8, args: anytype) void {
    const str = std.fmt.allocPrint(alloc, format, args) catch unreachable;
    defer alloc.free(str);
    throwErrorException(isolate, str);
}

/// Updates an existing persistent handle from a js value.
pub fn updateOptionalPersistent(comptime T: type, iso: v8.Isolate, existing: *?v8.Persistent(T), mb_val: ?T) void {
    if (mb_val) |val| {
        if (existing.* != null) {
            if (existing.*.?.inner.handle.* != val.handle.*) {
                // Internal addresses doesn't match, deinit existing persistent.
                existing.*.?.deinit();
            } else {
                // Internal addresses match.
                return;
            }
        }
        existing.* = v8.Persistent(T).init(iso, val);
    } else {
        if (existing.* != null) {
            existing.*.?.deinit();
            existing.* = null;
        }
    }
}