const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const FontId = graphics.font.FontId;
const Graphics = graphics.Graphics;
const Vec2 = stdx.math.Vec2;
const StdColor = graphics.Color;
const ds = stdx.ds;
const v8 = @import("v8");

const v8x = @import("v8x.zig");
const tasks = @import("tasks.zig");
const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const RuntimeValue = runtime.RuntimeValue;
const PromiseId = runtime.PromiseId;
const Data = runtime.Data;
const ManagedStruct = runtime.ManagedStruct;
const ManagedSlice = runtime.ManagedSlice;
const Uint8Array = runtime.Uint8Array;
const CsWindow = runtime.CsWindow;
const printFmt = runtime.printFmt;
const gen = @import("gen.zig");
const log = stdx.log.scoped(.api);

/// @title Window Management
/// @name window
/// @ns cs.window
/// Provides a cross platform API to create and manage windows.
pub const cs_window = struct {

    pub fn new(rt: *RuntimeContext, title: []const u8, width: u32, height: u32) v8.Object {
        const res = rt.createCsWindowResource();

        const win = graphics.Window.init(rt.alloc, .{
            .width = width,
            .height = height,
            .title = title,
        }) catch unreachable;
        res.ptr.init(rt.alloc, rt, win, res.id);

        rt.active_window = res.ptr;
        rt.active_graphics = rt.active_window.graphics;

        return res.ptr.js_window.castToObject();
    }

    pub fn getGraphics(rt: *RuntimeContext, this: v8.Object) *const anyopaque {
        const ctx = rt.context;
        const window_id = this.getInternalField(0).toU32(ctx);

        const res = rt.resources.get(window_id);
        if (res.tag == .CsWindow) {
            const win = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
            return @ptrCast(*const anyopaque, win.js_graphics.inner.handle);
        } else {
            v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Window no longer exists for id {}", .{window_id});
            return @ptrCast(*const anyopaque, rt.js_undefined.handle);
        }
    }

    pub fn onDrawFrame(rt: *RuntimeContext, this: v8.Object, arg: v8.Function) void {
        const iso = rt.isolate;
        const ctx = rt.context;
        const window_id = this.getInternalField(0).toU32(ctx);

        const res = rt.resources.get(window_id);
        if (res.tag == .CsWindow) {
            const win = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);

            // Persist callback func.
            const p = v8.Persistent(v8.Function).init(iso, arg);
            win.onDrawFrameCbs.append(p) catch unreachable;
        }
    }
};

pub fn color_Lighter(rt: *RuntimeContext, this: v8.Object) cs_graphics.Color {
    const color = rt.getNativeValue(cs_graphics.Color, this.toValue()).?;
    return fromStdColor(toStdColor(color).lighter());
}

pub fn color_Darker(rt: *RuntimeContext, this: v8.Object) cs_graphics.Color {
    const color = rt.getNativeValue(cs_graphics.Color, this.toValue()).?;
    return fromStdColor(toStdColor(color).darker());
}

pub fn color_WithAlpha(rt: *RuntimeContext, this: v8.Object, a: u8) cs_graphics.Color {
    const color = rt.getNativeValue(cs_graphics.Color, this.toValue()).?;
    return fromStdColor(toStdColor(color).withAlpha(a));
}

pub fn color_New(rt: *RuntimeContext, r: u8, g: u8, b: u8, a: u8) *const anyopaque {
    return rt.getJsValuePtr(cs_graphics.Color{ .r = r, .g = g, .b = b, .a = a });
}

