const std = @import("std");
const process = std.process;
const stdx = @import("stdx");
const string = stdx.string;
const ds = stdx.ds;
const graphics = @import("graphics");
const Color = graphics.Color;
const sdl = @import("sdl");

const v8 = @import("v8.zig");
const log = stdx.log.scoped(.main);

const VersionText = "0.1 Alpha";

// Cosmic main. Common entry point for cli and gui.
pub fn main() !void {
    // Fast temporary memory allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    if (args.len == 1) {
        replAndExit();
    }

    // Skip exe path arg.
    var arg_idx: usize = 1;

    const cmd = nextArg(args, &arg_idx).?;
    if (string.eq(cmd, "cli")) {
        replAndExit();
    } else if (string.eq(cmd, "run")) {
        const src_path = nextArg(args, &arg_idx) orelse {
            abortFmt("Expected path to main source file.", .{});
        };
        try runAndExit(src_path);
    } else if (string.eq(cmd, "help")) {
        usage();
        process.exit(0);
    } else if (string.eq(cmd, "version")) {
        version();
        process.exit(0);
    } else {
        usage();
        abortFmt("unsupported command {s}", .{cmd});
    }
}

fn runAndExit(src_path: []const u8) !void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    const src = try std.fs.cwd().readFileAlloc(alloc, src_path, 1e9);
    defer alloc.free(src);

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    v8.initV8();
    defer {
        _ = v8.deinitV8();
        v8.deinitV8Platform();
    }

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    v8_ctx.init(alloc, isolate);
    defer v8_ctx.deinit();

    isolate.enter();
    defer isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var context = initCosmicJsContext(&v8_ctx, isolate);
    context.enter();
    defer context.exit();

    const origin = v8.String.initUtf8(isolate, src_path);

    var res: v8.ExecuteResult = undefined;
    defer res.deinit();
    v8.executeString(alloc, isolate, src, origin, &res);

    while (platform.pumpMessageLoop(isolate, false)) {
        log.info("What does this do?", .{});
        unreachable;
    }

    if (!res.success) {
        printFmt("{s}", .{res.err.?});
        process.exit(1);
    }

    // Check if we need to enter an app loop.
    if (v8_ctx.num_windows > 0) {
        runUserLoop(&v8_ctx);
    }

    process.exit(0);
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

fn csWindow_OnDrawFrame(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len == 0) {
        v8.throwErrorException(isolate, "Expected callback arg");
        return;
    }
    const arg = info.getArg(0);
    if (!arg.isFunction()) {
        v8.throwErrorException(isolate, "Expected callback arg");
        return;
    }

    const this = info.getThis();
    const window_id = this.getInternalField(0).toU32(ctx);

    const res = v8_ctx.resources.get(window_id);
    if (res.tag == .CsWindow) {
        const window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
        
        // Persist callback func.
        const p = v8.Persistent.init(isolate, arg);
        window.onDrawFrameCbs.append(p.castToFunction()) catch unreachable;
    }
}

fn csColor_Get(comptime c: Color) v8.FunctionCallback {
    const S = struct {
        fn get(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const new = v8_ctx.color_class.getFunction(ctx).newInstance(ctx, &.{}).?;
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "r"), v8.Integer.initU32(isolate, c.channels.r));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "g"), v8.Integer.initU32(isolate, c.channels.g));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "b"), v8.Integer.initU32(isolate, c.channels.b));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "a"), v8.Integer.initU32(isolate, c.channels.a));

            const return_value = info.getReturnValue();
            return_value.set(new);
        }
    };
    return S.get;
}

fn csGraphics_SetFillColor(key: ?*const v8.Name, value: ?*const c_void, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
    _ = key;
    const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const val = v8.Value{ .handle = value.? };
    if (val.isObject()) {
        const r = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "r")).toU32(ctx);
        const g = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "g")).toU32(ctx);
        const b = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "b")).toU32(ctx);
        const a = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "a")).toU32(ctx);
        v8_ctx.active_graphics.setFillColor(Color.init(
            @intCast(u8, r),
            @intCast(u8, g),
            @intCast(u8, b),
            @intCast(u8, a),
        ));
    }
}

