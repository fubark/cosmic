const std = @import("std");
const stdx = @import("stdx");
const uv = @import("uv");
const graphics = @import("graphics");
const t = stdx.testing;

const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const CsWindow = runtime.CsWindow;
const log = stdx.log.scoped(.devmode);

const DevModeOptions = struct {
    max_cmd_items: u32 = 100,
    max_stdio_line_items: u32 = 100,
};

pub const DevModeContext = struct {
    const Self = @This();
    
    alloc: std.mem.Allocator,

    // When no user windows are created, there is always a dev window.
    dev_window: ?*CsWindow,

    // File watch. Currently just the main script.
    watcher: *WatchEntry,

    // For now, there is just one global dev term.
    term_items: std.ArrayList(TermItem),

    term_cmds: std.ArrayList(CommandItem),

    term_stdio_lines: std.ArrayList(StdioLineItem),
    
    // Whether the current pos is at an empty new line. (hasn't inserted a line item yet.)
    term_stdio_on_new_line: bool,

    opts: DevModeOptions,

    // In devmode, this is set true on the first uncaught js exception.
    // This is then used to ensure that only the dev window interface is active. (User scripts/cbs shouldn't be invoked.)
    has_error: bool,

    // Once restart is requested, the runtime will perform a restart when appropriate.
    // The flag is also used during restart to prevent some things from deiniting in order to persist them into the next session.
    restart_requested: bool,

    show_hud: bool,

    pub fn init(self: *Self, alloc: std.mem.Allocator, opts: DevModeOptions) void {
        self.* = .{
            .alloc = alloc,
            .dev_window = null,
            .watcher = undefined,
            .term_items = std.ArrayList(TermItem).init(alloc),
            .term_cmds = std.ArrayList(CommandItem).init(alloc),
            .term_stdio_lines = std.ArrayList(StdioLineItem).init(alloc),
            .term_stdio_on_new_line = true,
            .opts = opts,
            .has_error = false,
            .restart_requested = false,
            .show_hud = true,
        };
    }

    pub fn initWatcher(self: *Self, rt: *RuntimeContext, abs_path: []const u8) void {
        self.watcher = self.alloc.create(WatchEntry) catch unreachable;
        self.watcher.* = .{
            .event = undefined,
            .hash = undefined,
            .path = self.alloc.dupe(u8, abs_path) catch unreachable,
        };
        var uv_res = uv.uv_fs_event_init(rt.uv_loop, &self.watcher.event);
        uv.assertNoError(uv_res);
        self.watcher.event.data = rt;
        stdx.fs.getFileMd5Hash(self.alloc, abs_path, &self.watcher.hash) catch unreachable;

        const abs_path_z = std.cstr.addNullByte(self.alloc, abs_path) catch unreachable;
        defer self.alloc.free(abs_path_z);
        const S = struct {
            fn onFileChange(handle: *uv.uv_fs_event_t, filename: [*c]const u8, events: c_int, status: c_int) callconv(.C) void {
                _ = filename;
                uv.assertNoError(status);
                if (events & uv.UV_CHANGE != 0) {
                    // log.debug("on file change {s}", .{filename});
                    const entry = stdx.ptrCastAlign(*WatchEntry, handle);
                    const rt_ = stdx.ptrCastAlign(*RuntimeContext, entry.event.data);
                    var hash: [16]u8 = undefined;
                    stdx.fs.getFileMd5Hash(rt_.alloc, entry.path, &hash) catch unreachable;
                    if (!std.meta.eql(hash, entry.hash)) {
                        entry.hash = hash;
                        rt_.dev_ctx.requestRestart();
                    }
                }
            }
        };
        uv_res = uv.uv_fs_event_start(&self.watcher.event, S.onFileChange, abs_path_z, 0);
        uv.assertNoError(uv_res);
    }

    pub fn close(self: Self) void {
        const S = struct {
            fn onClose(ptr: [*c]uv.uv_handle_t) callconv(.C) void {
                const entry = @ptrCast(*WatchEntry, ptr);
                const rt = stdx.ptrCastAlign(*RuntimeContext, entry.event.data.?);
                entry.deinit(rt.alloc);
                rt.alloc.destroy(entry);
            }
        };
        uv.uv_close(@ptrCast(*uv.uv_handle_t, &self.watcher.event), S.onClose);
    }

    pub fn deinit(self: Self) void {
        for (self.term_cmds.items) |it| {
            it.deinit(self.alloc);
        }
        self.term_cmds.deinit();
        for (self.term_stdio_lines.items) |it| {
            it.deinit(self.alloc);
        }
        self.term_stdio_lines.deinit();
        self.term_items.deinit();
    }

    pub fn printFmt(self: *Self, comptime format: []const u8, args: anytype) void {
        const str = std.fmt.allocPrint(self.alloc, format, args) catch unreachable;
        defer self.alloc.free(str);
        self.print(str);
    }

    /// Records an emulated print to stdout.
    pub fn print(self: *Self, str: []const u8) void {
        var start: usize = 0;
        for (str) |ch, i| {
            if (ch == '\n') {
                if (self.term_stdio_on_new_line) {
                    // Prepend a new line with everything before the newline.
                    self.prependStdioLine(str[start..i]);
                } else {
                    // Append to the most recent line.
                    const new_str = std.fmt.allocPrint(self.alloc, "{s}{s}", .{self.term_stdio_lines.items[0].line, str[start..i]}) catch unreachable;
                    self.alloc.free(self.term_stdio_lines.items[0].line);
                    self.term_stdio_lines.items[0].line = new_str;
                }
                self.term_stdio_on_new_line = true;
                start = i + 1;
            }
        }
        if (start < str.len) {
            if (self.term_stdio_on_new_line) {
                self.prependStdioLine(str[start..str.len]);
                self.term_stdio_on_new_line = false;
            } else {
                const new_str = std.fmt.allocPrint(self.alloc, "{s}{s}", .{self.term_stdio_lines.items[0].line, str[start..str.len]}) catch unreachable;
                self.alloc.free(self.term_stdio_lines.items[0].line);
                self.term_stdio_lines.items[0].line = new_str;
            }
        }
    }

    fn prependStdioLine(self: *Self, line: []const u8) void {
        const full = self.term_stdio_lines.items.len == self.opts.max_stdio_line_items;
        if (full) {
            const last = self.term_stdio_lines.pop();
            last.deinit(self.alloc);
        }
        self.term_stdio_lines.insert(0, .{
            .line = self.alloc.dupe(u8, line) catch unreachable,
        }) catch unreachable;

        self.prependAggTermItem(.StdioLine, if (full) self.opts.max_stdio_line_items-1 else null);
    }

    fn prependAggTermItem(self: *Self, tag: TermItemTag, mb_remove_idx: ?usize) void {
        if (mb_remove_idx) |remove_idx| {
            // Remove from aggregate.
            var i: u32 = self.aggIndexOfTermItem(tag, remove_idx).?;
            while (i > 0) : (i -= 1) {
                if (self.term_items.items[i-1].tag == tag) {
                    self.term_items.items[i] = .{
                        .tag = tag,
                        // Increment 1 since we are prepending an item.
                        .idx = self.term_items.items[i-1].idx + 1,
                    };
                } else {
                    self.term_items.items[i] = self.term_items.items[i-1];
                }
            }
            self.term_items.items[0] = .{
                .tag = tag,
                .idx = 0,
            };
        } else {
            // Update aggregate items.
            var i: u32 = 0;
            while (i < self.term_items.items.len) : (i += 1) {
                if (self.term_items.items[i].tag == tag) {
                    self.term_items.items[i].idx += 1;
                }
            }
            self.term_items.insert(0, .{
                .tag = tag,
                .idx = 0,
            }) catch unreachable;
        }
    }

    pub fn cmdLog(self: *Self, str: []const u8) void {
        const full = self.term_cmds.items.len == self.opts.max_cmd_items;
        if (full) {
            const last = self.term_cmds.pop();
            last.deinit(self.alloc);
        }
        self.term_cmds.insert(0, .{
            .msg = self.alloc.dupe(u8, str) catch unreachable,
        }) catch unreachable;

        self.prependAggTermItem(.Command, if (full) self.opts.max_cmd_items-1 else null);
    }

    fn aggIndexOfTermItem(self: Self, tag: TermItemTag, idx: usize) ?u32 {
        var i: u32 = 0;
        while (i < self.term_items.items.len) : (i += 1) {
            if (self.term_items.items[i].tag == tag and self.term_items.items[i].idx == idx) {
                return i;
            }
        }
        return null;
    }

    pub fn getAggCommandItem(self: Self, idx: usize) CommandItem {
        const cmd_idx = self.term_items.items[idx].idx;
        return self.term_cmds.items[cmd_idx];
    }

    pub fn getAggStdioLineItem(self: Self, idx: usize) StdioLineItem {
        const cmd_idx = self.term_items.items[idx].idx;
        return self.term_stdio_lines.items[cmd_idx];
    }

    pub fn enterJsErrorState(self: *Self, rt: *RuntimeContext, js_err_trace: []const u8) void {
        self.print(js_err_trace);
        self.has_error = true;
        self.dev_window = rt.active_window;
    }

    pub fn enterJsSuccessState(self: *Self) void {
        self.has_error = false;
    }

    pub fn requestRestart(self: *Self) void {
        self.restart_requested = true;
    }
};

