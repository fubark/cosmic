const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const Vec2 = stdx.math.Vec2;
const Color = graphics.Color;
const ds = stdx.ds;

const v8 = @import("v8.zig");
const tasks = @import("tasks.zig");
const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const RuntimeValue = runtime.RuntimeValue;
const PromiseId = runtime.PromiseId;
const ManagedStruct = runtime.ManagedStruct;
const ManagedSlice = runtime.ManagedSlice;
const CsWindow = runtime.CsWindow;
const printFmt = runtime.printFmt;

pub fn window_New(rt: *RuntimeContext, title: []const u8, width: u32, height: u32) v8.Object {
    const res = rt.createCsWindowResource();

    const window = graphics.Window.init(rt.alloc, .{
        .width = width,
        .height = height,
        .title = title,
    }) catch unreachable;
    res.ptr.init(rt.alloc, rt, window, res.id);

    rt.active_window = res.ptr;
    rt.active_graphics = rt.active_window.graphics;

    return res.ptr.js_window.castToObject();
}

pub fn window_GetGraphics(rt: *RuntimeContext, this: v8.Object) *const anyopaque {
    const ctx = rt.context;
    const window_id = this.getInternalField(0).toU32(ctx);

    const res = rt.resources.get(window_id);
    if (res.tag == .CsWindow) {
        const window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
        return @ptrCast(*const anyopaque, window.js_graphics.inner.handle);
    } else {
        v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Window no longer exists for id {}", .{window_id});
        return @ptrCast(*const anyopaque, rt.js_undefined.handle);
    }
}

pub fn window_OnDrawFrame(rt: *RuntimeContext, this: v8.Object, arg: v8.Function) void {
    const iso = rt.isolate;
    const ctx = rt.context;
    const window_id = this.getInternalField(0).toU32(ctx);

    const res = rt.resources.get(window_id);
    if (res.tag == .CsWindow) {
        const window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);

        // Persist callback func.
        const p = v8.Persistent(v8.Function).init(iso, arg);
        window.onDrawFrameCbs.append(p) catch unreachable;
    }
}

pub fn color_Lighter(rt: *RuntimeContext, this: v8.Object) Color {
    return rt.getNativeValue(Color, this.toValue()).?.lighter();
}

pub fn color_Darker(rt: *RuntimeContext, this: v8.Object) Color {
    return rt.getNativeValue(Color, this.toValue()).?.darker();
}

pub fn color_WithAlpha(rt: *RuntimeContext, this: v8.Object, a: u8) Color {
    return rt.getNativeValue(Color, this.toValue()).?.withAlpha(a);
}

pub fn color_New(rt: *RuntimeContext, r: u8, g: u8, b: u8, a: u8) *const anyopaque {
    return rt.getJsValuePtr(Color.init(r, g, b, a));
}

pub fn graphics_FillPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
    rt.vec2_buf.resize(pts.len / 2) catch unreachable;
    var i: u32 = 0;
    var vec_idx: u32 = 0;
    while (i < pts.len - 1) : ({
        i += 2;
        vec_idx += 1;
    }) {
        rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
    }
    g.fillPolygon(rt.vec2_buf.items);
}

pub fn graphics_DrawSvgContent(g: *Graphics, content: []const u8) void {
    g.drawSvgContent(content) catch unreachable;
}

pub fn graphics_DrawImageSized(g: *Graphics, x: f32, y: f32, width: f32, height: f32, image: graphics.Image) void {
    g.drawImageSized(x, y, width, height, image.id);
}

pub fn graphics_ExecuteDrawList(rt: *RuntimeContext, g: *Graphics, handle: v8.Object) void {
    const ctx = rt.context;
    const ptr = handle.getInternalField(0).bitCastToU64(ctx);
    const list = @intToPtr(*graphics.DrawCommandList, ptr);
    g.executeDrawList(list.*);
}

pub fn graphics_CompileSvgContent(rt: *RuntimeContext, g: *Graphics, content: []const u8) v8.Persistent(v8.Object) {
    const draw_list = g.compileSvgContent(rt.alloc, content) catch unreachable;

    const native_ptr = rt.alloc.create(RuntimeValue(graphics.DrawCommandList)) catch unreachable;
    native_ptr.* = .{
        .rt = rt,
        .inner = draw_list,
    };
    _ = rt.weak_handles.add(.{
        .ptr = native_ptr,
        .tag = .DrawCommandList,
    }) catch unreachable;

    const ctx = rt.context;
    const iso = rt.isolate;
    const new = rt.handle_class.initInstance(ctx);
    new.setInternalField(0, iso.initNumberBitCastedU64(@ptrToInt(native_ptr)));

    var new_p = iso.initPersistent(v8.Object, new);
    new_p.setWeakFinalizer(native_ptr, finalize_DrawCommandList, v8.WeakCallbackType.kParameter);
    return new_p;
}

fn finalize_DrawCommandList(c_info: ?*const v8.C_WeakCallbackInfo) callconv(.C) void {
    const info = v8.WeakCallbackInfo.initFromC(c_info);
    const ptr = info.getParameter();
    const rt = stdx.mem.ptrCastAlign(*RuntimeValue(graphics.DrawCommandList), ptr).rt;
    rt.destroyWeakHandleByPtr(ptr);
}