/// @title Graphics
/// @name graphics
/// @ns cs.graphics
/// Provides a cross platform API to draw lines, shapes, text, images, and other graphics onto a window or buffer.
/// By default, the coordinate system assumes the origin is at the top-left corner (0, 0). Positive x values go right and positive y values go down.
/// In a future release, there will be a direct API to the OpenGL 3 context, and support for WebGPU to target modern graphics hardware.
/// Currently, the API is focused on 2D graphics, but there are plans to add 3D graphics utilities.
pub const cs_graphics = struct {

    pub const Color = struct {

        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub const lightGray = fromStdColor(StdColor.LightGray);
        pub const gray = fromStdColor(StdColor.Gray);
        pub const darkGray = fromStdColor(StdColor.DarkGray);
        pub const yellow = fromStdColor(StdColor.Yellow);
        pub const gold = fromStdColor(StdColor.Gold);
        pub const orange = fromStdColor(StdColor.Orange);
        pub const pink = fromStdColor(StdColor.Pink);
        pub const red = fromStdColor(StdColor.Red);
        pub const maroon = fromStdColor(StdColor.Maroon);
        pub const green = fromStdColor(StdColor.Green);
        pub const lime = fromStdColor(StdColor.Lime);
        pub const darkGreen = fromStdColor(StdColor.DarkGreen);
        pub const skyBlue = fromStdColor(StdColor.SkyBlue);
        pub const blue = fromStdColor(StdColor.Blue);
        pub const darkBlue = fromStdColor(StdColor.DarkBlue);
        pub const purple = fromStdColor(StdColor.Purple);
        pub const violet = fromStdColor(StdColor.Violet);
        pub const darkPurple = fromStdColor(StdColor.DarkPurple);
        pub const beige = fromStdColor(StdColor.Beige);
        pub const brown = fromStdColor(StdColor.Brown);
        pub const darkBrown = fromStdColor(StdColor.DarkBrown);
        pub const white = fromStdColor(StdColor.White);
        pub const black = fromStdColor(StdColor.Black);
        pub const transparent = fromStdColor(StdColor.Transparent);
        pub const magenta = fromStdColor(StdColor.Magenta);
    };

    /// This provides an interface to the underlying graphics handle. It has a similar API to Web Canvas.
    pub const Context = struct {

        pub inline fn fillColor(self: *Graphics) Color {
            return fromStdColor(self.getFillColor());
        }

        pub inline fn setFillColor(self: *Graphics, color: Color) void {
            return self.setFillColor(toStdColor(color));
        }

        pub inline fn strokeColor(self: *Graphics) Color {
            return fromStdColor(self.getStrokeColor());
        }

        pub inline fn setStrokeColor(self: *Graphics, color: Color) void {
            return self.setStrokeColor(toStdColor(color));
        }

        pub inline fn lineWidth(self: *Graphics) f32 {
            return self.getLineWidth();
        }

        pub inline fn setLineWidth(self: *Graphics, width: f32) void {
            return self.setLineWidth(width);
        }

        /// Path can be absolute or relative to the cwd.
        pub fn addTtfFont(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.font.FontId {
            return g.addTTF_FontFromPath(path) catch |err| {
                if (err == error.FileNotFound) {
                    v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
                    return 0;
                } else {
                    unreachable;
                }
            };
        }

        pub inline fn addFallbackFont(self: *Graphics, font_id: FontId) void {
            self.addFallbackFont(font_id);
        }

        /// Path can be absolute or relative to the cwd.
        pub fn newImage(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.Image {
            return g.createImageFromPath(path) catch |err| {
                if (err == error.FileNotFound) {
                    v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
                    return undefined;
                } else {
                    unreachable;
                }
            };
        }

        /// Fills a rectangle with the current fill color.
        pub inline fn fillRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
            Graphics.fillRect(self, x, y, width, height);
        }

        /// Strokes a rectangle with the current stroke color.
        pub inline fn drawRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
            Graphics.drawRect(self, x, y, width, height);
        }

        /// Shifts the origin x units to the right and y units down.
        pub inline fn translate(self: *Graphics, x: f32, y: f32) void {
            Graphics.translate(self, x, y);
        }

        /// Scales from the origin x units horizontally and y units vertically.
        /// Negative value flips the axis. Value of 1 does nothing.
        pub inline fn scale(self: *Graphics, x: f32, y: f32) void {
            Graphics.scale(self, x, y);
        }

        /// Rotates the origin by radians clockwise.
        pub inline fn rotate(self: *Graphics, rad: f32) void {
            Graphics.rotate(self, rad);
        }

        pub inline fn rotateDeg(self: *Graphics, deg: f32) void {
            self.rotateDeg(deg);
        }

        // Resets the current transform to identity.
        pub inline fn resetTransform(self: *Graphics) void {
            self.resetTransform();
        }

        pub inline fn setFont(self: *Graphics, font_gid: FontId, font_size: f32) void {
            self.setFont(font_gid, font_size);
        }

        pub inline fn fillText(self: *Graphics, x: f32, y: f32, text: []const u8) void {
            self.fillText(x, y, text);
        }

        pub inline fn fillCircleSector(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.fillCircleSector(x, y, radius, start_rad, sweep_rad);
        }

        pub inline fn fillCircleSectorDeg(self: *Graphics, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.fillCircleSectorDeg(x, y, radius, start_deg, sweep_deg);
        }

        pub inline fn drawCircleArc(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.drawCircleArc(x, y, radius, start_rad, sweep_rad);
        }

        pub inline fn drawCircleArcDeg(self: *Graphics, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.drawCircleArcDeg(x, y, radius, start_deg, sweep_deg);
        }

        pub inline fn drawCircle(self: *Graphics, x: f32, y: f32, radius: f32) void {
            self.drawCircle(x, y, radius);
        }

        pub inline fn fillCircle(self: *Graphics, x: f32, y: f32, radius: f32) void {
            self.fillCircle(x, y, radius);
        }

        pub inline fn fillEllipse(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
            self.fillEllipse(x, y, h_radius, v_radius);
        }

        pub inline fn fillEllipseSector(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.fillEllipseSector(x, y, h_radius, v_radius, start_rad, sweep_rad);
        }

        pub inline fn fillEllipseSectorDeg(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.fillEllipseSectorDeg(x, y, h_radius, v_radius, start_deg, sweep_deg);
        }

        pub inline fn drawEllipse(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
            self.drawEllipse(x, y, h_radius, v_radius);
        }

        pub inline fn drawEllipseArc(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.drawEllipseArc(x, y, h_radius, v_radius, start_rad, sweep_rad);
        }

        pub inline fn drawEllipseArcDeg(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.drawEllipseArcDeg(x, y, h_radius, v_radius, start_deg, sweep_deg);
        }

        pub inline fn drawPoint(self: *Graphics, x: f32, y: f32) void {
            self.drawPoint(x, y);
        }

        pub inline fn drawLine(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32) void {
            self.drawLine(x1, y1, x2, y2);
        }

        pub inline fn drawCubicBezierCurve(self: *Graphics, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
            self.drawCubicBezierCurve(x1, y1, c1x, c1y, c2x, c2y, x2, y2);
        }

        pub inline fn drawQuadraticBezierCurve(self: *Graphics, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
            self.drawQuadraticBezierCurve(x1, y1, cx, cy, x2, y2);
        }

        pub inline fn fillTriangle(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
            self.fillTriangle(x1, y1, x2, y2, x3, y3);
        }

        pub inline fn drawRoundRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
            self.drawRoundRect(x, y, width, height, radius);
        }

        pub inline fn fillRoundRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
            self.fillRoundRect(x, y, width, height, radius);
        }

        pub fn fillPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
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

        pub fn drawSvgContent(g: *Graphics, content: []const u8) void {
            g.drawSvgContent(content) catch unreachable;
        }

        pub fn drawImageSized(g: *Graphics, x: f32, y: f32, width: f32, height: f32, image: graphics.Image) void {
            g.drawImageSized(x, y, width, height, image.id);
        }

        pub fn executeDrawList(rt: *RuntimeContext, g: *Graphics, handle: v8.Object) void {
            const ctx = rt.context;
            const ptr = handle.getInternalField(0).bitCastToU64(ctx);
            const list = @intToPtr(*graphics.DrawCommandList, ptr);
            g.executeDrawList(list.*);
        }

        pub fn compileSvgContent(rt: *RuntimeContext, g: *Graphics, content: []const u8) v8.Persistent(v8.Object) {
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

        pub fn drawPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
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

        pub fn fillConvexPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
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
    };
};

