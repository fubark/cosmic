const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const t = stdx.testing;
const Vec2 = stdx.math.Vec2;
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");
const curl = @import("curl");
const uv = @import("uv");
const h2o = @import("h2o");
const v8 = @import("v8");
const platform = @import("platform");
const gl = @import("gl");
const builtin = @import("builtin");

const v8x = @import("v8x.zig");
const js_env = @import("js_env.zig");
const log = stdx.log.scoped(.runtime);
const api = @import("api.zig");
const cs_graphics = @import("api_graphics.zig").cs_graphics;
const gen = @import("gen.zig");
const audio = @import("audio.zig");

const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const tasks = @import("tasks.zig");
const WorkQueue = work_queue.WorkQueue;
const UvPoller = @import("uv_poller.zig").UvPoller;
const HttpServer = @import("server.zig").HttpServer;
const Timer = @import("timer.zig").Timer;
const EventDispatcher = stdx.events.EventDispatcher;
const NullId = stdx.ds.CompactNull(u32);
const devmode = @import("devmode.zig");
const DevModeContext = devmode.DevModeContext;
const adapter = @import("adapter.zig");
const PromiseSkipJsGen = adapter.PromiseSkipJsGen;
const FuncData = adapter.FuncData;
const FuncDataUserPtr = adapter.FuncDataUserPtr;
pub const Environment = @import("env.zig").Environment;

pub const PromiseId = u32;

// Js init scripts.
const api_init = @embedFile("snapshots/api_init.js");
const gen_api_init = @embedFile("snapshots/gen_api.js"); // Generated. Not tracked by git.
const test_init = @embedFile("snapshots/test_init.js");

// Keep a global rt for debugging and prototyping.
pub var global: *RuntimeContext = undefined;