fn csGraphics_GetFillColor(key: ?*const v8.Name, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
    const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    // const return_value = info.getReturnValue();
    // return_value.set();

    _ = key;
}

fn csGraphics_FillRect(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    var x: f32 = 0;
    var y: f32 = 0;
    var width: f32 = 0;
    var height: f32 = 0;

    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len >= 1) {
        x = info.getArg(0).toF32(ctx);
    }
    if (len >= 2) {
        y = info.getArg(1).toF32(ctx);
    }
    if (len >= 3) {
        width = info.getArg(2).toF32(ctx);
    }
    if (len >= 4) {
        height = info.getArg(3).toF32(ctx);
    }

    v8_ctx.active_graphics.fillRect(x, y, width, height);
}

fn csColor_New(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var r: u32 = 0;
    var g: u32 = 0;
    var b: u32 = 0;
    var a: u32 = 255;

    const len = info.length();
    if (len == 3) {
        r = info.getArg(0).toU32(ctx);
        g = info.getArg(1).toU32(ctx);
        b = info.getArg(2).toU32(ctx);
    } else if (len == 4) {
        r = info.getArg(0).toU32(ctx);
        g = info.getArg(1).toU32(ctx);
        b = info.getArg(2).toU32(ctx);
        a = info.getArg(3).toU32(ctx);
    } else {
        v8.throwErrorException(isolate, "Expected (r, g, b) or (r, g, b, a)");
        return;
    }

    const new = v8_ctx.color_class.getFunction(ctx).newInstance(ctx, &.{}).?;
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "r"), v8.Integer.initU32(isolate, r));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "g"), v8.Integer.initU32(isolate, g));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "b"), v8.Integer.initU32(isolate, b));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "a"), v8.Integer.initU32(isolate, a));

    const return_value = info.getReturnValue();
    return_value.set(new);
}

fn csWindow_New(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    var title: []const u8 = undefined;
    var width: u32 = 800;
    var height: u32 = 600;

    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len >= 1) {
        title = v8.valueToUtf8Alloc(v8_ctx.alloc, isolate, ctx, info.getArg(0));
    } else {
        title = string.dupe(v8_ctx.alloc, "Window") catch unreachable;
    }
    defer v8_ctx.alloc.free(title);
    if (len >= 2) {
        width = info.getArg(1).toU32(ctx);
    }
    if (len >= 3) {
        height = info.getArg(2).toU32(ctx);
    }

    log.debug("dim {} {}", .{width, height});

    const res = v8_ctx.createCsWindowResource();

    const js_window = v8_ctx.window_class.initInstance(ctx);
    log.debug("js_window ptr {*}", .{js_window.handle});
    const js_window_id = v8.Integer.initU32(isolate, res.id);
    js_window.setInternalField(0, js_window_id);
    const return_value = info.getReturnValue();
    return_value.set(js_window);

    const window = graphics.Window.init(v8_ctx.alloc, .{
        .width = width,
        .height = height,
        .title = title,
    }) catch unreachable;
    res.ptr.init(v8_ctx.alloc, window, v8.Persistent.init(isolate, js_window));

    v8_ctx.active_window = res.ptr;
    v8_ctx.active_graphics = v8_ctx.active_window.graphics;
}

fn print(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const len = info.length();

    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();
    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const str = v8.valueToUtf8Alloc(v8_ctx.alloc, isolate, ctx, info.getArg(i));
        defer v8_ctx.alloc.free(str);
        printFmt("{s} ", .{str});
    }
    printFmt("\n", .{});
}