/// @title File System
/// @name files
/// @ns cs.files
/// Provides a cross platform API to create and manage files.
pub const cs_files = struct {

    /// Path can be absolute or relative to the cwd.
    /// Returns the contents on success or null.
    pub fn readFile(rt: *RuntimeContext, path: []const u8) ?ManagedStruct(Uint8Array) {
        const res = std.fs.cwd().readFileAlloc(rt.alloc, path, 1e12) catch |err| switch (err) {
            // Whitelist errors to silence.
            error.FileNotFound => return null,
            else => unreachable,
        };
        return ManagedStruct(Uint8Array).init(rt.alloc, Uint8Array{ .buf = res });
    }

    /// Path can be absolute or relative to the cwd.
    /// Returns the contents as utf8 on success or null.
    pub fn readTextFile(rt: *RuntimeContext, path: []const u8) ?ds.Box([]const u8) {
        const res = std.fs.cwd().readFileAlloc(rt.alloc, path, 1e12) catch |err| switch (err) {
            // Whitelist errors to silence.
            error.FileNotFound => return null,
            else => unreachable,
        };
        return ds.Box([]const u8).init(rt.alloc, res);
    }

    /// Writes bytes to a file.
    /// Path can be absolute or relative to the cwd.
    /// Returns true on success or false.
    pub fn writeFile(path: []const u8, arr: Uint8Array) bool {
        std.fs.cwd().writeFile(path, arr.buf) catch return false;
        return true;
    }

    /// Writes UTF8 text to a file.
    /// Path can be absolute or relative to the cwd.
    /// Returns true on success or false.
    pub fn writeTextFile(path: []const u8, str: []const u8) bool {
        std.fs.cwd().writeFile(path, str) catch return false;
        return true;
    }

    /// Path can be absolute or relative to the cwd.
    pub fn copyFile(from: []const u8, to: []const u8) bool {
        std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch return false;
        return true;
    }

    /// Path can be absolute or relative to the cwd.
    pub fn moveFile(from: []const u8, to: []const u8) bool {
        std.fs.cwd().rename(from, to) catch return false;
        return true;
    }

    /// Returns the absolute path of the current working directory.
    pub fn cwd(rt: *RuntimeContext) ?ds.Box([]const u8) {
        const _cwd = std.fs.cwd().realpathAlloc(rt.alloc, ".") catch return null;
        return ds.Box([]const u8).init(rt.alloc, _cwd);
    }

    /// Path can be absolute or relative to the cwd.
    pub fn getPathInfo(path: []const u8) ?PathInfo {
        const stat = std.fs.cwd().statFile(path) catch return null;
        return PathInfo{
            .kind = stat.kind,
        };
    }

    pub const PathInfo = struct {
        kind: std.fs.File.Kind,
    };

    /// Path can be absolute or relative to the cwd.
    pub fn listDir(rt: *RuntimeContext, path: []const u8) ?ManagedSlice(FileEntry) {
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

        /// @internal
        pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
            alloc.free(self.name);
        }
    };

    /// Appends bytes to a file. File is created if it doesn't exist.
    /// Path can be absolute or relative to the cwd.
    /// Returns true on success or false.
    pub fn appendFile(path: []const u8, arr: Uint8Array) bool {
        stdx.fs.appendFile(path, arr.buf) catch return false;
        return true;
    }

    /// Appends UTF-8 text to a file. File is created if it doesn't exist.
    /// Path can be absolute or relative to the cwd.
    /// Returns true on success or false.
    pub fn appendTextFile(path: []const u8, str: []const u8) bool {
        stdx.fs.appendFile(path, str) catch return false;
        return true;
    }

    /// Path can be absolute or relative to the cwd.
    pub fn ensurePath(rt: *RuntimeContext, path: []const u8) bool {
        std.fs.cwd().makePath(path) catch |err| switch (err) {
            else => {
                v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
                return false;
            },
        };
        return true;
    }

    /// Path can be absolute or relative to the cwd.
    pub fn pathExists(rt: *RuntimeContext, path: []const u8) bool {
        return stdx.fs.pathExists(path) catch |err| {
            v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
            return false;
        };
    }

    /// Path can be absolute or relative to the cwd.
    pub fn removeFile(path: []const u8) bool {
        std.fs.cwd().deleteFile(path) catch return false;
        return true;
    }

    /// Path can be absolute or relative to the cwd.
    pub fn removeDir(path: []const u8, recursive: bool) bool {
        if (recursive) {
            std.fs.cwd().deleteTree(path) catch return false;
        } else {
            std.fs.cwd().deleteDir(path) catch return false;
        }
        return true;
    }

    /// Resolves '..' in paths and returns an absolute path.
    /// Currently does not resolve home '~'.
    pub fn resolvePath(rt: *RuntimeContext, path: []const u8) ?ds.Box([]const u8) {
        const res = std.fs.path.resolve(rt.alloc, &.{path}) catch return null;
        return ds.Box([]const u8).init(rt.alloc, res);
    }
};

