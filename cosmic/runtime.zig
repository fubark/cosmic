const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const graphics = @import("graphics");
const sdl = @import("sdl");

const v8 = @import("v8.zig");
const js_env = @import("js_env.zig");

// Manages runtime resources. 
// Used by V8 callback functions.
pub const RuntimeContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    str_buf: std.ArrayList(u8),

    window_class: v8.ObjectTemplate,
    color_class: v8.FunctionTemplate,

    // Collection of mappings from id to resource handles.
    resources: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle),

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

    js_graphics: v8.Object,

    pub fn init(self: *Self, alloc: std.mem.Allocator, isolate: v8.Isolate) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .color_class = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .window_resource_list = undefined,
            .window_resource_list_last = undefined,
            .num_windows = 0,
            .active_window = undefined,
            .active_graphics = undefined,
            .cur_isolate = isolate,
            .js_graphics = undefined,
        };

        // Insert dummy head so we can set last.
        const dummy: ResourceHandle = undefined;
        self.window_resource_list = self.resources.addListWithHead(dummy) catch unreachable;
        self.window_resource_list_last = self.resources.getListHead(self.window_resource_list).?;
    }

    fn deinit(self: *Self) void {
        self.str_buf.deinit();

        var iter = self.resources.items.iterator();
        while (iter.next()) |item| {
            switch (item.data.tag) {
                .Window => {
                    const window = stdx.mem.ptrCastAlign(*graphics.Window, item.data.ptr);
                    window.deinit();
                    self.alloc.destroy(window);
                },
            }
        }
        self.resources.deinit();
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
                        cs_window.deinit();
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

    pub fn setFuncGetter(self: Self, tmpl: v8.FunctionTemplate, key: []const u8, getter: v8.FunctionCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, v8.FunctionTemplate.initCallback(self.cur_isolate, getter));
    }

    pub fn setGetter(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, getter: v8.AccessorNameGetterCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, getter);
    }

    pub fn setAccessor(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, getter: v8.AccessorNameGetterCallback, setter: v8.AccessorNameSetterCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetterAndSetter(js_key, getter, setter);
    }

    pub fn setConstFuncT(self: Self, tmpl: anytype, key: []const u8, comptime func: anytype) void {
        self.setConstProp(tmpl, key, v8.FunctionTemplate.initCallback(self.cur_isolate, js_env.genJsFunc(func)));
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

    var fps_limiter = graphics.DefaultFpsLimiter.init(30);
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
            _ = onDrawFrame.call(isolate_ctx, ctx.active_window.js_window, &.{ctx.js_graphics.toValue()}) orelse {
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

    pub fn init(self: *Self, alloc: std.mem.Allocator, window: graphics.Window, js_window: v8.Persistent) void {
        self.* = .{
            .window = window,
            .onDrawFrameCbs = std.ArrayList(v8.Function).init(alloc),
            .js_window = js_window,
            .graphics = undefined,
        };
        self.graphics = alloc.create(graphics.Graphics) catch unreachable;
        self.graphics.init(alloc, window.getWidth(), window.getHeight());
    }

    pub fn deinit(self: Self) void {
        self.graphics.deinit();
        self.window.deinit();
        for (self.onDrawFrameCbs.items) |onDrawFrame| {
            onDrawFrame.castToPersistent().deinit();
        }
        self.onDrawFrameCbs.deinit();
        self.js_window.deinit();
    }
};

pub fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}