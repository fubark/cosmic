const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");
const curl = @import("curl");
const uv = @import("uv");
const h2o = @import("h2o");
const v8 = @import("v8");
const input = @import("input");
const gl = @import("gl");
const builtin = @import("builtin");

const v8x = @import("v8x.zig");
const js_env = @import("js_env.zig");
const log = stdx.log.scoped(.runtime);
const api = @import("api.zig");
const cs_graphics = @import("api_graphics.zig").cs_graphics;
const gen = @import("gen.zig");

const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const tasks = @import("tasks.zig");
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

    platform: v8.Platform,
    isolate: v8.Isolate,
    context: v8.Context,

    // Absolute path of the main script.
    main_script_path: []const u8,

    // This is used to store native string slices copied from v8.String for use in the immediate native callback functions.
    // It will automatically clear at the pre callback step if the current size is too large.
    // Native callback functions that have []const u8 in their params should assume they only live until end of function scope.
    cb_str_buf: std.ArrayList(u8),
    cb_f32_buf: std.ArrayList(f32),

    vec2_buf: std.ArrayList(Vec2),

    js_undefined: v8.Primitive,
    js_null: v8.Primitive,
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

    last_err: CsError,

    // uv_loop_t is quite large, so allocate on heap.
    uv_loop: *uv.uv_loop_t,
    uv_dummy_async: *uv.uv_async_t,
    uv_poller: UvPoller,

    received_uncaught_exception: bool,

    pub fn init(self: *Self, alloc: std.mem.Allocator, platform: v8.Platform, iso: v8.Isolate, main_script_path: []const u8) void {
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
            .platform = platform,
            .isolate = iso,
            .context = undefined,
            .main_script_path = alloc.dupe(u8, main_script_path) catch unreachable,
            .cb_str_buf = std.ArrayList(u8).init(alloc),
            .cb_f32_buf = std.ArrayList(f32).init(alloc),
            .vec2_buf = std.ArrayList(Vec2).init(alloc),

            // Store locally for quick access.
            .js_undefined = iso.initUndefined(),
            .js_null = iso.initNull(),
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
            .received_uncaught_exception = false,
            .last_err = error.NoError,
        };

        self.main_wakeup.init() catch unreachable;

        // Ensure we're using the right headers and the linked uv has patches applied.
        std.debug.assert(uv.uv_loop_size() == @sizeOf(uv.uv_loop_t));

        // Create libuv evloop instance.
        self.uv_loop = alloc.create(uv.uv_loop_t) catch unreachable;
        var res = uv.uv_loop_init(self.uv_loop);
        uv.assertNoError(res);

        const S = struct {
            fn onWatcherQueueChanged(_loop: [*c]uv.uv_loop_t) callconv(.C) void {
                // log.debug("on queue changed", .{});
                const loop = @ptrCast(*uv.uv_loop_t, _loop);
                const rt = stdx.mem.ptrCastAlign(*RuntimeContext, loop.data.?);
                const res_ = uv.uv_async_send(rt.uv_dummy_async);
                uv.assertNoError(res_);
            }
        };
        // Once this is merged: https://github.com/libuv/libuv/pull/3308,
        // we can remove patches/libuv_on_watcher_queue_updated.patch and use the better method.
        self.uv_loop.data = self;
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            self.uv_loop.on_watcher_queue_updated = S.onWatcherQueueChanged;
        }

        // Add dummy handle or UvPoller/uv_backend_timeout will think there is nothing to wait for.
        self.uv_dummy_async = alloc.create(uv.uv_async_t) catch unreachable;
        res = uv.uv_async_init(self.uv_loop, self.uv_dummy_async, null);
        uv.assertNoError(res);

        stdx.http.curlm_uvloop = self.uv_loop;
        stdx.http.uv_interrupt = self.uv_dummy_async;

        // Uv needs to run once to initialize or UvPoller will never get the first event.
        _ = uv.uv_run(self.uv_loop, uv.UV_RUN_NOWAIT);

        // Start uv poller thread.
        self.uv_poller = UvPoller.init(self.uv_loop, &self.main_wakeup);
        _ = std.Thread.spawn(.{}, UvPoller.run, .{&self.uv_poller}) catch unreachable;

        self.work_queue = WorkQueue.init(alloc, self.uv_loop, &self.main_wakeup);
        self.work_queue.createAndRunWorker();

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = .{ .ptr = undefined, .tag = .Dummy, .external_handle = undefined, .deinited = true, .on_deinit_cb = null };
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;
        self.generic_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.generic_resource_list_last = self.resources.getListHead(self.generic_resource_list).?;

        // Set up uncaught promise rejection handler.
        iso.setPromiseRejectCallback(promiseRejectCallback);

        // By default, scripts will automatically run microtasks when call depth returns to zero.
        // It also allows us to use performMicrotasksCheckpoint in cases where we need to sooner.
        iso.setMicrotasksPolicy(v8.MicrotasksPolicy.kAuto);

        // Receive the first uncaught exceptions and find the next opportunity to shutdown.
        const external = iso.initExternal(self).toValue();
        iso.setCaptureStackTraceForUncaughtExceptions(true, 10);
        _ = iso.addMessageListenerWithErrorLevel(v8MessageCallback, v8.MessageErrorLevel.kMessageError, external);

        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Ignore sigpipe for writes to sockets that have already closed and let it return as an error to callers.
            const SIG_IGN = @intToPtr(fn(c_int, *const std.os.siginfo_t, ?*const anyopaque) callconv(.C) void, 1);
            const act = std.os.Sigaction{
                .handler = .{ .sigaction = SIG_IGN },
                .mask = std.os.empty_sigset,
                .flags = 0,
            };
            std.os.sigaction(std.os.SIG.PIPE, &act, null);
        }
    }

    fn deinit(self: *Self) void {
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
            while (iter.nextPtr()) |_| {
                const res_id = iter.idx - 1;
                self.destroyResourceHandle(res_id);
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

        self.alloc.free(self.main_script_path);
    }

    /// Destroys the resource owned by the handle and marks it as deinited.
    /// If the resource can't be deinited immediately, the final deinitResourceHandle call will be deferred.
    pub fn startDeinitResourceHandle(self: *Self, id: ResourceId) void {
        const handle = self.resources.getPtr(id);
        if (handle.deinited) {
            log.err("Already deinited", .{});
            unreachable;
        }
        switch (handle.tag) {
            .CsWindow => {
                // TODO: This should do cleanup like deleteCsWindowBySdlId
                const window = stdx.mem.ptrCastAlign(*CsWindow, handle.ptr);
                window.deinit(self);

                // Update current vars.
                self.num_windows -= 1;
                if (self.num_windows > 0) {
                    if (self.active_window == stdx.mem.ptrCastAlign(*CsWindow, handle.ptr)) {
                        // TODO: Revisit this. For now just pick the last available window.
                        const list_id = self.getListId(handle.tag);
                        if (self.resources.findInList(list_id, {}, findFirstActiveResource)) |res_id| {
                            self.active_window = stdx.mem.ptrCastAlign(*CsWindow, self.resources.get(res_id).ptr);
                        }
                    }
                } else {
                    self.active_window = undefined;
                }
                self.deinitResourceHandleInternal(id);
            },
            .CsHttpServer => {
                const server = stdx.mem.ptrCastAlign(*HttpServer, handle.ptr);
                if (server.closed) {
                    self.deinitResourceHandleInternal(id);
                } else {
                    const S = struct {
                        fn onShutdown(ptr: *anyopaque, _: *HttpServer) void {
                            const ctx = stdx.mem.ptrCastAlign(*ExternalResourceHandle, ptr);
                            ctx.rt.deinitResourceHandleInternal(ctx.res_id);
                        }
                    };
                    // TODO: Should set cb atomically with shutdown op.
                    const cb = stdx.Callback(*anyopaque, *HttpServer).init(handle.external_handle, S.onShutdown);
                    server.on_shutdown_cb = cb;
                    server.requestShutdown();
                    server.deinitPreClosing();
                }
            },
            .Dummy => {},
        }
        handle.deinited = true;
    }

    // Internal func. Called when ready to actually free the handle
    fn deinitResourceHandleInternal(self: *Self, id: ResourceId) void {
        const handle = self.resources.get(id);
        // Fire callback.
        if (handle.on_deinit_cb) |cb| {
            cb.call(id);
        }
        switch (handle.tag) {
            .CsWindow => {
                self.alloc.destroy(stdx.mem.ptrCastAlign(*CsWindow, handle.ptr));
            },
            .CsHttpServer => {
                self.alloc.destroy(stdx.mem.ptrCastAlign(*HttpServer, handle.ptr));
            },
            else => unreachable,
        }
    }

    fn v8MessageCallback(message: ?*const v8.C_Message, value: ?*const v8.C_Value) callconv(.C) void {
        const val = v8.Value{.handle = value.?};
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, val.castTo(v8.External).get());

        // Only interested in the first uncaught exception.
        if (!rt.received_uncaught_exception) {
            // Print the stack trace immediately.
            const js_msg = v8.Message{ .handle = message.? };
            const err_str = v8x.allocPrintMessageStackTrace(rt.alloc, rt.isolate, rt.context, js_msg, "Uncaught Exception");
            defer rt.alloc.free(err_str);
            errorFmt("\n{s}", .{err_str});
            rt.received_uncaught_exception = true;
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
            .external_handle = undefined,
            .deinited = false,
            .on_deinit_cb = null,
        }) catch unreachable;

        const res_id = self.generic_resource_list_last;
        const external = self.alloc.create(ExternalResourceHandle) catch unreachable;
        external.* = .{
            .rt = self,
            .res_id = res_id,
        };
        self.resources.getPtr(res_id).external_handle = external;

        return .{
            .ptr = ptr,
            .id = res_id,
            .external = external,
        };
    }

    pub fn createCsWindowResource(self: *Self) CreatedResource(CsWindow) {
        const ptr = self.alloc.create(CsWindow) catch unreachable;
        self.window_resource_list_last = self.resources.insertAfter(self.window_resource_list_last, .{
            .ptr = ptr,
            .tag = .CsWindow,
            .external_handle = undefined,
            .deinited = false,
            .on_deinit_cb = null,
        }) catch unreachable;

        const res_id = self.window_resource_list_last;
        const external = self.alloc.create(ExternalResourceHandle) catch unreachable;
        external.* = .{
            .rt = self,
            .res_id = res_id,
        };
        self.resources.getPtr(res_id).external_handle = external;

        self.num_windows += 1;
        return .{
            .ptr = ptr,
            .id = res_id,
            .external = external,
        };
    }

    /// Destroys the ResourceHandle and removes it from the runtime. Doing so also frees the resource slot for reuse.
    /// This is called when the js handle invokes the weak finalizer. At that point no js handle
    /// still references the id so it is safe to remove the native handle.
    pub fn destroyResourceHandle(self: *Self, res_id: ResourceId) void {
        if (!self.resources.hasItem(res_id)) {
            log.err("Expected resource id: {}", .{res_id});
            unreachable;
        }
        const res = self.resources.getPtr(res_id);
        if (!res.deinited) {
            self.startDeinitResourceHandle(res_id);
        }

        // The external handle is kept alive after deinit since it's needed by a finalizer callback.
        if (res.tag != .Dummy) {
            self.alloc.destroy(res.external_handle);

            const list_id = self.getListId(res.tag);
            if (self.resources.findInList(list_id, res_id, findPrevResource)) |prev_id| {
                // Remove from resources.
                self.resources.removeNext(prev_id);

                if (res.tag == .CsWindow) {
                    if (self.window_resource_list_last == res_id) {
                        self.window_resource_list_last = prev_id;
                    }
                } else if (res.tag == .CsHttpServer) {
                    if (self.generic_resource_list == res_id) {
                        self.generic_resource_list = prev_id;
                    }
                } else unreachable;
            } else unreachable;
        }
    }

    fn getListId(self: *Self, tag: ResourceTag) ResourceListId {
        switch (tag) {
            .CsWindow => return self.window_resource_list,
            .CsHttpServer => return self.generic_resource_list,
            else => unreachable,
        }
    }

    fn findFirstActiveResource(_: void, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
        return !buf.get(item_id).deinited;
    }

    fn findPrevResource(target: ResourceId, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
        if (buf.getNext(item_id)) |next| {
            return next == target;
        } else return false;
    }

    fn getCsWindowResourceBySdlId(self: *Self, sdl_win_id: u32) ?ResourceId {
        if (graphics.Backend != .OpenGL) {
            @panic("unsupported");
        }
        const S = struct {
            fn pred(_sdl_win_id: u32, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
                const res = buf.get(item_id);
                // Skip dummy head.
                if (res.tag == .Dummy) {
                    return false;
                }
                const cs_window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
                return cs_window.window.inner.id == _sdl_win_id;
            }
        };
        return self.resources.findInList(self.window_resource_list, sdl_win_id, S.pred) orelse return null;
    }

    pub fn getJsValue(self: Self, native_val: anytype) v8.Value {
        return .{
            .handle = self.getJsValuePtr(native_val),
        };
    }

    /// Returns raw value pointer so we don't need to convert back to a v8.Value.
    pub fn getJsValuePtr(self: Self, native_val: anytype) *const v8.C_Value {
        const Type = @TypeOf(native_val);
        const iso = self.isolate;
        const ctx = self.context;
        switch (Type) {
            i16 => return iso.initIntegerI32(native_val).handle,
            u8 => return iso.initIntegerU32(native_val).handle,
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
            cs_graphics.Color => {
                const new = self.color_class.getFunction(ctx).initInstance(ctx, &.{}).?;
                _ = new.setValue(ctx, iso.initStringUtf8("r"), iso.initIntegerU32(native_val.r));
                _ = new.setValue(ctx, iso.initStringUtf8("g"), iso.initIntegerU32(native_val.g));
                _ = new.setValue(ctx, iso.initStringUtf8("b"), iso.initIntegerU32(native_val.b));
                _ = new.setValue(ctx, iso.initStringUtf8("a"), iso.initIntegerU32(native_val.a));
                return new.handle;
            },
            api.cs_files.PathInfo => {
                const new = self.default_obj_t.initInstance(ctx);
                _ = new.setValue(ctx, iso.initStringUtf8("kind"), iso.initStringUtf8(@tagName(native_val.kind)));
                return new.handle;
            },
            Uint8Array => {
                const store = v8.BackingStore.init(iso, native_val.buf.len);
                if (store.getData()) |ptr| {
                    const buf = @ptrCast([*]u8, ptr);
                    std.mem.copy(u8, buf[0..native_val.buf.len], native_val.buf);
                }
                var shared = store.toSharedPtr();
                defer v8.BackingStore.sharedPtrReset(&shared);

                const array_buffer = v8.ArrayBuffer.initWithBackingStore(iso, &shared);
                const js_uint8arr = v8.Uint8Array.init(array_buffer, 0, native_val.buf.len);
                return js_uint8arr.handle;
            },
            v8.Boolean => return native_val.handle,
            v8.Object => return native_val.handle,
            v8.Promise => return native_val.handle,
            []const u8 => {
                return iso.initStringUtf8(native_val).handle;
            },
            []const api.cs_files.FileEntry => {
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
                return stdx.mem.ptrCastAlign(*const v8.C_Value, native_val);
            },
            v8.Persistent(v8.Object) => {
                return native_val.inner.handle;
            },
            else => {
                if (@typeInfo(Type) == .Optional) {
                    if (native_val) |child_val| {
                        return self.getJsValuePtr(child_val);
                    } else {
                        return self.js_null.handle;
                    }
                } else if (@hasDecl(Type, "ManagedSlice")) {
                    return self.getJsValuePtr(native_val.slice);
                } else if (@hasDecl(Type, "ManagedStruct")) {
                    return self.getJsValuePtr(native_val.val);
                } else if (@typeInfo(Type) == .Struct) {
                    // Generic struct to js object.
                    const obj = iso.initObject();
                    const Fields = std.meta.fields(Type);
                    inline for (Fields) |Field| {
                        _ = obj.setValue(ctx, iso.initStringUtf8(Field.name), self.getJsValue(@field(native_val, Field.name)));
                    }
                    return obj.handle;
                } else if (@typeInfo(Type) == .Enum) {
                    if (@hasDecl(Type, "IsStringSumType")) {
                        // string value.
                        return iso.initStringUtf8(@tagName(native_val)).handle;
                    } else {
                        // int value.
                        return iso.initIntegerU32(@enumToInt(native_val)).handle;
                    }
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
                    const len = val.castTo(v8.Array).length();
                    var i: u32 = 0;
                    const obj = val.castTo(v8.Object);
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
                    return v8x.appendValueAsUtf8(&self.cb_str_buf, self.isolate, ctx, val);
                }
            },
            bool => return val.toBool(self.isolate),
            i32 => return val.toI32(ctx),
            u8 => return @intCast(u8, val.toU32(ctx)),
            u16 => return @intCast(u16, val.toU32(ctx)),
            u32 => return val.toU32(ctx),
            f32 => return val.toF32(ctx),
            graphics.Image => {
                if (val.isObject()) {
                    const obj = val.castTo(v8.Object);
                    if (obj.toValue().instanceOf(ctx, self.image_class.getFunction(ctx).toObject())) {
                        const image_id = obj.getInternalField(0).toU32(ctx);
                        return graphics.Image{ .id = image_id, .width = 0, .height = 0 };
                    }
                }
                return null;
            },
            Uint8Array => {
                if (val.isUint8Array()) {
                    var shared_store = val.castTo(v8.ArrayBufferView).getBuffer().getBackingStore();
                    defer v8.BackingStore.sharedPtrReset(&shared_store);

                    const store = v8.BackingStore.sharedPtrGet(&shared_store);
                    const len = store.getByteLength();
                    if (len > 0) {
                        const buf = @ptrCast([*]u8, store.getData().?);
                        return Uint8Array{ .buf = buf[0..len] };
                    } else return Uint8Array{ .buf = "" };
                } else return null;
            },
            v8.Uint8Array => {
                if (val.isUint8Array()) {
                    return val.castTo(v8.Uint8Array);
                } else return null;
            },
            v8.Function => {
                if (val.isFunction()) {
                    return val.castTo(v8.Function);
                } else return null;
            },
            v8.Object => {
                if (val.isObject()) {
                    return val.castTo(v8.Object);
                } else return null;
            },
            v8.Value => return val,
            std.StringHashMap([]const u8) => {
                if (val.isObject()) {
                    const obj = val.castTo(v8.Object);
                    var native_val = std.StringHashMap([]const u8).init(self.alloc);

                    const keys = obj.getOwnPropertyNames(ctx);
                    const keys_obj = keys.castTo(v8.Object);
                    const num_keys = keys.length();
                    var i: u32 = 0;
                    while (i < num_keys) {
                        const native_key = v8x.allocPrintValueAsUtf8(self.alloc, self.isolate, ctx, keys_obj.getAtIndex(ctx, i));
                        native_val.put(native_key, self.getNativeValue([]const u8, keys_obj.getAtIndex(ctx, i)).?) catch unreachable;
                    }
                    return native_val;
                } else return null;
            },
            else => {
                if (@typeInfo(T) == .Struct) {
                    if (val.isObject()) {
                        const obj = val.castTo(v8.Object);
                        var native_val: T = undefined;
                        if (comptime hasAllOptionalFields(T)) {
                            native_val = .{};
                        }
                        const Fields = std.meta.fields(T);
                        inline for (Fields) |Field| {
                            if (@typeInfo(Field.field_type) == .Optional) {
                                const js_val = obj.getValue(ctx, self.isolate.initStringUtf8(Field.name));
                                const ChildType = comptime @typeInfo(Field.field_type).Optional.child;
                                if (self.getNativeValue(ChildType, js_val)) |child_value| {
                                    @field(native_val, Field.name) = child_value;
                                } else {
                                    @field(native_val, Field.name) = null;
                                }
                            } else {
                                const js_val = obj.getValue(ctx, self.isolate.initStringUtf8(Field.name));
                                if (self.getNativeValue(Field.field_type, js_val)) |child_value| {
                                    @field(native_val, Field.name) = child_value;
                                }
                            }
                        }
                        return native_val;
                    } else return null;
                } else if (@typeInfo(T) == .Enum) {
                    // Compare with lower case.
                    const lower = v8x.appendValueAsUtf8Lower(&self.cb_str_buf, self.isolate, ctx, val);
                    const Fields = @typeInfo(T).Enum.fields;
                    inline for (Fields) |Field| {
                        if (std.mem.eql(u8, lower, comptime ctLower(Field.name))) {
                            return @intToEnum(T, Field.value);
                        }
                    }
                    return null;
                } else {
                    comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to {s}", .{ @typeName(@TypeOf(val)), @typeName(T) }));
                }
            },
        }
    }

    fn handleMouseDownEvent(self: *Self, e: api.cs_input.MouseDownEvent) void {
        const ctx = self.context;
        if (self.active_window.on_mouse_down_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleMouseUpEvent(self: *Self, e: api.cs_input.MouseUpEvent) void {
        const ctx = self.context;
        if (self.active_window.on_mouse_up_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleMouseMoveEvent(self: *Self, e: api.cs_input.MouseMoveEvent) void {
        const ctx = self.context;
        if (self.active_window.on_mouse_move_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleKeyUpEvent(self: *Self, e: api.cs_input.KeyUpEvent) void {
        const ctx = self.context;
        if (self.active_window.on_key_up_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleKeyDownEvent(self: *Self, e: api.cs_input.KeyDownEvent) void {
        const ctx = self.context;
        if (self.active_window.on_key_down_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }
};

fn hasAllOptionalFields(comptime T: type) bool {
    const Fields = comptime std.meta.fields(T);
    inline for (Fields) |Field| {
        if (Field.default_value == null) {
            return false;
        }
    }
    return true;
}

pub fn ctLower(comptime str: []const u8) []const u8 {
    return comptime blk :{
        var lower: []const u8 = &.{};
        for (str) |ch| {
            lower = lower ++ &[_]u8{std.ascii.toLower(ch)};
        }
        break :blk lower;
    };
}

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

/// To be converted to v8.Uint8Array.
pub const Uint8Array =  struct {
    buf: []const u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.buf);
    }
};

/// A struct that knows how to deinit itself.
pub fn ManagedStruct(comptime T: type) type {
    return struct {
        pub const ManagedStruct = true;

        alloc: std.mem.Allocator,
        val: T,

        pub fn init(alloc: std.mem.Allocator, val: T) @This() {
            return .{ .alloc = alloc, .val = val };
        }

        pub fn deinit(self: @This()) void {
            self.val.deinit(self.alloc);
        }
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
            const str = v8x.allocPrintValueAsUtf8(galloc, iso, ctx, msg.getValue());
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
    const iso = rt.isolate;

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    // Allow uncaught exceptions to reach message listener.
    try_catch.setVerbose(true);
    defer try_catch.deinit();

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_WINDOWEVENT => {
                    switch (event.window.event) {
                        sdl.SDL_WINDOWEVENT_CLOSE => {
                            if (rt.getCsWindowResourceBySdlId(event.window.windowID)) |res_id| {
                                rt.startDeinitResourceHandle(res_id);
                            }
                        },
                        else => {},
                    }
                },
                sdl.SDL_KEYDOWN => {
                    const std_event = input.initSdlKeyDownEvent(event.key);
                    rt.handleKeyDownEvent(api.fromStdKeyDownEvent(std_event));
                },
                sdl.SDL_KEYUP => {
                    const std_event = input.initSdlKeyUpEvent(event.key);
                    rt.handleKeyUpEvent(api.fromStdKeyUpEvent(std_event));
                },
                sdl.SDL_MOUSEBUTTONDOWN => {
                    const std_event = input.initSdlMouseDownEvent(event.button);
                    rt.handleMouseDownEvent(api.fromStdMouseDownEvent(std_event));
                },
                sdl.SDL_MOUSEBUTTONUP => {
                    const std_event = input.initSdlMouseUpEvent(event.button);
                    rt.handleMouseUpEvent(api.fromStdMouseUpEvent(std_event));
                },
                sdl.SDL_MOUSEMOTION => {
                    if (rt.active_window.on_mouse_move_cb != null) {
                        const std_event = input.initSdlMouseMoveEvent(event.motion);
                        rt.handleMouseMoveEvent(api.fromStdMouseMoveEvent(std_event));
                    }
                },
                sdl.SDL_QUIT => {
                    // This can fire if the last window was closed or we received a sigint.
                    // If we created a window, it will capture the keyboard input so the terminal won't detect ctrl+c.
                    return;
                },
                else => {},
            }
        }

        const should_update = rt.num_windows > 0 and !rt.received_uncaught_exception;
        if (!should_update) {
            return;
        }

        rt.work_queue.processDone();

        if (rt.num_windows == 1) {
            updateSingleWindow(rt);
        } else {
            updateMultipleWindows(rt);
        }
    }
}

fn updateMultipleWindows(rt: *RuntimeContext) void {
    const ctx = rt.context;

    // Currently, we just use the smallest delay. This forces larger target fps to be update more frequently.
    // TODO: Make windows with varying target fps work.
    var min_delay: u64 = std.math.maxInt(u64);

    var cur_res = rt.resources.getListHead(rt.window_resource_list);
    cur_res = rt.resources.getNext(cur_res.?);
    while (cur_res) |res_id| {
        const res = rt.resources.get(res_id);
        if (res.deinited) {
            cur_res = rt.resources.getNext(res_id);
            continue;
        }
        const win = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);

        win.window.makeCurrent();
        win.window.beginFrame();

        // Start frame timer after beginFrame since it could delay to sync with OpenGL pipeline.
        win.fps_limiter.beginFrame();

        if (win.on_update_cb) |cb| {
            const g_ctx = win.js_graphics.toValue();
            _ = cb.inner.call(ctx, win.js_window, &.{ g_ctx }) orelse {
                // const trace = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                // defer rt.alloc.free(trace);
                // errorFmt("{s}", .{trace});
                // return;
            };
        }

        win.window.endFrame();
        const delay = win.fps_limiter.endFrame();
        if (delay < min_delay) {
            min_delay = delay;
        }

        // swapBuffers will delay if vsync is on.
        win.window.swapBuffers();

        cur_res = rt.resources.getNext(res_id);
    }

    graphics.delay(min_delay);

    // TODO: Run any queued micro tasks.
}

fn updateSingleWindow(rt: *RuntimeContext) void {
    const ctx = rt.context;
    rt.active_window.window.beginFrame();

    // Start frame timer after beginFrame since it could delay to sync with OpenGL pipeline.
    rt.active_window.fps_limiter.beginFrame();

    if (rt.active_window.on_update_cb) |cb| {
        const g_ctx = rt.active_window.js_graphics.toValue();
        _ = cb.inner.call(ctx, rt.active_window.js_window, &.{ g_ctx }) orelse {
            // const trace = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
            // defer rt.alloc.free(trace);
            // errorFmt("{s}", .{trace});
            // return;
        };
    }

    rt.active_window.window.endFrame();
    const delay = rt.active_window.fps_limiter.endFrame();
    if (delay > 0) {
        graphics.delay(delay);
    }

    // TODO: Run any queued micro tasks.

    // swapBuffers will delay if vsync is on.
    rt.active_window.window.swapBuffers();
}

const ResourceListId = u32;
pub const ResourceId = u32;
const ResourceTag = enum {
    CsWindow,
    CsHttpServer,
    Dummy,
};

pub fn Resource(comptime Tag: ResourceTag) type {
    switch (Tag) {
        .CsWindow => return CsWindow,
        .CsHttpServer => return HttpServer,
        else => unreachable,
    }
}

pub fn GetResourceTag(comptime T: type) ResourceTag {
    switch (T) {
        *HttpServer => return .CsHttpServer,
        else => @compileError("unreachable"),
    }
}

const ResourceHandle = struct {
    ptr: *anyopaque,
    tag: ResourceTag,

    // Passed into a weak finalizer callback.
    external_handle: *ExternalResourceHandle,

    // Whether the underlying resource has been deinited.
    // The handle can still remain until the js handle is no longer used.
    deinited: bool,

    on_deinit_cb: ?stdx.Callback(*anyopaque, ResourceId),
};

fn CreatedResource(comptime T: type) type {
    return struct {
        ptr: *T,
        id: ResourceId,
        external: *ExternalResourceHandle,
    };
}

pub const CsWindow = struct {
    const Self = @This();

    window: graphics.Window,
    on_update_cb: ?v8.Persistent(v8.Function),
    on_mouse_up_cb: ?v8.Persistent(v8.Function),
    on_mouse_down_cb: ?v8.Persistent(v8.Function),
    on_mouse_move_cb: ?v8.Persistent(v8.Function),
    on_key_up_cb: ?v8.Persistent(v8.Function),
    on_key_down_cb: ?v8.Persistent(v8.Function),
    js_window: v8.Persistent(v8.Object),

    // Managed by window handle.
    graphics: *graphics.Graphics,
    js_graphics: v8.Persistent(v8.Object),

    fps_limiter: graphics.DefaultFpsLimiter,

    pub fn init(self: *Self, rt: *RuntimeContext, window: graphics.Window, window_id: ResourceId) void {
        const iso = rt.isolate;
        const ctx = rt.context;
        const js_window = rt.window_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        const js_window_id = iso.initIntegerU32(window_id);
        js_window.setInternalField(0, js_window_id);

        const g = window.getGraphics();
        const js_graphics = rt.graphics_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        js_graphics.setInternalField(0, iso.initExternal(g));

        self.* = .{
            .window = window,
            .on_update_cb = null,
            .on_mouse_up_cb = null,
            .on_mouse_down_cb = null,
            .on_mouse_move_cb = null,
            .on_key_up_cb = null,
            .on_key_down_cb = null,
            .js_window = iso.initPersistent(v8.Object, js_window),
            .js_graphics = iso.initPersistent(v8.Object, js_graphics),
            .graphics = g,
            .fps_limiter = graphics.DefaultFpsLimiter.init(60),
        };
    }

    pub fn deinit(self: *Self, rt: *RuntimeContext) void {
        self.window.deinit();

        if (self.on_update_cb) |*cb| {
            cb.deinit();
        }
        if (self.on_mouse_up_cb) |*cb| {
            cb.deinit();
        }
        if (self.on_mouse_down_cb) |*cb| {
            cb.deinit();
        }
        if (self.on_mouse_move_cb) |*cb| {
            cb.deinit();
        }
        if (self.on_key_up_cb) |*cb| {
            cb.deinit();
        }
        if (self.on_key_down_cb) |*cb| {
            cb.deinit();
        }

        self.js_window.deinit();
        // Invalidate graphics ptr.
        const iso = rt.isolate;
        const zero = iso.initNumberBitCastedU64(0);
        self.js_graphics.castToObject().setInternalField(0, zero);
        self.js_graphics.deinit();
    }
};

pub fn onFreeResource(c_info: ?*const v8.C_WeakCallbackInfo) callconv(.C) void {
    const info = v8.WeakCallbackInfo.initFromC(c_info);
    const ptr = info.getParameter();
    const external = stdx.mem.ptrCastAlign(*ExternalResourceHandle, ptr);
    external.rt.destroyResourceHandle(external.res_id);
}

pub fn errorFmt(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(format, args) catch unreachable;
}

pub fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}

const api_init = @embedFile("snapshots/api_init.js");
const test_init = @embedFile("snapshots/test_init.js");

pub fn runTestMain(alloc: std.mem.Allocator, src_path: []const u8) !bool {
    // Measure total time.
    const timer = try std.time.Timer.start();
    defer {
        const duration = timer.read();
        printFmt("time: {}ms\n", .{duration / @floatToInt(u64, 1e6)});
    }

    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

    _ = curl.initDefault();
    defer curl.deinit();

    stdx.http.init(alloc);
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

    const abs_path = try std.fs.cwd().realpathAlloc(alloc, src_path);
    defer alloc.free(abs_path);

    var rt: RuntimeContext = undefined;
    rt.init(alloc, platform, iso, abs_path);
    defer rt.deinit();

    rt.is_test_env = true;

    var ctx = js_env.initContext(&rt, iso);
    rt.context = ctx;

    ctx.enter();
    defer ctx.exit();

    {
        // Run api_init.js
        var res: v8x.ExecuteResult = undefined;
        defer res.deinit();
        const origin = v8.String.initUtf8(iso, "api_init.js");
        v8x.executeString(alloc, iso, ctx, api_init, origin, &res);
        if (!res.success) {
            errorFmt("{s}", .{res.err.?});
            return error.InitScriptError;
        }
    }

    {
        // Run test_init.js
        var res: v8x.ExecuteResult = undefined;
        defer res.deinit();
        const origin = v8.String.initUtf8(iso, "test_init.js");
        v8x.executeString(alloc, iso, ctx, test_init, origin, &res);
        if (!res.success) {
            errorFmt("{s}", .{res.err.?});
            return error.TestInitScriptError;
        }
    }

    const origin = v8.String.initUtf8(iso, src_path);

    var res: v8x.ExecuteResult = undefined;
    defer res.deinit();
    v8x.executeString(alloc, iso, ctx, src, origin, &res);

    processV8EventLoop(&rt);

    if (!res.success) {
        errorFmt("{s}", .{res.err.?});
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

    return rt.num_tests_passed == rt.num_tests;
}

/// Shutdown other threads gracefully before starting deinit.
fn shutdownRuntime(rt: *RuntimeContext) void {
    rt.uv_poller.close_flag.store(true, .Release);

    // Make uv poller wake up with dummy update.
    _ = uv.uv_async_send(rt.uv_dummy_async);

    // uv poller might be waiting for wakeup.
    rt.uv_poller.wakeup.set();

    // Busy wait.
    while (rt.uv_poller.close_flag.load(.Acquire)) {}

    // Request workers to close.
    // On MacOS, it's especially important to make sure semaphores (eg. std.Thread.ResetEvent)
    // are not in use (their counters should be reset to the original value) or we'll get an error from libdispatch.
    for (rt.work_queue.workers.items) |worker| {
        worker.close_flag.store(true, .Release);
        worker.wakeup.set();
    }

    uv.uv_stop(rt.uv_loop);
    // Walk and close every handle.
    const S = struct {
        fn closeHandle(handle: [*c]uv.uv_handle_t, ctx: ?*anyopaque) callconv(.C) void {
            _ = ctx;
            uv.uv_close(@ptrCast(*uv.uv_handle_t, handle), null);
        }
    };
    uv.uv_walk(rt.uv_loop, S.closeHandle, null);
    while (uv.uv_run(rt.uv_loop, uv.UV_RUN_NOWAIT) > 0) {}
    const res = uv.uv_loop_close(rt.uv_loop);
    if (res == uv.UV_EBUSY) {
        @panic("Did not expect more work.");
    }

    // Wait for workers to close.
    for (rt.work_queue.workers.items) |worker| {
        while (worker.close_flag.load(.Acquire)) {}
    }

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

/// Returns whether there are pending events in libuv or the work queue.
inline fn hasPendingEvents(rt: *RuntimeContext) bool {
    // log.debug("hasPending {} {} {} {}", .{rt.uv_loop.active_handles, rt.uv_loop.active_reqs.count, rt.uv_loop.closing_handles !=null, rt.work_queue.hasUnfinishedTasks()});

    // There will at least be 1 active handle (the dummy async handle used to do interrupts from main thread).
    // uv handle checks is based on uv_loop_alive():
    if (builtin.os.tag == .windows) {
        return rt.uv_loop.active_handles > 1 or 
            rt.uv_loop.active_reqs.count > 0 or
            rt.uv_loop.endgame_handles != null or 
            rt.work_queue.hasUnfinishedTasks();
    } else {
        return rt.uv_loop.active_handles > 1 or 
            rt.uv_loop.active_reqs.count > 0 or
            rt.uv_loop.closing_handles != null or 
            rt.work_queue.hasUnfinishedTasks();
    }
}

/// Waits until there is work to process if there is work in progress.
/// If true, a follow up processMainEventLoop should be called to do the work and reset the poller.
/// If false, there are no more pending tasks, and the caller should exit the loop.
fn pollMainEventLoop(rt: *RuntimeContext) bool {
    while (hasPendingEvents(rt)) {
        // Wait for events.
        // log.debug("main thread wait", .{});
        const Timeout = 4 * 1e9;
        const wait_res = rt.main_wakeup.timedWait(Timeout);
        rt.main_wakeup.reset();
        if (wait_res == .timed_out) {
            continue;
        }
        return true;
    }
    return false;
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
            // Start the next test.
            // Assume async test, should have already validated.
            const case = rt.isolated_tests.items[next_test];
            // log.debug("run isolated: {}/{} {s}", .{next_test, rt.isolated_tests.items.len, case.name});
            if (case.js_fn.inner.call(ctx, rt.js_undefined, &.{})) |val| {
                const promise = val.castTo(v8.Promise);

                const data = iso.initExternal(rt);
                const on_fulfilled = v8.Function.initWithData(ctx, gen.genJsFuncSync(passIsolatedTest), data);

                const tmpl = iso.initObjectTemplateDefault();
                tmpl.setInternalFieldCount(2);
                const extra_data = tmpl.initInstance(ctx);
                extra_data.setInternalField(0, data);
                extra_data.setInternalField(1, iso.initStringUtf8(case.name));
                const on_rejected = v8.Function.initWithData(ctx, gen.genJsFunc(reportIsolatedTestFailure, .{
                    .asyncify = false,
                    .is_data_rt = false,
                }), extra_data);

                _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected);

                if (promise.getState() == v8.PromiseState.kRejected or promise.getState() == v8.PromiseState.kFulfilled) {
                    // If the initial async call is already fullfilled or rejected,
                    // we'll need to run microtasks manually to run our handlers.
                    iso.performMicrotasksCheckpoint();
                }
            } else {
                const err_str = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(err_str);
                errorFmt("Test: {s}\n{s}", .{ case.name, err_str });
                break;
            }
            next_test += 1;
        }

        if (pollMainEventLoop(rt)) {
            processMainEventLoop(rt);
            continue;
        } else {
            // Nothing in event queue.

            // Check if we're done or need to go to the next test.
            if (rt.num_isolated_tests_finished == rt.isolated_tests.items.len) {
                break;
            } else if (rt.num_isolated_tests_finished == next_test) {
                continue;
            }
            break;
        }
    }

    // Check for any js uncaught exceptions from calling into js.
    if (v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch)) |err_str| {
        defer rt.alloc.free(err_str);
        errorFmt("Uncaught Exception:\n{s}", .{ err_str });
    }
}