/// @title HTTP Client and Server
/// @name http
/// @ns cs.http
/// Provides an API to make HTTP requests and host HTTP servers. HTTPS is supported.
/// There are plans to support WebSockets.
pub const cs_http = struct {

    /// Makes a GET request and Returns the response body text if successful.
    /// Returns false if there was a connection error, timeout error (30 secs), or the response code is 5xx.
    /// Advanced: cs.http.request
    pub fn get(rt: *RuntimeContext, url: []const u8) ?ds.Box([]const u8) {
        const opts = RequestOptions{
            .method = .Get,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequest(rt, url, opts);
    }

    pub fn getAsync(rt: *RuntimeContext, url: []const u8) v8.Promise {
        const opts = RequestOptions{
            .method = .Get,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequestAsync(rt, url, opts);
    }

    /// Makes a POST request and returns the response body text if successful.
    /// Returns false if there was a connection error, timeout error (30 secs), or the response code is 5xx.
    /// Advanced: cs.http.request
    pub fn post(rt: *RuntimeContext, url: []const u8, body: []const u8) ?ds.Box([]const u8) {
        const opts = RequestOptions{
            .method = .Post,
            .body = body,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequest(rt, url, opts);
    }

    /// Async version of cs.http.post
    pub fn postAsync(rt: *RuntimeContext, url: []const u8, body: []const u8) v8.Promise {
        const opts = RequestOptions{
            .method = .Post,
            .body = body,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequestAsync(rt, url, opts);
    }

    fn simpleRequest(rt: *RuntimeContext, url: []const u8, opts: RequestOptions) ?ds.Box([]const u8) {
        const std_opts = toStdRequestOptions(opts);
        const resp = stdx.http.request(rt.alloc, url, std_opts) catch return null;
        defer resp.deinit(rt.alloc);
        if (resp.status_code < 500) {
            return ds.Box([]const u8).init(rt.alloc, rt.alloc.dupe(u8, resp.body) catch unreachable);
        } else {
            return null;
        }
    }

    fn simpleRequestAsync(rt: *RuntimeContext, url: []const u8, opts: RequestOptions) v8.Promise {
        const iso = rt.isolate;

        const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));
        const promise = resolver.inner.getPromise();
        const promise_id = rt.promises.add(resolver) catch unreachable;

        const S = struct {
            fn onSuccess(ptr: *anyopaque, resp: stdx.http.Response) void {
                const ctx = stdx.mem.ptrCastAlign(*RuntimeValue(PromiseId), ptr);
                const pid = ctx.inner;
                if (resp.status_code < 500) {
                    runtime.resolvePromise(ctx.rt, pid, resp.body);
                } else {
                    runtime.resolvePromise(ctx.rt, pid, ctx.rt.js_false);
                }
                resp.deinit(ctx.rt.alloc);
            }

            fn onFailure(ctx: RuntimeValue(PromiseId), err: anyerror) void {
                const _promise_id = ctx.inner;
                runtime.rejectPromise(ctx.rt, _promise_id, err);
            }
        };

        const ctx = RuntimeValue(PromiseId){
            .rt = rt,
            .inner = promise_id,
        };

        stdx.http.requestAsync(rt.alloc, url, toStdRequestOptions(opts), ctx, S.onSuccess) catch |err| S.onFailure(ctx, err);

        return promise;
    }

    fn toStdRequestOptions(opts: RequestOptions) stdx.http.RequestOptions {
        var res = stdx.http.RequestOptions{
            .method = std.meta.stringToEnum(stdx.http.RequestMethod, @tagName(opts.method)).?,
            .body = opts.body,
            .keep_connection = opts.keepConnection,
            .timeout = opts.timeout,
            .headers = opts.headers,
        };
        if (opts.contentType) |content_type| {
            res.content_type = std.meta.stringToEnum(stdx.http.ContentType, @tagName(content_type)).?;
        }
        return res;
    }

    /// Returns Response object if request was successful.
    /// Throws exception if there was a connection or protocol error.
    pub fn request(rt: *RuntimeContext, url: []const u8, mb_opts: ?RequestOptions) !ManagedStruct(stdx.http.Response) {
        const opts = mb_opts orelse RequestOptions{};
        const std_opts = toStdRequestOptions(opts);
        const resp = try stdx.http.request(rt.alloc, url, std_opts);
        return ManagedStruct(stdx.http.Response){
            .alloc = rt.alloc,
            .val = resp,
        };
    }

    pub fn requestAsync(rt: *RuntimeContext, url: []const u8, mb_opts: ?RequestOptions) v8.Promise {
        const opts = mb_opts orelse RequestOptions{};

        const iso = rt.isolate;

        const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));
        const promise = resolver.inner.getPromise();
        const promise_id = rt.promises.add(resolver) catch unreachable;

        const S = struct {
            fn onSuccess(ptr: *anyopaque, resp: stdx.http.Response) void {
                const ctx = stdx.mem.ptrCastAlign(*RuntimeValue(PromiseId), ptr);
                const pid = ctx.inner;
                runtime.resolvePromise(ctx.rt, pid, resp);
                resp.deinit(ctx.rt.alloc);
            }

            fn onFailure(ctx: RuntimeValue(PromiseId), err: anyerror) void {
                const _promise_id = ctx.inner;
                runtime.rejectPromise(ctx.rt, _promise_id, err);
            }
        };

        const ctx = RuntimeValue(PromiseId){
            .rt = rt,
            .inner = promise_id,
        };

        const std_opts = toStdRequestOptions(opts);
        stdx.http.requestAsync(rt.alloc, url, std_opts, ctx, S.onSuccess) catch |err| S.onFailure(ctx, err);
        return promise;
    }

    const RequestMethod = enum {
        Head,
        Get,
        Post,
        Put,
        Delete,
    };

    const ContentType = enum {
        Json,
        FormData,
    };

    pub const RequestOptions = struct {
        method: RequestMethod = .Get,
        keepConnection: bool = false,

        contentType: ?ContentType = null,
        body: ?[]const u8 = null,

        /// In seconds. 0 timeout = no timeout
        timeout: u32 = 30,
        headers: ?std.StringHashMap([]const u8) = null,
    };

    pub fn serveHttps(rt: *RuntimeContext, host: []const u8, port: u16, cert_path: []const u8, key_path: []const u8) !v8.Object {
        const handle = rt.createCsHttpServerResource();
        const server = handle.ptr;
        server.init(rt);
        try server.startHttps(host, port, cert_path, key_path);

        const js_handle = rt.http_server_class.getFunction(rt.context).initInstance(rt.context, &.{}).?;
        js_handle.setInternalField(0, rt.isolate.initIntegerU32(handle.id));
        return js_handle;
    }

    pub fn serveHttp(rt: *RuntimeContext, host: []const u8, port: u16) !v8.Object {
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
};

/// @title Core
/// @name core
/// @ns cs.core
/// Contains common utilities. All functions here are also available in the global scope. You can call them directly without the cs.core prefix.
pub const cs_core = struct {

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
            const str = v8x.valueToUtf8Alloc(rt.alloc, iso, ctx, info.getArg(i));
            defer rt.alloc.free(str);
            printFmt("{s} ", .{str});
        }
        printFmt("\n", .{});
    }

    pub fn bufferToUtf8(buf: v8.Uint8Array) ?[]const u8 {
        var shared_ptr_store = v8.ArrayBufferView.castFrom(buf).getBuffer().getBackingStore();
        defer v8.BackingStore.sharedPtrReset(&shared_ptr_store);

        const store = v8.BackingStore.sharedPtrGet(&shared_ptr_store);
        const len = store.getByteLength();
        if (len > 0) {
            const ptr = @ptrCast([*]u8, store.getData().?);
            if (std.unicode.utf8ValidateSlice(ptr[0..len])) {
                return ptr[0..len];
            } else return null;
        } else return "";
    }
};

