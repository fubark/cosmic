const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");
const curl = @import("curl");
const uv = @import("uv");
const h2o = @import("h2o");

const v8 = @import("v8.zig");
const js_env = @import("js_env.zig");
const log = stdx.log.scoped(.runtime);

const work_queue = @import("work_queue.zig");
const WorkQueue = work_queue.WorkQueue;
const UvPoller = @import("uv_poller.zig").UvPoller;
const HttpServer = @import("server.zig").HttpServer;

pub const PromiseId = u32;

// Manages runtime resources.
// Used by V8 callback functions.
pub const RuntimeContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    str_buf: std.ArrayList(u8),

    window_class: v8.FunctionTemplate,
    graphics_class: v8.FunctionTemplate,
    http_response_class: v8.FunctionTemplate,
    http_server_class: v8.FunctionTemplate,
    http_response_writer: v8.ObjectTemplate,
    image_class: v8.FunctionTemplate,
    color_class: v8.FunctionTemplate,
    handle_class: v8.ObjectTemplate,
    default_obj_t: v8.ObjectTemplate,

    // Collection of mappings from id to resource handles.
    resources: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle),

    weak_handles: ds.CompactUnorderedList(u32, WeakHandle),

    generic_resource_list: ResourceListId,
    generic_resource_list_last: ResourceId,

    window_resource_list: ResourceListId,
    window_resource_list_last: ResourceId,
    // Keep track of active windows so we know when to stop the app.
    num_windows: u32,
    // Window that has keyboard focus and will receive swap buffer.
    // Note: This is only safe if the allocation doesn't change.
    active_window: *CsWindow,
    // Active graphics handle for receiving js draw calls.
    active_graphics: *graphics.Graphics,

    platform: v8.Platform,
    isolate: v8.Isolate,
    context: v8.Context,
    cur_script_dir_abs: []const u8,

    // This is used to store native string slices copied from v8.String for use in the immediate native callback functions.
    // It will automatically clear at the pre callback step if the current size is too large.
    // Native callback functions that have []const u8 in their params should assume they only live until end of function scope.
    cb_str_buf: std.ArrayList(u8),
    cb_f32_buf: std.ArrayList(f32),

    vec2_buf: std.ArrayList(Vec2),

    js_undefined: v8.Primitive,
    js_false: v8.Boolean,
    js_true: v8.Boolean,

    // Whether this was invoked from "cosmic test"
    is_test_env: bool,

    // Test runner.
    num_tests: u32, // Includes sync and async tests.
    num_tests_passed: u32,

    num_async_tests: u32,
    num_async_tests_finished: u32,
    num_async_tests_passed: u32,

    num_isolated_tests_finished: u32,
    isolated_tests: std.ArrayList(IsolatedTest),

    // Main thread waits for a wakeup call before running event loop.
    main_wakeup: std.Thread.ResetEvent,

    work_queue: WorkQueue,

    promises: ds.CompactUnorderedList(PromiseId, v8.Persistent(v8.PromiseResolver)),

    // uv_loop_t is quite large, so allocate on heap.
    uv_loop: *uv.uv_loop_t,
    uv_dummy_async: *uv.uv_async_t,
    uv_poller: UvPoller,

    // Number of long lived uv handles.
    num_uv_handles: u32,

    pub fn init(self: *Self, alloc: std.mem.Allocator, platform: v8.Platform, iso: v8.Isolate, src_path: []const u8) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .color_class = undefined,
            .graphics_class = undefined,
            .http_response_class = undefined,
            .http_response_writer = undefined,
            .http_server_class = undefined,
            .image_class = undefined,
            .handle_class = undefined,
            .default_obj_t = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .weak_handles = ds.CompactUnorderedList(u32, WeakHandle).init(alloc),
            .generic_resource_list = undefined,
            .generic_resource_list_last = undefined,
            .window_resource_list = undefined,
            .window_resource_list_last = undefined,
            .num_windows = 0,
            .active_window = undefined,
            .active_graphics = undefined,
            .platform = platform,
            .isolate = iso,
            .context = undefined,
            .cur_script_dir_abs = getSrcPathDirAbs(alloc, src_path) catch unreachable,
            .cb_str_buf = std.ArrayList(u8).init(alloc),
            .cb_f32_buf = std.ArrayList(f32).init(alloc),
            .vec2_buf = std.ArrayList(Vec2).init(alloc),

            // Store locally for quick access.
            .js_undefined = iso.initUndefined(),
            .js_false = iso.initFalse(),
            .js_true = iso.initTrue(),

            .is_test_env = false,
            .num_tests = 0,
            .num_tests_passed = 0,
            .num_async_tests = 0,
            .num_async_tests_finished = 0,
            .num_async_tests_passed = 0,
            .num_isolated_tests_finished = 0,
            .isolated_tests = std.ArrayList(IsolatedTest).init(alloc),

            .main_wakeup = undefined,
            .work_queue = undefined,
            .promises = ds.CompactUnorderedList(PromiseId, v8.Persistent(v8.PromiseResolver)).init(alloc),
            .uv_loop = undefined,
            .uv_dummy_async = undefined,
            .uv_poller = undefined,
            .num_uv_handles = 0,
        };

        self.main_wakeup.init() catch unreachable;

        // Create libuv evloop instance.
        self.uv_loop = alloc.create(uv.uv_loop_t) catch unreachable;
        var res = uv.uv_loop_init(self.uv_loop);
        if (res != 0) {
            stdx.panicFmt("uv_loop_init: {s}", .{ uv.uv_strerror(res) });
        }
        const S = struct {
            fn onWatcherQueueChanged(_loop: [*c]uv.uv_loop_t) callconv(.C) void {
                // log.debug("on queue changed", .{});
                const loop = @ptrCast(*uv.uv_loop_t, _loop);
                const rt = stdx.mem.ptrCastAlign(*RuntimeContext, loop.data.?);
                _ = uv.uv_async_send(rt.uv_dummy_async);
            }
        };
        // Once this is merged: https://github.com/libuv/libuv/pull/3308,
        // we can remove patches/libuv_on_watcher_queue_updated.patch and use the better method.
        self.uv_loop.data = self;
        self.uv_loop.on_watcher_queue_updated = S.onWatcherQueueChanged;

        // Add dummy handle or UvPoller/uv_backend_timeout will think there is nothing to wait for.
        self.uv_dummy_async = alloc.create(uv.uv_async_t) catch unreachable;
        _ = uv.uv_async_init(self.uv_loop, self.uv_dummy_async, null);

        // Uv needs to run once to initialize or UvPoller will never get the first event.
        _ = uv.uv_run(self.uv_loop, uv.UV_RUN_NOWAIT);

        // Start uv poller thread.
        self.uv_poller = UvPoller.init(self.uv_loop, &self.main_wakeup);
        _ = std.Thread.spawn(.{}, UvPoller.loop, .{&self.uv_poller}) catch unreachable;

        self.work_queue = WorkQueue.init(alloc, self.uv_loop, &self.main_wakeup);
        self.work_queue.createAndRunWorker();

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = .{ .ptr = undefined, .tag = .Dummy };
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;
        self.generic_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.generic_resource_list_last = self.resources.getListHead(self.generic_resource_list).?;

        // Set up uncaught promise rejection handler.
        iso.setPromiseRejectCallback(promiseRejectCallback);

        // By default, scripts will automatically run microtasks when call depth returns to zero.
        // It also allows us to use performMicrotasksCheckpoint in cases where we need to sooner.
        iso.setMicrotasksPolicy(v8.MicrotasksPolicy.kAuto);
    }

    fn deinit(self: *Self) void {
        self.alloc.free(self.cur_script_dir_abs);
        self.str_buf.deinit();
        self.cb_str_buf.deinit();
        self.cb_f32_buf.deinit();
        self.vec2_buf.deinit();

        {
            var iter = self.weak_handles.iterator();
            while (iter.nextPtr()) |handle| {
                handle.deinit(self);
            }
            self.weak_handles.deinit();
        }
        {
            var iter = self.resources.items.iterator();
            while (iter.next()) |item| {
                self.deinitResourceHandle(item.data);
            }
            self.resources.deinit();
        }

        self.work_queue.deinit();

        {
            var iter = self.promises.iterator();
            while (iter.nextPtr()) |p| {
                p.deinit();
            }
        }
        self.promises.deinit();

        for (self.isolated_tests.items) |*case| {
            case.deinit(self.alloc);
        }
        self.isolated_tests.deinit();

        self.main_wakeup.deinit();

        self.alloc.destroy(self.uv_dummy_async);
        self.alloc.destroy(self.uv_loop);
    }

    /// Destroys the resource owned by the handle.
    fn deinitResourceHandle(self: *Self, handle: ResourceHandle) void {
        switch (handle.tag) {
            .CsWindow => {
                // TODO: This should do cleanup like deleteCsWindowBySdlId
                const window = stdx.mem.ptrCastAlign(*CsWindow, handle.ptr);
                window.deinit(self);
                self.alloc.destroy(window);
            },
            .CsHttpServer => {
                const server = stdx.mem.ptrCastAlign(*HttpServer, handle.ptr);
                server.requestShutdown();
                server.deinitPreClosing();
                self.alloc.destroy(server);
            },
            .Dummy => {},
        }
    }

    pub fn getResourcePtr(self: *Self, comptime Ptr: type, res_id: ResourceId) ?Ptr {
        const Tag = GetResourceTag(Ptr);
        if (self.resources.hasItem(res_id)) {
            const item = self.resources.get(res_id);
            if (item.tag == Tag) {
                return stdx.mem.ptrCastAlign(Ptr, item.ptr);
            }
        }
        return null;
    }

    pub fn destroyWeakHandleByPtr(self: *Self, ptr: *const anyopaque) void {
        var id: u32 = 0;
        while (id < self.weak_handles.data.items.len) : (id += 1) {
            if (self.weak_handles.hasItem(id)) {
                var handle = self.weak_handles.get(id);
                if (handle.ptr == ptr) {
                    handle.deinit(self);
                    self.weak_handles.remove(id);
                    break;
                }
            }
        }
    }

    pub fn createCsHttpServerResource(self: *Self) CreatedResource(HttpServer) {
        const ptr = self.alloc.create(HttpServer) catch unreachable;
        self.generic_resource_list_last = self.resources.insertAfter(self.generic_resource_list_last, .{
            .ptr = ptr,
            .tag = .CsHttpServer,
        }) catch unreachable;
        return .{
            .ptr = ptr,
            .id = self.generic_resource_list_last,
        };
    }

    pub fn createCsWindowResource(self: *Self) CreatedResource(CsWindow) {
        const ptr = self.alloc.create(CsWindow) catch unreachable;
        self.window_resource_list_last = self.resources.insertAfter(self.window_resource_list_last, .{
            .ptr = ptr,
            .tag = .CsWindow,
        }) catch unreachable;
        self.num_windows += 1;
        return .{
            .ptr = ptr,
            .id = self.window_resource_list_last,
        };
    }

    /// Deinit the underlying resource and removes the handle from the runtime.
    pub fn destroyResource(self: *Self, list_id: ResourceListId, res_id: ResourceId) void {
        const S = struct {
            fn findPrev(target: ResourceId, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
                if (buf.getNext(item_id)) |next| {
                    return next == target;
                } else return false;
            }
        };

        if (self.resources.findInList(list_id, res_id, S.findPrev)) |prev_id| {
            const id = self.resources.getNext(prev_id).?;
            self.deinitResourceHandle(self.resources.get(id));

            // Remove from resources.
            self.resources.removeNext(prev_id);
        }
    }

    fn deleteCsWindowBySdlId(self: *Self, sdl_win_id: u32) void {
        if (graphics.Backend != .OpenGL) {
            @panic("unsupported");
        }
        const S = struct {
            fn pred(_sdl_win_id: u32, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
                if (buf.getNext(item_id)) |next| {
                    const res = buf.get(next);
                    const cs_window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
                    return cs_window.window.inner.id == _sdl_win_id;
                } else return false;
            }
        };
        if (self.resources.findInList(self.window_resource_list, sdl_win_id, S.pred)) |prev_id| {
            const window_id = self.resources.getNext(prev_id).?;
            const res = self.resources.get(window_id);

            const cs_window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
            // Deinit and destroy.
            cs_window.deinit(self);
            self.alloc.destroy(cs_window);

            // Remove from resources.
            self.resources.removeNext(prev_id);

            // Update current vars.
            if (self.window_resource_list_last == window_id) {
                self.window_resource_list_last = prev_id;
            }
            self.num_windows -= 1;
            if (self.num_windows > 0) {
                if (self.active_window == cs_window) {
                    // TODO: Revisit this. For now just pick the last window.
                    self.active_window = stdx.mem.ptrCastAlign(*CsWindow, self.resources.get(prev_id).ptr);
                    self.active_graphics = self.active_window.graphics;
                }
            } else {
                self.active_window = undefined;
                self.active_graphics = undefined;
            }
        }
    }

    /// Returns raw value pointer so we don't need to convert back to a v8.Value.
    pub fn getJsValuePtr(self: Self, native_val: anytype) *const anyopaque {
        const Type = @TypeOf(native_val);
        const iso = self.isolate;
        const ctx = self.context;
        switch (Type) {
            u32 => return iso.initIntegerU32(native_val).handle,
            f32 => return iso.initNumber(native_val).handle,
            bool => return iso.initBoolean(native_val).handle,
            stdx.http.Response => {
                const headers_buf = self.alloc.alloc(v8.Value, native_val.headers.len) catch unreachable;
                defer self.alloc.free(headers_buf);
                for (native_val.headers) |header, i| {
                    const js_header = self.default_obj_t.initInstance(ctx);
                    _ = js_header.setValue(ctx, iso.initStringUtf8("key"), iso.initStringUtf8(native_val.header[header.key.start..header.key.end]));
                    _ = js_header.setValue(ctx, iso.initStringUtf8("value"), iso.initStringUtf8(native_val.header[header.value.start..header.value.end]));
                    headers_buf[i] = .{ .handle = js_header.handle };
                }

                const new = self.http_response_class.getFunction(ctx).initInstance(ctx, &.{}).?;
                _ = new.setValue(ctx, iso.initStringUtf8("status"), iso.initIntegerU32(native_val.status_code));
                _ = new.setValue(ctx, iso.initStringUtf8("headers"), iso.initArrayElements(headers_buf));
                _ = new.setValue(ctx, iso.initStringUtf8("body"), iso.initStringUtf8(native_val.body));
                return new.handle;
            },
            graphics.Image => {
                const new = self.image_class.getFunction(ctx).initInstance(ctx, &.{}).?;
                new.setInternalField(0, iso.initIntegerU32(native_val.id));
                _ = new.setValue(ctx, iso.initStringUtf8("width"), iso.initIntegerU32(@intCast(u32, native_val.width)));
                _ = new.setValue(ctx, iso.initStringUtf8("height"), iso.initIntegerU32(@intCast(u32, native_val.height)));
                return new.handle;
            },
            graphics.Color => {
                const new = self.color_class.getFunction(ctx).initInstance(ctx, &.{}).?;
                _ = new.setValue(ctx, iso.initStringUtf8("r"), iso.initIntegerU32(native_val.channels.r));
                _ = new.setValue(ctx, iso.initStringUtf8("g"), iso.initIntegerU32(native_val.channels.g));
                _ = new.setValue(ctx, iso.initStringUtf8("b"), iso.initIntegerU32(native_val.channels.b));
                _ = new.setValue(ctx, iso.initStringUtf8("a"), iso.initIntegerU32(native_val.channels.a));
                return new.handle;
            },
            js_env.PathInfo => {
                const new = self.default_obj_t.initInstance(ctx);
                _ = new.setValue(ctx, iso.initStringUtf8("kind"), iso.initStringUtf8(@tagName(native_val.kind)));
                return new.handle;
            },
            v8.Object => {
                return native_val.handle;
            },
            v8.Promise => {
                return native_val.handle;
            },
            []const u8 => {
                return iso.initStringUtf8(native_val).handle;
            },
            []const js_env.FileEntry => {
                const buf = self.alloc.alloc(v8.Value, native_val.len) catch unreachable;
                defer self.alloc.free(buf);
                for (native_val) |it, i| {
                    const obj = self.default_obj_t.initInstance(ctx);
                    _ = obj.setValue(ctx, iso.initStringUtf8("name"), iso.initStringUtf8(it.name));
                    _ = obj.setValue(ctx, iso.initStringUtf8("kind"), iso.initStringUtf8(it.kind));
                    buf[i] = obj.toValue();
                }
                return iso.initArrayElements(buf).handle;
            },
            ds.Box([]const u8) => {
                return iso.initStringUtf8(native_val.slice).handle;
            },
            anyerror => {
                // TODO: Should this be an Error/Exception object instead?
                const str = std.fmt.allocPrint(self.alloc, "{}", .{native_val}) catch unreachable;
                defer self.alloc.free(str);
                return iso.initStringUtf8(str).handle;
            },
            *const anyopaque => {
                return native_val;
            },
            v8.Persistent(v8.Object) => {
                return @ptrCast(*const anyopaque, native_val.inner.handle);
            },
            else => {
                if (@typeInfo(Type) == .Optional) {
                    if (native_val) |child_val| {
                        return self.getJsValuePtr(child_val);
                    } else {
                        return @ptrCast(*const anyopaque, self.js_false.handle);
                    }
                } else if (@hasDecl(Type, "ManagedSlice")) {
                    return self.getJsValuePtr(native_val.slice);
                } else if (@hasDecl(Type, "ManagedStruct")) {
                    return self.getJsValuePtr(native_val.val);
                } else {
                    comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to js.", .{@typeName(Type)}));
                }
            },
        }
    }

    pub fn getNativeValue(self: *Self, comptime T: type, val: anytype) ?T {
        const ctx = self.context;
        switch (T) {
            []const f32 => {
                if (val.isArray()) {
                    const len = val.castToArray().length();
                    var i: u32 = 0;
                    const obj = val.castToObject();
                    const start = self.cb_f32_buf.items.len;
                    self.cb_f32_buf.resize(start + len) catch unreachable;
                    while (i < len) : (i += 1) {
                        self.cb_f32_buf.items[start + i] = obj.getAtIndex(ctx, i).toF32(ctx);
                    }
                    return self.cb_f32_buf.items[start..];
                } else return null;
            },
            []const u8 => {
                if (@TypeOf(val) == SizedJsString) {
                    return appendSizedJsStringAssumeCap(&self.cb_str_buf, self.isolate, val);
                } else {
                    return ctx.appendValueAsUtf8(&self.cb_str_buf, val);
                }
            },
            bool => return val.toBool(self.isolate),
            u8 => return @intCast(u8, val.toU32(ctx)),
            u16 => return @intCast(u16, val.toU32(ctx)),
            u32 => return val.toU32(ctx),
            f32 => return val.toF32(ctx),
            graphics.Image => {
                if (val.isObject()) {
                    const obj = val.castToObject();
                    if (obj.toValue().instanceOf(ctx, self.image_class.getFunction(ctx).toObject())) {
                        const image_id = obj.getInternalField(0).toU32(ctx);
                        return graphics.Image{ .id = image_id, .width = 0, .height = 0 };
                    }
                }
                return null;
            },
            graphics.Color => {
                if (val.isObject()) {
                    const iso = self.isolate;
                    const obj = val.castToObject();
                    const r = obj.getValue(ctx, iso.initStringUtf8("r")).toU32(ctx);
                    const g = obj.getValue(ctx, iso.initStringUtf8("g")).toU32(ctx);
                    const b = obj.getValue(ctx, iso.initStringUtf8("b")).toU32(ctx);
                    const a = obj.getValue(ctx, iso.initStringUtf8("a")).toU32(ctx);
                    return graphics.Color.init(
                        @intCast(u8, r),
                        @intCast(u8, g),
                        @intCast(u8, b),
                        @intCast(u8, a),
                    );
                } else return null;
            },
            v8.Function => {
                if (val.isFunction()) {
                    return val.castToFunction();
                } else return null;
            },
            v8.Object => {
                if (val.isObject()) {
                    return val.castToObject();
                } else return null;
            },
            v8.Value => return val,
            else => comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to {s}", .{ @typeName(@TypeOf(val)), @typeName(T) })),
        }
    }
};