// TODO: Use comptime to generate zig callback functions.
// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
fn initCosmicJsContext(ctx: *RuntimeContext, isolate: v8.Isolate) v8.Context {
    // We set with the same undef values for each type, it might help the optimizing compiler if it knows the field types ahead of time.
    const undef_u32 = v8.Integer.initU32(isolate, 0);

    // JsWindow
    const window_class = v8.ObjectTemplate.initDefault(isolate);
    window_class.setInternalFieldCount(1);
    ctx.setProp(window_class, "onDrawFrame", v8.FunctionTemplate.initCallback(isolate, csWindow_OnDrawFrame));
    ctx.window_class = window_class;

    // JsColor
    const color_class = v8.FunctionTemplate.initDefault(isolate);
    var instance = color_class.getInstanceTemplate();
    ctx.setProp(instance, "r", undef_u32);
    ctx.setProp(instance, "g", undef_u32);
    ctx.setProp(instance, "b", undef_u32);
    ctx.setProp(instance, "a", undef_u32);
    ctx.setProp(color_class, "new", v8.FunctionTemplate.initCallback(isolate, csColor_New));
    const colors = &[_]std.meta.Tuple(&.{[]const u8, Color}){
        .{"LightGray", Color.LightGray},
        .{"Gray", Color.Gray},
        .{"DarkGray", Color.DarkGray},
        .{"Yellow", Color.Yellow},
        .{"Gold", Color.Gold},
        .{"Orange", Color.Orange},
        .{"Pink", Color.Pink},
        .{"Red", Color.Red},
        .{"Maroon", Color.Maroon},
        .{"Green", Color.Green},
        .{"Lime", Color.Lime},
        .{"DarkGreen", Color.DarkGreen},
        .{"SkyBlue", Color.SkyBlue},
        .{"Blue", Color.Blue},
        .{"DarkBlue", Color.DarkBlue},
        .{"Purple", Color.Purple},
        .{"Violet", Color.Violet},
        .{"DarkPurple", Color.DarkPurple},
        .{"Beige", Color.Beige},
        .{"Brown", Color.Brown},
        .{"DarkBrown", Color.DarkBrown},
        .{"White", Color.White},
        .{"Black", Color.Black},
        .{"Transparent", Color.Transparent},
        .{"Magenta", Color.Magenta},
    };
    inline for (colors) |it| {
        ctx.setFuncGetter(color_class, it.@"0", csColor_Get(it.@"1"));
    }
    ctx.color_class = color_class;

    const global_constructor = v8.FunctionTemplate.initDefault(isolate);
    global_constructor.setClassName(v8.String.initUtf8(isolate, "Global"));
    // Since Context.init only accepts ObjectTemplate, we can still name the global by using a FunctionTemplate as the constructor.
    const global = v8.ObjectTemplate.init(isolate, global_constructor);

    // cs
    const cs_constructor = v8.FunctionTemplate.initDefault(isolate);
    cs_constructor.setClassName(v8.String.initUtf8(isolate, "cosmic"));
    const cs = v8.ObjectTemplate.init(isolate, cs_constructor);

    // cs.window
    const window_constructor = v8.FunctionTemplate.initDefault(isolate);
    window_constructor.setClassName(v8.String.initUtf8(isolate, "window"));
    const window = v8.ObjectTemplate.init(isolate, window_constructor);
    ctx.setConstProp(window, "new", v8.FunctionTemplate.initCallback(isolate, csWindow_New));
    ctx.setConstProp(cs, "window", window);

    // cs.graphics
    const cs_graphics = v8.ObjectTemplate.initDefault(isolate);

    // cs.graphics.Color
    ctx.setConstProp(cs_graphics, "Color", color_class);
    ctx.setConstProp(cs, "graphics", cs_graphics);

    const graphics_class = v8.FunctionTemplate.initDefault(isolate);
    graphics_class.setClassName(v8.String.initUtf8(isolate, "Graphics"));
    {
        const proto = graphics_class.getPrototypeTemplate();
        ctx.setAccessor(proto, "fillColor", csGraphics_GetFillColor, csGraphics_SetFillColor);
        ctx.setConstProp(proto, "fillRect", v8.FunctionTemplate.initCallback(isolate, csGraphics_FillRect));
    }

    ctx.setConstProp(global, "cs", cs);
    ctx.setConstProp(global, "print", v8.FunctionTemplate.initCallback(isolate, print));

    const res = v8.Context.init(isolate, global, null);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(isolate, "cs")).castToObject();
    // For now, just create one JsGraphics instance for everything.
    ctx.js_graphics = graphics_class.getFunction(res).newInstance(res, &.{}).?;

    return res;
}