/// Path can be absolute or relative to the current executing script.
fn resolveEnvPath(rt: *RuntimeContext, path: []const u8) []const u8 {
    return std.fs.path.resolve(rt.alloc, &.{ rt.cur_script_dir_abs, path }) catch unreachable;
}

// FUTURE: Save test cases and execute them in parallel.
pub fn createTest(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
    const iso = rt.isolate;
    const ctx = rt.context;

    // Dupe name since we will be invoking functions that could clear the transient string buffer.
    const name_dupe = rt.alloc.dupe(u8, name) catch unreachable;
    defer rt.alloc.free(name_dupe);

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    defer try_catch.deinit();

    rt.num_tests += 1;
    if (cb.toValue().isAsyncFunction()) {
        // Async test.
        rt.num_async_tests += 1;
        if (cb.call(ctx, rt.js_undefined, &.{})) |val| {
            const promise = val.castTo(v8.Promise);

            const data = iso.initExternal(rt);
            const on_fulfilled = v8.Function.initWithData(ctx, gen.genJsFuncSync(passAsyncTest), data);

            const tmpl = iso.initObjectTemplateDefault();
            tmpl.setInternalFieldCount(2);
            const extra_data = tmpl.initInstance(ctx);
            extra_data.setInternalField(0, data);
            extra_data.setInternalField(1, iso.initStringUtf8(name_dupe));
            const on_rejected = v8.Function.initWithData(ctx, gen.genJsFunc(reportAsyncTestFailure, .{
                .asyncify = false,
                .is_data_rt = false,
            }), extra_data);

            _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected);
        } else {
            const err_str = v8x.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
            defer rt.alloc.free(err_str);
            printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
        }
    } else {
        // Sync test.
        if (cb.call(ctx, rt.js_undefined, &.{})) |_| {
            rt.num_tests_passed += 1;
        } else {
            const err_str = v8x.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
            defer rt.alloc.free(err_str);
            printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
        }
    }
}