/// A slice that knows how to deinit itself and it's items.
pub fn ManagedSlice(comptime T: type) type {
    return struct {
        pub const ManagedSlice = true;

        alloc: std.mem.Allocator,
        slice: []const T,

        pub fn deinit(self: @This()) void {
            for (self.slice) |it| {
                it.deinit(self.alloc);
            }
            self.alloc.free(self.slice);
        }
    };
}

/// A struct that knows how to deinit itself.
pub fn ManagedStruct(comptime T: type) type {
    return struct {
        pub const ManagedStruct = true;

        alloc: std.mem.Allocator,
        val: T,

        pub fn deinit(self: @This()) void {
            self.val.deinit(self.alloc);
        }
    };
}

// Resolves to native ptr from resource id attached to js this.
pub fn ThisResource(comptime Ptr: type) type {
    return struct {
        pub const ThisResource = true;
        ptr: Ptr,
    };
}

var galloc: std.mem.Allocator = undefined;
var uncaught_promise_errors: std.AutoHashMap(c_int, []const u8) = undefined;

fn initGlobal(alloc: std.mem.Allocator) void {
    galloc = alloc;
    uncaught_promise_errors = std.AutoHashMap(c_int, []const u8).init(alloc);
}

fn deinitGlobal() void {
    var iter = uncaught_promise_errors.valueIterator();
    while (iter.next()) |err_str| {
        galloc.free(err_str.*);
    }
    uncaught_promise_errors.deinit();
} 

