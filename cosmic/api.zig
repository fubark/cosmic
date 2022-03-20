const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const builtin = @import("builtin");
const ds = stdx.ds;
const v8 = @import("v8");
const input = @import("input");
const KeyCode = input.KeyCode;
const t = stdx.testing;
const Mock = t.Mock;
const curl = @import("curl");
const ma = @import("miniaudio");
const Vec3 = stdx.math.Vec3;

const audio = @import("audio.zig");
const AudioEngine = audio.AudioEngine;
const StdSound = audio.Sound;
const v8x = @import("v8x.zig");
const tasks = @import("tasks.zig");
const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const RuntimeValue = runtime.RuntimeValue;
const ResourceId = runtime.ResourceId;
const PromiseId = runtime.PromiseId;
const F64SafeUint = runtime.F64SafeUint;
const Error = runtime.CsError;
const onFreeResource = runtime.onFreeResource;
const ManagedStruct = runtime.ManagedStruct;
const ManagedSlice = runtime.ManagedSlice;
const Uint8Array = runtime.Uint8Array;
const CsWindow = runtime.CsWindow;
const gen = @import("gen.zig");
const log = stdx.log.scoped(.api);
const _server = @import("server.zig");
const HttpServer = _server.HttpServer;
const adapter = @import("adapter.zig");
const RtTempStruct = adapter.RtTempStruct;
const PromiseSkipJsGen = adapter.PromiseSkipJsGen;
const This = adapter.This;
const ThisResource = adapter.ThisResource;
const ThisHandle = adapter.ThisHandle;
const FuncData = adapter.FuncData;

// TODO: Once https://github.com/ziglang/zig/issues/8259 is resolved, use comptime to set param names.

/// @title Window Management
/// @name window
/// @ns cs.window
/// Provides a cross platform API to create and manage windows.
pub const cs_window = struct {

    /// Creates a new window and returns the handle.
    /// @param width
    /// @param height
    /// @param title
    pub fn create(rt: *RuntimeContext, width: u32, height: u32, title: []const u8) v8.Object {
        if (rt.dev_mode and rt.dev_ctx.dev_window != null) {
            const S = struct {
                var replaced_dev_window_before = false;
            };
            // Take over the dev window.
            const dev_win = rt.dev_ctx.dev_window.?;
            const cur_width = dev_win.window.getWidth();
            const cur_height = dev_win.window.getHeight();
            dev_win.window.setTitle(title);
            if (cur_width != width or cur_height != height) {
                dev_win.resize(width, height);
                if (!S.replaced_dev_window_before) {
                    // Only recenter if this is the first time the user window is taking over the dev window.
                    dev_win.window.center();
                }
            }
            rt.dev_ctx.dev_window = null;
            rt.active_window = dev_win;
            S.replaced_dev_window_before = true;
            return dev_win.js_window.castToObject();
        }

        var win: graphics.Window = undefined;
        if (rt.num_windows > 0) {
            // Create a new window using an existing open gl context.
            win = graphics.Window.initWithSharedContext(rt.alloc, .{
                .width = width,
                .height = height,
                .title = title,
                .resizable = true,
                .high_dpi = true,
                .mode = .Windowed,
            }, rt.active_window.window) catch unreachable;
        } else {
            // Create a new window with a new open gl context.
            win = graphics.Window.init(rt.alloc, .{
                .width = width,
                .height = height,
                .title = title,
                .resizable = true,
                .high_dpi = true,
                .mode = .Windowed,
            }) catch unreachable;
        }
        const res = rt.createCsWindowResource();
        res.ptr.init(rt, win, res.id);

        rt.active_window = res.ptr;

        res.ptr.js_window.setWeakFinalizer(res.external, onFreeResource, v8.WeakCallbackType.kParameter);

        return res.ptr.js_window.castToObject();
    }

    /// An interface for a window handle.
    pub const Window = struct {

        /// Returns the graphics context attached to this window.
        pub fn getGraphics(this: ThisResource(.CsWindow)) *const anyopaque {
            return @ptrCast(*const anyopaque, this.res.js_graphics.inner.handle);
        }

        /// Provide the handler for the window's frame updates.
        /// Provide a null value to disable these events.
        /// This is a good place to do your app's update logic and draw to the screen.
        /// The frequency of frame updates is limited by an FPS counter.
        /// Eventually, this frequency will be configurable.
        /// @param callback
        pub fn onUpdate(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_update_cb, mb_cb);
        }

        /// Provide the handler for receiving mouse down events when this window is active.
        /// Provide a null value to disable these events.
        /// @param callback
        pub fn onMouseDown(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_mouse_down_cb, mb_cb);
        }

        /// Provide the handler for receiving mouse up events when this window is active.
        /// Provide a null value to disable these events.
        /// @param callback
        pub fn onMouseUp(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_mouse_up_cb, mb_cb);
        }

        /// Provide the handler for receiving mouse move events when this window is active.
        /// Provide a null value to disable these events.
        /// @param callback
        pub fn onMouseMove(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_mouse_move_cb, mb_cb);
        }

        /// Provide the handler for receiving key down events when this window is active.
        /// Provide a null value to disable these events.
        /// @param callback
        pub fn onKeyDown(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_key_down_cb, mb_cb);
        }

        /// Provide the handler for receiving key up events when this window is active.
        /// Provide a null value to disable these events.
        /// @param callback
        pub fn onKeyUp(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_key_up_cb, mb_cb);
        }

        /// Provide the handler for the window's resize event.
        /// Provide a null value to disable these events.
        /// A window can be resized by the user or the platform's window manager.
        /// @param callback
        pub fn onResize(rt: *RuntimeContext, this: ThisResource(.CsWindow), mb_cb: ?v8.Function) void {
            v8x.updateOptionalPersistent(v8.Function, rt.isolate, &this.res.on_resize_cb, mb_cb);
        }

        /// Returns how long the last frame took in microseconds. This includes the onUpdate call and the delay to achieve the target FPS.
        /// This is useful for animation or physics for calculating the next position of an object.
        pub fn getLastFrameDuration(this: ThisResource(.CsWindow)) u32 {
            return @intCast(u32, this.res.fps_limiter.getLastFrameDelta());
        }

        /// Returns how long the last frame took to perform onUpdate in microseconds. 
        /// This is useful to measure the performance of your onUpdate logic.
        pub fn getLastUpdateDuration(this: ThisResource(.CsWindow)) u32 {
            // TODO: Provide config for more accurate measurement with glFinish.
            return @intCast(u32, this.res.fps_limiter.getLastUpdateDelta());
        }

        /// Returns the average frames per second.
        pub fn getFps(this: ThisResource(.CsWindow)) u32 {
            return @intCast(u32, this.res.fps_limiter.getFps());
        }

        /// Closes the window and frees the handle.
        pub fn close(rt: *RuntimeContext, this: ThisResource(.CsWindow)) void {
            rt.startDeinitResourceHandle(this.res_id);
        }

        /// Minimizes the window.
        pub fn minimize(this: ThisResource(.CsWindow)) void {
            this.res.window.minimize();
        }

        /// Maximizes the window. The window must be resizable. 
        pub fn maximize(this: ThisResource(.CsWindow)) void {
            this.res.window.maximize();
        }

        /// Restores the window to the size before it was minimized or maximized. 
        pub fn restore(this: ThisResource(.CsWindow)) void {
            this.res.window.restore();
        }

        /// Set to fullscreen mode with a videomode change.
        pub fn setFullscreenMode(this: ThisResource(.CsWindow)) void {
            this.res.window.setMode(.Fullscreen);
        }

        /// Set to pseudo fullscreen mode which takes up the entire screen but does not change the videomode. 
        pub fn setPseudoFullscreenMode(this: ThisResource(.CsWindow)) void {
            this.res.window.setMode(.PseudoFullscreen);
        }

        /// Set to windowed mode.
        pub fn setWindowedMode(this: ThisResource(.CsWindow)) void {
            this.res.window.setMode(.Windowed);
        }

        /// Creates a child window attached to this window. Returns the new child window handle.
        /// @param title
        /// @param width
        /// @param height
        pub fn createChild(rt: *RuntimeContext, this: ThisResource(.CsWindow), title: []const u8, width: u32, height: u32) v8.Object {
            // TODO: Make child windows behave different than creating a new window.
            const new_res = rt.createCsWindowResource();

            const new_win = graphics.Window.initWithSharedContext(rt.alloc, .{
                .width = width,
                .height = height,
                .title = title,
                .resizable = true,
                .high_dpi = true,
                .mode = .Windowed,
            }, this.res.window) catch unreachable;
            new_res.ptr.init(rt, new_win, new_res.id);

            // rt.active_window = new_res.ptr;

            return new_res.ptr.js_window.castToObject();
        }

        /// Sets the window position on the screen.
        /// @param x
        /// @param y
        pub fn position(this: ThisResource(.CsWindow), x: i32, y: i32) void {
            this.res.window.setPosition(x, y);
        }

        /// Center the window on the screen.
        pub fn center(this: ThisResource(.CsWindow)) void {
            this.res.window.center();
        }

        /// Raises the window above other windows and acquires the input focus.
        pub fn focus(this: ThisResource(.CsWindow)) void {
            this.res.window.focus();
        }

        /// Returns the width of the window in logical pixel units.
        pub fn getWidth(this: ThisResource(.CsWindow)) u32 {
            return this.res.window.getWidth();
        }

        /// Returns the height of the window in logical pixel units.
        pub fn getHeight(this: ThisResource(.CsWindow)) u32 {
            return this.res.window.getWidth();
        }

        /// Sets the window's title.
        /// @param title
        pub fn setTitle(this: ThisResource(.CsWindow), title: []const u8) void {
            this.res.window.setTitle(title);
        }

        /// Gets the window's title.
        /// @param title
        pub fn getTitle(rt: *RuntimeContext, this: ThisResource(.CsWindow)) ds.Box([]const u8) {
            const title = this.res.window.getTitle(rt.alloc);
            return ds.Box([]const u8).init(rt.alloc, title);
        }

        /// Resizes the window.
        /// @param width
        /// @param height
        pub fn resize(this: ThisResource(.CsWindow), width: u32, height: u32) void {
            this.res.window.resize(width, height);
        }
    };
};