/// Currently meant for async tests that need to be run sequentially after all sync tests have ran.
pub fn createIsolatedTest(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
    if (!cb.toValue().isAsyncFunction()) {
        v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Test \"{s}\": Only async tests can use testIsolated.", .{name});
        return;
    }
    rt.num_tests += 1;
    // Store the function to be run later.
    rt.isolated_tests.append(.{
        .name = rt.alloc.dupe(u8, name) catch unreachable,
        .js_fn = rt.isolate.initPersistent(v8.Function, cb),
    }) catch unreachable;
}

fn reportAsyncTestFailure(data: Data, val: v8.Value) void {
    const obj = data.val.castTo(v8.Object);
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castTo(v8.External).get());

    const test_name = v8x.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    // TODO: report stack trace.
    rt.num_async_tests_finished += 1;
    const str = v8x.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, val);
    defer rt.alloc.free(str);

    printFmt("Test Failed: \"{s}\"\n{s}\n", .{test_name, str});
}

fn passAsyncTest(rt: *RuntimeContext) void {
    rt.num_async_tests_passed += 1;
    rt.num_async_tests_finished += 1;
    rt.num_tests_passed += 1;
}

// This function sets up a async endpoint manually for future reference.
// We can also resuse the sync endpoint and run it on the worker thread with ctx.setConstAsyncFuncT.
// fn files_ReadFileAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
//     const iso = rt.isolate;

