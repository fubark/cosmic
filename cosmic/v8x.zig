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

    var origin = v8.ScriptOrigin.initDefault(iso, src_origin.toValue());

    var context = iso.getCurrentContext();

    // Since es modules are in strict mode it makes sense that everything else should also be in strict mode.
    // Append 'use strict'; There isn't an internal api to enable it.
    // Append void 0 so empty source still evaluates to undefined.
    const final_src = stdx.string.concat(alloc, &[_][]const u8{ "'use strict';void 0;\n", src }) catch unreachable;
    defer alloc.free(final_src);

    const js_src = v8.String.initUtf8(iso, final_src);

    // TODO: Use ScriptCompiler.compile to take a ScriptCompilerSource option that can account for the extra line offset.
    const script = v8.Script.compile(context, js_src, origin) catch {
        setResultError(alloc, iso, ctx, try_catch, result);
        return;
    };
    const script_res = script.run(context) catch {
        setResultError(alloc, iso, ctx, try_catch, result);
        return;
    };
    result.* = .{
        .alloc = alloc,
        .result = allocValueAsUtf8(alloc, iso, context, script_res),
        .err = null,
        .success = true,
    };
}

pub fn allocPrintMessageStackTrace(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, message: v8.Message, default_msg: []const u8) []const u8 {
    // TODO: Use default message if getMessage is null.
    _ = default_msg;
    var buf = std.ArrayList(u8).init(alloc);
    const writer = buf.writer();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    // Some exceptions don't have a line mapping by default. eg. Exceptions thrown in native callbacks.
    if (message.getLineNumber(ctx) != null) {
        // Append source line.
        const source_line = message.getSourceLine(ctx).?;
        _ = appendValueAsUtf8(&buf, iso, ctx, source_line);
        writer.writeAll("\n") catch unreachable;

        // Print wavy underline.
        const col_start = message.getStartColumn().?;
        const col_end = message.getEndColumn().?;
        var i: u32 = 0;
        while (i < col_start) : (i += 1) {
            writer.writeByte(' ') catch unreachable;
        }
        // Sometimes a syntax error gives back the same start and end column which means the end column should be inclusive.
        if (col_end == col_start) {
            writer.writeByte('^') catch unreachable;
        } else {
            while (i < col_end) : (i += 1) {
                writer.writeByte('^') catch unreachable;
            }
        }
        writer.writeAll("\n") catch unreachable;
    }

    // Exception message.
    appendStringAsUtf8(&buf, iso, message.getMessage());
    writer.writeAll("\n") catch unreachable;

    if (message.getStackTrace()) |trace| {
        if (trace.getFrameCount() == 0 and message.getLineNumber(ctx) != null) {
            // Syntax errors don't have a stack trace, so just print the message location.
            const name = allocValueAsUtf8(alloc, iso, ctx, message.getScriptResourceName());
            defer alloc.free(name);
            const line = message.getLineNumber(ctx).?;
            const col = message.getStartColumn().?;
            writer.print("    at {s}:{}:{}\n", .{ name, line, col }) catch unreachable;
        } else {
            appendStackTraceString(&buf, iso, trace);
        }
    }
    return buf.toOwnedSlice();
}

pub fn appendStackTraceString(buf: *std.ArrayList(u8), iso: v8.Isolate, trace: v8.StackTrace) void {
    const writer = buf.writer();
    const num_frames = trace.getFrameCount();
    var i: u32 = 0;
    while (i < num_frames) : (i += 1) {
        const frame = trace.getFrame(iso, i);
        writer.writeAll("    at ") catch unreachable;
        if (frame.getFunctionName()) |name| {
            appendStringAsUtf8(buf, iso, name);
            writer.writeAll(" ") catch unreachable;
        }
        appendStringAsUtf8(buf, iso, frame.getScriptNameOrSourceUrl());
        writer.print(":{}:{}", .{frame.getLineNumber(), frame.getColumn()}) catch unreachable;
        writer.writeAll("\n") catch unreachable;
    }
}