pub fn graphics_DrawPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
    rt.vec2_buf.resize(pts.len / 2) catch unreachable;
    var i: u32 = 0;
    var vec_idx: u32 = 0;
    while (i < pts.len - 1) : ({
        i += 2;
        vec_idx += 1;
    }) {
        rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
    }
    g.drawPolygon(rt.vec2_buf.items);
}

pub fn graphics_FillConvexPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
    rt.vec2_buf.resize(pts.len / 2) catch unreachable;
    var i: u32 = 0;
    var vec_idx: u32 = 0;
    while (i < pts.len - 1) : ({
        i += 2;
        vec_idx += 1;
    }) {
        rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
    }
    g.fillConvexPolygon(rt.vec2_buf.items);
}

/// Path can be absolute or relative to the cwd.
/// Returns the contents on success or false.
pub fn files_readFile(rt: *RuntimeContext, path: []const u8) ?ds.Box([]const u8) {
    const res = std.fs.cwd().readFileAlloc(rt.alloc, path, 1e12) catch |err| switch (err) {
        // Whitelist errors to silence.
        error.FileNotFound => return null,
        else => unreachable,
    };
    return ds.Box([]const u8).init(rt.alloc, res);
}

/// This function sets up a async endpoint manually for future reference.
/// We can also resuse the sync endpoint and run it on the worker thread with ctx.setConstAsyncFuncT.
fn files_ReadFileAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
    const iso = rt.isolate;

    const task = tasks.ReadFileTask{
        .alloc = rt.alloc,
        .path = rt.alloc.dupe(u8, path) catch unreachable,
    };

    const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));

    const promise = resolver.inner.getPromise();
    const promise_id = rt.promises.add(resolver) catch unreachable;

    const S = struct {
        fn onSuccess(ctx: RuntimeValue(PromiseId), _res: TaskOutput(tasks.ReadFileTask)) void {
            const _promise_id = ctx.inner;
            runtime.resolvePromise(ctx.rt, _promise_id, .{
                .handle = ctx.rt.getJsValuePtr(_res),
            });
        }

        fn onFailure(ctx: RuntimeValue(PromiseId), _err: anyerror) void {
            const _promise_id = ctx.inner;
            runtime.rejectPromise(ctx.rt, _promise_id, .{
                .handle = ctx.rt.getJsValuePtr(_err),
            });
        }
    };

    const task_ctx = RuntimeValue(PromiseId){
        .rt = rt,
        .inner = promise_id,
    };
    _ = rt.work_queue.addTaskWithCb(task, task_ctx, S.onSuccess, S.onFailure);

    return promise;
}

/// Path can be absolute or relative to the cwd.
pub fn files_writeFile(path: []const u8, str: []const u8) bool {
    std.fs.cwd().writeFile(path, str) catch return false;
    return true;
}

/// Path can be absolute or relative to the cwd.
pub fn files_copyFile(from: []const u8, to: []const u8) bool {
    std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch return false;
    return true;
}

/// Path can be absolute or relative to the cwd.
pub fn files_moveFile(from: []const u8, to: []const u8) bool {
    std.fs.cwd().rename(from, to) catch return false;
    return true;
}

/// Returns the absolute path of the current working directory.
pub fn files_cwd(rt: *RuntimeContext) ?[]const u8 {
    return std.fs.cwd().realpathAlloc(rt.alloc, ".") catch return null;
}

/// Path can be absolute or relative to the cwd.
pub fn files_getPathInfo(path: []const u8) ?PathInfo {
    const stat = std.fs.cwd().statFile(path) catch return null;
    return PathInfo{
        .kind = stat.kind,
    };
}

pub const PathInfo = struct {
    kind: std.fs.File.Kind,
};

/// Path can be absolute or relative to the cwd.
pub fn files_listDir(rt: *RuntimeContext, path: []const u8) ?ManagedSlice(FileEntry) {
    const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;

    var iter = dir.iterate();
    var buf = std.ArrayList(FileEntry).init(rt.alloc);
    while (iter.next() catch unreachable) |entry| {
        buf.append(.{
            .name = rt.alloc.dupe(u8, entry.name) catch unreachable,
            .kind = @tagName(entry.kind),
        }) catch unreachable;
    }
    return ManagedSlice(FileEntry){
        .alloc = rt.alloc,
        .slice = buf.toOwnedSlice(),
    };
}

pub const FileEntry = struct {
    name: []const u8,

    // This will be static memory.
    kind: []const u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.name);
    }
};

/// Path can be absolute or relative to the cwd.
pub fn files_appendFile(path: []const u8, str: []const u8) bool {
    stdx.fs.appendFile(path, str) catch return false;
    return true;
}

/// Path can be absolute or relative to the cwd.
pub fn files_ensurePath(rt: *RuntimeContext, path: []const u8) bool {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        else => {
            v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
            return false;
        },
    };
    return true;
}