test "DevModeContext command items" {
    var ctx: DevModeContext = undefined;
    ctx.init(t.alloc, .{
        .max_cmd_items = 3,
        .max_stdio_line_items = 3,
    });
    defer ctx.deinit();

    // Insert command item.
    ctx.cmdLog("Command Log");
    try t.eq(ctx.term_cmds.items.len, 1);
    try t.eq(ctx.term_items.items.len, 1);
    try t.eq(ctx.term_items.items[0].tag, .Command);
    try t.eqStr(ctx.getAggCommandItem(0).msg, "Command Log");

    // Insert command item to limit.
    ctx.cmdLog("Log 1");
    ctx.cmdLog("Log 2");
    try t.eq(ctx.term_cmds.items.len, 3);
    try t.eq(ctx.term_items.items.len, 3);
    try t.eqStr(ctx.getAggCommandItem(0).msg, "Log 2");
    try t.eqStr(ctx.getAggCommandItem(1).msg, "Log 1");
    try t.eqStr(ctx.getAggCommandItem(2).msg, "Command Log");

    // Insert command item at limit.
    ctx.cmdLog("Command Log");
    try t.eq(ctx.term_cmds.items.len, 3);
    try t.eq(ctx.term_items.items.len, 3);
    try t.eqStr(ctx.getAggCommandItem(0).msg, "Command Log");
    try t.eqStr(ctx.getAggCommandItem(1).msg, "Log 2");
    try t.eqStr(ctx.getAggCommandItem(2).msg, "Log 1");
}