fn promiseRejectCallback(c_msg: v8.C_PromiseRejectMessage) callconv(.C) void {
    const msg = v8.PromiseRejectMessage.initFromC(c_msg);

    // TODO: Use V8_PROMISE_INTERNAL_FIELD_COUNT and PromiseHook to set rt handle on every promise so we have proper context.
    const promise = msg.getPromise();
    const iso = promise.toObject().getIsolate();
    const ctx = promise.toObject().getCreationContext();

    switch (msg.getEvent()) {
        v8.PromiseRejectEvent.kPromiseRejectWithNoHandler => {
            // Record this uncaught incident since a follow up kPromiseHandlerAddedAfterReject can remove the record.
            // At a later point reportUncaughtPromiseRejections will list all of them.
            const str = v8.valueToUtf8Alloc(galloc, iso, ctx, msg.getValue());
            const key = promise.toObject().getIdentityHash();
            uncaught_promise_errors.put(key, str) catch unreachable;
        },
        v8.PromiseRejectEvent.kPromiseHandlerAddedAfterReject => {
            // Remove the record.
            const key = promise.toObject().getIdentityHash();
            const value = uncaught_promise_errors.get(key).?;
            galloc.free(value);
            _ = uncaught_promise_errors.remove(key);
        },
        else => {},
    }
}