fn readInternal(alloc: std.mem.Allocator, path: []const u8) Error![]const u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 1e12) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.IsDir => return error.IsDir,
        else => {
            log.debug("unknown error: {}", .{err});
            unreachable;
        }
    };
}

/// @title File System
/// @name files
/// @ns cs.files
/// Provides a cross platform API to create and manage files.
/// Functions with path params can be absolute or relative to the cwd.
pub const cs_files = struct {

    /// Reads a file as raw bytes.
    /// Returns the contents on success or null.
    /// @param path
    pub fn read(rt: *RuntimeContext, path: []const u8) Error!ManagedStruct(Uint8Array) {
        const res = try readInternal(rt.alloc, path);
        return ManagedStruct(Uint8Array).init(rt.alloc, Uint8Array{ .buf = res });
    }

    /// @param path
    pub fn readAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, read, .{ rt, path });
        return runtime.invokeFuncAsync(rt, read, args);
    }

    /// Reads a file as a UTF-8 string.
    /// Returns the contents on success or null.
    /// @param path
    pub fn readText(rt: *RuntimeContext, path: []const u8) Error!ds.Box([]const u8) {
        const res = std.fs.cwd().readFileAlloc(rt.alloc, path, 1e12) catch |err| switch (err) {
            // Whitelist errors to silence.
            error.FileNotFound => return error.FileNotFound,
            error.IsDir => return error.IsDir,
            else => {
                log.debug("unknown error: {}", .{err});
                unreachable;
            }
        };
        return ds.Box([]const u8).init(rt.alloc, res);
    }

    /// @param path
    pub fn readTextAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, readText, .{ rt, path });
        return runtime.invokeFuncAsync(rt, readText, args);
    }

    /// Writes raw bytes to a file. If the file already exists, it's replaced.
    /// Returns true on success or false.
    /// @param path
    /// @param buffer
    pub fn write(path: []const u8, arr: Uint8Array) bool {
        std.fs.cwd().writeFile(path, arr.buf) catch return false;
        return true;
    }

    /// @param path
    /// @param buffer
    pub fn writeAsync(rt: *RuntimeContext, path: []const u8, arr: Uint8Array) v8.Promise {
        const args = dupeArgs(rt.alloc, write, .{ path, arr });
        return runtime.invokeFuncAsync(rt, write, args);
    }

    /// Writes UTF-8 text to a file. If the file already exists, it's replaced.
    /// Returns true on success or false.
    /// @param path
    /// @param str
    pub fn writeText(path: []const u8, str: []const u8) bool {
        std.fs.cwd().writeFile(path, str) catch return false;
        return true;
    }

    /// @param path
    /// @param str
    pub fn writeTextAsync(rt: *RuntimeContext, path: []const u8, str: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, writeText, .{ path, str });
        return runtime.invokeFuncAsync(rt, writeText, args);
    }

    /// Appends raw bytes to a file. File is created if it doesn't exist.
    /// Returns true on success or false.
    /// @param path
    /// @param buffer
    pub fn append(path: []const u8, arr: Uint8Array) bool {
        stdx.fs.appendFile(path, arr.buf) catch return false;
        return true;
    }

    /// @param path
    /// @param buffer
    pub fn appendAsync(rt: *RuntimeContext, path: []const u8, arr: Uint8Array) v8.Promise {
        const args = dupeArgs(rt.alloc, append, .{ path, arr });
        return runtime.invokeFuncAsync(rt, append, args);
    }

    /// Appends UTF-8 text to a file. File is created if it doesn't exist.
    /// Returns true on success or false.
    /// @param path
    /// @param str
    pub fn appendText(path: []const u8, str: []const u8) bool {
        stdx.fs.appendFile(path, str) catch return false;
        return true;
    }

    /// @param path
    /// @param str
    pub fn appendTextAsync(rt: *RuntimeContext, path: []const u8, str: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, appendText, .{ path, str });
        return runtime.invokeFuncAsync(rt, appendText, args);
    }

    /// Copies a file.
    /// @param from
    /// @param to
    pub fn copy(from: []const u8, to: []const u8) bool {
        std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch return false;
        return true;
    }

    /// @param from
    /// @param to
    pub fn copyAsync(rt: *RuntimeContext, from: []const u8, to: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, copy, .{ from, to });
        return runtime.invokeFuncAsync(rt, copy, args);
    }

    /// Moves a file.
    /// @param from
    /// @param to
    pub fn move(from: []const u8, to: []const u8) bool {
        std.fs.cwd().rename(from, to) catch return false;
        return true;
    }

    /// @param from
    /// @param to
    pub fn moveAsync(rt: *RuntimeContext, from: []const u8, to: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, move, .{ from, to });
        return runtime.invokeFuncAsync(rt, move, args);
    }

    /// Returns the absolute path of the current working directory.
    pub fn cwd(rt: *RuntimeContext) ?ds.Box([]const u8) {
        const cwd_ = std.process.getCwdAlloc(rt.alloc) catch return null;
        return ds.Box([]const u8).init(rt.alloc, cwd_);
    }

    /// Returns info about a file, folder, or special object at a given path.
    /// @param path
    pub fn getPathInfo(path: []const u8) Error!PathInfo {
        // TODO: statFile opens the file first so it doesn't detect symlink.
        const stat = std.fs.cwd().statFile(path) catch |err| {
            return switch (err) {
                error.FileNotFound => error.FileNotFound,
                else => {
                    log.debug("unknown error: {}", .{err});
                    unreachable;
                },
            };
        };
        return PathInfo{
            .kind = @intToEnum(FileKind, @enumToInt(stat.kind)),
            .atime = @intCast(F64SafeUint, @divFloor(stat.atime, 1_000_000)),
            .mtime = @intCast(F64SafeUint, @divFloor(stat.mtime, 1_000_000)),
            .ctime = @intCast(F64SafeUint, @divFloor(stat.ctime, 1_000_000)),
        };
    }

    /// @param path
    pub fn getPathInfoAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, getPathInfo, .{ path });
        return runtime.invokeFuncAsync(rt, getPathInfo, args);
    }

    pub const FileKind = enum(u4) {
        blockDevice = @enumToInt(std.fs.File.Kind.BlockDevice),
        characterDevice = @enumToInt(std.fs.File.Kind.CharacterDevice),
        directory = @enumToInt(std.fs.File.Kind.Directory),
        namedPipe = @enumToInt(std.fs.File.Kind.NamedPipe),
        symLink = @enumToInt(std.fs.File.Kind.SymLink),
        file = @enumToInt(std.fs.File.Kind.File),
        unixDomainSocket = @enumToInt(std.fs.File.Kind.UnixDomainSocket),
        whiteout = @enumToInt(std.fs.File.Kind.Whiteout),
        door = @enumToInt(std.fs.File.Kind.Door),
        eventPort = @enumToInt(std.fs.File.Kind.EventPort),
        unknown = @enumToInt(std.fs.File.Kind.Unknown),
    };

    pub const PathInfo = struct {
        kind: FileKind,
        // Last access time in milliseconds since the unix epoch.
        atime: F64SafeUint,
        // Last modified time in milliseconds since the unix epoch.
        mtime: F64SafeUint,
        // Created time in milliseconds since the unix epoch.
        ctime: F64SafeUint,
    };

    /// List the files in a directory. This is not recursive.
    /// @param path
    pub fn listDir(rt: *RuntimeContext, path: []const u8) ?ManagedSlice(FileEntry) {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;
        defer dir.close();

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

    /// @param path
    pub fn listDirAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, listDir, .{ rt, path });
        return runtime.invokeFuncAsync(rt, listDir, args);
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

    /// Ensures that a path exists by creating parent directories as necessary.
    /// @param path
    pub fn ensurePath(rt: *RuntimeContext, path: []const u8) bool {
        std.fs.cwd().makePath(path) catch |err| switch (err) {
            else => {
                v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
                return false;
            },
        };
        return true;
    }

    /// @param path
    pub fn ensurePathAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, ensurePath, .{ rt, path });
        return runtime.invokeFuncAsync(rt, ensurePath, args);
    }

    /// Returns whether something exists at a path.
    /// @param path
    pub fn pathExists(rt: *RuntimeContext, path: []const u8) bool {
        return stdx.fs.pathExists(path) catch |err| {
            v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "{}", .{err});
            return false;
        };
    }

    /// @param path
    pub fn pathExistsAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, pathExists, .{ rt, path });
        return runtime.invokeFuncAsync(rt, pathExists, args);
    }

    /// Removes a file.
    /// @param path
    pub fn remove(path: []const u8) bool {
        std.fs.cwd().deleteFile(path) catch return false;
        return true;
    }

    /// @param path
    pub fn removeAsync(rt: *RuntimeContext, path: []const u8) v8.Promise {
        const args = dupeArgs(rt.alloc, remove, .{ path });
        return runtime.invokeFuncAsync(rt, remove, args);
    }

    /// Removes a directory.
    /// @param path
    /// @param recursive
    pub fn removeDir(path: []const u8, recursive: bool) bool {
        if (recursive) {
            std.fs.cwd().deleteTree(path) catch |err| {
                if (builtin.os.tag == .windows and err == error.FileBusy) {
                    // If files were deleted, the root directory remains and returns FileBusy, so try again.
                    std.fs.cwd().deleteDir(path) catch return false;
                    return true;
                }
                return false;
            };
        } else {
            std.fs.cwd().deleteDir(path) catch return false;
            if (builtin.os.tag == .windows) {
                // Underlying NtCreateFile call returns success when it ignores a recursive directory.
                // For now, check that it doesn't exist.
                const exists = stdx.fs.pathExists(path) catch return false;
                return !exists;
            }
        }
        return true;
    }

    /// @param path
    /// @param recursive
    pub fn removeDirAsync(rt: *RuntimeContext, path: []const u8, recursive: bool) v8.Promise {
        const args = dupeArgs(rt.alloc, removeDir, .{ path, recursive });
        return runtime.invokeFuncAsync(rt, removeDir, args);
    }

    /// Expands relative pathing such as '..' from the cwd and returns an absolute path.
    /// See realPath to resolve symbolic links.
    /// @param path
    pub fn expandPath(rt: *RuntimeContext, path: []const u8) ds.Box([]const u8) {
        const res = std.fs.path.resolve(rt.alloc, &.{path}) catch |err| {
            log.debug("unknown error: {}", .{err});
            unreachable;
        };
        return ds.Box([]const u8).init(rt.alloc, res);
    }

    /// Expands relative pathing from the cwd and resolves symbolic links.
    /// Returns the canonicalized absolute path.
    /// Path provided must point to a filesystem object.
    /// @param path
    pub fn realPath(rt: *RuntimeContext, path: []const u8) Error!ds.Box([]const u8) {
        const res = std.fs.realpathAlloc(rt.alloc, path) catch |err| {
            return switch (err) {
                error.FileNotFound => error.FileNotFound,
                else => {
                    log.debug("unknown error: {}", .{err});
                    unreachable;
                },
            };
        };
        return ds.Box([] const u8).init(rt.alloc, res);
    }

    /// Creates a symbolic link (a soft link) at symPath to an existing or nonexisting file at targetPath.
    /// @param symPath
    /// @param targetPath
    pub fn symLink(sym_path: []const u8, target_path: []const u8) Error!void {
        if (builtin.os.tag == .windows) {
            return error.Unsupported;
        }
        std.os.symlink(target_path, sym_path) catch |err| {
            return switch(err) {
                error.PathAlreadyExists => error.PathExists,
                else => {
                    log.debug("unknown error: {}", .{err});
                    unreachable;
                },
            };
        };
    }
};

