const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");

const v8 = @import("v8.zig");
const js_env = @import("js_env.zig");
const log = stdx.log.scoped(.runtime);

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

    cur_isolate: v8.Isolate,
    cur_script_dir_abs: []const u8,

    // This is used to store native string slices copied from v8.String for use in the immediate native callback functions.
    // It will automatically clear at the pre callback step if the current size is too large.
    // Native callback functions that have []const u8 in their params should assume they only live until end of function scope.
    cb_str_buf: std.ArrayList(u8),
    cb_f32_buf: std.ArrayList(f32),

    vec2_buf: std.ArrayList(Vec2),

    js_undefined: v8.Primitive,

    pub fn init(self: *Self, alloc: std.mem.Allocator, isolate: v8.Isolate, src_path: []const u8) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .color_class = undefined,
            .graphics_class = undefined,
            .image_class = undefined,
            .handle_class = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .weak_handles = ds.CompactUnorderedList(u32, WeakHandle).init(alloc),
            .window_resource_list = undefined,
            .window_resource_list_last = undefined,
            .num_windows = 0,
            .active_window = undefined,
            .active_graphics = undefined,
            .cur_isolate = isolate,
            .cur_script_dir_abs = getSrcPathDirAbs(alloc, src_path) catch unreachable,
            .cb_str_buf = std.ArrayList(u8).init(alloc),
            .cb_f32_buf = std.ArrayList(f32).init(alloc),
            .vec2_buf = std.ArrayList(Vec2).init(alloc),

            // Store locally for quick access.
            .js_undefined = v8.Primitive.initUndefined(isolate),
        };

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = .{ .ptr = undefined, .tag = .Dummy };
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;
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
    }

    pub fn destroyWeakHandleByPtr(self: *Self, ptr: *const c_void) void {
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

    pub fn setFuncGetter(self: Self, tmpl: v8.FunctionTemplate, key: []const u8, comptime native_val_or_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        if (@typeInfo(@TypeOf(native_val_or_cb)) == .Fn) {
            @compileError("TODO");
        } else {
            tmpl.setGetter(js_key, v8.FunctionTemplate.initCallback(self.cur_isolate, js_env.genJsFuncGetValue(native_val_or_cb)));
        }
    }

    pub fn setGetter(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, js_env.genJsGetter(native_cb));
    }

    pub fn setAccessor(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, comptime native_getter_cb: anytype, comptime native_setter_cb: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetterAndSetter(js_key, js_env.genJsGetter(native_getter_cb), js_env.genJsSetter(native_setter_cb));
    }

    pub fn setFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        self.setProp(tmpl, key, v8.FunctionTemplate.initCallback(self.cur_isolate, js_env.genJsFunc(native_cb)));
    }

    pub fn setConstFuncT(self: Self, tmpl: anytype, key: []const u8, comptime native_cb: anytype) void {
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallback(self.cur_isolate, js_env.genJsFunc(native_cb)));
    }

    pub fn setConstProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        switch (@TypeOf(value)) {
            u32 => {
                tmpl.set(js_key, v8.Integer.initU32(self.cur_isolate, value), v8.PropertyAttribute.ReadOnly);
            },
            else => {
                tmpl.set(js_key, value, v8.PropertyAttribute.ReadOnly);
            }
        }
    }

    pub fn initFuncT(self: Self, name: []const u8) v8.FunctionTemplate {
        const new = v8.FunctionTemplate.initDefault(self.cur_isolate);
        new.setClassName(v8.String.initUtf8(self.cur_isolate, name));
        return new;
    }

    pub fn setProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        switch (@TypeOf(value)) {
            u32 => {
                tmpl.set(js_key, v8.Integer.initU32(self.cur_isolate, value), v8.PropertyAttribute.None);
            },
            else => {
                tmpl.set(js_key, value, v8.PropertyAttribute.None);
            }
        }
    }
};