fn reportUncaughtPromiseRejections() void {
    var iter = uncaught_promise_errors.valueIterator();
    while (iter.next()) |err_str| {
        errorFmt("Uncaught promise rejection: {s}\n", .{err_str.*});
    }
}

// Main loop for running user apps.
pub fn runUserLoop(rt: *RuntimeContext) void {
    var fps_limiter = graphics.DefaultFpsLimiter.init(60);
    var fps: u64 = 0;

    const iso = rt.isolate;
    const ctx = rt.context;

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    defer try_catch.deinit();

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_WINDOWEVENT => {
                    switch (event.window.event) {
                        sdl.SDL_WINDOWEVENT_CLOSE => {
                            rt.deleteCsWindowBySdlId(event.window.windowID);
                        },
                        else => {},
                    }
                },
                sdl.SDL_QUIT => {
                    // We shouldn't need this since we already check the number of open windows.
                },
                else => {},
            }
        }

        const should_update = rt.num_windows > 0;
        if (!should_update) {
            return;
        }

        // FUTURE: This could benefit being in a separate thread.
        rt.work_queue.processDone();

        rt.active_graphics.beginFrame();

        for (rt.active_window.onDrawFrameCbs.items) |onDrawFrame| {
            _ = onDrawFrame.inner.call(ctx, rt.active_window.js_window, &.{
                rt.active_window.js_graphics.toValue(), iso.initNumber(@intToFloat(f64, fps)).toValue(),
            }) orelse {
                const trace = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(trace);
                printFmt("{s}", .{trace});
                return;
            };
        }
        rt.active_graphics.endFrame();

        // TODO: Run any queued micro tasks.

        rt.active_window.window.swapBuffers();

        fps_limiter.endFrameAndDelay();
        fps = fps_limiter.getFps();
    }
}