/// @title HTTP Client and Server
/// @name http
/// @ns cs.http
/// Provides an API to make HTTP requests and host HTTP servers. HTTPS is supported.
/// There are plans to support WebSockets.
pub const cs_http = struct {

    /// Makes a GET request and returns the response body text if successful.
    /// Returns false if there was a connection error, timeout error (30 secs), or the response code is 5xx.
    /// Advanced: cs.http.request
    /// @param url
    pub fn get(rt: *RuntimeContext, url: []const u8) ?ds.Box([]const u8) {
        const opts = RequestOptions{
            .method = .Get,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequest(rt, url, opts);
    }

    /// @param url
    pub fn getAsync(rt: *RuntimeContext, url: []const u8) v8.Promise {
        const opts = RequestOptions{
            .method = .Get,
            .timeout = 30,
            .keepConnection = false,
        };
        return requestAsyncInternal(rt, url, opts, false);
    }

    /// Makes a POST request and returns the response body text if successful.
    /// Returns false if there was a connection error, timeout error (30 secs), or the response code is 5xx.
    /// Advanced: cs.http.request
    /// @param url
    /// @param body
    pub fn post(rt: *RuntimeContext, url: []const u8, body: []const u8) ?ds.Box([]const u8) {
        const opts = RequestOptions{
            .method = .Post,
            .body = body,
            .timeout = 30,
            .keepConnection = false,
        };
        return simpleRequest(rt, url, opts);
    }

    /// @param url
    /// @param body
    pub fn postAsync(rt: *RuntimeContext, url: []const u8, body: []const u8) v8.Promise {
        const opts = RequestOptions{
            .method = .Post,
            .body = body,
            .timeout = 30,
            .keepConnection = false,
        };
        return requestAsyncInternal(rt, url, opts, false);
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

    /// detailed=false will just return the body text.
    /// detailed=true will return the entire response object.
    fn requestAsyncInternal(rt: *RuntimeContext, url: []const u8, opts: RequestOptions, comptime detailed: bool) v8.Promise {
        const iso = rt.isolate;

        const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.getContext()));
        const promise = resolver.inner.getPromise();
        const promise_id = rt.promises.add(resolver) catch unreachable;

        const S = struct {
            fn onSuccess(ptr: *anyopaque, resp: stdx.http.Response) void {
                const ctx = stdx.mem.ptrCastAlign(*RuntimeValue(PromiseId), ptr);
                const pid = ctx.inner;
                if (detailed) {
                    runtime.resolvePromise(ctx.rt, pid, resp);
                } else {
                    runtime.resolvePromise(ctx.rt, pid, resp.body);
                }
                resp.deinit(ctx.rt.alloc);
            }

            fn onFailure(ctx: RuntimeValue(PromiseId), err: Error) void {
                const _promise_id = ctx.inner;
                const js_err = runtime.createPromiseError(ctx.rt, err);
                runtime.rejectPromise(ctx.rt, _promise_id, js_err);
            }

            fn onCurlFailure(ptr: *anyopaque, curle_err: u32) void {
                const ctx = stdx.mem.ptrCastAlign(*RuntimeValue(PromiseId), ptr).*;
                const cs_err = switch (curle_err) {
                    curl.CURLE_COULDNT_CONNECT => error.ConnectFailed,
                    curl.CURLE_PEER_FAILED_VERIFICATION => error.CertVerify,
                    curl.CURLE_SSL_CACERT_BADFILE => error.CertBadFile,
                    curl.CURLE_COULDNT_RESOLVE_HOST => error.CantResolveHost,
                    else => b: {
                        log.debug("curl unknown error: {}", .{curle_err});
                        break :b error.Unknown;
                    },
                };
                onFailure(ctx, cs_err);
            }
        };

        const ctx = RuntimeValue(PromiseId){
            .rt = rt,
            .inner = promise_id,
        };

        const std_opts = toStdRequestOptions(opts);

        // Catch any immediate errors as well as async errors.
        stdx.http.requestAsync(rt.alloc, url, std_opts, ctx, S.onSuccess, S.onCurlFailure) catch |err| switch (err) {
            else => {
                log.debug("unknown error: {}", .{err});
                S.onFailure(ctx, error.Unknown);
            }
        };

        return promise;
    }

    fn toStdRequestOptions(opts: RequestOptions) stdx.http.RequestOptions {
        var res = stdx.http.RequestOptions{
            .method = std.meta.stringToEnum(stdx.http.RequestMethod, @tagName(opts.method)).?,
            .body = opts.body,
            .keep_connection = opts.keepConnection,
            .timeout = opts.timeout,
            .headers = opts.headers,
            .cert_file = opts.certFile,
        };
        if (opts.contentType) |content_type| {
            res.content_type = std.meta.stringToEnum(stdx.http.ContentType, @tagName(content_type)).?;
        }
        return res;
    }

    /// Returns Response object if request was successful.
    /// Throws exception if there was a connection or protocol error.
    /// @param url
    /// @param options
    pub fn request(rt: *RuntimeContext, url: []const u8, mb_opts: ?RequestOptions) !ManagedStruct(stdx.http.Response) {
        const opts = mb_opts orelse RequestOptions{};
        const std_opts = toStdRequestOptions(opts);
        const resp = try stdx.http.request(rt.alloc, url, std_opts);
        return ManagedStruct(stdx.http.Response){
            .alloc = rt.alloc,
            .val = resp,
        };
    }

    /// @param url
    /// @param options
    pub fn requestAsync(rt: *RuntimeContext, url: []const u8, mb_opts: ?RequestOptions) PromiseSkipJsGen {
        const opts = mb_opts orelse RequestOptions{};
        return .{ .inner = requestAsyncInternal(rt, url, opts, true) };
    }

    pub const RequestMethod = enum {
        pub const IsStringSumType = true;
        Head,
        Get,
        Post,
        Put,
        Delete,
    };

    pub const ContentType = enum {
        pub const IsStringSumType = true;
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

        // For HTTPS, if no cert file is provided, the default from the current operating system is used.
        certFile: ?[]const u8 = null,
    };

    /// The response object holds the data received from making a HTTP request.
    pub const Response = struct {
        status: u32,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
    };

    /// Starts a HTTP server and returns the handle.
    /// @param host
    /// @param port
    pub fn serveHttp(rt: *RuntimeContext, host: []const u8, port: u16) !v8.Object {
        // log.debug("serving http at {s}:{}", .{host, port});

        // TODO: Implement "cosmic serve-http" and "cosmic serve-https" cli utilities.

        const handle = rt.createCsHttpServerResource();
        const server = handle.ptr;
        server.init(rt);
        try server.startHttp(host, port);

        const ctx = rt.getContext();
        const js_handle = rt.http_server_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
        js_handle.setInternalField(0, rt.isolate.initIntegerU32(handle.id));
        return js_handle;
    }

    /// Starts a HTTPS server and returns the handle.
    /// @param host
    /// @param port
    /// @param certPath
    /// @param keyPath
    pub fn serveHttps(rt: *RuntimeContext, host: []const u8, port: u16, cert_path: []const u8, key_path: []const u8) Error!v8.Object {
        const handle = rt.createCsHttpServerResource();
        const server = handle.ptr;
        server.init(rt);
        server.startHttps(host, port, cert_path, key_path) catch |err| switch (err) {
            else => {
                log.debug("unknown error: {}", .{err});
                return error.Unknown;
            }
        };

        const ctx = rt.getContext();
        const js_handle = rt.http_server_class.inner.getFunction(ctx).initInstance(ctx, &.{}).?;
        js_handle.setInternalField(0, rt.isolate.initIntegerU32(handle.id));
        return js_handle;
    }

    /// Provides an interface to the underlying server handle.
    pub const Server = struct {

        /// Sets the handler for receiving requests.
        /// @param callback
        pub fn setHandler(rt: *RuntimeContext, this: ThisResource(.CsHttpServer), handler: v8.Function) void {
            this.res.js_handler = rt.isolate.initPersistent(v8.Function, handler);
        }

        /// Request the server to close. It will gracefully shutdown in the background.
        pub fn requestClose(rt: *RuntimeContext, this: ThisResource(.CsHttpServer)) void {
            rt.startDeinitResourceHandle(this.res_id);
        }

        /// Requests the server to close. The promise will resolve when it's done.
        pub fn closeAsync(rt: *RuntimeContext, this: ThisResource(.CsHttpServer)) v8.Promise {
            const iso = rt.isolate;
            const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(rt.getContext()));
            const promise = resolver.inner.getPromise();
            const promise_id = rt.promises.add(resolver) catch unreachable;

            const S = struct {
                const Context = struct {
                    rt: *RuntimeContext,
                    promise_id: PromiseId,
                };
                fn onDeinit(ptr: *anyopaque, _: ResourceId) void {
                    const ctx = stdx.mem.ptrCastAlign(*Context, ptr);
                    runtime.resolvePromise(ctx.rt, ctx.promise_id, ctx.rt.js_true);
                    ctx.rt.alloc.destroy(ctx);
                }
            };

            const ctx = rt.alloc.create(S.Context) catch unreachable;
            ctx.* = .{
                .rt = rt,
                .promise_id = promise_id,
            };
            const cb = stdx.Callback(*anyopaque, ResourceId).init(ctx, S.onDeinit);

            rt.resources.getPtrAssumeExists(this.res_id).on_deinit_cb = cb;
            rt.startDeinitResourceHandle(this.res_id);
            return promise;
        }

        pub fn getBindAddress(rt: *RuntimeContext, this: ThisResource(.CsHttpServer)) RtTempStruct(Address) {
            const addr = this.res.allocBindAddress(rt.alloc);
            return RtTempStruct(Address).init(.{
                .host = addr.host,
                .port = addr.port,
            });
        }
    };

    pub const Address = struct {
        host: []const u8,
        port: u32,

        /// @internal
        pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
            alloc.free(self.host);
        }
    };

    /// Provides an interface to the current response writer.
    pub const ResponseWriter = struct {

        /// @param status
        pub fn setStatus(status_code: u32) void {
            _server.ResponseWriter.setStatus(status_code);
        }

        /// @param key
        /// @param value
        pub fn setHeader(key: []const u8, value: []const u8) void {
            _server.ResponseWriter.setHeader(key, value);
        }

        /// Sends UTF-8 text to the response.
        /// @param text
        pub fn send(text: []const u8) void {
            _server.ResponseWriter.send(text);
        }

        /// Sends raw bytes to the response.
        /// @param buffer
        pub fn sendBytes(arr: runtime.Uint8Array) void {
            _server.ResponseWriter.sendBytes(arr);
        }
    };

    /// Holds data about the request when hosting an HTTP server.
    pub const Request = struct {
        method: RequestMethod,
        path: []const u8,
        data: Uint8Array,
    };
};