// Main loop for running user apps.
pub fn runUserLoop(ctx: *RuntimeContext) void {

    var fps_limiter = graphics.DefaultFpsLimiter.init(60);
    var fps: u64 = 0;

    const isolate = ctx.cur_isolate;
    const isolate_ctx = ctx.cur_isolate.getCurrentContext();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_WINDOWEVENT => {
                    switch (event.window.event) {
                        sdl.SDL_WINDOWEVENT_CLOSE => {
                            ctx.deleteCsWindowBySdlId(event.window.windowID);
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

        const should_update = ctx.num_windows > 0;
        if (!should_update) {
            return;
        }

        ctx.active_graphics.beginFrame();

        for (ctx.active_window.onDrawFrameCbs.items) |onDrawFrame| {
            _ = onDrawFrame.call(isolate_ctx, ctx.active_window.js_window, &.{ctx.active_window.js_graphics.toValue(), v8.Number.init(isolate, @intToFloat(f64, fps)).toValue()}) orelse {
                const trace = v8.getTryCatchErrorString(ctx.alloc, isolate, try_catch);
                defer ctx.alloc.free(trace);
                printFmt("{s}", .{trace});
                return;
            };
        }
        ctx.active_graphics.endFrame();

        // TODO: Run any queued micro tasks.

        ctx.active_window.window.swapBuffers();

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
    ptr: *c_void,
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
    onDrawFrameCbs: std.ArrayList(v8.Function),
    js_window: v8.Persistent,

    // Currently, each window has its own graphics handle.
    graphics: *graphics.Graphics,
    js_graphics: v8.Persistent,

    pub fn init(self: *Self, alloc: std.mem.Allocator, rt: *RuntimeContext, window: graphics.Window, window_id: ResourceId) void {
        const isolate = rt.cur_isolate;
        const ctx = isolate.getCurrentContext();

        const js_window = rt.window_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        const js_window_id = v8.Integer.initU32(isolate, window_id);
        js_window.setInternalField(0, js_window_id);

        const g = alloc.create(graphics.Graphics) catch unreachable;
        const js_graphics = rt.graphics_class.getFunction(ctx).initInstance(ctx, &.{}).?;
        const js_graphics_ptr = v8.Number.initBitCastedU64(isolate, @ptrToInt(g));
        js_graphics.setInternalField(0, js_graphics_ptr);

        self.* = .{
            .window = window,
            .onDrawFrameCbs = std.ArrayList(v8.Function).init(alloc),
            .js_window = v8.Persistent.init(isolate, js_window),
            .js_graphics = v8.Persistent.init(isolate, js_graphics),
            .graphics = g,
        };
        self.graphics.init(alloc, window.getWidth(), window.getHeight());
    }

    pub fn deinit(self: *Self, rt: *RuntimeContext) void {
        self.graphics.deinit();
        rt.alloc.destroy(self.graphics);
        self.window.deinit();
        for (self.onDrawFrameCbs.items) |onDrawFrame| {
            onDrawFrame.castToPersistent().deinit();
        }
        self.onDrawFrameCbs.deinit();
        self.js_window.deinit();
        // Invalidate graphics ptr.
        self.js_graphics.castToObject().setInternalField(0, v8.Number.initBitCastedU64(rt.cur_isolate, 0));
        self.js_graphics.deinit();
    }
};

pub fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}

fn getSrcPathDirAbs(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.fs.path.dirname(path)) |dir| {
        return try std.fs.path.resolve(alloc, &.{ dir });
    } else {
        const cwd = try std.process.getCwdAlloc(alloc);
        defer alloc.free(cwd);
        return try std.fs.path.resolve(alloc, &.{ cwd });
    }
}

/// Returns false if main script run encountered an error.
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
    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    isolate.enter();
    defer isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    global_rt.init(alloc, isolate, src_path);
    defer global_rt.deinit();

    var context = js_env.init(&global_rt, isolate);
    context.enter();
    defer context.exit();

    const origin = v8.String.initUtf8(isolate, src_path);

    var res: v8.ExecuteResult = undefined;
    defer res.deinit();
    v8.executeString(alloc, isolate, src, origin, &res);

    while (platform.pumpMessageLoop(isolate, false)) {
        log.debug("What does this do?", .{});
        unreachable;
    }

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        return error.MainScriptError;
    }

    // Check if we need to enter an app loop.
    if (global_rt.num_windows > 0) {
        runUserLoop(&global_rt);
    }
}

// TODO: Move out of global scope.
var global_rt: RuntimeContext = undefined;

const WeakHandle = struct {
    const Self = @This();

    ptr: *const c_void,
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