const ResourceListId = u32;
pub const ResourceId = u32;
const ResourceTag = enum {
    CsWindow,
    CsHttpServer,
    Dummy,
};

pub fn GetResourceTag(comptime T: type) ResourceTag {
    switch (T) {
        *HttpServer => return .CsHttpServer,
        else => @compileError("unreachable"),
    }
}

const ResourceHandle = struct {
    ptr: *anyopaque,
    tag: ResourceTag,
};

fn CreatedResource(comptime T: type) type {
    return struct {
        ptr: *T,
        id: ResourceId,
    };
}

pub const CsWindow = struct {
    const Self = @This();

    window: graphics.Window,
    onDrawFrameCbs: std.ArrayList(v8.Persistent(v8.Function)),
    js_window: v8.Persistent(v8.Object),

    // Currently, each window has its own graphics handle.
    graphics: *graphics.Graphics,
    js_graphics: v8.Persistent(v8.Object),

    pub fn init(self: *Self, alloc: std.mem.Allocator, rt: *RuntimeContext, window: graphics.Window, window_id: ResourceId) void {
        const iso = rt.isolate;
        const ctx = rt.context;
        const js_window = rt.window_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        const js_window_id = iso.initIntegerU32(window_id);
        js_window.setInternalField(0, js_window_id);

        const g = alloc.create(graphics.Graphics) catch unreachable;
        const js_graphics = rt.graphics_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        js_graphics.setInternalField(0, iso.initExternal(g));

        self.* = .{
            .window = window,
            .onDrawFrameCbs = std.ArrayList(v8.Persistent(v8.Function)).init(alloc),
            .js_window = iso.initPersistent(v8.Object, js_window),
            .js_graphics = iso.initPersistent(v8.Object, js_graphics),
            .graphics = g,
        };
        self.graphics.init(alloc, window.getWidth(), window.getHeight());
    }

    pub fn deinit(self: *Self, rt: *RuntimeContext) void {
        self.graphics.deinit();
        rt.alloc.destroy(self.graphics);
        self.window.deinit();
        for (self.onDrawFrameCbs.items) |*onDrawFrame| {
            onDrawFrame.deinit();
        }
        self.onDrawFrameCbs.deinit();
        self.js_window.deinit();
        // Invalidate graphics ptr.
        const iso = rt.isolate;
        const zero = iso.initNumberBitCastedU64(0);
        self.js_graphics.castToObject().setInternalField(0, zero);
        self.js_graphics.deinit();
    }
};

