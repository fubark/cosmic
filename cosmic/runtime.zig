const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");
const curl = @import("curl");

const v8 = @import("v8.zig");
const js_env = @import("js_env.zig");
const log = stdx.log.scoped(.runtime);

const work_queue = @import("work_queue.zig");
const WorkQueue = work_queue.WorkQueue;

pub const PromiseId = u32;

// Manages runtime resources.
// Used by V8 callback functions.
pub const RuntimeContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    str_buf: std.ArrayList(u8),

    window_class: v8.FunctionTemplate,
    graphics_class: v8.FunctionTemplate,
    image_class: v8.FunctionTemplate,
    color_class: v8.FunctionTemplate,
    handle_class: v8.ObjectTemplate,
    default_obj_t: v8.ObjectTemplate,

    // Collection of mappings from id to resource handles.
    resources: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle),

    weak_handles: ds.CompactUnorderedList(u32, WeakHandle),

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

    work_queue: WorkQueue,

    promises: ds.CompactUnorderedList(PromiseId, v8.Persistent(v8.PromiseResolver)),

    has_background_task: bool,

    pub fn init(self: *Self, alloc: std.mem.Allocator, platform: v8.Platform, iso: v8.Isolate, src_path: []const u8) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .color_class = undefined,
            .graphics_class = undefined,
            .image_class = undefined,
            .handle_class = undefined,
            .default_obj_t = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .weak_handles = ds.CompactUnorderedList(u32, WeakHandle).init(alloc),
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
            .js_undefined = v8.initUndefined(iso),
            .js_false = v8.initFalse(iso),

            .is_test_env = false,
            .num_tests = 0,
            .num_tests_passed = 0,
            .num_async_tests = 0,
            .num_async_tests_finished = 0,
            .num_async_tests_passed = 0,
            .num_isolated_tests_finished = 0,
            .isolated_tests = std.ArrayList(IsolatedTest).init(alloc),

            .work_queue = WorkQueue.init(alloc),
            .promises = ds.CompactUnorderedList(PromiseId, v8.Persistent(v8.PromiseResolver)).init(alloc),
            .has_background_task = false,
        };
        self.work_queue.createAndRunWorker();

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = .{ .ptr = undefined, .tag = .Dummy };
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;

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
                switch (item.data.tag) {
                    .CsWindow => {
                        const window = stdx.mem.ptrCastAlign(*CsWindow, item.data.ptr);
                        window.deinit(self);
                        self.alloc.destroy(window);
                    },
                    .Dummy => {},
                }
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

    fn deleteCsWindowBySdlId(self: *Self, sdl_win_id: u32) void {
        // Head is always a dummy resource for convenience.
        var last_window_id: ResourceId = self.resources.getListHead(self.window_resource_list).?;
        var mb_window_id = self.resources.getNext(last_window_id);
        while (mb_window_id) |window_id| {
            const res = self.resources.get(window_id);
            const cs_window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
            switch (graphics.Backend) {
                .OpenGL => {
                    if (cs_window.window.inner.id == sdl_win_id) {
                        // Deinit and destroy.
                        cs_window.deinit(self);
                        self.alloc.destroy(cs_window);

                        // Remove from resources.
                        self.resources.removeNext(last_window_id);

                        // Update current vars.
                        if (self.window_resource_list_last == window_id) {
                            self.window_resource_list_last = last_window_id;
                        }
                        self.num_windows -= 1;
                        if (self.num_windows > 0) {
                            if (self.active_window == cs_window) {
                                // TODO: Revisit this. For now just pick the last window.
                                self.active_window = stdx.mem.ptrCastAlign(*CsWindow, self.resources.get(last_window_id).ptr);
                                self.active_graphics = self.active_window.graphics;
                            }
                        } else {
                            self.active_window = undefined;
                            self.active_graphics = undefined;
                        }
                        break;
                    }
                },
                else => stdx.panic("unsupported"),
            }
            last_window_id = window_id;
            mb_window_id = self.resources.getNext(window_id);
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
                const trace = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch);
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
const ResourceId = u32;
const ResourceTag = enum {
    CsWindow,
    Dummy,
};

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
        const js_graphics_ptr = iso.initNumberBitCastedU64(@ptrToInt(g));
        js_graphics.setInternalField(0, js_graphics_ptr);

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

    while (platform.pumpMessageLoop(iso, false)) {
        log.debug("What does this do?", .{});
        unreachable;
    }

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        return error.MainScriptError;
    }

    while (rt.num_async_tests_finished < rt.num_async_tests) {
        rt.work_queue.processDone();
        // Wait on the next done.
        const Timeout = 4 * 1e9;
        const wait_res = rt.work_queue.done_wakeup.timedWait(Timeout);
        rt.work_queue.done_wakeup.reset();
        if (wait_res == .timed_out) {
            break;
        }
    }

    if (rt.num_isolated_tests_finished < rt.isolated_tests.items.len) {
        runIsolatedTests(&rt);
    }

    reportUncaughtPromiseRejections();

    // Test results.
    printFmt("Passed: {d}\n", .{rt.num_tests_passed});
    printFmt("Tests: {d}\n", .{rt.num_tests});
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
                const err_str = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch);
                defer rt.alloc.free(err_str);
                printFmt("Test: {s}\n{s}", .{ case.name, err_str });
                break;
            }
            next_test += 1;
        }

        // Continue running tasks.
        rt.work_queue.processDone();

        if (!rt.work_queue.hasUnfinishedTasks()) {
            if (rt.num_isolated_tests_finished == rt.isolated_tests.items.len) {
                break;
            } else if (rt.num_isolated_tests_finished == next_test) {
                continue;
            }
        }

        // Wait on the next done task.
        const Timeout = 4 * 1e9;
        const wait_res = rt.work_queue.done_wakeup.timedWait(Timeout);
        rt.work_queue.done_wakeup.reset();
        if (wait_res == .timed_out) {
            break;
        }
    }
}

pub fn runUserMain(alloc: std.mem.Allocator, src_path: []const u8) !void {
    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

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
        log.debug("What does this do?", .{});
        unreachable;
    }

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        return error.MainScriptError;
    }

    // Check if we need to enter an app loop.
    if (rt.num_windows > 0) {
        runUserLoop(&rt);
    }
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