fn replAndExit() void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    var input_buf = std.ArrayList(u8).init(alloc);
    defer input_buf.deinit();

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    v8.initV8();
    defer {
        _ = v8.deinitV8();
        v8.deinitV8Platform();
    }

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

    var context = v8.Context.init(isolate, null, null);
    context.enter();
    defer context.exit();

    const origin = v8.String.initUtf8(isolate, "(shell)");

    printFmt(
        \\Cosmic ({s})
        \\exit with Ctrl+D or "exit()"
        \\
    , .{VersionText});

    while (true) {
        printFmt("\n> ", .{});
        const input = getInputOrExit(&input_buf);
        if (string.eq(input, "exit()")) {
            break;
        }

        var res: v8.ExecuteResult = undefined;
        defer res.deinit();
        v8.executeString(alloc, isolate, input, origin, &res);
        if (res.success) {
            printFmt("{s}", .{res.result.?});
        } else {
            printFmt("{s}", .{res.err.?});
        }

        while (platform.pumpMessageLoop(isolate, false)) {
            log.info("What does this do?", .{});
            unreachable;
        }
        // log.info("input: {s}", .{input});
    }
    process.exit(0);
}

fn printFmt(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(format, args) catch unreachable;
}

// TODO: We'll need to support extended key bindings/ncurses (eg. up arrow for last command) per platform.
// (Low priority since there will be a repl in the GUI)
fn getInputOrExit(input_buf: *std.ArrayList(u8)) []const u8 {
    input_buf.clearRetainingCapacity();
    std.io.getStdIn().reader().readUntilDelimiterArrayList(input_buf, '\n', 1000 * 1000 * 1000) catch |err| {
        if (err == error.EndOfStream) {
            printFmt("\n", .{});
            process.exit(0);
        } else {
            unreachable;
        }
    };
    return input_buf.items;
}

var v8_ctx: RuntimeContext = undefined;

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

const ResourceListId = u32;
const ResourceId = u32;
const ResourceTag = enum {
    CsWindow,
};

// Manages runtime resources. 
// Used by V8 callback functions.
const RuntimeContext = struct {
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

    fn init(self: *Self, alloc: std.mem.Allocator, isolate: v8.Isolate) void {
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

    fn createCsWindowResource(self: *Self) CreatedResource(CsWindow) {
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

    fn setFuncGetter(self: Self, tmpl: v8.FunctionTemplate, key: []const u8, getter: v8.FunctionCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, v8.FunctionTemplate.initCallback(self.cur_isolate, getter));
    }

    fn setGetter(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, getter: v8.AccessorNameGetterCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetter(js_key, getter);
    }

    fn setAccessor(self: Self, tmpl: v8.ObjectTemplate, key: []const u8, getter: v8.AccessorNameGetterCallback, setter: v8.AccessorNameSetterCallback) void {
        const js_key = v8.String.initUtf8(self.cur_isolate, key);
        tmpl.setGetterAndSetter(js_key, getter, setter);
    }

    fn setConstProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
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

    fn setProp(self: Self, tmpl: anytype, key: []const u8, value: anytype) void {
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
fn runUserLoop(ctx: *RuntimeContext) void {

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

const main_usage =
    \\Usage: cosmic [command] [options]
    \\
    \\Commands:
    \\
    \\  cli              Starts a REPL session.
    \\  run              Runs a Javascript or Typescript source file.
    \\  test             TODO: Runs tests in source files.
    \\  exe              TODO: Packages source files into a single binary executable.
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage.
    \\
;

fn usage() void {
    printFmt("{s}\n", .{main_usage});
}

fn version() void {
    printFmt("cosmic {s}\nv8 {s}\n", .{VersionText, v8.getVersion()});
}

pub fn abortFmt(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    process.exit(1);
}

fn nextArg(args: [][]const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}