pub fn errorFmt(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(format, args) catch unreachable;
}

pub fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}

fn getSrcPathDirAbs(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.fs.path.dirname(path)) |dir| {
        return try std.fs.path.resolve(alloc, &.{dir});
    } else {
        const cwd = try std.process.getCwdAlloc(alloc);
        defer alloc.free(cwd);
        return try std.fs.path.resolve(alloc, &.{cwd});
    }
}

const api_init = @embedFile("snapshots/api_init.js");
const test_init = @embedFile("snapshots/test_init.js");

pub fn runTestMain(alloc: std.mem.Allocator, src_path: []const u8) !void {
    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

    _ = curl.initDefault();
    defer curl.deinit();

    stdx.http.init();
    defer stdx.http.deinit();

    h2o.init();

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    defer v8.deinitV8Platform();

    v8.initV8();
    defer _ = v8.deinitV8();

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var iso = v8.Isolate.init(&params);
    defer iso.deinit();

    iso.enter();
    defer iso.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    initGlobal(alloc);
    defer deinitGlobal();

    var rt: RuntimeContext = undefined;
    rt.init(alloc, platform, iso, src_path);
    defer rt.deinit();

    rt.is_test_env = true;

    var ctx = js_env.initContext(&rt, iso);
    rt.context = ctx;

    ctx.enter();
    defer ctx.exit();

    {
        // Run api_init.js
        var res: v8.ExecuteResult = undefined;
        defer res.deinit();
        const origin = v8.String.initUtf8(iso, "api_init.js");
        v8.executeString(alloc, iso, ctx, api_init, origin, &res);
    }

    {
        // Run test_init.js
        var res: v8.ExecuteResult = undefined;
        defer res.deinit();
        const origin = v8.String.initUtf8(iso, "test_init.js");
        v8.executeString(alloc, iso, ctx, test_init, origin, &res);
    }

    const origin = v8.String.initUtf8(iso, src_path);

    var res: v8.ExecuteResult = undefined;
    defer res.deinit();
    v8.executeString(alloc, iso, ctx, src, origin, &res);

    processV8EventLoop(&rt);

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        return error.MainScriptError;
    }

    while (rt.num_async_tests_finished < rt.num_async_tests) {
        if (pollMainEventLoop(&rt)) {
            processMainEventLoop(&rt);
            continue;
        } else break;
    }

    if (rt.num_isolated_tests_finished < rt.isolated_tests.items.len) {
        runIsolatedTests(&rt);
    }

    reportUncaughtPromiseRejections();

    // Test results.
    printFmt("Passed: {d}\n", .{rt.num_tests_passed});
    printFmt("Tests: {d}\n", .{rt.num_tests});

    shutdownRuntime(&rt);
}