/// Path can be absolute or relative to the cwd.
pub fn files_pathExists(rt: *RuntimeContext, path: []const u8) bool {
    return stdx.fs.pathExists(path) catch |err| {
        v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
        return false;
    };
}

/// Path can be absolute or relative to the cwd.
pub fn files_removeFile(path: []const u8) bool {
    std.fs.cwd().deleteFile(path) catch return false;
    return true;
}

/// Path can be absolute or relative to the cwd.
pub fn files_removeDir(path: []const u8, recursive: bool) bool {
    if (recursive) {
        std.fs.cwd().deleteTree(path) catch return false;
    } else {
        std.fs.cwd().deleteDir(path) catch return false;
    }
    return true;
}

/// Resolves '..' in paths and returns an absolute path.
/// Currently does not resolve home '~'.
pub fn files_resolvePath(rt: *RuntimeContext, path: []const u8) ?[]const u8 {
    return std.fs.path.resolve(rt.alloc, &.{path}) catch return null;
}

/// Returns response body text if request was successful.
/// Returns false if there was a connection error, timeout error (30 secs), or the response code is 5xx.
/// Advanced: cs.http.request
pub fn http_get(rt: *RuntimeContext, url: []const u8) ?ds.Box([]const u8) {
    const resp = stdx.http.get(rt.alloc, url, 30, false) catch return null;
    defer resp.deinit(rt.alloc);
    if (resp.status_code < 500) {
        return ds.Box([]const u8).init(rt.alloc, rt.alloc.dupe(u8, resp.body) catch unreachable);
    } else {
        return null;
    }
}

pub fn http_getAsync(rt: *RuntimeContext, url: []const u8) v8.Promise {
    const iso = rt.isolate;

    const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));
    const promise = resolver.inner.getPromise();
    const promise_id = rt.promises.add(resolver) catch unreachable;

    const S = struct {
        fn onSuccess(ptr: *anyopaque, resp: stdx.http.Response) void {
            const ctx = stdx.mem.ptrCastAlign(*RuntimeValue(PromiseId), ptr);
            const pid = ctx.inner;
            if (resp.status_code < 500) {
                runtime.resolvePromise(ctx.rt, pid, .{
                    .handle = ctx.rt.getJsValuePtr(resp.body),
                });
            } else {
                runtime.resolvePromise(ctx.rt, pid, .{
                    .handle = ctx.rt.js_false.handle,
                });
            }
            resp.deinit(ctx.rt.alloc);
        }

        fn onFailure(ctx: RuntimeValue(PromiseId), err: anyerror) void {
            const _promise_id = ctx.inner;
            runtime.rejectPromise(ctx.rt, _promise_id, .{
                .handle = ctx.rt.getJsValuePtr(err),
            });
        }
    };

    const ctx = RuntimeValue(PromiseId){
        .rt = rt,
        .inner = promise_id,
    };

    stdx.http.getAsync(rt.alloc, url, 30, false, ctx, S.onSuccess) catch |err| S.onFailure(ctx, err);

    return promise;
}

/// Returns Response object if request was successful.
/// Throws exception if there was a connection or protocol error.
pub fn http_request(rt: *RuntimeContext, method: []const u8, url: []const u8) !ManagedStruct(stdx.http.Response) {
    rt.str_buf.resize(method.len) catch unreachable;
    const lower = stdx.string.toLower(method, rt.str_buf.items[0..method.len]);
    if (stdx.string.eq("get", lower)) {
        const resp = try stdx.http.get(rt.alloc, url, 30, false);
        return ManagedStruct(stdx.http.Response){
            .alloc = rt.alloc,
            .val = resp,
        };
    } else {
        return error.UnsupportedMethod;
    }
}

pub fn http_serveHttps(rt: *RuntimeContext, host: []const u8, port: u16, cert_path: []const u8, key_path: []const u8) !v8.Object {
    const handle = rt.createCsHttpServerResource();
    const server = handle.ptr;
    server.init(rt);
    try server.startHttps(host, port, cert_path, key_path);

    const js_handle = rt.http_server_class.getFunction(rt.context).initInstance(rt.context, &.{}).?;
    js_handle.setInternalField(0, rt.isolate.initIntegerU32(handle.id));
    return js_handle;
}

pub fn http_serveHttp(rt: *RuntimeContext, host: []const u8, port: u16) !v8.Object {
    // log.debug("serving http at {s}:{}", .{host, port});

    // TODO: Implement "cosmic serve-http" and "cosmic serve-https" cli utilities.

    const handle = rt.createCsHttpServerResource();
    const server = handle.ptr;
    server.init(rt);
    try server.startHttp(host, port);

    const js_handle = rt.http_server_class.getFunction(rt.context).initInstance(rt.context, &.{}).?;
    js_handle.setInternalField(0, rt.isolate.initIntegerU32(handle.id));
    return js_handle;
}

pub fn print(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const len = info.length();
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
    const iso = rt.isolate;
    const ctx = rt.context;

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const str = v8.valueToUtf8Alloc(rt.alloc, iso, ctx, info.getArg(i));
        defer rt.alloc.free(str);
        printFmt("{s} ", .{str});
    }
    printFmt("\n", .{});
}