// Manages runtime resources.
// Used by V8 callback functions.
// TODO: Rename to Runtime
pub const RuntimeContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    str_buf: std.ArrayList(u8),

    window_class: v8.Persistent(v8.FunctionTemplate),
    graphics_class: v8.Persistent(v8.FunctionTemplate),
    http_response_class: v8.Persistent(v8.FunctionTemplate),
    http_server_class: v8.Persistent(v8.FunctionTemplate),
    http_response_writer: v8.Persistent(v8.ObjectTemplate),
    image_class: v8.Persistent(v8.FunctionTemplate),
    color_class: v8.Persistent(v8.FunctionTemplate),
    transform_class: v8.Persistent(v8.FunctionTemplate),
    sound_class: v8.Persistent(v8.ObjectTemplate),
    random_class: v8.Persistent(v8.ObjectTemplate),
    handle_class: v8.Persistent(v8.ObjectTemplate),
    rt_ctx_tmpl: v8.Persistent(v8.ObjectTemplate),
    default_obj_t: v8.Persistent(v8.ObjectTemplate),

    /// Collection of mappings from id to resource handles.
    /// Resources of similar type are linked together.
    /// Resources can be deinited by js but the resource id slot won't be freed until a js finalizer callback.
    resources: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle),

    /// Weak handles are like resources except they aren't grouped together by type.
    /// A weak handle can be deinited but the slot won't be freed until a js finalizer callback.
    /// Since the finalizer callback relies on the garbage collector, the handles should be light in memory
    /// and have a pointer to the inner struct which can be deinited explicitly
    /// either through the runtime or user request.
    weak_handles: ds.PooledHandleList(WeakHandleId, WeakHandle),

    generic_resource_list: ResourceListId,
    generic_resource_list_last: ResourceId,

    window_resource_list: ResourceListId,
    window_resource_list_last: ResourceId,
    // Keep track of active windows so we know when to stop the app.
    num_windows: u32,
    // Window that has keyboard focus and will receive swap buffer.
    // Note: This is only safe if the allocation doesn't change.
    active_window: *CsWindow,

    /// Only one renderer exists for drawing to all windows and targets.
    renderer: graphics.Renderer,
    inited_renderer: bool,

    // Absolute path of the main script.
    main_script_path: ?[]const u8,

    // This is used to store native string slices copied from v8.String for use in the immediate native callback functions.
    // It will automatically clear at the pre callback step if the current size is too large.
    // Native callback functions that have []const u8 in their params should assume they only live until end of function scope.
    cb_str_buf: std.ArrayList(u8),
    cb_f32_buf: std.ArrayList(f32),

    vec2_buf: std.ArrayList(Vec2),

    // Whether this was invoked from "cosmic test"
    // TODO: Rename to is_test_runner
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

    promises: ds.PooledHandleList(PromiseId, v8.Persistent(v8.PromiseResolver)),

    last_err: CsError,

    // uv_loop_t is quite large, so allocate on heap.
    uv_loop: *uv.uv_loop_t,
    uv_dummy_async: *uv.uv_async_t,
    uv_poller: UvPoller,

    received_uncaught_exception: bool,

    // Used in test callbacks to shutdown the runtime.
    requested_shutdown: bool,

    timer: Timer,

    dev_mode: bool,
    dev_ctx: DevModeContext,

    event_dispatcher: EventDispatcher,

    // V8.
    platform: v8.Platform,
    create_params: v8.CreateParams,
    isolate: v8.Isolate,
    context: v8.Persistent(v8.Context),
    hscope: v8.HandleScope,
    global: v8.Persistent(v8.Object),

    // Store locally for quick access.
    js_undefined: v8.Primitive,
    js_null: v8.Primitive,
    js_false: v8.Boolean,
    js_true: v8.Boolean,

    modules: std.AutoHashMap(u32, ModuleInfo),

    // Holds the result of running the main script.
    run_main_script_res: ?RunModuleScriptResult,

    // Whether the main script is done with top level awaits.
    // This doesn't mean that the process is done since some resources can keep it alive (eg. a window)
    main_script_done: bool,

    get_native_val_err: anyerror,

    env: *Environment,

    pub fn init(self: *Self,
        alloc: std.mem.Allocator,
        platform_: v8.Platform,
        config: RuntimeConfig,
        env: *Environment,
    ) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .color_class = undefined,
            .transform_class = undefined,
            .graphics_class = undefined,
            .http_response_class = undefined,
            .http_response_writer = undefined,
            .http_server_class = undefined,
            .image_class = undefined,
            .handle_class = undefined,
            .rt_ctx_tmpl = undefined,
            .sound_class = undefined,
            .random_class = undefined,
            .default_obj_t = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .weak_handles = ds.PooledHandleList(u32, WeakHandle).init(alloc),
            .generic_resource_list = undefined,
            .generic_resource_list_last = undefined,
            .window_resource_list = undefined,
            .window_resource_list_last = undefined,
            .num_windows = 0,
            .active_window = undefined,
            .global = undefined,
            .main_script_path = null,
            .cb_str_buf = std.ArrayList(u8).init(alloc),
            .cb_f32_buf = std.ArrayList(f32).init(alloc),
            .vec2_buf = std.ArrayList(Vec2).init(alloc),

            .renderer = undefined,
            .inited_renderer = false,

            .js_undefined = undefined,
            .js_null = undefined,
            .js_false = undefined,
            .js_true = undefined,

            .is_test_env = config.is_test_runner,
            .num_tests = 0,
            .num_tests_passed = 0,
            .num_async_tests = 0,
            .num_async_tests_finished = 0,
            .num_async_tests_passed = 0,
            .num_isolated_tests_finished = 0,
            .isolated_tests = std.ArrayList(IsolatedTest).init(alloc),

            .main_wakeup = undefined,
            .work_queue = undefined,
            .promises = ds.PooledHandleList(PromiseId, v8.Persistent(v8.PromiseResolver)).init(alloc),
            .uv_loop = undefined,
            .uv_dummy_async = undefined,
            .uv_poller = undefined,
            .received_uncaught_exception = false,
            .requested_shutdown = false,
            .last_err = error.NoError,
            .timer = undefined,
            .dev_mode = config.is_dev_mode,
            .dev_ctx = undefined,
            .event_dispatcher = undefined,

            .platform = platform_,
            .isolate = undefined,
            .context = undefined,
            .create_params = undefined,
            .hscope = undefined,

            .modules = std.AutoHashMap(u32, ModuleInfo).init(alloc),
            .run_main_script_res = null,
            .main_script_done = false,
            .get_native_val_err = undefined,
            .env = env,
        };
        self.main_wakeup.reset();

        self.initUv();

        self.work_queue = WorkQueue.init(alloc, self.uv_loop, &self.main_wakeup);
        self.work_queue.createAndRunWorker();

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = .{ .ptr = undefined, .tag = .Dummy, .external_handle = undefined, .deinited = true, .on_deinit_cb = null };
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;
        self.generic_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.generic_resource_list_last = self.resources.getListHead(self.generic_resource_list).?;

        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Ignore sigpipe for writes to sockets that have already closed and let it return as an error to callers.
            const SIG_IGN = @intToPtr(fn(c_int, *const std.os.siginfo_t, ?*const anyopaque) callconv(.C) void, 1);
            const act = std.os.Sigaction{
                .handler = .{ .sigaction = SIG_IGN },
                .mask = std.os.empty_sigset,
                .flags = 0,
            };
            std.os.sigaction(std.os.SIG.PIPE, &act, null) catch unreachable;
        }

        self.initJs();

        // Set up timer. Needs v8 context.
        self.timer.init(self) catch unreachable;

        global = self;
    }

    fn initJs(self: *Self) void {
        self.create_params = v8.initCreateParams();
        self.create_params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
        var iso = v8.Isolate.init(&self.create_params);
        self.isolate = iso;

        iso.enter();
        defer iso.exit();

        self.hscope.init(iso);
        defer self.hscope.deinit();

        self.js_undefined = iso.initUndefined();
        self.js_null = iso.initNull();
        self.js_false = iso.initFalse();
        self.js_true = iso.initTrue();

        // Set up uncaught promise rejection handler.
        iso.setPromiseRejectCallback(promiseRejectCallback);

        // By default, scripts will automatically run microtasks when call depth returns to zero.
        // It also allows us to use performMicrotasksCheckpoint in cases where we need to sooner.
        iso.setMicrotasksPolicy(v8.MicrotasksPolicy.kAuto);

        // Receive the first uncaught exceptions and find the next opportunity to shutdown.
        const external = iso.initExternal(self).toValue();
        iso.setCaptureStackTraceForUncaughtExceptions(true, 10);
        _ = iso.addMessageListenerWithErrorLevel(v8MessageCallback, v8.MessageErrorLevel.kMessageError, external);

        self.context = v8.Persistent(v8.Context).init(iso, js_env.initContext(self, iso));
        self.global = iso.initPersistent(v8.Object, self.context.inner.getGlobal());

        const ctx = self.getContext();
        ctx.enter();
        defer ctx.exit();

        // Attach user context from json string.
        if (self.env.user_ctx_json) |json| {
            const json_str = iso.initStringUtf8(json);
            const json_val = v8.Json.parse(ctx, json_str) catch unreachable;
            _ = self.global.inner.setValue(ctx, iso.initStringUtf8("user"), json_val);
        }

        // Run api_init.js
        self.runScript("api_init.js", api_init) catch unreachable;

        // Run gen_api.js
        self.runScript("gen_api.js", gen_api_init) catch unreachable;

        if (self.is_test_env or builtin.is_test or self.env.include_test_api) {
            // Run test_init.js
            self.runScript("test_init.js", test_init) catch unreachable;
        }
    }

    fn initUv(self: *Self) void {
        // Ensure we're using the right headers and the linked uv has patches applied.
        std.debug.assert(uv.uv_loop_size() == @sizeOf(uv.uv_loop_t));

        // Create libuv evloop instance.
        self.uv_loop = self.alloc.create(uv.uv_loop_t) catch unreachable;
        var res = uv.uv_loop_init(self.uv_loop);
        uv.assertNoError(res);
        // Make sure iocp allows 2 concurrent threads on windows (Main thread and uv poller thread).
        // If set to 1 (libuv default), the first thread that calls GetQueuedCompletionStatus will attach to the iocp and other threads won't be able to receive events.
        if (builtin.os.tag == .windows) {
            std.os.windows.CloseHandle(self.uv_loop.iocp.?);
            self.uv_loop.iocp = std.os.windows.CreateIoCompletionPort(std.os.windows.INVALID_HANDLE_VALUE, null, 0, 2) catch unreachable;
        }

        const S = struct {
            fn onWatcherQueueChanged(_loop: [*c]uv.uv_loop_t) callconv(.C) void {
                // log.debug("on queue changed", .{});
                const loop = @ptrCast(*uv.uv_loop_t, _loop);
                const rt = stdx.ptrCastAlign(*RuntimeContext, loop.data.?);
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
        self.uv_dummy_async = self.alloc.create(uv.uv_async_t) catch unreachable;
        res = uv.uv_async_init(self.uv_loop, self.uv_dummy_async, null);
        uv.assertNoError(res);
        self.event_dispatcher = EventDispatcher.init(self.uv_dummy_async);

        stdx.http.curlm_uvloop = self.uv_loop;
        stdx.http.dispatcher = self.event_dispatcher;

        // uv needs to run once to initialize or UvPoller will never get the first event.
        // TODO: Revisit this again.
        _ = uv.uv_run(self.uv_loop, uv.UV_RUN_NOWAIT);

        // Start uv poller thread.
        self.uv_poller = UvPoller.init(self.uv_loop, &self.main_wakeup);
        const thread = std.Thread.spawn(.{}, UvPoller.run, .{&self.uv_poller}) catch unreachable;
        _ = thread.setName("UV Poller") catch {};
    }

    /// Isolate should not be entered when calling this.
    fn deinit(self: *Self) void {
        self.enter();

        self.str_buf.deinit();
        self.cb_str_buf.deinit();
        self.cb_f32_buf.deinit();
        self.vec2_buf.deinit();

        if (self.dev_mode and !self.dev_ctx.restart_requested) {
            self.dev_ctx.deinit();
        }

        if (self.inited_renderer) {
            self.renderer.deinit(self.alloc);
        }

        {
            var iter = self.weak_handles.iterator();
            while (iter.nextPtr()) |handle| {
                handle.deinit(self);
            }
            self.weak_handles.deinit();
        }
        {
            var iter = self.resources.nodes.iterator();
            while (iter.nextPtr()) |_| {
                const res_id = iter.cur_id;
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

        self.alloc.destroy(self.uv_dummy_async);
        self.alloc.destroy(self.uv_loop);

        if (self.main_script_path) |path| {
            self.alloc.free(path);
        }

        {
            var iter = self.modules.valueIterator();
            while (iter.next()) |it| {
                it.deinit(self.alloc);
            }
            self.modules.deinit();
        }

        self.timer.deinit();

        self.window_class.deinit();
        self.graphics_class.deinit();
        self.http_response_class.deinit();
        self.http_server_class.deinit();
        self.http_response_writer.deinit();
        self.image_class.deinit();
        self.color_class.deinit();
        self.transform_class.deinit();
        self.handle_class.deinit();
        self.rt_ctx_tmpl.deinit();
        self.sound_class.deinit();
        self.random_class.deinit();
        self.default_obj_t.deinit();
        self.global.deinit();

        if (self.run_main_script_res) |*res| {
            res.deinit(self.alloc);
        }

        // Deinit isolate after exiting.
        self.exit();
        self.context.deinit();
        self.isolate.deinit();
        v8.destroyArrayBufferAllocator(self.create_params.array_buffer_allocator.?);
    }

    /// No other v8 isolate should execute js until exit is called.
    fn enter(self: *Self) void {
        self.isolate.enter();
        self.hscope.init(self.isolate);
        self.getContext().enter();
    }

    fn exit(self: *Self) void {
        self.getContext().exit();
        self.hscope.deinit();
        self.isolate.exit();
    }

    pub inline fn getContext(self: Self) v8.Context {
        return self.context.inner;
    }

    fn runModuleScriptFile(self: *Self, abs_path: []const u8) !RunModuleScriptResult {
        if (self.env.main_script_override) |src_override| {
            return self.runModuleScript(abs_path, self.env.main_script_origin orelse abs_path, src_override);
        } else {
            const src = try std.fs.cwd().readFileAlloc(self.alloc, abs_path, 1e9);
            defer self.alloc.free(src);
            return self.runModuleScript(abs_path, abs_path, src);
        }
    }

    fn getRenderer(self: *Self, win: *platform.Window) *graphics.Renderer {
        if (self.inited_renderer) {
            // Lazy load renderer.
            self.renderer.init(self.alloc, win) catch fatal();
            self.inited_renderer = true;
        }
        return &self.renderer;
    }

    /// origin_str is an identifier for this script and is what is displayed in stack traces.
    /// Normally it is set to the abs_path but somtimes it can be different (eg. for in memory scripts for tests)
    /// Even though the src is provided, abs_path is still needed to set up import path resolving.
    /// Returns a result with a success flag.
    /// If a js exception was thrown, the stack trace is printed to stderr and also attached to the result.
    fn runModuleScript(self: *Self, abs_path: []const u8, origin_str: []const u8, src: []const u8) !RunModuleScriptResult {
        const iso = self.isolate;

        const js_origin_str = iso.initStringUtf8(origin_str);
        const js_src = iso.initStringUtf8(src);

        var try_catch: v8.TryCatch = undefined;
        try_catch.init(iso);
        defer try_catch.deinit();

        var origin = v8.ScriptOrigin.init(iso, js_origin_str.toValue(), 
            0, 0, false, -1, null, false, false, true, null,
        );

        var mod_src: v8.ScriptCompilerSource = undefined;
        // TODO: Look into CachedData.
        mod_src.init(js_src, origin, null);
        defer mod_src.deinit();

        const mod = v8.ScriptCompiler.compileModule(self.isolate, &mod_src, .kNoCompileOptions, .kNoCacheNoReason) catch {
            const trace_str = v8x.allocPrintTryCatchStackTrace(self.alloc, self.isolate, self.getContext(), try_catch).?;
            self.env.errorFmt("{s}", .{trace_str});
            return RunModuleScriptResult{
                .state = .Failed,
                .mod = null,
                .eval = null,
                .js_err_trace = trace_str,
            };
        };
        std.debug.assert(mod.getStatus() == .kUninstantiated);

        const mod_info = ModuleInfo{
            .dir = self.alloc.dupe(u8, std.fs.path.dirname(abs_path).?) catch unreachable,
        };
        self.modules.put(mod.getScriptId(), mod_info) catch unreachable;

        // const reqs = mod.getModuleRequests();
        // log.debug("reqs: {}", .{ reqs.length() });
        // const req = reqs.get(self.getContext(), 0).castTo(v8.ModuleRequest);
        // const spec = v8x.allocPrintValueAsUtf8(self.alloc, self.isolate, self.getContext(), req.getSpecifier());
        // defer self.alloc.free(spec);
        // log.debug("import: {s}", .{spec});

        const S = struct {
            fn resolveModule(
                ctx_ptr: ?*const v8.C_Context,
                spec_: ?*const v8.C_Data,
                import_assertions: ?*const v8.C_FixedArray,
                referrer: ?*const v8.C_Module
            ) callconv(.C) ?*const v8.C_Module {
                _ = import_assertions;
                const ctx = v8.Context{ .handle = ctx_ptr.? };
                const rt = stdx.ptrCastAlign(*RuntimeContext, ctx.getEmbedderData(0).castTo(v8.External).get());
                const js_spec = v8.String{ .handle = spec_.? };
                const iso_ = ctx.getIsolate();

                var origin_ = v8.ScriptOrigin.init(iso_, js_spec.toValue(), 
                    0, 0, false, -1, null, false, false, true, null,
                );

                const spec_str = v8x.allocStringAsUtf8(rt.alloc, iso_, js_spec);
                defer rt.alloc.free(spec_str);

                var abs_path_: []const u8 = undefined;
                var abs_path_needs_free = false;
                defer {
                    if (abs_path_needs_free) {
                        rt.alloc.free(abs_path_);
                    }
                }
                if (std.fs.path.isAbsolute(spec_str)) {
                    abs_path_ = spec_str;
                } else {
                    // Build path from referrer's script dir.
                    const referrer_mod = v8.Module{ .handle = referrer.? };
                    const referrer_info = rt.modules.get(referrer_mod.getScriptId()).?;
                    abs_path_ = std.fmt.allocPrint(rt.alloc, "{s}/{s}", .{ referrer_info.dir, spec_str }) catch unreachable;
                    abs_path_needs_free = true;
                }

                const src_ = std.fs.cwd().readFileAlloc(rt.alloc, abs_path_, 1e9) catch {
                    v8x.throwErrorExceptionFmt(rt.alloc, iso_, "Failed to load module: {s}", .{spec_str});
                    return null;
                };
                defer rt.alloc.free(src_);

                const js_src_ = iso_.initStringUtf8(src_);

                var mod_src_: v8.ScriptCompilerSource = undefined;
                mod_src_.init(js_src_, origin_, null);
                defer mod_src_.deinit();

                var try_catch_: v8.TryCatch = undefined;
                try_catch_.init(iso_);
                defer try_catch_.deinit();

                const mod_ = v8.ScriptCompiler.compileModule(iso_, &mod_src_, .kNoCompileOptions, .kNoCacheNoReason) catch {
                    _ = try_catch_.rethrow();
                    return null;
                };

                const mod_info_ = ModuleInfo{
                    .dir = rt.alloc.dupe(u8, std.fs.path.dirname(abs_path_).?) catch unreachable,
                };
                rt.modules.put(mod_.getScriptId(), mod_info_) catch unreachable;

                return mod_.handle;
            }
        };

        const success = mod.instantiate(self.getContext(), S.resolveModule) catch {
            const trace_str = v8x.allocPrintTryCatchStackTrace(self.alloc, self.isolate, self.getContext(), try_catch).?;
            self.env.errorFmt("{s}", .{trace_str});
            return RunModuleScriptResult{
                .state = .Failed,
                .mod = iso.initPersistent(v8.Module, mod),
                .eval = null,
                .js_err_trace = trace_str,
            };
        };
        if (!success) {
            stdx.panic("TODO: Did not expect !success.");
        }
        std.debug.assert(mod.getStatus() == .kInstantiated);

        const res = mod.evaluate(self.getContext()) catch {
            const trace_str = v8x.allocPrintTryCatchStackTrace(self.alloc, self.isolate, self.getContext(), try_catch).?;
            self.env.errorFmt("{s}", .{trace_str});
            return RunModuleScriptResult{
                .state = .Failed,
                .mod = iso.initPersistent(v8.Module, mod),
                .eval = null,
                .js_err_trace = trace_str,
            };
        };
        // res is a promise that resolves to undefined if successful and rejects to an exception object on error.
        _ = res;
        switch (mod.getStatus()) {
            .kErrored => {
                const trace_str = allocExceptionJsStackTraceString(self, mod.getException());
                self.env.errorFmt("{s}", .{trace_str});
                return RunModuleScriptResult{
                    .state = .Failed,
                    .mod = iso.initPersistent(v8.Module, mod),
                    .eval = iso.initPersistent(v8.Promise, res.castTo(v8.Promise)),
                    .js_err_trace = trace_str,
                };
            },
            .kEvaluated => {
                const res_p = res.castTo(v8.Promise);
                switch (res_p.getState()) {
                    .kFulfilled => {
                        return RunModuleScriptResult{
                            .state = .Success,
                            .mod = iso.initPersistent(v8.Module, mod),
                            .eval = iso.initPersistent(v8.Promise, res_p),
                            .js_err_trace = null,
                        };
                    },
                    .kPending => {
                        // Attempt to pump the v8 event loop once to see if it can finish the script.
                        // If not, the script is using the worker or evented io and needs to continue with the main event loop.
                        processV8EventLoop(self);
                        switch (res_p.getState()) {
                            .kRejected => {
                                const trace_str = allocExceptionJsStackTraceString(self, mod.getException());
                                self.env.errorFmt("{s}", .{trace_str});
                                return RunModuleScriptResult{
                                    .state = .Failed,
                                    .mod = iso.initPersistent(v8.Module, mod),
                                    .eval = iso.initPersistent(v8.Promise, res_p),
                                    .js_err_trace = trace_str,
                                };
                            },
                            .kFulfilled => {
                                return RunModuleScriptResult{
                                    .state = .Success,
                                    .mod = iso.initPersistent(v8.Module, mod),
                                    .eval = iso.initPersistent(v8.Promise, res_p),
                                    .js_err_trace = null,
                                };
                            },
                            .kPending => {
                                return RunModuleScriptResult{
                                    .state = .Pending,
                                    .mod = iso.initPersistent(v8.Module, mod),
                                    .eval = iso.initPersistent(v8.Promise, res_p),
                                    .js_err_trace = null,
                                };
                            },
                        }
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
        }
    }

    fn runScriptFile(self: *Self, abs_path: []const u8) !void {
        const src = try std.fs.cwd().readFileAlloc(self.alloc, abs_path, 1e9);
        defer self.alloc.free(src);
        return self.runScript(abs_path, src);
    }

    fn runScript(self: *Self, origin: []const u8, src: []const u8) !void {
        const res = self.runScriptGetResult(origin, src);
        defer res.deinit();
        if (!res.success) {
            self.env.errorFmt("{s}", .{res.err.?});
            return error.RunScriptError;
        }
    }

    pub fn runScriptGetResult(self: *Self, origin: []const u8, src: []const u8) v8x.ExecuteResult {
        const js_origin = v8.String.initUtf8(self.isolate, origin);
        var res: v8x.ExecuteResult = undefined;
        v8x.executeString(self.alloc, self.isolate, self.getContext(), src, js_origin, &res);
        return res;
    }

    fn runMainScript(self: *Self, abs_path: []const u8) !void {
        self.main_script_path = self.alloc.dupe(u8, abs_path) catch unreachable;

        if (self.dev_mode) {
            // Start watching the main script.
            self.dev_ctx.initWatcher(self, abs_path);
        }

        const res = try self.runModuleScriptFile(self.main_script_path.?);
        self.run_main_script_res = res;

        switch (res.state) {
            .Failed => {
                self.finishMainScript();
                if (!self.dev_mode) {
                    return error.MainScriptError;
                } else {
                    self.dev_ctx.enterJsErrorState(self, res.js_err_trace.?);
                }
            },
            .Success => {
                self.finishMainScript();
                if (self.dev_mode) {
                    self.dev_ctx.enterJsSuccessState();
                }
            },
            .Pending => {
                // Since module has a handler for top level async calls, it won't trigger the uncaught exception callback.
                // Attach then and catch handlers to handle the final outcome.
                self.main_script_done = false;
                const data = self.isolate.initExternal(self);
                const on_fulfill = v8.Function.initWithData(self.getContext(), gen.genJsFuncSync(handleMainModuleScriptSuccess), data);
                const on_reject = v8.Function.initWithData(self.getContext(), gen.genJsFuncSync(handleMainModuleScriptError), data);
                _ = res.eval.?.inner.thenAndCatch(self.getContext(), on_fulfill, on_reject) catch unreachable;

                if (self.dev_mode) {
                    self.dev_ctx.enterJsSuccessState();
                }
            }
        }
    }

    pub fn wakeUpEventPoller(self: Self) void {
        const res = uv.uv_async_send(self.uv_dummy_async);
        uv.assertNoError(res);
    }

    /// Destroys the resource owned by the handle and marks it as deinited.
    /// If the resource can't be deinited immediately, the final deinitResourceHandle call will be deferred.
    pub fn startDeinitResourceHandle(self: *Self, id: ResourceId) void {
        const handle = self.resources.getPtrNoCheck(id);
        if (handle.deinited) {
            log.debug("Already deinited", .{});
            unreachable;
        }
        switch (handle.tag) {
            .CsWindow => {
                // TODO: This should do cleanup like deleteCsWindowBySdlId
                const window = stdx.ptrCastAlign(*CsWindow, handle.ptr);
                if (self.dev_mode and self.dev_ctx.restart_requested) {
                    // Skip deiniting the window for a dev mode restart.
                    window.deinit(self, self.dev_ctx.dev_window == window);
                } else {
                    window.deinit(self, false);
                }

                // Update current vars.
                self.num_windows -= 1;
                if (self.num_windows > 0) {
                    if (self.active_window == stdx.ptrCastAlign(*CsWindow, handle.ptr)) {
                        // TODO: Revisit this. For now just pick the last available window.
                        const list_id = self.getResourceListId(handle.tag);
                        if (self.resources.findInList(list_id, {}, findFirstActiveResource)) |res_id| {
                            self.active_window = stdx.ptrCastAlign(*CsWindow, self.resources.getNoCheck(res_id).ptr);
                        }
                    }
                } else {
                    self.active_window = undefined;
                }
                self.deinitResourceHandleInternal(id);
            },
            .CsHttpServer => {
                const server = stdx.ptrCastAlign(*HttpServer, handle.ptr);
                if (server.closed) {
                    self.deinitResourceHandleInternal(id);
                } else {
                    const S = struct {
                        fn onShutdown(ptr: *anyopaque, _: *HttpServer) void {
                            const ctx = stdx.ptrCastAlign(*ExternalResourceHandle, ptr);
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
        const handle = self.resources.getNoCheck(id);
        // Fire callback.
        if (handle.on_deinit_cb) |cb| {
            cb.call(id);
        }
        switch (handle.tag) {
            .CsWindow => {
                self.alloc.destroy(stdx.ptrCastAlign(*CsWindow, handle.ptr));
            },
            .CsHttpServer => {
                self.alloc.destroy(stdx.ptrCastAlign(*HttpServer, handle.ptr));
            },
            else => unreachable,
        }
    }

    fn v8MessageCallback(message: ?*const v8.C_Message, value: ?*const v8.C_Value) callconv(.C) void {
        const val = v8.Value{.handle = value.?};
        const rt = stdx.ptrCastAlign(*RuntimeContext, val.castTo(v8.External).get());

        // Only interested in the first uncaught exception.
        if (!rt.received_uncaught_exception) {
            // Print the stack trace immediately.
            const js_msg = v8.Message{ .handle = message.? };
            const err_str = v8x.allocPrintMessageStackTrace(rt.alloc, rt.isolate, rt.getContext(), js_msg, "Uncaught Exception");
            defer rt.alloc.free(err_str);
            rt.env.errorFmt("\n{s}", .{err_str});
            rt.received_uncaught_exception = true;
            if (rt.dev_mode) {
                rt.dev_ctx.enterJsErrorState(rt, err_str);
            }
        }
    }

    pub fn allocResourceIdsByTag(self: Self, tag: ResourceTag) []const ResourceId {
        const list = self.getResourceListId(tag);
        var cur_res = self.resources.getListHead(list).?;
        cur_res = self.resources.getNextIdNoCheck(cur_res);
        var res = std.ArrayList(ResourceId).init(self.alloc);
        while (cur_res != NullId) {
            res.append(cur_res) catch unreachable;
            cur_res = self.resources.getNextIdNoCheck(cur_res);
        }
        return res.toOwnedSlice();
    }

    pub fn getResourcePtr(self: *Self, comptime Tag: ResourceTag, res_id: ResourceId) ?*Resource(Tag) {
        if (self.resources.has(res_id)) {
            const item = self.resources.getNoCheck(res_id);
            if (item.tag == Tag) {
                return stdx.ptrCastAlign(*Resource(Tag), item.ptr);
            }
        }
        return null;
    }

    pub fn destroyWeakHandle(self: *Self, id: WeakHandleId) void {
        const handle = self.weak_handles.getPtr(id).?;
        if (handle.tag != .Null) {
            handle.deinit(self);
        }
        handle.obj.deinit();
        self.weak_handles.remove(id);
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
        self.resources.getPtrNoCheck(res_id).external_handle = external;

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
        self.resources.getPtrNoCheck(res_id).external_handle = external;

        self.num_windows += 1;
        return .{
            .ptr = ptr,
            .id = res_id,
            .external = external,
        };
    }

    /// Destroys the ResourceHandle and removes it from the runtime.
    /// Doing so also frees the resource slot for reuse.
    /// This is called when the js handle invokes the weak finalizer.
    /// At that point no js handle still references the id so it is safe to remove the native handle.
    pub fn destroyResourceHandle(self: *Self, res_id: ResourceId) void {
        if (!self.resources.has(res_id)) {
            log.err("Expected resource id: {}", .{res_id});
            unreachable;
        }
        const res = self.resources.getPtrNoCheck(res_id);
        if (!res.deinited) {
            self.startDeinitResourceHandle(res_id);
        }

        // The external handle is kept alive after the deinit step,
        // since it's needed by a finalizer callback.
        if (res.tag != .Dummy) {
            self.alloc.destroy(res.external_handle);

            const list_id = self.getResourceListId(res.tag);
            if (self.resources.findInList(list_id, res_id, findPrevResource)) |prev_id| {
                // Remove from resources.
                _ = self.resources.removeNext(prev_id) catch unreachable;

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

    fn getResourceListId(self: Self, tag: ResourceTag) ResourceListId {
        switch (tag) {
            .CsWindow => return self.window_resource_list,
            .CsHttpServer => return self.generic_resource_list,
            else => unreachable,
        }
    }

    fn findFirstActiveResource(_: void, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
        return !buf.getNoCheck(item_id).deinited;
    }

    fn findPrevResource(target: ResourceId, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
        return buf.getNextIdNoCheck(item_id) == target;
    }

    fn getCsWindowResourceBySdlId(self: *Self, sdl_win_id: u32) ?ResourceId {
        if (Backend != .OpenGL) {
            @panic("unsupported");
        }
        const S = struct {
            fn pred(_sdl_win_id: u32, buf: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle), item_id: ResourceId) bool {
                const res = buf.getNoCheck(item_id);
                // Skip dummy head.
                if (res.tag == .Dummy) {
                    return false;
                }
                const cs_window = stdx.ptrCastAlign(*CsWindow, res.ptr);
                return cs_window.window.impl.id == _sdl_win_id;
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
        const ctx = self.context.inner;
        switch (Type) {
            void => return self.js_undefined.handle,
            i16 => return iso.initIntegerI32(native_val).handle,
            u8 => return iso.initIntegerU32(native_val).handle,
            u16 => return iso.initIntegerU32(native_val).handle,
            u32 => return iso.initIntegerU32(native_val).handle,
            F64SafeUint => return iso.initNumber(@intToFloat(f64, native_val)).handle,
            u64 => return iso.initBigIntU64(native_val).handle,
            f32 => return iso.initNumber(native_val).handle,
            f64 => return iso.initNumber(native_val).handle,
            bool => return iso.initBoolean(native_val).handle,
            stdx.http.Response => {
                const headers_buf = self.alloc.alloc(v8.Value, native_val.headers.len) catch unreachable;
                defer self.alloc.free(headers_buf);
                for (native_val.headers) |header, i| {
                    const js_header = self.default_obj_t.inner.initInstance(ctx);
                    _ = js_header.setValue(ctx, iso.initStringUtf8("key"), iso.initStringUtf8(native_val.header[header.key.start..header.key.end]));
                    _ = js_header.setValue(ctx, iso.initStringUtf8("value"), iso.initStringUtf8(native_val.header[header.value.start..header.value.end]));
                    headers_buf[i] = .{ .handle = js_header.handle };
                }

                const new = self.http_response_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
                _ = new.setValue(ctx, iso.initStringUtf8("status"), iso.initIntegerU32(native_val.status_code));
                _ = new.setValue(ctx, iso.initStringUtf8("headers"), iso.initArrayElements(headers_buf));
                _ = new.setValue(ctx, iso.initStringUtf8("body"), iso.initStringUtf8(native_val.body));
                return new.handle;
            },
            graphics.Image => {
                const new = self.image_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
                new.setInternalField(0, iso.initIntegerU32(native_val.id));
                _ = new.setValue(ctx, iso.initStringUtf8("width"), iso.initIntegerU32(@intCast(u32, native_val.width)));
                _ = new.setValue(ctx, iso.initStringUtf8("height"), iso.initIntegerU32(@intCast(u32, native_val.height)));
                return new.handle;
            },
            cs_graphics.Color => {
                const new = self.color_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
                _ = new.setValue(ctx, iso.initStringUtf8("r"), iso.initIntegerU32(native_val.r));
                _ = new.setValue(ctx, iso.initStringUtf8("g"), iso.initIntegerU32(native_val.g));
                _ = new.setValue(ctx, iso.initStringUtf8("b"), iso.initIntegerU32(native_val.b));
                _ = new.setValue(ctx, iso.initStringUtf8("a"), iso.initIntegerU32(native_val.a));
                return new.handle;
            },
            cs_graphics.Transform => {
                const new = self.transform_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
                var buf: [16]v8.Value = undefined;
                for (native_val.mat) |it, i| {
                    buf[i] = iso.initNumber(it).toValue();
                }
                _ = new.setValue(ctx, iso.initStringUtf8("mat"), iso.initArrayElements(&buf));
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
            v8.Value,
            v8.Boolean,
            v8.Object,
            v8.Array,
            v8.Promise => return native_val.handle,
            PromiseSkipJsGen => return native_val.inner.handle,
            []const u8 => {
                return iso.initStringUtf8(native_val).handle;
            },
            []const api.cs_files.FileEntry => {
                const buf = self.alloc.alloc(v8.Value, native_val.len) catch unreachable;
                defer self.alloc.free(buf);
                for (native_val) |it, i| {
                    const obj = self.default_obj_t.inner.initInstance(ctx);
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
                return @ptrCast(*const v8.C_Value, native_val);
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
                } else if (@typeInfo(Type) == .Pointer) {
                    if (@typeInfo(Type).Pointer.size == .Slice) {
                        const buf = self.alloc.alloc(v8.Value, native_val.len) catch unreachable;
                        defer self.alloc.free(buf);
                        for (native_val) |child_val, i| {
                            buf[i] = self.getJsValue(child_val);
                        }
                        return iso.initArrayElements(buf).handle;
                    }
                } else if (@typeInfo(Type) == .Struct) {
                    if (@hasDecl(Type, "ManagedSlice")) {
                        return self.getJsValuePtr(native_val.slice);
                    } else if (@hasDecl(Type, "ManagedStruct")) {
                        return self.getJsValuePtr(native_val.val);
                    } else if (@hasDecl(Type, "RtTempStruct")) {
                        return self.getJsValuePtr(native_val.inner);
                    } else {
                        // Generic struct to js object.
                        // TODO: Is it more performant to initialize from an object template if we know the fields beforehand?
                        const obj = iso.initObject();
                        const Fields = std.meta.fields(Type);
                        inline for (Fields) |Field| {
                            _ = obj.setValue(ctx, iso.initStringUtf8(Field.name), self.getJsValue(@field(native_val, Field.name)));
                        }
                        return obj.handle;
                    }
                } else if (@typeInfo(Type) == .Enum) {
                    if (@hasDecl(Type, "IsStringSumType")) {
                        // string value.
                        return iso.initStringUtf8(@tagName(native_val)).handle;
                    } else {
                        // int value.
                        return iso.initIntegerU32(@enumToInt(native_val)).handle;
                    }
                }
                comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to js.", .{@typeName(Type)}));
            },
        }
    }

    /// functions with error returns have problems being inside inlines so a quick hack is to return an optional
    /// and set a temporary error var.
    pub inline fn getNativeValue2(self: *Self, comptime T: type, val: anytype) ?T {
        return self.getNativeValue(T, val) catch |err| {
            self.get_native_val_err = err;
            return null;
        };
    }

    // TODO: Rename to getNativeArgValue to indicate it's meant to be used with converting from js callback args.
    /// Converts a js value to a target native type.
    /// Slice-like types depend on temporary buffers.
    /// This can't easily reuse runtime.getNativeValue since we are using temporary buffers, and objects/arrays can have nested children.
    /// Returns an error if conversion failed.
    pub fn getNativeValue(self: *Self, comptime T: type, val: anytype) !T {
        const ctx = self.getContext();
        switch (T) {
            []const f32 => {
                if (val.isArray()) {
                    const len = val.castTo(v8.Array).length();
                    var i: u32 = 0;
                    const obj = val.castTo(v8.Object);
                    const start = self.cb_f32_buf.items.len;
                    self.cb_f32_buf.resize(start + len) catch unreachable;
                    while (i < len) : (i += 1) {
                        const child_val = obj.getAtIndex(ctx, i) catch return error.CantConvert;
                        self.cb_f32_buf.items[start + i] = child_val.toF32(ctx) catch return error.CantConvert;
                    }
                    return self.cb_f32_buf.items[start..];
                } else return error.CantConvert;
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
            u8 => return @intCast(u8, val.toU32(ctx) catch return error.CantConvert),
            u16 => return @intCast(u16, val.toU32(ctx) catch return error.CantConvert),
            u32 => return val.toU32(ctx),
            f32 => return val.toF32(ctx),
            u64 => {
                if (val.isBigInt()) {
                    return val.castTo(v8.BigInt).getUint64();
                } else {
                    return @intCast(u64, val.toU32(ctx) catch return error.CantConvert);
                }
            },
            graphics.Image => {
                if (val.isObject()) {
                    const obj = val.castTo(v8.Object);
                    if (obj.toValue().instanceOf(ctx, self.image_class.inner.getFunction(ctx).toObject()) catch return error.CantConvert) {
                        const image_id = obj.getInternalField(0).toU32(ctx) catch return error.CantConvert;
                        return graphics.Image{ .id = image_id, .width = 0, .height = 0 };
                    }
                }
                return error.CantConvert;
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
                } else return error.CantConvert;
            },
            v8.Uint8Array => {
                if (val.isUint8Array()) {
                    return val.castTo(v8.Uint8Array);
                } else return error.CantConvert;
            },
            v8.Function => {
                if (val.isFunction()) {
                    return val.castTo(v8.Function);
                } else return error.CantConvert;
            },
            v8.Object => {
                if (val.isObject()) {
                    return val.castTo(v8.Object);
                } else return error.CantConvert;
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
                        const key = keys_obj.getAtIndex(ctx, i) catch return error.CantConvert;
                        const key_str = v8x.allocValueAsUtf8(self.alloc, self.isolate, ctx, key);
                        if (self.getNativeValue([]const u8, key)) |child_native_val| {
                            native_val.put(key_str, child_native_val) catch unreachable;
                        } else |_| {}
                    }
                    return native_val;
                } else return error.CantConvert;
            },
            else => {
                if (@typeInfo(T) == .Struct) {
                    if (val.isObject()) {
                        if (@hasDecl(T, "Handle")) {
                            const Ptr = stdx.meta.FieldType(T, .ptr);
                            const handle_id = @intCast(u32, @ptrToInt(val.castTo(v8.Object).getInternalField(0).castTo(v8.External).get()));
                            const handle = self.weak_handles.getNoCheck(handle_id);
                            if (handle.tag != .Null) {
                                return T{
                                    .ptr = stdx.ptrCastAlign(Ptr, handle.ptr),
                                    .id = handle_id,
                                    .obj = val.castTo(v8.Object),
                                };
                            } else {
                                return error.HandleExpired;
                            }
                        } else {
                            const obj = val.castTo(v8.Object);
                            var native_val: T = undefined;
                            if (comptime hasAllOptionalFields(T)) {
                                native_val = .{};
                            }
                            const Fields = std.meta.fields(T);
                            inline for (Fields) |Field| {
                                if (@typeInfo(Field.field_type) == .Optional) {
                                    const child_val = obj.getValue(ctx, self.isolate.initStringUtf8(Field.name)) catch return error.CantConvert;
                                    const Child = comptime @typeInfo(Field.field_type).Optional.child;
                                    if (child_val.isNullOrUndefined()) {
                                        @field(native_val, Field.name) = null;
                                    } else {
                                        @field(native_val, Field.name) = self.getNativeValue2(Child, child_val);
                                    }
                                } else {
                                    const js_val = obj.getValue(ctx, self.isolate.initStringUtf8(Field.name)) catch return error.CantConvert;
                                    if (self.getNativeValue2(Field.field_type, js_val)) |child_value| {
                                        @field(native_val, Field.name) = child_value;
                                    }
                                }
                            }
                            return native_val;
                        }
                    } else return error.CantConvert;
                } else if (@typeInfo(T) == .Array) {
                    const ArrayInfo = @typeInfo(T).Array;
                    var native_val: [ArrayInfo.len]ArrayInfo.child = undefined;
                    if (val.isArray()) {
                        const len = val.castTo(v8.Array).length();
                        if (len < ArrayInfo.len) {
                            return error.CantConvert;
                        } else {
                            var i: u32 = 0;
                            const obj = val.castTo(v8.Object);
                            while (i < len) : (i += 1) {
                                const child_val = obj.getAtIndex(ctx, i) catch return error.CantConvert;
                                native_val[i] = self.getNativeValue(ArrayInfo.child, child_val) catch return error.CantConvert;
                            }
                            return native_val;
                        }
                    } else return error.CantConvert;
                } else if (@typeInfo(T) == .Enum) {
                    if (@hasDecl(T, "IsStringSumType")) {
                        // String to enum conversion.
                        const lower = v8x.appendValueAsUtf8Lower(&self.cb_str_buf, self.isolate, ctx, val);
                        const Fields = @typeInfo(T).Enum.fields;
                        inline for (Fields) |Field| {
                            // Compare with lower case.
                            if (std.mem.eql(u8, lower, comptime ctLower(Field.name))) {
                                return @intToEnum(T, Field.value);
                            }
                        }
                        return error.CantConvert;
                    } else {
                        // Integer to enum conversion.
                        const ival = val.toU32(ctx) catch return error.CantConvert;
                        return std.meta.intToEnum(T, ival) catch {
                            if (@hasDecl(T, "Default")) {
                                return T.Default;
                            } else return error.CantConvert;
                        };
                    }
                } else {
                    comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to {s}", .{ @typeName(@TypeOf(val)), @typeName(T) }));
                }
            },
        }
    }

    fn handleMouseDownEvent(self: *Self, e: api.cs_input.MouseDownEvent, comptime DevMode: bool) void {
        if (DevMode and self.dev_ctx.has_error) {
            return;
        }
        const ctx = self.getContext();
        if (self.active_window.on_mouse_down_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleMouseUpEvent(self: *Self, e: api.cs_input.MouseUpEvent, comptime DevMode: bool) void {
        if (DevMode and self.dev_ctx.has_error) {
            return;
        }
        const ctx = self.getContext();
        if (self.active_window.on_mouse_up_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleMouseMoveEvent(self: *Self, e: api.cs_input.MouseMoveEvent, comptime DevMode: bool) void {
        if (DevMode and self.dev_ctx.has_error) {
            return;
        }
        const ctx = self.getContext();
        if (self.active_window.on_mouse_move_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleKeyUpEvent(self: *Self, e: api.cs_input.KeyUpEvent, comptime DevMode: bool) void {
        if (DevMode) {
            // Manual restart hotkey.
            if (e.key == .f5) {
                self.dev_ctx.requestRestart();
            }
            if (self.dev_ctx.has_error) {
                return;
            }
        }
        const ctx = self.getContext();
        if (self.active_window.on_key_up_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    fn handleKeyDownEvent(self: *Self, e: api.cs_input.KeyDownEvent, comptime DevMode: bool) void {
        if (DevMode and self.dev_ctx.has_error) {
            return;
        }
        const ctx = self.getContext();
        if (self.active_window.on_key_down_cb) |cb| {
            const js_event = self.getJsValue(e);
            _ = cb.inner.call(ctx, self.active_window.js_window, &.{ js_event });
        }
    }

    pub fn evalModuleScript(self: *Self, js: []const u8) !RunModuleScriptResult {
        return self.runModuleScript("/eval", "eval", js);
    }

    pub fn attachPromiseHandlers(
        self: *Self,
        p: v8.Promise,
        ctx_ptr: anytype,
        comptime on_success: fn (@TypeOf(ctx_ptr), *RuntimeContext, v8.Value) void,
        comptime on_failure: fn (@TypeOf(ctx_ptr), *RuntimeContext, v8.Value) void,
    ) !void {
        const Ptr = @TypeOf(ctx_ptr);
        const S = struct {
            fn onSuccess(rt: *RuntimeContext, ctx: FuncDataUserPtr(Ptr), val: v8.Value) void {
                on_success(ctx.ptr, rt, val);
            }
            fn onFailure(rt: *RuntimeContext, ctx: FuncDataUserPtr(Ptr), val: v8.Value) void {
                on_failure(ctx.ptr, rt, val);
            }
        };
        const rt_val = self.isolate.initExternal(self);
        const data = self.rt_ctx_tmpl.inner.initInstance(self.getContext());
        data.setInternalField(0, rt_val);
        const ctx_val = self.isolate.initExternal(ctx_ptr);
        data.setInternalField(1, ctx_val);
        const js_on_success = v8.Function.initWithData(self.getContext(), gen.genJsFunc(S.onSuccess, .{
            .asyncify = false,
            .is_data_rt = false,
        }), data);
        const js_on_failure = v8.Function.initWithData(self.getContext(), gen.genJsFunc(S.onFailure, .{
            .asyncify = false,
            .is_data_rt = false,
        }), data);
        _ = try p.thenAndCatch(self.getContext(), js_on_success, js_on_failure);
    }

    /// Currently only used in test env where a callback wants to end the runtime.
    pub fn requestShutdown(self: *Self) void {
        if (builtin.is_test) {
            self.requested_shutdown = true;
            const res = uv.uv_async_send(self.uv_dummy_async);
            uv.assertNoError(res);
        }
    }

    pub fn finishMainScript(self: *Self) void {
        self.main_script_done = true;
        if (builtin.is_test) {
            if (self.env.on_main_script_done) |handler| {
                handler(self.env.on_main_script_done_ctx, self) catch unreachable;
            }
        }
    }

    pub fn spawnProcess(self: *Self, ctx: ?*anyopaque, cmd: []const []const u8, cb: ProcessEndCallback) !void {
        const new = try ProcessHandle.create(self.alloc, self.uv_loop, cmd);
        new.user_ctx = ctx;
        new.user_cb = cb;
    }
};

const ProcessEndCallback = fn (ctx: ?*anyopaque, output: []const u8) void;

const ProcessHandle = struct {
    handle: uv.uv_process_t,
    out: uv.uv_pipe_t,
    out_buf: std.ArrayList(u8),
    user_cb: ProcessEndCallback,
    user_ctx: ?*anyopaque,
    alloc: std.mem.Allocator,
    closed_handles: u1,

    const Self = @This();

    fn create(alloc: std.mem.Allocator, loop: *uv.uv_loop_t, cmd: []const []const u8) !*Self {
        const new = alloc.create(ProcessHandle) catch @panic("error");
        new.out_buf = std.ArrayList(u8).init(alloc);
        new.alloc = alloc;
        new.closed_handles = 0;
        errdefer new.startDestroy();

        var res = uv.uv_pipe_init(loop, &new.out, 0);
        uv.assertNoError(res);

        const cargs = stdx.cstr.allocCStrings(alloc, cmd) catch @panic("error");
        defer alloc.free(cargs);

        const cfile = std.cstr.addNullByte(alloc, cmd[0]) catch @panic("error");
        defer alloc.free(cfile);

        var opts: uv.uv_process_options_t = undefined;
        opts.file = cfile;
        opts.args = stdx.ptrCastAlign([*c][*c]u8, cargs.ptr);
        opts.exit_cb = onExit;
        opts.flags = 0;
        opts.env = null;
        opts.cwd = null;
        opts.stdio_count = 3;
        var stdio: [3]uv.uv_stdio_container_t = undefined;
        opts.stdio = &stdio;
        opts.stdio[0].flags = uv.UV_IGNORE;
        opts.stdio[1].flags = uv.UV_CREATE_PIPE | uv.UV_WRITABLE_PIPE;
        opts.stdio[1].data.stream = @ptrCast(*uv.uv_stream_t, &new.out);
        opts.stdio[2].flags = uv.UV_IGNORE;
        opts.uid = 0;
        opts.gid = 0;

        res = uv.uv_spawn(loop, &new.handle, &opts);
        switch (res) {
            uv.UV_ENOENT => {
                return error.MissingBin;
            },
            else => uv.assertNoError(res),
        }

        res = uv.uv_read_start(@ptrCast(*uv.uv_stream_t, &new.out), onAlloc, onRead);
        uv.assertNoError(res);

        return new;
    }

    fn onRead(stream: [*c]uv.uv_stream_t, nread: isize, buf: [*c]const uv.uv_buf_t) callconv(.C) void {
        const self = @fieldParentPtr(Self, "out", @ptrCast(*uv.uv_pipe_t, stream));
        defer self.alloc.free(buf[0].base[0..buf[0].len]);
        if (nread < 0) {
            if (nread == uv.UV_EOF) {
                return;
            } else {
                @panic("Handle error");
            }
        }
        const str = buf[0].base[0..@intCast(usize, nread)];
        self.out_buf.appendSlice(str) catch @panic("error");
    }

    fn onExit(ptr: [*c]uv.uv_process_t, exit_status: i64, term_signal: c_int) callconv(.C) void {
        _ = exit_status;
        _ = term_signal;
        const self = @ptrCast(*ProcessHandle, ptr);
        self.user_cb(self.user_ctx, self.out_buf.items);
        self.startDestroy();
    }

    /// This handle is not destroyed until all close callbacks are fired.
    fn startDestroy(self: *Self) void {
        self.out_buf.deinit();
        uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.out), onCloseOut);
        // Must call close if uv_spawn failed.
        uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.handle), onClose);
    }

    fn onAlloc(handle: [*c]uv.uv_handle_t, suggested_size: usize, out_buf: [*c]uv.uv_buf_t) callconv(.C) void {
        const self = @fieldParentPtr(Self, "out", @ptrCast(*uv.uv_pipe_t, handle));
        const buf = self.alloc.alloc(u8, suggested_size) catch @panic("error");
        out_buf[0].base = buf.ptr;
        out_buf[0].len = buf.len;
    }

    fn onCloseOut(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const self = @fieldParentPtr(Self, "out", @ptrCast(*uv.uv_pipe_t, ptr));
        if (self.closed_handles == 1) {
            self.alloc.destroy(self);
        } else {
            self.closed_handles += 1;
        }
    }

    fn onClose(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
        const self = @ptrCast(*Self, ptr);
        if (self.closed_handles == 1) {
            self.alloc.destroy(self);
        } else {
            self.closed_handles += 1;
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

/// To be converted to v8.Uint8Array.
pub const Uint8Array =  struct {
    buf: []const u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.buf);
    }
};

var galloc: std.mem.Allocator = undefined;
var uncaught_promise_errors: std.AutoHashMap(u32, []const u8) = undefined;

fn initGlobal(alloc: std.mem.Allocator) void {
    galloc = alloc;
    uncaught_promise_errors = std.AutoHashMap(u32, []const u8).init(alloc);
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
            const str = v8x.allocValueAsUtf8(galloc, iso, ctx, msg.getValue());
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

fn reportUncaughtPromiseRejections(env: *Environment) void {
    var iter = uncaught_promise_errors.valueIterator();
    while (iter.next()) |err_str| {
        env.errorFmt("Uncaught promise rejection: {s}\n", .{err_str.*});
    }
}

// Main loop for running user apps.
pub fn runUserLoop(rt: *RuntimeContext, comptime DevMode: bool) void {
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
                        sdl.SDL_WINDOWEVENT_RESIZED => handleSdlWindowResized(rt, event.window),
                        else => {},
                    }
                },
                sdl.SDL_KEYDOWN => {
                    const std_event = platform.initSdlKeyDownEvent(event.key);
                    rt.handleKeyDownEvent(api.fromStdKeyDownEvent(std_event), DevMode);
                },
                sdl.SDL_KEYUP => {
                    const std_event = platform.initSdlKeyUpEvent(event.key);
                    rt.handleKeyUpEvent(api.fromStdKeyUpEvent(std_event), DevMode);
                },
                sdl.SDL_MOUSEBUTTONDOWN => {
                    const std_event = platform.initSdlMouseDownEvent(event.button);
                    rt.handleMouseDownEvent(api.fromStdMouseDownEvent(std_event), DevMode);
                },
                sdl.SDL_MOUSEBUTTONUP => {
                    const std_event = platform.initSdlMouseUpEvent(event.button);
                    rt.handleMouseUpEvent(api.fromStdMouseUpEvent(std_event), DevMode);
                },
                sdl.SDL_MOUSEMOTION => {
                    if (rt.active_window.on_mouse_move_cb != null) {
                        const std_event = platform.initSdlMouseMoveEvent(event.motion);
                        rt.handleMouseMoveEvent(api.fromStdMouseMoveEvent(std_event), DevMode);
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

        // Receiving an uncaught exception exits in normal mode.
        // In dev mode, dev_ctx.has_error should also be set and continue to display a dev window.
        const exitFromUncaughtError = !DevMode and rt.received_uncaught_exception;
        const should_update = rt.num_windows > 0 and !exitFromUncaughtError;
        if (!should_update) {
            return;
        }

        if (rt.num_windows == 1) {
            updateSingleWindow(rt, DevMode);
        } else {
            updateMultipleWindows(rt, DevMode);
        }

        if (rt.uv_poller.polled) {
            processMainEventLoop(rt);
        }

        if (DevMode) {
            if (rt.dev_ctx.restart_requested) {
                return;
            }
        }
    }
}

fn updateMultipleWindows(rt: *RuntimeContext, comptime DevMode: bool) void {
    _ = DevMode;
    const ctx = rt.getContext();

    // Currently, we just use the smallest delay. This forces larger target fps to be update more frequently.
    // TODO: Make windows with varying target fps work.
    var min_delay: u64 = std.math.maxInt(u64);

    var cur_res = rt.resources.getListHead(rt.window_resource_list).?;
    cur_res = rt.resources.getNextIdNoCheck(cur_res);
    while (cur_res != NullId) {
        const res = rt.resources.getNoCheck(cur_res);
        if (res.deinited) {
            cur_res = rt.resources.getNextIdNoCheck(cur_res);
            continue;
        }
        const win = stdx.ptrCastAlign(*CsWindow, res.ptr);

        win.window.makeCurrent();
        var cam: graphics.Camera = undefined;
        cam.init2D(win.window.getWidth(), win.window.getHeight());
        rt.renderer.beginFrame(cam);

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

        rt.renderer.endFrame();
        const delay = win.fps_limiter.endFrame();
        if (delay < min_delay) {
            min_delay = delay;
        }
        cur_res = rt.resources.getNextIdNoCheck(cur_res);
    }

    platform.delay(min_delay);

    // TODO: Run any queued micro tasks.
}

fn updateSingleWindow(rt: *RuntimeContext, comptime DevMode: bool) void {
    const ctx = rt.getContext();
    var cam: graphics.Camera = undefined;
    cam.init2D(rt.active_window.window.getWidth(), rt.active_window.window.getHeight());
    rt.renderer.beginFrame(cam);

    // Start frame timer after beginFrame since it could delay to sync with OpenGL pipeline.
    rt.active_window.fps_limiter.beginFrame();

    // Don't call user's onUpdate if dev mode has an error.
    if (!DevMode or !rt.dev_ctx.has_error) {
        if (rt.active_window.on_update_cb) |cb| {
            const g_ctx = rt.active_window.js_graphics.toValue();
            _ = cb.inner.call(ctx, rt.active_window.js_window, &.{ g_ctx }) orelse {
                // const trace = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                // defer rt.alloc.free(trace);
                // errorFmt("{s}", .{trace});
                // return;
            };
        }
    }

    if (DevMode) {
        if (rt.dev_ctx.dev_window != null) {
            // No user windows are active. Draw a default background.
            const g = rt.active_window.graphics;
            g.pushState();
            defer g.popState();
            g.resetTransform();
            // Background.
            const Background = graphics.Color.init(30, 30, 30, 255);
            g.setFillColor(Background);
            g.fillRect(0, 0, @intToFloat(f32, rt.active_window.window.impl.width), @intToFloat(f32, rt.active_window.window.impl.height));
            devmode.renderDevHud(rt, rt.active_window);
        } else if (rt.active_window.show_dev_mode) {
            const g = rt.active_window.graphics;
            g.pushState();
            defer g.popState();
            g.resetTransform();
            devmode.renderDevHud(rt, rt.active_window);
        }
    }

    rt.renderer.endFrame();
    const delay = rt.active_window.fps_limiter.endFrame();
    if (delay > 0) {
        platform.delay(delay);
    }

    // TODO: Run any queued micro tasks.
}

const ResourceListId = u32;
pub const ResourceId = u32;
pub const ResourceTag = enum {
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

    window: platform.Window,
    on_update_cb: ?v8.Persistent(v8.Function),
    on_mouse_up_cb: ?v8.Persistent(v8.Function),
    on_mouse_down_cb: ?v8.Persistent(v8.Function),
    on_mouse_move_cb: ?v8.Persistent(v8.Function),
    on_key_up_cb: ?v8.Persistent(v8.Function),
    on_key_down_cb: ?v8.Persistent(v8.Function),
    on_resize_cb: ?v8.Persistent(v8.Function),
    js_window: v8.Persistent(v8.Object),

    // Managed by window handle.
    graphics: *graphics.Graphics,
    js_graphics: v8.Persistent(v8.Object),

    fps_limiter: graphics.DefaultFpsLimiter,

    show_dev_mode: bool,

    pub fn init(self: *Self, rt: *RuntimeContext, window: platform.Window, window_id: ResourceId) void {
        self.window = window;
        const iso = rt.isolate;
        const ctx = rt.getContext();
        const js_window = rt.window_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
        const js_window_id = iso.initIntegerU32(window_id);
        js_window.setInternalField(0, js_window_id);

        const g = rt.getRenderer(&self.window).getGraphics();
        const js_graphics = rt.graphics_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
        js_graphics.setInternalField(0, iso.initExternal(g));

        self.* = .{
            .window = window,
            .on_update_cb = null,
            .on_mouse_up_cb = null,
            .on_mouse_down_cb = null,
            .on_mouse_move_cb = null,
            .on_key_up_cb = null,
            .on_key_down_cb = null,
            .on_resize_cb = null,
            .js_window = iso.initPersistent(v8.Object, js_window),
            .js_graphics = iso.initPersistent(v8.Object, js_graphics),
            .graphics = g,
            .fps_limiter = graphics.DefaultFpsLimiter.init(60),
            .show_dev_mode = false,
        };
    }

    pub fn deinit(self: *Self, rt: *RuntimeContext, skip_window: bool) void {
        if (!skip_window) {
            self.window.deinit();
        }

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
        if (self.on_resize_cb) |*cb| {
            cb.deinit();
        }

        self.js_window.deinit();
        // Invalidate graphics ptr.
        const iso = rt.isolate;
        const zero = iso.initNumberBitCastedU64(0);
        self.js_graphics.castToObject().setInternalField(0, zero);
        self.js_graphics.deinit();
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self.window.resize(width, height);
        // SDL is designed to not fire SDL_WINDOWEVENT_RESIZED for resizes invoked from code,
        // so the user onResize handler wouldn't be called.
        // However, if the window was adjusted by the os window manager,
        // we should fire SDL_WINDOWEVENT_RESIZED just like it does for window creation.
        const final_width = self.window.getWidth();
        const final_height = self.window.getHeight();
        if (final_width != width or final_height != height) {
            if (Backend == .OpenGL) {
                var e = sdl.SDL_Event{
                    .window = sdl.SDL_WindowEvent{
                        .type = sdl.SDL_WINDOWEVENT,
                        .event = sdl.SDL_WINDOWEVENT_RESIZED,
                        .data1 = @intCast(c_int, final_width),
                        .data2 = @intCast(c_int, final_height),
                        .windowID = self.window.impl.id,
                        .timestamp = undefined,
                        .padding1 = undefined,
                        .padding2 = undefined,
                        .padding3 = undefined,
                    },
                };
                _ = sdl.SDL_PushEvent(&e);
            }
        }
    }

    fn handleResizeEvent(self: *Self, rt: *RuntimeContext, e: api.cs_input.ResizeEvent) void {
        // Update the backend buffer.
        self.window.handleResize(e.width, e.height);

        if (rt.dev_mode and rt.dev_ctx.has_error) {
            return;
        }

        if (self.on_resize_cb) |cb| {
            const js_event = rt.getJsValue(e);
            _ = cb.inner.call(rt.getContext(), self.js_window, &.{ js_event });
        }
    }
};

pub fn onFreeResource(c_info: ?*const v8.C_WeakCallbackInfo) callconv(.C) void {
    const info = v8.WeakCallbackInfo.initFromC(c_info);
    const ptr = info.getParameter();
    const external = stdx.ptrCastAlign(*ExternalResourceHandle, ptr);
    external.rt.destroyResourceHandle(external.res_id);
}

pub fn runTestMain(alloc: std.mem.Allocator, src_path: []const u8, env: *Environment) !bool {
    // Measure total time.
    var timer = try std.time.Timer.start();
    defer {
        const duration = timer.read();
        env.printFmt("time: {}ms\n", .{duration / @floatToInt(u64, 1e6)});
    }

    const abs_path = try std.fs.cwd().realpathAlloc(alloc, src_path);
    defer alloc.free(abs_path);

    const config = RuntimeConfig{
        .is_test_runner = true,
        .is_dev_mode = false,
    };

    var rt: RuntimeContext = undefined;
    initGlobalRuntime(alloc, &rt, config, env);
    defer deinitGlobalRuntime(alloc, &rt);

    try rt.runMainScript(abs_path);

    while (rt.num_async_tests_finished < rt.num_async_tests) {
        if (pollMainEventLoop(&rt)) {
            processMainEventLoop(&rt);
            continue;
        } else break;
    }

    if (rt.num_isolated_tests_finished < rt.isolated_tests.items.len) {
        runIsolatedTests(&rt);
    }

    reportUncaughtPromiseRejections(rt.env);

    // Test results.
    rt.env.printFmt("Passed: {d}\n", .{rt.num_tests_passed});
    rt.env.printFmt("Tests: {d}\n", .{rt.num_tests});

    return rt.num_tests_passed == rt.num_tests;
}

/// Performs a restart for dev mode.
fn restart(rt: *RuntimeContext) !void {
    // log.debug("restart", .{});

    // Save context.
    const alloc = rt.alloc;
    const platform_ = rt.platform;

    var main_script_path: ?[]const u8 = null;
    if (rt.main_script_path) |path| {
        main_script_path = alloc.dupe(u8, path) catch unreachable;
    }
    defer {
        if (main_script_path) |path| {
            alloc.free(path);
        }
    }

    rt.dev_ctx.dev_window = rt.active_window; // Set dev_window so deinit skips this window resource.
    const win = rt.dev_ctx.dev_window.?.window;
    const dev_ctx = rt.dev_ctx;
    const env = rt.env;

    // Shutdown runtime.
    shutdownRuntime(rt);
    rt.exit();
    rt.deinit();

    // Start runtime again with saved context.
    const config = RuntimeConfig{
        .is_test_runner = false,
        .is_dev_mode = true,
    };
    rt.init(alloc, platform_, config, env);
    rt.enter();

    // Reuse dev context.
    rt.dev_ctx = dev_ctx;
    rt.dev_ctx.restart_requested = false;

    // Reuse window.
    const res = rt.createCsWindowResource();
    res.ptr.init(rt, win, res.id);
    rt.active_window = res.ptr;
    rt.active_window.show_dev_mode = true;

    rt.dev_ctx.cmdLog("Restarted.");
    rt.dev_ctx.dev_window = res.ptr;

    if (main_script_path) |path| {
        try rt.runMainScript(path);
    }
}

/// Shutdown other threads gracefully before starting deinit.
fn shutdownRuntime(rt: *RuntimeContext) void {
    if (rt.dev_mode) {
        rt.dev_ctx.close();
    }

    // Start deiniting resources so they queue up their final events.
    // Resources like the http server will need some time to close out their connections.
    var iter = rt.resources.nodes.iterator();
    while (iter.nextPtr()) |it| {
        const res_id = iter.cur_id;
        if (!it.data.deinited) {
            rt.startDeinitResourceHandle(res_id);
        }
    }

    if (rt.env.pump_rt_on_graceful_shutdown) {
        // Pump events for 3 seconds before force closing everything.
        pumpMainEventLoopFor(rt, 3000);
    }

    rt.timer.close();

    rt.uv_poller.close_flag.store(true, .Release);

    // Make uv poller wake up with dummy update.
    var res = uv.uv_async_send(rt.uv_dummy_async);
    uv.assertNoError(res);

    // uv poller might be waiting for wakeup.
    rt.uv_poller.setPollReady();

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
        fn closeHandle(ptr: [*c]uv.uv_handle_t, ctx: ?*anyopaque) callconv(.C) void {
            _ = ctx;
            const handle = @ptrCast(*uv.uv_handle_t, ptr);
            // Don't close if it's already in a closing state.
            if (uv.uv_is_closing(handle) == 0) {
                uv.uv_close(handle, null);
            }
        }
    };
    uv.uv_walk(rt.uv_loop, S.closeHandle, null);
    while (uv.uv_run(rt.uv_loop, uv.UV_RUN_NOWAIT) > 0) {}
    res = uv.uv_loop_close(rt.uv_loop);
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

    // Always return true if main script is still pending (eg. top level await new Promise(() => {}))
    if (!rt.main_script_done) {
        return true;
    }

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

/// Pumps the main event loop for a given period in milliseconds.
/// This is useful if the runtime needs to shutdown gracefully and still meet a deadline to exit the process.
fn pumpMainEventLoopFor(rt: *RuntimeContext, max_ms: u32) void {
    var timer = std.time.Timer.start() catch unreachable;

    // The implementation is very similar to pollMainEventLoop/processMainEventLoop,
    // except we check against a timer during the poll step.
    while (hasPendingEvents(rt)) {
        const elapsed_ms = timer.read()/1000000;
        if (elapsed_ms > max_ms) {
            return;
        }
        // Keep timeout low (200ms) so we can return and check against the timer.
        const Timeout = 200 * 1e6;
        const wait_res = rt.main_wakeup.timedWait(Timeout);
        rt.main_wakeup.reset();
        if (wait_res) |_| {
            // Nop.
        } else |err| {
            if (err == error.Timeout) {
                continue;
            } else {
                stdx.panicFmt("unknown error: {}", .{err});
            }
        }
        processMainEventLoop(rt);
    }
}

/// Waits until there is work to process.
/// If true, a follow up processMainEventLoop should be called to do the work and reset the poller.
/// If false, there are no more pending tasks, and the caller should exit the loop.
pub fn pollMainEventLoop(rt: *RuntimeContext) bool {
    while (hasPendingEvents(rt)) {
        // Wait for events.
        // log.debug("main thread wait", .{});
        const Timeout = 4 * 1e9;
        const wait_res = rt.main_wakeup.timedWait(Timeout);

        rt.main_wakeup.reset();
        if (wait_res) |_| {
            // Nop.
        } else |err| {
            if (err == error.Timeout) {
                continue;
            } else {
                stdx.panicFmt("unknown error: {}", .{err});
            }
        }
        return true;
    }
    return false;
}

pub fn processMainEventLoop(rt: *RuntimeContext) void {
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

    rt.uv_poller.polled = false;
    rt.uv_poller.setPollReady();
}

/// If there are too many promises to execute for a js execution, v8 will defer the rest into it's event loop.
/// This is usually called right after a js execution.
fn processV8EventLoop(rt: *RuntimeContext) void {
    while (rt.platform.pumpMessageLoop(rt.isolate, false)) {}
}

fn runIsolatedTests(rt: *RuntimeContext) void {
    const iso = rt.isolate;
    const ctx = rt.getContext();

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

                const extra_data = rt.rt_ctx_tmpl.inner.initInstance(ctx);
                extra_data.setInternalField(0, data);
                extra_data.setInternalField(1, iso.initStringUtf8(case.name));
                const on_rejected = v8.Function.initWithData(ctx, gen.genJsFunc(reportIsolatedTestFailure, .{
                    .asyncify = false,
                    .is_data_rt = false,
                }), extra_data);

                _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected) catch unreachable;

                if (promise.getState() == .kRejected or promise.getState() == .kFulfilled) {
                    // If the initial async call is already fullfilled or rejected,
                    // we'll need to run microtasks manually to run our handlers.
                    iso.performMicrotasksCheckpoint();
                }
            } else {
                const err_str = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(err_str);
                rt.env.errorFmt("Test: {s}\n{s}", .{ case.name, err_str });
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
        rt.env.errorFmt("Uncaught Exception:\n{s}", .{ err_str });
    }
}

pub const RuntimeConfig = struct {
    is_test_runner: bool = false,
    is_dev_mode: bool = false,
};

/// Initialize libs, deps, globals, and the runtime assumed to be global.
/// This is intended to be the common setup for one global runtime.
pub fn initGlobalRuntime(alloc: std.mem.Allocator, rt: *RuntimeContext, config: RuntimeConfig, env: *Environment) void {
    _ = curl.initDefault();
    stdx.http.init(alloc);
    h2o.init();
    initGlobal(alloc);

    const platform_ = ensureV8Platform();

    rt.init(alloc, platform_, config, env);
    rt.enter();
}

pub fn deinitGlobalRuntime(_: std.mem.Allocator, rt: *RuntimeContext) void {
    shutdownRuntime(rt);
    rt.exit();
    rt.deinit();

    deinitGlobal();
    stdx.http.deinit();
    curl.deinit();
}

/// src_path is absolute or relative to the cwd.
pub fn runUserMain(alloc: std.mem.Allocator, src_path: []const u8, dev_mode: bool, env: *Environment) !void {
    const abs_path = try std.fs.path.resolve(alloc, &.{ src_path });
    defer alloc.free(abs_path);

    const config = RuntimeConfig{
        .is_test_runner = false,
        .is_dev_mode = dev_mode,
    };

    var rt: RuntimeContext = undefined;
    initGlobalRuntime(alloc, &rt, config, env);
    defer deinitGlobalRuntime(alloc, &rt);

    if (dev_mode) {
        rt.dev_ctx.init(alloc, .{});

        // Create the dev mode window.
        // The first window created by the user script will take over this window.
        const win = platform.Window.init(rt.alloc, .{
            .width = 800,
            .height = 600,
            .title = "Dev Mode",
            .high_dpi = true,
            .resizable = true,
            .mode = .Windowed,
        }) catch unreachable;
        const res = rt.createCsWindowResource();
        res.ptr.init(&rt, win, res.id);
        rt.active_window = res.ptr;
        rt.active_window.show_dev_mode = true;
        rt.dev_ctx.cmdLog("Dev Mode started.");
        rt.dev_ctx.dev_window = res.ptr;
    }

    try rt.runMainScript(abs_path);

    // Check whether to start off with a realtime loop or event loop.
    if (!dev_mode) {
        if (rt.num_windows > 0) {
            runUserLoop(&rt, false);
        } else {
            // TODO: Detect need for realtime loop (eg. on creation of a window) and switch to runUserLoop.
            while (true) {
                if (builtin.is_test and rt.requested_shutdown) {
                    break;
                }
                if (pollMainEventLoop(&rt)) {
                    processMainEventLoop(&rt);
                    continue;
                } else break;
            }
        }
    } else {
        while (true) {
            runUserLoop(&rt, true);
            if (rt.dev_ctx.restart_requested) {
                try restart(&rt);
                continue;
            } else break;
        }
    }
}

pub const WeakHandleId = u32;

const WeakHandle = struct {
    const Self = @This();

    ptr: *anyopaque,
    tag: WeakHandleTag,
    obj: v8.Persistent(v8.Object),

    fn deinit(self: *Self, rt: *RuntimeContext) void {
        switch (self.tag) {
            .DrawCommandList => {
                const ptr = stdx.ptrCastAlign(*graphics.DrawCommandList, self.ptr);
                ptr.deinit();
                rt.alloc.destroy(ptr);
            },
            .Sound => {
                const ptr = stdx.ptrCastAlign(*audio.Sound, self.ptr);
                ptr.deinit(rt.alloc);
                rt.alloc.destroy(ptr);
            },
            .Random => {
                const ptr = stdx.ptrCastAlign(*Random, self.ptr);
                rt.alloc.destroy(ptr);
            },
            .Null => {},
        }
    }
};

pub const WeakHandleTag = enum {
    DrawCommandList,
    Sound,
    Random,
    Null,
};

pub fn WeakHandlePtr(comptime Tag: WeakHandleTag) type {
    return switch (Tag) {
        .DrawCommandList => *graphics.DrawCommandList,
        .Sound => *audio.Sound,
        .Random => *Random,
        else => unreachable,
    };
}

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
    const resolver = rt.promises.getNoCheck(promise_id);
    _ = resolver.inner.reject(rt.getContext(), .{ .handle = js_val_ptr });
}

pub fn resolvePromise(rt: *RuntimeContext, promise_id: PromiseId, native_val: anytype) void {
    const js_val_ptr = rt.getJsValuePtr(native_val);
    const resolver = rt.promises.getNoCheck(promise_id);
    _ = resolver.inner.resolve(rt.getContext(), .{ .handle = js_val_ptr });
}

/// A struct that also has the runtime context.
pub fn RuntimeValue(comptime T: type) type {
    return struct {
        rt: *RuntimeContext,
        inner: T,
    };
}

/// Holds the rt and resource id for passing into a callback.
const ExternalResourceHandle = struct {
    rt: *RuntimeContext,
    res_id: ResourceId,
};

fn reportIsolatedTestFailure(data: FuncData, val: v8.Value) void {
    const obj = data.val.castTo(v8.Object);
    const rt = stdx.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castTo(v8.External).get());

    const test_name = v8x.allocValueAsUtf8(rt.alloc, rt.isolate, rt.getContext(), obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    rt.num_isolated_tests_finished += 1;

    const trace_str = allocExceptionJsStackTraceString(rt, val);
    defer rt.alloc.free(trace_str);
    rt.env.printFmt("Test Failed: \"{s}\"\n{s}", .{test_name, trace_str});
}

fn passIsolatedTest(rt: *RuntimeContext) void {
    rt.num_isolated_tests_finished += 1;
    rt.num_tests_passed += 1;
}

const Promise = struct {
    task_id: u32,
};

// TODO: Since Cosmic uses the js stack trace api,
// it might be faster to return a plain object with the code and msg.
pub fn createPromiseError(rt: *RuntimeContext, err: CsError) v8.Value {
    const iso = rt.isolate;
    const api_err = std.meta.stringToEnum(api.cs_core.CsError, @errorName(err)).?;
    const err_msg = api.cs_core.errString(api_err);
    const js_err = v8.Exception.initError(iso.initStringUtf8(err_msg));
    _ = js_err.castTo(v8.Object).setValue(rt.getContext(), iso.initStringUtf8("code"), iso.initIntegerU32(@enumToInt(api_err)));
    return js_err;
}

pub fn invokeFuncAsync(rt: *RuntimeContext, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) v8.Promise {
    const ClosureTask = tasks.ClosureTask(func);
    const task = ClosureTask{
        .alloc = rt.alloc,
        .args = args,
    };

    const iso = rt.isolate;
    const ctx = rt.getContext();
    const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(ctx));
    const promise = resolver.inner.getPromise();
    const promise_id = rt.promises.add(resolver) catch unreachable;
    const S = struct {
        fn onSuccess(_ctx: RuntimeValue(PromiseId), _res: TaskOutput(ClosureTask)) void {
            const _promise_id = _ctx.inner;
            resolvePromise(_ctx.rt, _promise_id, _res);
        }
        fn onFailure(ctx_: RuntimeValue(PromiseId), err_: anyerror) void {
            const _promise_id = ctx_.inner;
            if (std.meta.stringToEnum(api.cs_core.CsError, @errorName(err_))) |_| {
                const js_err = createPromiseError(ctx_.rt, @errSetCast(CsError, err_));
                rejectPromise(ctx_.rt, _promise_id, js_err);
            } else {
                rejectPromise(ctx_.rt, _promise_id, err_);
            }
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
    PathExists,
    IsDir,
    InvalidFormat,
    ConnectFailed,
    CertVerify,
    CertBadFile,
    CantResolveHost,
    Unsupported,
    Unknown,
};

/// Double precision can represent a 53 bit significand. 
pub const F64SafeUint = u53;
pub const F64SafeInt = i54;

test "F64SafeUint, F64SafeInt" {
    const uint: F64SafeUint = std.math.maxInt(F64SafeUint);
    var double = @intToFloat(f64, uint);
    try t.eq(@floatToInt(F64SafeUint, double), uint);

    const int: F64SafeInt = std.math.maxInt(F64SafeInt);
    double = @intToFloat(f64, int);
    try t.eq(@floatToInt(F64SafeInt, double), int);
}

const ModuleInfo = struct {
    const Self = @This();

    dir: []const u8,

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.dir);
    }
};

pub fn finalizeHandle(c_info: ?*const v8.C_WeakCallbackInfo) callconv(.C) void {
    const info = v8.WeakCallbackInfo.initFromC(c_info);
    const rt = stdx.ptrCastAlign(*RuntimeContext, info.getParameter());
    const id = @intCast(u32, @ptrToInt(info.getInternalField(1)) / 2);
    rt.destroyWeakHandle(id);
}

pub fn createWeakHandle(rt: *RuntimeContext, comptime Tag: WeakHandleTag, ptr: WeakHandlePtr(Tag)) v8.Object {
    const ctx = rt.getContext();
    const iso = rt.isolate;
    const template = switch (Tag) {
        .DrawCommandList => rt.handle_class,
        .Sound => rt.sound_class,
        .Random => rt.random_class,
        else => unreachable,
    };
    const new = template.inner.initInstance(ctx);
    var new_p = iso.initPersistent(v8.Object, new);

    const id = rt.weak_handles.add(.{
        .ptr = ptr,
        .tag = Tag,
        .obj = new_p,
    }) catch unreachable;

    const js_id = iso.initExternal(@intToPtr(?*anyopaque, id));
    new.setInternalField(0, js_id);

    // id is doubled then halved on callback.
    // Set on the second internal field since the first is already used for the original id.
    new.setAlignedPointerInInternalField(1, @intToPtr(?*anyopaque, @intCast(u64, id) * 2));

    new_p.setWeakFinalizer(rt, finalizeHandle, .kInternalFields);

    return new_p.inner;
}

const RunModuleScriptResult = struct {
    const Self = @This();

    const State = enum {
        Pending,
        Success,
        Failed,
    };

    // This only reflects the state after returning from runModuleScript.
    // To query the module eval state, check the eval promise.
    state: State,

    // If Failed, mod can be null if it failed on the compile step.
    mod: ?v8.Persistent(v8.Module),

    // The eval promise. Will resolve to undefined or reject with error.
    eval: ?v8.Persistent(v8.Promise),

    // If Failed, js_err_trace will be present.
    js_err_trace: ?[]const u8,

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        if (self.js_err_trace) |trace| {
            alloc.free(trace);
        }
        if (self.mod) |*mod_| {
            mod_.deinit();
        }
        if (self.eval) |*eval_| {
            eval_.deinit();
        }
    }
};

fn handleSdlWindowResized(rt: *RuntimeContext, event: sdl.SDL_WindowEvent) void {
    if (rt.getCsWindowResourceBySdlId(event.windowID)) |res_id| {
        if (rt.getResourcePtr(.CsWindow, res_id)) |win| {
            win.handleResizeEvent(rt, .{
                .width = @intCast(u32, event.data1),
                .height = @intCast(u32, event.data2),
            });
        }
    }
}

// The v8 platform is stored as a global since after it's deinited,
// we can no longer reinit v8. See v8.deinitV8/v8.deinitV8Platform.
var g_platform: ?v8.Platform = null;

/// Returns global v8 platform. Initializes if needed.
pub fn ensureV8Platform() v8.Platform {
    if (g_platform == null) {
        const platform_ = v8.Platform.initDefault(0, true);
        v8.initV8Platform(platform_);
        v8.initV8();

        const S = struct {
            fn handleDcheck(file: [*c]const u8, line: c_int, msg: [*c]const u8) callconv(.C) void {
                log.debug("v8 dcheck {s}:{} {s}", .{file, line, msg});
                // Just panic and print zig's stack trace.
                unreachable;
            }
        };
        // Override v8 debug assert reporting.
        v8.setDcheckFunction(S.handleDcheck);
        g_platform = platform_;
    }
    return g_platform.?;
}

/// This should only be called at the end of the program or when v8 is no longer needed.
/// V8 can't be reinited after this.
fn deinitV8() void {
    if (g_platform) |platform_| {
        v8.deinitV8();
        v8.deinitV8Platform();
        platform_.deinit();
        g_platform = null;
    }
}

/// v8.StackTrace/v8.StackFrame are limited and not as rich as the js stack trace API.
/// JsStackTrace will contain data from CallSiteInfos passed into js Error.prepareStackTrace.
/// See api_init.js on how Error.prepareStackTrace is set up.
const JsStackTrace = struct {
    const Self = @This();

    frames: []const JsStackFrame,

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        for (self.frames) |frame| {
            frame.deinit(alloc);
        }
        alloc.free(self.frames);
    }
};

const JsStackFrame = struct {
    const Self = @This();

    url: []const u8,
    func_name: ?[]const u8,
    line_num: u32,
    col_num: u32,
    is_constructor: bool,
    is_async: bool,

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.url);
        if (self.func_name) |name| {
            alloc.free(name);
        }
    }
};

pub fn appendJsStackTraceString(buf: *std.ArrayList(u8), trace: JsStackTrace) void {
    const writer = buf.writer();
    for (trace.frames) |frame| {
        writer.writeAll("    at ") catch unreachable;
        if (frame.is_async) {
            writer.writeAll("async ") catch unreachable;
        }
        if (frame.func_name) |name| {
            writer.print("{s} ", .{ name }) catch unreachable;
        }
        writer.print("{s}:{}:{}\n", .{ frame.url, frame.line_num, frame.col_num }) catch unreachable;
    }
}

pub fn allocExceptionJsStackTraceString(rt: *RuntimeContext, exception: v8.Value) []const u8 {
    const alloc = rt.alloc;
    const iso = rt.isolate;
    const ctx = rt.getContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var buf = std.ArrayList(u8).init(alloc);
    const writer = buf.writer();

    _ = v8x.appendValueAsUtf8(&buf, iso, ctx, exception);
    writer.writeAll("\n") catch unreachable;

    // Access js stack property to invoke Error.prepareStackTrace
    if (exception.isObject()) {
        const exception_o = exception.castTo(v8.Object);
        if (exception_o.getValue(ctx, iso.initStringUtf8("stack"))) |stack| {
            if (stack.isString()) {
                if (exception_o.getValue(ctx, iso.initStringUtf8("__frames"))) |frames| {
                    if (frames.isArray()) {
                        // Convert to JsStackTrace
                        const trace = JsStackTrace{
                            .frames = getNativeValue(alloc, iso, ctx, []const JsStackFrame, frames) catch &.{},
                        };
                        defer trace.deinit(alloc);
                        appendJsStackTraceString(&buf, trace);
                    }
                } else |_| {}
            }
        } else |_| {}
    }

    return buf.toOwnedSlice();
}

/// Converts a js value to a target native type without a RuntimeContext.
fn getNativeValue(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, comptime Target: type, val: v8.Value) !Target {
    switch (Target) {
        bool => return val.toBool(iso),
        u32 => return val.toU32(ctx),
        []const u8 => {
            return v8x.allocValueAsUtf8(alloc, iso, ctx, val);
        },
        else => {
            if (@typeInfo(Target) == .Struct) {
                if (val.isObject()) {
                    const obj = val.castTo(v8.Object);
                    var res: Target = undefined;
                    if (comptime hasAllOptionalFields(Target)) {
                        res = .{};
                    }
                    const Fields = std.meta.fields(Target);
                    inline for (Fields) |Field| {
                        if (@typeInfo(Field.field_type) == .Optional) {
                            const child_val = obj.getValue(ctx, iso.initStringUtf8(Field.name)) catch return error.CantConvert;
                            const ChildType = comptime @typeInfo(Field.field_type).Optional.child;
                            if (child_val.isNullOrUndefined()) {
                                @field(res, Field.name) = null;
                            } else {
                                @field(res, Field.name) = getNativeValue2(alloc, iso, ctx, ChildType, child_val);
                            }
                        } else {
                            const js_val = obj.getValue(ctx, iso.initStringUtf8(Field.name)) catch return error.CantConvert;
                            if (getNativeValue2(alloc, iso, ctx, Field.field_type, js_val)) |child_value| {
                                @field(res, Field.name) = child_value;
                            }
                        }
                    }
                    return res;
                } else return error.CantConvert;
            } else if (@typeInfo(Target) == .Pointer) {
                if (@typeInfo(Target).Pointer.size == .Slice) {
                    const Child = @typeInfo(Target).Pointer.child;
                    if (val.isArray()) {
                        const len = val.castTo(v8.Array).length();
                        const buf = alloc.alloc(Child, len) catch unreachable;
                        errdefer alloc.free(buf);
                        const val_o = val.castTo(v8.Object);
                        var i: u32 = 0;
                        while (i < len) : (i += 1) {
                            const child_val = val_o.getAtIndex(ctx, i) catch return error.CantConvert;
                            buf[i] = getNativeValue(alloc, iso, ctx, Child, child_val) catch return error.CantConvert;
                        }
                        return buf;
                    } else return error.CantConvert;
                }
            }
            comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to {s}", .{ @typeName(@TypeOf(val)), @typeName(Target) }));
        }
    }
}

fn getNativeValue2(alloc: std.mem.Allocator, iso: v8.Isolate, ctx: v8.Context, comptime Target: type, val: v8.Value) ?Target {
    return getNativeValue(alloc, iso, ctx, Target, val) catch return null;
}

fn handleMainModuleScriptError(rt: *RuntimeContext, val: v8.Value) void {
    const err_str = allocExceptionJsStackTraceString(rt, val);
    defer rt.alloc.free(err_str);
    rt.env.errorFmt("{s}", .{err_str});

    rt.main_script_done = true;
    if (rt.dev_mode) {
        rt.dev_ctx.enterJsErrorState(rt, err_str);
    }

    const res = uv.uv_async_send(rt.uv_dummy_async);
    uv.assertNoError(res);
}

fn handleMainModuleScriptSuccess(rt: *RuntimeContext) void {
    rt.main_script_done = true;
    if (rt.dev_mode) {
        rt.dev_ctx.enterJsSuccessState();
    }

    const res = uv.uv_async_send(rt.uv_dummy_async);
    uv.assertNoError(res);
}

/// Override libc assert fail handler to abort with zig stack trace.
/// Some dependencies like libuv use it.
export fn __assert_fail(assertion: [*c]const u8, file: [*c]const u8, line: c_uint, function: [*c]const u8) callconv(.C) void {
    log.debug("libc assert failed: {s} {s}:{}, Assertion: {s}", .{function, file, line, assertion});
    unreachable;
}

pub const Random = struct {
    impl: std.rand.DefaultPrng,
    iface: std.rand.Random,
};