/// @title Core
/// @name core
/// @ns cs.core
/// Contains common utilities. All functions here are also available in the global scope. You can call them directly without the cs.core prefix.
pub const cs_core = struct {

    /// Whether print should also output to stdout in devmode.
    const DevModeToStdout = false;

    /// Returns an array of arguments used to start the process in the command line.
    pub fn getCliArgs(rt: *RuntimeContext) v8.Array {
        const args = std.process.argsAlloc(rt.alloc) catch unreachable;
        defer std.process.argsFree(rt.alloc, args);
        const args_slice: []const []const u8 = args;
        return rt.getJsValue(args_slice).castTo(v8.Array);
    }

    /// Prints any number of variables as strings separated by " ".
    /// @param args
    pub fn print(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        printInternal(info, false, false);
    }

    pub fn print_DEV(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        printInternal(info, true, false);
    }

    inline fn printInternal(info: v8.FunctionCallbackInfo, comptime DevMode: bool, comptime Dump: bool) void {
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
        printInternal2(rt, info, DevMode, Dump);
    }

    fn printInternal2(rt: *RuntimeContext, info: v8.FunctionCallbackInfo, comptime DevMode: bool, comptime Dump: bool) void {
        const len = info.length();
        const iso = rt.isolate;
        const ctx = rt.getContext();

        var hscope: v8.HandleScope = undefined;
        hscope.init(iso);
        defer hscope.deinit();

        if (len > 0) {
            const str = if (Dump) v8x.allocValueDump(rt.alloc, iso, ctx, info.getArg(0))
                else v8x.allocValueAsUtf8(rt.alloc, iso, ctx, info.getArg(0));
            defer rt.alloc.free(str);
            if (!DevMode or DevModeToStdout) {
                rt.env.printFmt("{s}", .{str});
            }
            if (DevMode) {
                rt.dev_ctx.printFmt("{s}", .{str});
            }
        }

        var i: u32 = 1;
        while (i < len) : (i += 1) {
            const str = if (Dump) v8x.allocValueDump(rt.alloc, iso, ctx, info.getArg(i))
                else v8x.allocValueAsUtf8(rt.alloc, iso, ctx, info.getArg(i));
            defer rt.alloc.free(str);
            if (!DevMode or DevModeToStdout) {
                rt.env.printFmt(" {s}", .{str});
            }
            if (DevMode) {
                rt.dev_ctx.printFmt(" {s}", .{str});
            }
        }
    }

    /// Prints any number of variables as strings separated by " ". Wraps to the next line.
    /// @param args
    pub fn puts(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
        printInternal2(rt, info, false, false);
        rt.env.printFmt("\n", .{});
    }

    pub fn puts_DEV(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
        printInternal2(rt, info, true, false);
        if (DevModeToStdout) {
            rt.env.printFmt("\n", .{});
        }
        rt.dev_ctx.print("\n");
    }

    /// Prints a descriptive string of the js value(s) separated by " ". Wraps to the next line.
    /// @param args
    pub fn dump(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
        printInternal2(rt, info, false, true);
        rt.env.printFmt("\n", .{});
    }

    pub fn dump_DEV(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
        printInternal2(rt, info, true, true);
        if (DevModeToStdout) {
            rt.env.printFmt("\n", .{});
        }
        rt.dev_ctx.print("\n");
    }

    /// Converts a buffer to a UTF-8 string.
    /// @param buffer
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

    /// Invoke a callback after a timeout in milliseconds.
    /// @param timeout
    /// @param callback
    /// @param callbackArg
    pub fn setTimeout(rt: *RuntimeContext, timeout: u32, cb: v8.Function, cb_arg: ?v8.Value) u32 {
        const p_cb = rt.isolate.initPersistent(v8.Function, cb);
        if (cb_arg) |cb_arg_| {
            const p_cb_arg = rt.isolate.initPersistent(v8.Value, cb_arg_);
            return rt.timer.setTimeout(timeout, p_cb, p_cb_arg) catch unreachable;
        } else {
            return rt.timer.setTimeout(timeout, p_cb, null) catch unreachable;
        }
    }

    /// Returns the absolute path of the main script.
    pub fn getMainScriptPath(rt: *RuntimeContext) []const u8 {
        return rt.main_script_path;
    }

    /// Returns the absolute path of the main script's directory. Does not include an ending slash.
    /// This is useful if you have additional source or assets that depends on the location of your main script.
    pub fn getMainScriptDir(rt: *RuntimeContext) []const u8 {
        return std.fs.path.dirname(rt.main_script_path) orelse unreachable;
    }

    /// Given an app name, returns the platform's app directory to read/write files to.
    /// This does not ensure that the directory exists. See ensurePath.
    pub fn getAppDir(rt: *RuntimeContext, app_name: []const u8) ?ds.Box([]const u8) {
        const dir = std.fs.getAppDataDir(rt.alloc, app_name) catch return null;
        return ds.Box([]const u8).init(rt.alloc, dir);
    }

    /// Prints the current stack trace and exits the program with an error code.
    /// This is useful to short circuit your program.
    /// @param msg
    pub fn panic(rt: *RuntimeContext, msg: ?[]const u8) void {
        const trace = v8.StackTrace.getCurrentStackTrace(rt.isolate, 10);

        var buf = std.ArrayList(u8).init(rt.alloc);
        const writer = buf.writer();

        // Exception message.
        writer.writeAll("\n") catch unreachable;
        if (msg) |msg_| {
            writer.print("Panic: {s}", .{msg_}) catch unreachable;
        } else {
            writer.writeAll("Panic") catch unreachable;
        }
        writer.writeAll("\n") catch unreachable;
        
        v8x.appendStackTraceString(&buf, rt.isolate, trace);
        rt.env.errorFmt("{s}", .{buf.items});
        rt.env.exit(1);
    }

    /// Terminate the program with a code. Use code=0 for a successful exit and a positive value for an error exit.
    /// @param code
    pub fn exit(rt: *RuntimeContext, code: u8) void {
        rt.env.exit(code);
    }

    /// Returns the last error code. API calls that return null will set their error code to be queried by errCode() and errString().
    pub fn errCode(rt: *RuntimeContext) u32 {
        return @enumToInt(std.meta.stringToEnum(CsError, @errorName(rt.last_err)).?);
    }

    /// Returns an error message for an error code.
    pub fn errString(err: CsError) []const u8 {
        return switch (err) {
            .NoError => "No error.",
            .NotAnError => "Not an error.",
            else => @tagName(err),
        };
    }

    /// Clears the last error.
    pub fn clearError(rt: *RuntimeContext) void {
        rt.last_err = error.NoError;
    }

    /// Returns the host operating system.
    pub fn getOs() Os {
        switch (builtin.os.tag) {
            .linux => return .linux,
            .macos => return .macos,
            .windows => return .windows,
            else => unreachable,
        }
    }

    /// Returns the host operating system and version number as a string.
    pub fn getOsVersion(rt: *RuntimeContext) ds.Box([]const u8) {
        const info = std.zig.system.NativeTargetInfo.detect(rt.alloc, std.zig.CrossTarget{}) catch unreachable;
        const range = info.target.os.getVersionRange();
        var str: []const u8 = undefined;
        switch (range) {
            .none => {},
            .semver => {
                str = std.fmt.allocPrint(rt.alloc, "{s} {}", .{@tagName(info.target.os.tag), range.semver.min}) catch unreachable;
            },
            .linux => {
                str = std.fmt.allocPrint(rt.alloc, "{s} {}", .{@tagName(info.target.os.tag), range.linux.range.min}) catch unreachable;
            },
            .windows => {
                str = std.fmt.allocPrint(rt.alloc, "{s} {}", .{@tagName(info.target.os.tag), range.windows}) catch unreachable;
            },
        }
        return ds.Box([]const u8).init(rt.alloc, str);
    }

    /// Returns the host cpu arch and model as a string.
    pub fn getCpu(rt: *RuntimeContext) ds.Box([]const u8) {
        const info = std.zig.system.NativeTargetInfo.detect(rt.alloc, std.zig.CrossTarget{}) catch unreachable;
        const str = std.fmt.allocPrint(rt.alloc, "{} {s}", .{info.target.cpu.arch, info.target.cpu.model.name}) catch unreachable;
        return ds.Box([]const u8).init(rt.alloc, str);
    }

    /// Returns the resource usage of the current process.
    pub fn getResourceUsage() ResourceUsage {
        const RUSAGE_SELF: i32 = 0;
        if (builtin.os.tag == .linux) {
            var usage: std.os.linux.rusage = undefined;
            if (std.os.linux.getrusage(std.os.linux.rusage.SELF, &usage) != 0) {
                unreachable;
            }
            return .{
                .user_time_secs = @intCast(u32, usage.utime.tv_sec),
                .user_time_usecs = @intCast(u32, usage.utime.tv_usec),
                .sys_time_secs = @intCast(u32, usage.stime.tv_sec),
                .sys_time_usecs = @intCast(u32, usage.stime.tv_usec),
                .memory = @intCast(F64SafeUint, usage.maxrss),
            };
        } else if (builtin.os.tag == .windows) {
            var creation_time: std.os.windows.FILETIME = undefined;
            var exit_time: std.os.windows.FILETIME = undefined;
            var kernel_time: std.os.windows.FILETIME = undefined;
            var user_time: std.os.windows.FILETIME = undefined;
            var pmc: std.os.windows.PROCESS_MEMORY_COUNTERS = undefined;
            const process = std.os.windows.kernel32.GetCurrentProcess();
            if (!GetProcessTimes(process, &creation_time, &exit_time, &kernel_time, &user_time)) {
                log.debug("Failed to get process times.", .{});
                unreachable;
            }
            if (std.os.windows.kernel32.K32GetProcessMemoryInfo(process, &pmc, @sizeOf(std.os.windows.PROCESS_MEMORY_COUNTERS)) == 0) {
                log.debug("Failed to get process memory info: {}", .{ std.os.windows.kernel32.GetLastError() });
                unreachable;
            }
            // In 100ns
            const user_time_u64 = twoToU64(user_time.dwLowDateTime, user_time.dwHighDateTime);
            const kernel_time_u64 = twoToU64(kernel_time.dwLowDateTime, kernel_time.dwHighDateTime);
            return .{
                .user_time_secs = @intCast(u32, user_time_u64 / 10000000),
                .user_time_usecs = @intCast(u32, (user_time_u64 % 10000000) / 10),
                .sys_time_secs = @intCast(u32, kernel_time_u64 / 10000000),
                .sys_time_usecs = @intCast(u32, (kernel_time_u64 % 10000000) / 10),
                .memory = @intCast(F64SafeUint, pmc.PeakWorkingSetSize / 1024),
            };
        } else {
            const usage = std.os.getrusage(RUSAGE_SELF);
            return .{
                .user_time_secs = @intCast(u32, usage.utime.tv_sec),
                .user_time_usecs = @intCast(u32, usage.utime.tv_usec),
                .sys_time_secs = @intCast(u32, usage.stime.tv_sec),
                .sys_time_usecs = @intCast(u32, usage.stime.tv_usec),
                .memory = @intCast(F64SafeUint, usage.maxrss),
            };
        }
    }

    /// Invokes the JS engine garbage collector.
    pub fn gc(rt: *RuntimeContext) void {
        rt.isolate.lowMemoryNotification();
    }

    pub const ResourceUsage = struct {
        // User cpu time seconds.
        user_time_secs: u32,
        // User cpu time microseconds.
        user_time_usecs: u32,
        // System cpu time seconds.
        sys_time_secs: u32,
        // System cpu time microseconds.
        sys_time_usecs: u32,
        // Total memory allocated.
        memory: F64SafeUint,
    };

    pub const Os = enum {
        linux,
        macos,
        windows,
        web,
    };

    pub const CsError = enum {
        pub const Default = .NotAnError;
        NoError,
        FileNotFound,
        PathExists,
        IsDir,
        ConnectFailed,
        CertVerify,
        CertBadFile,
        CantResolveHost,
        InvalidFormat,
        Unsupported,
        Unknown,
        NotAnError,
    };

    test "every CsError maps to core.CsError" {
        inline for (@typeInfo(Error).ErrorSet.?) |err| {
            _ = std.meta.stringToEnum(cs_core.CsError, err.name) orelse std.debug.panic("Missing {s}", .{err.name});
        }
    }
};