/// Shutdown other threads gracefully before starting deinit.
fn shutdownRuntime(rt: *RuntimeContext) void {
    rt.uv_poller.close_flag.store(true, .Release);

    // Make uv poller wake up with dummy update.
    _ = uv.uv_async_send(rt.uv_dummy_async);

    // uv poller might be waiting for wakeup.
    rt.uv_poller.wakeup.set();

    // Busy wait.
    while (!rt.uv_poller.close_flag.load(.Acquire)) {}

    // Block on uv loop until all uv handles are done.
    while (rt.num_uv_handles > 0) {
        // RUN_ONCE lets it return after running some events. RUN_DEFAULT keeps blocking since we have dummy async in the queue.
        _ = uv.uv_run(rt.uv_loop, uv.UV_RUN_ONCE);
    }

    // TODO: Shutdown worker threads.
    // Wait for worker queue to finish.
    while (rt.work_queue.hasUnfinishedTasks()) {
        rt.main_wakeup.wait();
        rt.main_wakeup.reset();

        rt.work_queue.processDone();
    }

    // log.debug("shutdown runtime", .{});
}

/// Isolated tests are stored to be run later.
const IsolatedTest = struct {
    const Self = @This();

    name: []const u8,
    js_fn: v8.Persistent(v8.Function),

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        self.js_fn.deinit();
    }
};

/// Waits until there is work to process.
/// If true, a follow up processMainEventLoop should be called to do the work and reset the poller.
/// If false, there are no more pending tasks, and the caller should exit the loop.
fn pollMainEventLoop(rt: *RuntimeContext) bool {
    while (true) {
        // Wait for events.
        // log.debug("main thread wait", .{});
        const Timeout = 4 * 1e9;
        const wait_res = rt.main_wakeup.timedWait(Timeout);
        rt.main_wakeup.reset();
        if (wait_res == .timed_out) {
            if (rt.num_uv_handles > 0) {
                // Continue until no more long lived uv handles.
                continue;
            } else {
                return false;
            }
        }
        return true;
    }
}

fn processMainEventLoop(rt: *RuntimeContext) void {
    // Resolve done tasks.
    rt.work_queue.processDone();

    // Run uv loop tasks.
    // [uv] Poll for i/o once but don’t block if there are no pending callbacks.
    //      Returns zero if done (no active handles or requests left),
    //      or non-zero if more callbacks are expected (meaning you should run the event loop again sometime in the future).
    _ = uv.uv_run(rt.uv_loop, uv.UV_RUN_NOWAIT);
    // log.debug("uv run {}", .{res});

    // After callbacks and js executions are done, process V8 event loop.
    processV8EventLoop(rt);

    // Notify poller to continue.
    rt.uv_poller.wakeup.set();
}

/// If there are too many promises to execute for a js execution, v8 will defer the rest into it's event loop.
/// This is usually called right after a js execution.
fn processV8EventLoop(rt: *RuntimeContext) void {
    while (rt.platform.pumpMessageLoop(rt.isolate, false)) {}
}

fn runIsolatedTests(rt: *RuntimeContext) void {
    const iso = rt.isolate;
    const ctx = rt.context;

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    defer try_catch.deinit();

    var next_test: u32 = 0;

    while (rt.num_isolated_tests_finished < rt.isolated_tests.items.len) {
        if (rt.num_isolated_tests_finished == next_test) {
            // log.debug("run isolated: {} {}", .{next_test, rt.isolated_tests.items.len});

            // Start the next test.
            // Assume async test, should have already validated.
            const case = rt.isolated_tests.items[next_test];
            if (case.js_fn.inner.call(ctx, rt.js_undefined, &.{})) |val| {
                const promise = val.castToPromise();

                const data = iso.initExternal(rt);
                const on_fulfilled = v8.Function.initWithData(ctx, js_env.genJsFuncSync(js_env.passIsolatedTest), data);

                const tmpl = iso.initObjectTemplateDefault();
                tmpl.setInternalFieldCount(2);
                const extra_data = tmpl.initInstance(ctx);
                extra_data.setInternalField(0, data);
                extra_data.setInternalField(1, iso.initStringUtf8(case.name));
                const on_rejected = v8.Function.initWithData(ctx, js_env.genJsFunc(js_env.reportIsolatedTestFailure, false, false), extra_data);

                _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected);

                if (promise.getState() == v8.PromiseState.kRejected or promise.getState() == v8.PromiseState.kFulfilled) {
                    // If the initial async call is already fullfilled or rejected,
                    // we'll need to run microtasks manually to run our handlers.
                    iso.performMicrotasksCheckpoint();
                }
            } else {
                const err_str = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(err_str);
                printFmt("Test: {s}\n{s}", .{ case.name, err_str });
                break;
            }
            next_test += 1;
        }

        // Check if we're done or need to go to the next test.
        if (rt.num_isolated_tests_finished == rt.isolated_tests.items.len) {
            break;
        } else if (rt.num_isolated_tests_finished == next_test) {
            continue;
        }

        if (pollMainEventLoop(rt)) {
            processMainEventLoop(rt);
            continue;
        } else break;
    }

    // Check for any js uncaught exceptions from calling into js.
    if (v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch)) |err_str| {
        defer rt.alloc.free(err_str);
        printFmt("Uncaught Exception:\n{s}", .{ err_str });
    }
}