test "DevModeContext stdio lines" {
    t.setLogLevel(.debug);
    var ctx: DevModeContext = undefined;
    ctx.init(t.alloc, .{
       .max_cmd_items = 3,
       .max_stdio_line_items = 3,
    });
    defer ctx.deinit();

    ctx.print("Foo");
    try t.eq(ctx.term_items.items.len, 1);
    try t.eq(ctx.term_stdio_lines.items.len, 1);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Foo");
    ctx.print("Bar");
    try t.eq(ctx.term_items.items.len, 1);
    try t.eq(ctx.term_stdio_lines.items.len, 1);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "FooBar");
    ctx.print("\n");
    try t.eq(ctx.term_items.items.len, 1);
    try t.eq(ctx.term_stdio_lines.items.len, 1);
    ctx.print("Foo\n");
    try t.eq(ctx.term_items.items.len, 2);
    try t.eq(ctx.term_stdio_lines.items.len, 2);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Foo");
    try t.eqStr(ctx.getAggStdioLineItem(1).line, "FooBar");
    ctx.print("Foo\n");
    try t.eq(ctx.term_items.items.len, 3);
    try t.eq(ctx.term_stdio_lines.items.len, 3);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Foo");
    try t.eqStr(ctx.getAggStdioLineItem(1).line, "Foo");
    try t.eqStr(ctx.getAggStdioLineItem(2).line, "FooBar");
    ctx.print("Overflow\n");
    try t.eq(ctx.term_items.items.len, 3);
    try t.eq(ctx.term_stdio_lines.items.len, 3);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Overflow");
    try t.eqStr(ctx.getAggStdioLineItem(1).line, "Foo");
    try t.eqStr(ctx.getAggStdioLineItem(2).line, "Foo");
}