fn twoToU64(lower: u32, higher: u32) u64 {
    if (builtin.cpu.arch.endian() == .Little) {
        var val: [2]u32 = .{lower, higher};
        return @bitCast(u64, val);
    } else {
        var val: [2]u32 = .{higher, lower};
        return @bitCast(u64, val);
    }
}

test "twoToU64" {
    var num: u64 = std.math.maxInt(u64) - 1;
    if (builtin.cpu.arch.endian() == .Little) {
        const lower = @ptrCast([*]u32, &num)[0];
        try t.eq(lower, std.math.maxInt(u32)-1);
        const higher = @ptrCast([*]u32, &num)[1];
        try t.eq(higher, std.math.maxInt(u32));
        try t.eq(twoToU64(lower, higher), num);
    } else {
        const lower = @ptrCast([*]u32, &num)[1];
        try t.eq(lower, std.math.maxInt(u32));
        const higher = @ptrCast([*]u32, &num)[0];
        try t.eq(higher, std.math.maxInt(u32)-1);
        try t.eq(twoToU64(lower, higher), num);
    }
}

pub extern "kernel32" fn GetProcessTimes(
    process: std.os.windows.HANDLE,
    creation_time: *std.os.windows.FILETIME,
    exit_time: *std.os.windows.FILETIME,
    kernel_time: *std.os.windows.FILETIME,
    user_time: *std.os.windows.FILETIME,
) bool;