pub fn runUserMain(alloc: std.mem.Allocator, src_path: []const u8) !void {
    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

    h2o.init();

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    defer v8.deinitV8Platform();

    v8.initV8();
    defer _ = v8.deinitV8();

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var iso = v8.Isolate.init(&params);
    defer iso.deinit();

    iso.enter();
    defer iso.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    initGlobal(alloc);
    defer deinitGlobal();

    var rt: RuntimeContext = undefined;
    rt.init(alloc, platform, iso, src_path);
    defer rt.deinit();

    var ctx = js_env.initContext(&rt, iso);
    rt.context = ctx;

    ctx.enter();
    defer ctx.exit();

    const origin = v8.String.initUtf8(iso, src_path);

    var res: v8.ExecuteResult = undefined;
    defer res.deinit();
    v8.executeString(alloc, iso, ctx, src, origin, &res);

    while (platform.pumpMessageLoop(iso, false)) {
        @panic("Did not expect v8 event loop task");
    }

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        return error.MainScriptError;
    }

    // Check if we need to enter an app loop.
    if (rt.num_windows > 0) {
        runUserLoop(&rt);
    }

    // For now we assume the user won't use a realtime loop with event loop.
    // TODO: process event loop tasks in the realtime loop.
    while (true) {
        if (pollMainEventLoop(&rt)) {
            processMainEventLoop(&rt);
            continue;
        } else break;
    }

    shutdownRuntime(&rt);
}

const WeakHandle = struct {
    const Self = @This();

    ptr: *const anyopaque,
    tag: WeakHandleTag,

    fn deinit(self: *Self, rt: *RuntimeContext) void {
        switch (self.tag) {
            .DrawCommandList => {
                const list = stdx.mem.ptrCastAlign(*const graphics.DrawCommandList, self.ptr);
                list.deinit();
                rt.alloc.destroy(list);
            },
        }
    }
};

const WeakHandleTag = enum {
    DrawCommandList,
};

/// Convenience wrapper around v8 when constructing the v8.Context.
pub const ContextBuilder = struct {
    const Self = @This();

    rt: *RuntimeContext,
    isolate: v8.Isolate,

    pub fn setFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        const data = self.isolate.initExternal(self.rt);
        self.setProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, js_env.genJsFuncSync(native_cb), data));
    }

    pub fn setConstFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        const data = self.isolate.initExternal(self.rt);
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, js_env.genJsFuncSync(native_cb), data));
    }

    pub fn setConstAsyncFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        const data = self.isolate.initExternal(self.rt);
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, js_env.genJsFuncAsync(native_cb), data));
    }

    pub fn setProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
        const js_key = v8.String.initUtf8(self.isolate, key);
        switch (@TypeOf(value)) {
            u32 => {
                tmpl.set(js_key, v8.Integer.initU32(self.isolate, value), v8.PropertyAttribute.None);
            },
            else => {
                tmpl.set(js_key, value, v8.PropertyAttribute.None);
            },
        }
    }

    pub fn setFuncGetter(self: Self, tmpl: v8.FunctionTemplate, key: []const u8, comptime native_val_or_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.isolate, key);
        if (@typeInfo(@TypeOf(native_val_or_cb)) == .Fn) {
            @compileError("TODO");
        } else {
            tmpl.setGetter(js_key, v8.FunctionTemplate.initCallback(self.isolate, js_env.genJsFuncGetValue(native_val_or_cb)));
        }
    }

    pub fn setGetter(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, js_env.genJsGetter(native_cb));
    }

    pub fn setAccessor(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_getter_cb: anytype, comptime native_setter_cb: anytype) void {
        const js_key = self.isolate.initStringUtf8(key);
        tmpl.setGetterAndSetter(js_key, js_env.genJsGetter(native_getter_cb), js_env.genJsSetter(native_setter_cb));
    }

    pub fn setConstProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
        const iso = self.isolate;
        const js_key = iso.initStringUtf8(key);
        switch (@TypeOf(value)) {
            u32 => {
                tmpl.set(js_key, iso.initIntegerU32(value), v8.PropertyAttribute.ReadOnly);
            },
            else => {
                tmpl.set(js_key, value, v8.PropertyAttribute.ReadOnly);
            },
        }
    }

    pub fn initFuncT(self: Self, name: []const u8) v8.FunctionTemplate {
        const iso = self.isolate;
        const new = iso.initFunctionTemplateDefault();
        new.setClassName(iso.initStringUtf8(name));
        return new;
    }
};

pub const SizedJsString = struct {
    str: v8.String,
    len: u32,
};

pub fn appendSizedJsStringAssumeCap(arr: *std.ArrayList(u8), isolate: v8.Isolate, val: SizedJsString) []const u8 {
    const start = arr.items.len;
    arr.items.len = start + val.len;
    _ = val.str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return arr.items[start..];
}

pub fn rejectPromise(rt: *RuntimeContext, promise_id: PromiseId, val: v8.Value) void {
    const resolver = rt.promises.get(promise_id);
    _ = resolver.inner.reject(rt.context, val);
}

pub fn resolvePromise(rt: *RuntimeContext, promise_id: PromiseId, val: v8.Value) void {
    const resolver = rt.promises.get(promise_id);
    _ = resolver.inner.resolve(rt.context, val);
}