pub fn allocExceptionStackTraceString(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, exception: v8.Value) []const u8 {
    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var buf = std.ArrayList(u8).init(alloc);
    const writer = buf.writer();

    _ = appendValueAsUtf8(&buf, iso, ctx, exception);
    writer.writeAll("\n") catch unreachable;

    appendStackTraceString(&buf, iso, v8.Exception.getStackTrace(exception));

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
        const exception_str = allocValueAsUtf8(alloc, iso, ctx, exception);
        defer alloc.free(exception_str);
        return allocPrintMessageStackTrace(alloc, iso, ctx, message, exception_str);
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException().?;
        return allocValueAsUtf8(alloc, iso, ctx, exception);
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
    const str = val.toString(ctx) catch unreachable;
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return std.ascii.lowerString(arr.items[start..], arr.items[start..]);
}

pub fn appendValueAsUtf8(arr: *std.ArrayList(u8), isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx) catch unreachable;
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return arr.items[start..];
}

pub fn allocStringAsUtf8(alloc: std.mem.Allocator, iso: v8.Isolate, str: v8.String) []const u8 {
    const len = str.lenUtf8(iso);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(iso, buf);
    return buf;
}

/// Custom dump format that shows top 2 level children.
pub fn allocValueDump(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, val: v8.Value) []const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    allocValueDump2(&buf, iso, ctx, val, 0, 2);
    return buf.toOwnedSlice();
}

fn allocValueDump2(buf: *std.ArrayList(u8), iso: v8.Isolate, ctx: v8.Context, val: v8.Value, level: u32, level_max: u32) void {
    if (val.isString()) {
        const writer = buf.writer();
        writer.writeAll("\"") catch unreachable;
        _ = appendStringAsUtf8(buf, iso, val.castTo(v8.String));
        writer.writeAll("\"") catch unreachable;
    } else if (val.isArray()) {
        if (level < level_max) {
            const writer = buf.writer();
            const arr = val.castTo(v8.Array);
            const num_elems = arr.length();
            if (num_elems > 0) {
                writer.writeAll("[ ") catch unreachable;
                var i: u32 = 0;
                while (i < num_elems) : (i += 1) {
                    const elem = val.castTo(v8.Object).getAtIndex(ctx, i);
                    allocValueDump2(buf, iso, ctx, elem, level + 1, level_max);
                    if (i + 1 < num_elems) {
                        writer.writeAll(", ") catch unreachable;
                    }
                }
                writer.writeAll(" ]") catch unreachable;
            } else writer.writeAll("[]") catch unreachable;
        } else buf.writer().writeAll("(Array)") catch unreachable;
    } else if (val.isObject()) {
        if (level < level_max) {
            const writer = buf.writer();
            const obj = val.castTo(v8.Object);
            const props = obj.getOwnPropertyNames(ctx);
            const num_props = props.length();
            if (num_props > 0) {
                writer.writeAll("{ ") catch unreachable;
                var i: u32 = 0;
                while (i < num_props) : (i += 1) {
                    const prop = props.castTo(v8.Object).getAtIndex(ctx, i);
                    const value = obj.getValue(ctx, prop);
                    _ = appendValueAsUtf8(buf, iso, ctx, prop);
                    writer.writeAll(": ") catch unreachable;
                    allocValueDump2(buf, iso, ctx, value, level + 1, level_max);
                    if (i + 1 < num_props) {
                        writer.writeAll(", ") catch unreachable;
                    }
                }
                writer.writeAll(" }") catch unreachable;
            } else writer.writeAll("{}") catch unreachable;
        } else buf.writer().writeAll("(Object)") catch unreachable;
    } else {
        _ = appendValueAsUtf8(buf, iso, ctx, val);
    }
}

pub fn allocValueAsUtf8(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx) catch unreachable;
    const len = str.lenUtf8(iso);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(iso, buf);
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
            const existing_addr = stdx.mem.ptrCastAlign(*const v8.C_InternalAddress, existing.*.?.inner.handle);
            const val_addr = stdx.mem.ptrCastAlign(*const v8.C_InternalAddress, val.handle);
            if (existing_addr.* != val_addr.*) {
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