var audio_engine: AudioEngine = undefined;
var audio_engine_inited = false;

fn getAudioEngine() *AudioEngine {
    if (!audio_engine_inited) {
        audio_engine.init();
        audio_engine_inited = true;
    }
    return &audio_engine;
}

test "getAudioEngine inits once" {
    const m = Mock.create();
    defer m.destroy();
    m.add(.ma_engine_init);

    const eng1 = getAudioEngine();
    try t.eq(m.getNumCalls(.ma_engine_init), 1);
    const eng2 = getAudioEngine();
    try t.eq(m.getNumCalls(.ma_engine_init), 1);
    try t.eq(eng1, eng2);
}

/// @title Audio Playback and Capture
/// @name audio
/// @ns cs.audio
/// This module provides a cross platform API to decode sound files, capture audio, and play audio.
/// There is support for 3D Spatialization. You can adjust the listener's or sound's position, direction, and velocity.
/// The positions are absolute values in the 3D space.
pub const cs_audio = struct {

    fn loadInternal(rt: *RuntimeContext, data: Uint8Array, encoder: StdSound.Encoding) Error!v8.Object {
        const engine = getAudioEngine();
        const sound = engine.createSound(rt.alloc, encoder, data.buf) catch |err| switch (err) {
            error.InvalidFormat => return error.InvalidFormat,
            else => {
                log.debug("unexpected: {}", .{err});
                unreachable;
            },
        };
        return runtime.createWeakHandle(rt, .Sound, sound);
    }

    /// Decodes .wav data into a Sound handle.
    /// @param data
    pub fn loadWav(rt: *RuntimeContext, data: Uint8Array) Error!v8.Object {
        return try loadInternal(rt, data, .Wav);
    }

    /// Decodes a .wav file into a Sound handle. File path can be absolute or relative to the cwd.
    /// @param path
    pub fn loadWavFile(rt: *RuntimeContext, path: []const u8) Error!v8.Object {
        const data = try readInternal(rt.alloc, path);
        defer rt.alloc.free(data);
        return loadWav(rt, Uint8Array{ .buf = data });
    }

    /// Decodes .mp3 data into a Sound handle.
    /// @param data
    pub fn loadMp3(rt: *RuntimeContext, data: Uint8Array) Error!v8.Object {
        return try loadInternal(rt, data, .Mp3);
    }

    /// Decodes a .mp3 file into a Sound handle. File path can be absolute or relative to the cwd.
    /// @param path
    pub fn loadMp3File(rt: *RuntimeContext, path: []const u8) Error!v8.Object {
        const data = try readInternal(rt.alloc, path);
        defer rt.alloc.free(data);
        return loadMp3(rt, Uint8Array{ .buf = data });
    }

    /// Decodes .flac data into a Sound handle.
    /// @param data
    pub fn loadFlac(rt: *RuntimeContext, data: Uint8Array) Error!v8.Object {
        return try loadInternal(rt, data, .Flac);
    }

    /// Decodes a .flac file into a Sound handle. File path can be absolute or relative to the cwd.
    /// @param path
    pub fn loadFlacFile(rt: *RuntimeContext, path: []const u8) Error!v8.Object {
        const data = try readInternal(rt.alloc, path);
        defer rt.alloc.free(data);
        return loadFlac(rt, Uint8Array{ .buf = data });
    }

    /// Decodes .ogg data into a Sound handle.
    /// @param data
    pub fn loadOgg(rt: *RuntimeContext, data: Uint8Array) Error!v8.Object {
        return try loadInternal(rt, data, .Ogg);
    }

    /// Decodes a .ogg file into a Sound handle. File path can be absolute or relative to the cwd.
    /// @param path
    pub fn loadOggFile(rt: *RuntimeContext, path: []const u8) Error!v8.Object {
        const data = try readInternal(rt.alloc, path);
        defer rt.alloc.free(data);
        return loadOgg(rt, Uint8Array{ .buf = data });
    }

    /// Attempt to decode wav, mp3, flac, or ogg data into a Sound handle.
    /// @param data
    pub fn load(rt: *RuntimeContext, data: Uint8Array) Error!v8.Object {
        return try loadInternal(rt, data, .Unknown);
    }

    /// Attempt to decode wav, mp3, flac, or ogg file into a Sound handle.
    /// File path can be absolute or relative to the cwd.
    /// @param path
    pub fn loadFile(rt: *RuntimeContext, path: []const u8) Error!v8.Object {
        const data = try readInternal(rt.alloc, path);
        defer rt.alloc.free(data);
        return load(rt, Uint8Array{ .buf = data });
    }

    /// Sets the listener's position in 3D space.
    pub fn setListenerPos(x: f32, y: f32, z: f32) void {
        const engine = getAudioEngine();
        engine.setListenerPosition(0, .{ .x = x, .y = y, .z = z });
    }

    /// Returns the listener's position in 3D space.
    pub fn getListenerPos() Vec3 {
        const engine = getAudioEngine();
        return engine.getListenerPosition(0);
    }

    /// Sets the listener's forward direction in 3D space. See also setListenerUpDir.
    /// @param x
    /// @param y
    /// @param z
    pub fn setListenerDir(x: f32, y: f32, z: f32) void {
        const engine = getAudioEngine();
        engine.setListenerDirection(0, .{ .x = x, .y = y, .z = z });
    }

    /// Returns the listener's forward direction in 3D space.
    pub fn getListenerDir() Vec3 {
        const engine = getAudioEngine();
        return engine.getListenerDirection(0);
    }

    /// Sets the listener's up direction in 3D space.
    /// @param x
    /// @param y
    /// @param z
    pub fn setListenerUpDir(x: f32, y: f32, z: f32) void {
        const engine = getAudioEngine();
        engine.setListenerWorldUp(0, .{ .x = x, .y = y, .z = z });
    }

    /// Returns the listener's up direction in 3D space.
    pub fn getListenerUpDir() Vec3 {
        const engine = getAudioEngine();
        return engine.getListenerWorldUp(0);
    }

    /// Sets the listener's velocity in 3D space. This is for the doppler effect.
    /// @param x
    /// @param y
    /// @param z
    pub fn setListenerVel(x: f32, y: f32, z: f32) void {
        const engine = getAudioEngine();
        engine.setListenerVelocity(0, .{ .x = x, .y = y, .z = z });
    }

    /// Returns the listener's velocity in 3D space.
    pub fn getListenerVel() Vec3 {
        const engine = getAudioEngine();
        return engine.getListenerVelocity(0);
    }

    pub const Sound = struct {

        /// Plays the sound. This won't return until the sound is done playing.
        pub fn play(self: ThisHandle(.Sound)) void {
            self.ptr.play();
        }

        /// Starts playing the sound in the background. Returns immediately.
        /// Playing the sound while it's already playing will rewind to the start and begin playback.
        pub fn playBg(self: ThisHandle(.Sound)) void {
            self.ptr.playBg();
        }

        /// Returns whether the sound is playing or looping in the background.
        pub fn isPlayingBg(self: ThisHandle(.Sound)) bool {
            return self.ptr.isPlayingBg();
        }

        /// Starts looping the sound in the background.
        pub fn loopBg(self: ThisHandle(.Sound)) void {
            self.ptr.loopBg();
        }

        /// Returns whether the sound is looping in the background.
        pub fn isLoopingBg(self: ThisHandle(.Sound)) bool {
            return self.ptr.isLoopingBg();
        }

        /// Pauses the playback. 
        pub fn pauseBg(self: ThisHandle(.Sound)) void {
            self.ptr.pauseBg();
        }

        /// Resumes the playback from the current cursor position.
        /// If the cursor is at the end, it will rewind to the start and begin playback.
        pub fn resumeBg(self: ThisHandle(.Sound)) void {
            self.ptr.resumeBg();
        }

        /// Stops the playback and rewinds to the start.
        pub fn stopBg(self: ThisHandle(.Sound)) void {
            self.ptr.stopBg();
        }

        /// Sets the volume in a positive linear scale. Volume at 0 is muted. 1 is the default value.
        /// @param volume
        pub fn setVolume(self: ThisHandle(.Sound), volume: f32) void {
            self.ptr.setVolume(volume);
        }

        /// Returns the volume in a positive linear scale.
        pub fn getVolume(self: ThisHandle(.Sound)) f32 {
            return self.ptr.getVolume();
        }

        /// Sets the volume with gain in decibels.
        /// @param gain
        pub fn setGain(self: ThisHandle(.Sound), gain: f32) void {
            self.ptr.setGain(gain);
        }

        /// Gets the gain in decibels.
        pub fn getGain(self: ThisHandle(.Sound)) f32 {
            return self.ptr.getGain();
        }

        /// Sets the pitch. A higher value results in a higher pitch and must be greater than 0. Default value is 1.
        /// @param pitch
        pub fn setPitch(self: ThisHandle(.Sound), pitch: f32) void {
            self.ptr.setPitch(pitch);
        }

        /// Returns the current pitch.
        pub fn getPitch(self: ThisHandle(.Sound)) f32 {
            return self.ptr.getPitch();
        }

        /// Sets the stereo pan. Default value is 0.
        /// Set to -1 to shift the sound to the left and +1 to shift the sound to the right.
        /// @param pan
        pub fn setPan(self: ThisHandle(.Sound), pan: f32) void {
            self.ptr.setPan(pan);
        }

        /// Returns the current stereo pan.
        pub fn getPan(self: ThisHandle(.Sound)) f32 {
            return self.ptr.getPan();
        }

        /// Returns the length of the sound in pcm frames. Unsupported for ogg.
        pub fn getLengthInPcmFrames(self: ThisHandle(.Sound)) Error!u64 {
            return self.ptr.getLengthInPcmFrames() catch return error.Unsupported;
        }

        /// Returns the length of the sound in milliseconds. Unsupported for ogg.
        pub fn getLength(self: ThisHandle(.Sound)) Error!u64 {
            return self.ptr.getLength() catch return error.Unsupported;
        }

        /// Returns the current playback position in pcm frames. Unsupported for ogg.
        pub fn getCursorPcmFrame(self: ThisHandle(.Sound)) u64 {
            return self.ptr.getCursorPcmFrame();
        }

        /// Seeks to playback position in pcm frames.
        /// @param frameIndex
        pub fn seekToPcmFrame(self: ThisHandle(.Sound), frame_index: u64) void {
            return self.ptr.seekToPcmFrame(frame_index);
        }

        /// Sets the sound's position in 3D space.
        /// @param x
        /// @param y
        /// @param z
        pub fn setPosition(self: ThisHandle(.Sound), x: f32, y: f32, z: f32) void {
            self.ptr.setPosition(x, y, z);
        }

        /// Returns the sound's position in 3D space.
        pub fn getPosition(self: ThisHandle(.Sound)) Vec3 {
            return self.ptr.getPosition();
        }

        /// Sets the sound's direction in 3D space.
        /// @param x
        /// @param y
        /// @param z
        pub fn setDirection(self: ThisHandle(.Sound), x: f32, y: f32, z: f32) void {
            self.ptr.setDirection(x, y, z);
        }

        /// Returns the sound's direction in 3D space.
        pub fn getDirection(self: ThisHandle(.Sound)) Vec3 {
            return self.ptr.getDirection();
        }

        /// Sets the sound's velocity in 3D space. This is for the doppler effect.
        /// @param x
        /// @param y
        /// @param z
        pub fn setVelocity(self: ThisHandle(.Sound), x: f32, y: f32, z: f32) void {
            self.ptr.setVelocity(x, y, z);
        }

        /// Returns the sound's velocity in 3D space.
        pub fn getVelocity(self: ThisHandle(.Sound)) Vec3 {
            return self.ptr.getVelocity();
        }
    };
};

