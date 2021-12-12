const std = @import("std");
const process = std.process;
const stdx = @import("stdx");
const string = stdx.string;
const ds = stdx.ds;
const graphics = @import("graphics");
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

    v8_ctx.init(alloc);
    defer v8_ctx.deinit();

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

    isolate.enter();
    defer isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var context = initCosmicJsContext(&v8_ctx, isolate);
    context.enter();
    defer context.exit();

    const origin = v8.String.initUtf8(isolate, src_path);
    const src_js = v8.String.initUtf8(isolate, src);

    var res: v8.ExecuteResult = undefined;
    defer res.deinit();
    v8.executeString(alloc, isolate, src_js, origin, &res);

    while (platform.pumpMessageLoop(isolate, false)) {
        log.info("What does this do?", .{});
        unreachable;
    }

    // Check if we need to enter an app loop.
    if (v8_ctx.num_windows > 0) {
        runUserLoop(&v8_ctx);
    }

    if (res.success) {
        process.exit(0);
    } else {
        printFmt("{s}", .{res.err.?});
        process.exit(1);
    }
}

fn window_create(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
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
        title = v8.valueToRawUtf8Alloc(v8_ctx.alloc, isolate, ctx, info.getArg(0));
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

    const res = v8_ctx.createWindowResource();
    res.ptr.* = graphics.Window.init(v8_ctx.alloc, .{
        .width = width,
        .height = height,
        .title = title,
    }) catch unreachable;

    v8_ctx.active_window = res.ptr;

    const new = v8_ctx.window_class.initInstance(ctx);
    const return_value = info.getReturnValue();
    return_value.set(new);
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
        const str = v8.valueToRawUtf8Alloc(v8_ctx.alloc, isolate, ctx, info.getArg(i));
        defer v8_ctx.alloc.free(str);
        printFmt("{} {s}\n", .{i, str});
    }
}

// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
fn initCosmicJsContext(ctx: *V8_CallbackContext, isolate: v8.Isolate) v8.Context {
    const window_class = v8.ObjectTemplate.initDefault(isolate);
    ctx.window_class = window_class;

    var key: v8.String = undefined;

    const global = v8.ObjectTemplate.initDefault(isolate);

    // cs
    const cs = v8.ObjectTemplate.initDefault(isolate);

    // cs.window
    const window = v8.ObjectTemplate.initDefault(isolate);
    key = v8.String.initUtf8(isolate, "create");
    window.set(key, v8.FunctionTemplate.initDefault(isolate, window_create), v8.PropertyAttribute.None);

    key = v8.String.initUtf8(isolate, "window");
    cs.set(key, window, v8.PropertyAttribute.None);

    key = v8.String.initUtf8(isolate, "print");
    global.set(key, v8.FunctionTemplate.initDefault(isolate, print), v8.PropertyAttribute.None);

    key = v8.String.initUtf8(isolate, "cs");
    global.set(key, cs, v8.PropertyAttribute.None);

    return v8.Context.init(isolate, global, null);
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

        const input_js = v8.String.initUtf8(isolate, input);

        var res: v8.ExecuteResult = undefined;
        defer res.deinit();
        v8.executeString(alloc, isolate, input_js, origin, &res);
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

var v8_ctx: V8_CallbackContext = undefined;

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
    Window,
};

// Context for V8 calling into app code.
const V8_CallbackContext = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    str_buf: std.ArrayList(u8),

    window_class: v8.ObjectTemplate,

    // Collection of mappings from id to resource handles.
    resources: ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle),

    window_resource_list: ResourceListId,
    window_resource_list_last: ResourceId,
    // Keep track of active windows so we know when to stop the app.
    num_windows: u32,
    // Window that has keyboard focus and will receive swap buffer.
    active_window: *graphics.Window,

    fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .alloc = alloc,
            .str_buf = std.ArrayList(u8).init(alloc),
            .window_class = undefined,
            .resources = ds.CompactManySinglyLinkedList(ResourceListId, ResourceId, ResourceHandle).init(alloc),
            .window_resource_list = undefined,
            .window_resource_list_last = undefined,
            .num_windows = 0,
            .active_window = undefined,
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

    fn createWindowResource(self: *Self) CreatedResource(graphics.Window) {
        const ptr = self.alloc.create(graphics.Window) catch unreachable;
        self.window_resource_list_last = self.resources.insertAfter(self.window_resource_list_last, .{
            .ptr = ptr,
            .tag = .Window,
        }) catch unreachable;
        self.num_windows += 1;
        return .{
            .ptr = ptr,
            .id = self.window_resource_list_last,
        };
    }

    fn deleteWindowBySdlId(self: *Self, sdl_win_id: u32) void {
        // Head is always a dummy resource for convenience.
        var last_window_id: ResourceId = self.resources.getListHead(self.window_resource_list).?;
        var mb_window_id = self.resources.getNext(last_window_id);
        while (mb_window_id) |window_id| {
            const res = self.resources.get(window_id);
            const window = stdx.mem.ptrCastAlign(*graphics.Window, res.ptr);
            switch (graphics.Backend) {
                .OpenGL => {
                    if (window.inner.id == sdl_win_id) {
                        // Deinit and destroy.
                        window.deinit();
                        self.alloc.destroy(window);

                        // Remove from resources.
                        self.resources.removeNext(last_window_id);

                        // Update current vars.
                        if (self.window_resource_list_last == window_id) {
                            self.window_resource_list_last = last_window_id;
                        }
                        self.num_windows -= 1;
                        if (self.num_windows > 0) {
                            if (self.active_window == window) {
                                // TODO: Revisit this. For now just pick the last window.
                                self.active_window = stdx.mem.ptrCastAlign(*graphics.Window, self.resources.get(last_window_id).ptr);
                            }
                        } else {
                            self.active_window = undefined;
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
};

// Main loop for running user apps.
fn runUserLoop(ctx: *V8_CallbackContext) void {

    var fps_limiter = graphics.DefaultFpsLimiter.init(30);
    var fps: u64 = 0;

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_WINDOWEVENT => {
                    switch (event.window.event) {
                        sdl.SDL_WINDOWEVENT_CLOSE => {
                            ctx.deleteWindowBySdlId(event.window.windowID);
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
            break;
        }

        // TODO: User draw frame.

        // TODO: Run any queued micro tasks.

        ctx.active_window.swapBuffers();
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