//     const task = tasks.ReadFileTask{
//         .alloc = rt.alloc,
//         .path = rt.alloc.dupe(u8, path) catch unreachable,
//     };

//     const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.context));

//     const promise = resolver.inner.getPromise();
//     const promise_id = rt.promises.add(resolver) catch unreachable;

//     const S = struct {
//         fn onSuccess(ctx: RuntimeValue(PromiseId), _res: TaskOutput(tasks.ReadFileTask)) void {
//             const _promise_id = ctx.inner;
//             runtime.resolvePromise(ctx.rt, _promise_id, .{
//                 .handle = ctx.rt.getJsValuePtr(_res),
//             });
//         }

//         fn onFailure(ctx: RuntimeValue(PromiseId), _err: anyerror) void {
//             const _promise_id = ctx.inner;
//             runtime.rejectPromise(ctx.rt, _promise_id, .{
//                 .handle = ctx.rt.getJsValuePtr(_err),
//             });
//         }
//     };

//     const task_ctx = RuntimeValue(PromiseId){
//         .rt = rt,
//         .inner = promise_id,
//     };
//     _ = rt.work_queue.addTaskWithCb(task, task_ctx, S.onSuccess, S.onFailure);

//     return promise;
// }

fn fromStdColor(color: StdColor) cs_graphics.Color {
    return .{ .r = color.channels.r, .g = color.channels.g, .b = color.channels.b, .a = color.channels.a };
}

fn toStdColor(color: cs_graphics.Color) StdColor {
    return .{ .channels = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a } };
}