/// @title User Input
/// @name input
/// @ns cs.input
/// This module provides access to input devices connected to your computer like the keyboard and mouse.
/// You'll need to create a <a href="window.html#create">Window</a> before you can register for events.
pub const cs_input = struct {

    pub const MouseDownEvent = struct {
        button: MouseButton,
        x: i16,
        y: i16,
        clicks: u8,
    };

    pub const MouseUpEvent = struct {
        button: MouseButton,
        x: i16,
        y: i16,
        clicks: u8,
    };

    pub const MouseButton = enum(u3) {
        left = @enumToInt(input.MouseButton.Left),
        middle = @enumToInt(input.MouseButton.Middle),
        right = @enumToInt(input.MouseButton.Right),
        x1 = @enumToInt(input.MouseButton.X1),
        x2 = @enumToInt(input.MouseButton.X2),
    };

    pub const MouseMoveEvent = struct {
        x: i16,
        y: i16,
    };

    pub const ResizeEvent = struct {
        width: u32,
        height: u32,
    };

    pub const KeyDownEvent = struct {
        key: Key,
        keyChar: []const u8,
        isRepeat: bool,
        shiftDown: bool,
        ctrlDown: bool,
        altDown: bool,
        metaDown: bool,
    };

    pub const KeyUpEvent = struct {
        key: Key,
        keyChar: []const u8,
        shiftDown: bool,
        ctrlDown: bool,
        altDown: bool,
        metaDown: bool,
    };

    pub const Key = enum(u8) {
        unknown = eint(KeyCode.Unknown),
        backspace = eint(KeyCode.Backspace),
        tab = eint(KeyCode.Tab),
        enter = eint(KeyCode.Enter),
        shift = eint(KeyCode.Shift),
        control = eint(KeyCode.Control),
        alt = eint(KeyCode.Alt),
        pause = eint(KeyCode.Pause),
        capsLock = eint(KeyCode.CapsLock),
        escape = eint(KeyCode.Escape),
        space = eint(KeyCode.Space),
        pageUp = eint(KeyCode.PageUp),
        pageDown = eint(KeyCode.PageDown),
        end = eint(KeyCode.End),
        home = eint(KeyCode.Home),
        arrowUp = eint(KeyCode.ArrowUp),
        arrowLeft = eint(KeyCode.ArrowLeft),
        arrowRight = eint(KeyCode.ArrowRight),
        arrowDown = eint(KeyCode.ArrowDown),
        printScreen = eint(KeyCode.PrintScreen),
        insert = eint(KeyCode.Insert),
        delete = eint(KeyCode.Delete),

        digit0 = eint(KeyCode.Digit0),
        digit1 = eint(KeyCode.Digit1),
        digit2 = eint(KeyCode.Digit2),
        digit3 = eint(KeyCode.Digit3),
        digit4 = eint(KeyCode.Digit4),
        digit5 = eint(KeyCode.Digit5),
        digit6 = eint(KeyCode.Digit6),
        digit7 = eint(KeyCode.Digit7),
        digit8 = eint(KeyCode.Digit8),
        digit9 = eint(KeyCode.Digit9),

        a = eint(KeyCode.A),
        b = eint(KeyCode.B),
        c = eint(KeyCode.C),
        d = eint(KeyCode.D),
        e = eint(KeyCode.E),
        f = eint(KeyCode.F),
        g = eint(KeyCode.G),
        h = eint(KeyCode.H),
        i = eint(KeyCode.I),
        j = eint(KeyCode.J),
        k = eint(KeyCode.K),
        l = eint(KeyCode.L),
        m = eint(KeyCode.M),
        n = eint(KeyCode.N),
        o = eint(KeyCode.O),
        p = eint(KeyCode.P),
        q = eint(KeyCode.Q),
        r = eint(KeyCode.R),
        s = eint(KeyCode.S),
        t = eint(KeyCode.T),
        u = eint(KeyCode.U),
        v = eint(KeyCode.V),
        w = eint(KeyCode.W),
        x = eint(KeyCode.X),
        y = eint(KeyCode.Y),
        z = eint(KeyCode.Z),

        contextMenu = eint(KeyCode.ContextMenu),

        f1 = eint(KeyCode.F1),
        f2 = eint(KeyCode.F2),
        f3 = eint(KeyCode.F3),
        f4 = eint(KeyCode.F4),
        f5 = eint(KeyCode.F5),
        f6 = eint(KeyCode.F6),
        f7 = eint(KeyCode.F7),
        f8 = eint(KeyCode.F8),
        f9 = eint(KeyCode.F9),
        f10 = eint(KeyCode.F10),
        f11 = eint(KeyCode.F11),
        f12 = eint(KeyCode.F12),
        f13 = eint(KeyCode.F13),
        f14 = eint(KeyCode.F14),
        f15 = eint(KeyCode.F15),
        f16 = eint(KeyCode.F16),
        f17 = eint(KeyCode.F17),
        f18 = eint(KeyCode.F18),
        f19 = eint(KeyCode.F19),
        f20 = eint(KeyCode.F20),
        f21 = eint(KeyCode.F21),
        f22 = eint(KeyCode.F22),
        f23 = eint(KeyCode.F23),
        f24 = eint(KeyCode.F24),

        scrollLock = eint(KeyCode.ScrollLock),
        semicolon = eint(KeyCode.Semicolon),
        equal = eint(KeyCode.Equal),
        comma = eint(KeyCode.Comma),
        minus = eint(KeyCode.Minus),
        period = eint(KeyCode.Period),
        slash = eint(KeyCode.Slash),
        backquote = eint(KeyCode.Backquote),
        bracketLeft = eint(KeyCode.BracketLeft),
        backslash = eint(KeyCode.Backslash),
        bracketRight = eint(KeyCode.BracketRight),
        quote = eint(KeyCode.Quote),
    };
};