test "DevModeContext mix term items" {
    var ctx: DevModeContext = undefined;
    ctx.init(t.alloc, .{
        .max_cmd_items = 3,
        .max_stdio_line_items = 3,
    });
    defer ctx.deinit();

    ctx.cmdLog("Command 1");
    ctx.print("Foo 1\n");
    try t.eq(ctx.term_items.items.len, 2);
    try t.eq(ctx.term_cmds.items.len, 1);
    try t.eq(ctx.term_stdio_lines.items.len, 1);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Foo 1");
    try t.eqStr(ctx.getAggCommandItem(1).msg, "Command 1");
    ctx.cmdLog("Command 2");
    ctx.print("Foo 2\n");
    try t.eq(ctx.term_items.items.len, 4);
    try t.eq(ctx.term_cmds.items.len, 2);
    try t.eq(ctx.term_stdio_lines.items.len, 2);
    try t.eqStr(ctx.getAggStdioLineItem(0).line, "Foo 2");
    try t.eqStr(ctx.getAggCommandItem(1).msg, "Command 2");
    try t.eqStr(ctx.getAggStdioLineItem(2).line, "Foo 1");
    try t.eqStr(ctx.getAggCommandItem(3).msg, "Command 1");
}

const WatchEntry = struct {
    const Self = @This();

    event: uv.uv_fs_event_t,
    hash: [16]u8,
    path: []const u8,

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
    }
};

const TermItemTag = enum {
    Command,
    StdioLine,
};

const TermItem = struct {
    tag: TermItemTag,
    idx: u32,
};

const CommandItem = struct {
    const Self = @This();

    msg: []const u8,

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.msg);
    }
};

const StdioLineItem = struct {
    const Self = @This();

    line: []const u8,

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.line);
    }
};

pub fn renderDevHud(rt: *RuntimeContext, w: *CsWindow) void {
    if (!rt.dev_ctx.show_hud) {
        return;
    }

    const g = w.graphics;
    _ = @intToFloat(f32, w.window.impl.width);
    const height = @intToFloat(f32, w.window.impl.height);

    g.setFont(g.getDefaultFontId(), 16);
    var y = height - 70;
    for (rt.dev_ctx.term_items.items) |it, i| {
        switch (it.tag) {
            .Command => {
                const item = rt.dev_ctx.getAggCommandItem(i);
                g.setFillColor(graphics.Color.Yellow);
                g.fillText(20, y, item.msg);
                y -= 25;
            },
            .StdioLine => {
                const item = rt.dev_ctx.getAggStdioLineItem(i);
                g.setFillColor(graphics.Color.White);
                g.fillText(20, y, item.line);
                y -= 25;
            },
        }
    }

    // TODO: Render input.
}