pub fn runUserMain(alloc: std.mem.Allocator, src_path: []const u8) !void {
    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

    _ = curl.initDefault();
    defer curl.deinit();

    stdx.http.init(alloc);
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

    const abs_path = try std.fs.cwd().realpathAlloc(alloc, src_path);
    defer alloc.free(abs_path);

    var rt: RuntimeContext = undefined;
    rt.init(alloc, platform, iso, abs_path);
    defer {
        shutdownRuntime(&rt);
        rt.deinit();
    }

    var ctx = js_env.initContext(&rt, iso);
    rt.context = ctx;

    ctx.enter();
    defer ctx.exit();

    {
        // Run api_init.js
        var res: v8x.ExecuteResult = undefined;
        defer res.deinit();
        const origin = v8.String.initUtf8(iso, "api_init.js");
        v8x.executeString(alloc, iso, ctx, api_init, origin, &res);
        if (!res.success) {
            errorFmt("{s}", .{res.err.?});
            return error.InitScriptError;
        }
    }

    const origin = v8.String.initUtf8(iso, src_path);

    var res: v8x.ExecuteResult = undefined;
    defer res.deinit();
    v8x.executeString(alloc, iso, ctx, src, origin, &res);

    processV8EventLoop(&rt);

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
}

const WeakHandle = struct {
    const Self = @This();

    ptr: *const anyopaque,
    tag: WeakHandleTag,

    fn deinit(self: *Self, rt: *RuntimeContext) void {
        switch (self.tag) {
            .DrawCommandList => {
                const ptr = stdx.mem.ptrCastAlign(*const RuntimeValue(graphics.DrawCommandList), self.ptr);
                ptr.inner.deinit();
                rt.alloc.destroy(ptr);
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
        self.setProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, gen.genJsFuncSync(native_cb), data));
    }

    pub fn setConstFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        const data = self.isolate.initExternal(self.rt);
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, gen.genJsFuncSync(native_cb), data));
    }

    pub fn setConstAsyncFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        const data = self.isolate.initExternal(self.rt);
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallbackData(self.isolate, gen.genJsFuncAsync(native_cb), data));
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
            const data = self.isolate.initExternal(self.rt);
            tmpl.setGetter(js_key, v8.FunctionTemplate.initCallbackData(self.isolate, gen.genJsFuncGetValue(native_val_or_cb), data));
        }
    }

    pub fn setGetter(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.isolate, key);
        tmpl.setGetter(js_key, gen.genJsGetter(native_cb));
    }

    pub fn setAccessor(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_getter_cb: anytype, comptime native_setter_cb: anytype) void {
        const js_key = self.isolate.initStringUtf8(key);
        tmpl.setGetterAndSetter(js_key, gen.genJsGetter(native_getter_cb), gen.genJsSetter(native_setter_cb));
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

pub fn rejectPromise(rt: *RuntimeContext, promise_id: PromiseId, native_val: anytype) void {
    const js_val_ptr = rt.getJsValuePtr(native_val);
    const resolver = rt.promises.get(promise_id);
    _ = resolver.inner.reject(rt.context, .{ .handle = js_val_ptr });
}

pub fn resolvePromise(rt: *RuntimeContext, promise_id: PromiseId, native_val: anytype) void {
    const js_val_ptr = rt.getJsValuePtr(native_val);
    const resolver = rt.promises.get(promise_id);
    _ = resolver.inner.resolve(rt.context, .{ .handle = js_val_ptr });
}

/// A struct that also has the runtime context.
pub fn RuntimeValue(comptime T: type) type {
    return struct {
        rt: *RuntimeContext,
        inner: T,
    };
}

// Holds the rt and resource id for passing into a callback.
const ExternalResourceHandle = struct {
    rt: *RuntimeContext,
    res_id: ResourceId,
};

// This is converted from a js object that has a resource id in their first internal field.
pub fn ThisResource(comptime Tag: ResourceTag) type {
    return struct {
        pub const ThisResource = true;

        res_id: ResourceId,
        res: *Resource(Tag),
        obj: v8.Object,
    };
}

pub const This = struct {
    obj: v8.Object,
};

// Attached function data.
pub const Data = struct {
    val: v8.Value,
};

fn reportIsolatedTestFailure(data: Data, val: v8.Value) void {
    const obj = data.val.castTo(v8.Object);
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castTo(v8.External).get());

    const test_name = v8x.allocPrintValueAsUtf8(rt.alloc, rt.isolate, rt.context, obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    rt.num_isolated_tests_finished += 1;
    const str = v8x.allocPrintValueAsUtf8(rt.alloc, rt.isolate, rt.context, val);
    defer rt.alloc.free(str);

    // TODO: Show stack trace.
    printFmt("Test Failed: \"{s}\"\n{s}\n", .{test_name, str});
}

fn passIsolatedTest(rt: *RuntimeContext) void {
    rt.num_isolated_tests_finished += 1;
    rt.num_tests_passed += 1;
}

const Promise = struct {
    task_id: u32,
};

pub fn invokeFuncAsync(rt: *RuntimeContext, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) v8.Promise {
    const ClosureTask = tasks.ClosureTask(func);
    const task = ClosureTask{
        .alloc = rt.alloc,
        .args = args,
    };

    const iso = rt.isolate;
    const ctx = rt.context;
    const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(ctx));
    const promise = resolver.inner.getPromise();
    const promise_id = rt.promises.add(resolver) catch unreachable;
    const S = struct {
        fn onSuccess(_ctx: RuntimeValue(PromiseId), _res: TaskOutput(ClosureTask)) void {
            const _promise_id = _ctx.inner;
            resolvePromise(_ctx.rt, _promise_id, _res);
        }
        fn onFailure(_ctx: RuntimeValue(PromiseId), _err: anyerror) void {
            const _promise_id = _ctx.inner;
            rejectPromise(_ctx.rt, _promise_id, _err);
        }
    };
    const task_ctx = RuntimeValue(PromiseId){
        .rt = rt,
        .inner = promise_id,
    };
    _ = rt.work_queue.addTaskWithCb(task, task_ctx, S.onSuccess, S.onFailure);

    return promise;
}

pub const CsError = error {
    NoError,
    FileNotFound,
    IsDir,
};