fn eint(e: anytype) @typeInfo(@TypeOf(e)).Enum.tag_type {
    return @enumToInt(e);
}

pub fn fromStdKeyDownEvent(e: input.KeyDownEvent) cs_input.KeyDownEvent {
    return .{
        .key = @intToEnum(cs_input.Key, @enumToInt(e.code)),
        .keyChar = Ascii[e.getKeyChar()..e.getKeyChar()+1],
        .isRepeat = e.is_repeat,
        .shiftDown = e.isShiftPressed(),
        .ctrlDown = e.isControlPressed(),
        .altDown = e.isAltPressed(),
        .metaDown = e.isMetaPressed(),
    };
}

pub fn fromStdKeyUpEvent(e: input.KeyUpEvent) cs_input.KeyUpEvent {
    return .{
        .key = @intToEnum(cs_input.Key, @enumToInt(e.code)),
        .keyChar = Ascii[e.getKeyChar()..e.getKeyChar()+1],
        .shiftDown = e.isShiftPressed(),
        .ctrlDown = e.isControlPressed(),
        .altDown = e.isAltPressed(),
        .metaDown = e.isMetaPressed(),
    };
}

test "every input.KeyCode maps to cs_input.Key" {
    for (std.enums.values(KeyCode)) |code| {
        _ = std.meta.intToEnum(cs_input.Key, @enumToInt(code)) catch |err| {
            std.debug.panic("Missing {}", .{code});
            return err;
        };
    }
    // TODO: Make sure the mapping is correct.
}

const Ascii: [256]u8 = b: {
    var res: [256]u8 = undefined;
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        res[i] = i;
    }
    break :b res;
};

pub fn fromStdMouseDownEvent(e: input.MouseDownEvent) cs_input.MouseDownEvent {
    return .{
        .button = @intToEnum(cs_input.MouseButton, @enumToInt(e.button)),
        .x = e.x,
        .y = e.y,
        .clicks = e.clicks,
    };
}

pub fn fromStdMouseUpEvent(e: input.MouseUpEvent) cs_input.MouseUpEvent {
    return .{
        .button = @intToEnum(cs_input.MouseButton, @enumToInt(e.button)),
        .x = e.x,
        .y = e.y,
        .clicks = e.clicks,
    };
}

pub fn fromStdMouseMoveEvent(e: input.MouseMoveEvent) cs_input.MouseMoveEvent {
    return .{
        .x = e.x,
        .y = e.y,
    };
}

/// @title Networking
/// @name net
/// @ns cs.net
/// There are plans to implement a networking API to allow connecting to another device and hosting a TCP/UDP server.
pub const cs_net = struct {
};

/// @title Testing
/// @name test
/// @ns cs.test
/// The testing API is only avaiable when using the test runner.
pub const cs_test = struct {

    /// Creates a test to be run. If the callback is async the test will be run concurrently.
    /// @param name
    /// @param callback
    pub fn create(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
        // FUTURE: Save test cases and execute them in parallel.
        const iso = rt.isolate;
        const ctx = rt.getContext();

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

                _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected) catch unreachable;
            } else {
                const err_str = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(err_str);
                rt.env.printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
            }
        } else {
            // Sync test.
            if (cb.call(ctx, rt.js_undefined, &.{})) |_| {
                rt.num_tests_passed += 1;
            } else {
                const err_str = v8x.allocPrintTryCatchStackTrace(rt.alloc, iso, ctx, try_catch).?;
                defer rt.alloc.free(err_str);
                rt.env.printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
            }
        }
    }

    /// Creates an isolated test to be run. An isolated test runs after all normal tests and are run one by one even if they are async.
    /// @param name
    /// @param callback
    pub fn createIsolated(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
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

    /// Asserts that the actual value equals the expected value.
    /// @param act
    /// @param exp
    pub fn eq(act: v8.Value, exp: v8.Value) void {
        _ = act;
        _ = exp;
        // Js Func.
    }

    /// Asserts that the actual value does not equal the expected value.
    /// @param act
    /// @param exp
    pub fn neq(act: v8.Value, exp: v8.Value) void {
        _ = act;
        _ = exp;
        // Js Func.
    }

    /// Asserts that the actual value contains a sub value.
    /// For a string, a sub value is a substring.
    /// @param act
    /// @param needle
    pub fn contains(act: v8.Value, needle: v8.Value) void {
        _ = act;
        _ = needle;
        // Js Func.
    }

    /// Asserts that the anonymous function throws an exception.
    /// An optional substring can be provided to check against the exception message.
    /// @param func
    /// @param expErrorSubStr
    pub fn throws(func: v8.Function, exp_str: ?v8.String) void {
        _ = func;
        _ = exp_str;
        // Js Func.
    }
};

/// @title Worker Threads
/// @name worker
/// @ns cs.worker
/// There are plans to implement worker threads for Javascript similar to Web Workers.
pub const cs_worker = struct {
};

fn reportAsyncTestFailure(data: FuncData, val: v8.Value) void {
    const obj = data.val.castTo(v8.Object);
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castTo(v8.External).get());

    const test_name = v8x.allocValueAsUtf8(rt.alloc, rt.isolate, rt.getContext(), obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    // TODO: report stack trace.
    rt.num_async_tests_finished += 1;
    const str = v8x.allocValueAsUtf8(rt.alloc, rt.isolate, rt.getContext(), val);
    defer rt.alloc.free(str);

    rt.env.printFmt("Test Failed: \"{s}\"\n{s}\n", .{test_name, str});
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

fn dupeArgs(alloc: std.mem.Allocator, comptime Func: anytype, args: anytype) std.meta.ArgsTuple(@TypeOf(Func)) {
    const ArgsTuple = std.meta.ArgsTuple(@TypeOf(Func));
    const Fields = std.meta.fields(ArgsTuple);
    const InputFields = std.meta.fields(@TypeOf(args));
    var res: ArgsTuple = undefined;
    inline for (Fields) |Field, I| {
        if (Field.field_type == []const u8) {
            @field(res, Field.name) = alloc.dupe(u8, @field(args, InputFields[I].name)) catch unreachable;
        } else {
            @field(res, Field.name) = @field(args, InputFields[I].name);
        }
    }
    return res;
}
