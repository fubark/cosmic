const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

pub const document = @import("document.zig");

/// Simple UTF8 buffer that facilitates text editing.
pub const TextBuffer = struct {
    buf: std.ArrayList(u8),
    num_chars: u32,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, buf: []const u8) !Self {
        var new = Self{
            .buf = std.ArrayList(u8).init(alloc),
            .num_chars = 0,
        };
        if (buf.len > 0) {
            const view = try std.unicode.Utf8View.init(buf);
            var iter = view.iterator();
            var i: u32 = 0;
            while (iter.nextCodepoint()) |_| {
                i += 1;
            }
            new.buf.appendSlice(buf) catch @panic("error");
            new.num_chars = i;
        }
        return new;
    }

    pub fn deinit(self: Self) void {
        self.buf.deinit();
    }

    pub fn clear(self: *Self) void {
        self.buf.clearRetainingCapacity();
        self.num_chars = 0;
    }

    pub fn insertCodepoint(self: *Self, idx: u32, cp: u21) !void {
        const len = try std.unicode.utf8CodepointSequenceLength(cp);
        const buf_idx = self.getBufferIdx(idx);
        const old_len = self.buf.items.len;
        self.buf.resize(old_len + len) catch @panic("error");
        std.mem.copyBackwards(u8, self.buf.items[buf_idx+len..], self.buf.items[buf_idx..old_len]);
        _ = std.unicode.utf8Encode(cp, self.buf.items[buf_idx..buf_idx+len]) catch @panic("error");
        self.num_chars += 1;
    }

    pub fn appendCodepoint(self: *Self, cp: u21) !void {
        const len = try std.unicode.utf8CodepointSequenceLength(cp);
        const next = self.buf.items.len;
        self.buf.resize(next + len) catch @panic("error");
        _ = std.unicode.utf8Encode(cp, self.buf.items[next..self.buf.items.len]) catch @panic("error");
        self.num_chars += 1;
    }

    pub fn appendSubStr(self: *Self, str: []const u8) !void {
        const view = try std.unicode.Utf8View.init(str);
        var iter = view.iterator();
        var i: u32 = 0;
        while (iter.nextCodepoint()) |_| {
            i += 1;
        }
        self.buf.appendSlice(str) catch @panic("error");
        self.num_chars += i;
    }

    pub fn appendFmt(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const next = self.buf.items.len;
        self.buf.resize(next + @intCast(usize, std.fmt.count(fmt, args))) catch @panic("error");
        _ = std.fmt.bufPrint(self.buf.items[next..], fmt, args) catch @panic("error");
        const view = std.unicode.Utf8View.initUnchecked(self.buf.items[next..]);
        var iter = view.iterator();
        var i: u32 = 0;
        while (iter.nextCodepoint()) |_| {
            i += 1;
        }
        self.num_chars += i;
    }

    pub fn getSubStr(self: Self, start_idx: u32, end_idx: u32) []const u8 {
        const range = self.getBufferRange(start_idx, end_idx);
        return self.buf.items[range.buf_start_idx..range.buf_end_idx];
    }

    pub fn removeChar(self: *Self, idx: u32) void {
        self.removeSubStr(idx, idx + 1);
    }

    pub fn removeSubStr(self: *Self, start_idx: u32, end_idx: u32) void {
        const range = self.getBufferRange(start_idx, end_idx);
        self.buf.replaceRange(range.buf_start_idx, range.buf_end_idx - range.buf_start_idx, "") catch @panic("error");
        self.num_chars -= (end_idx - start_idx);
    }

    fn getBufferIdx(self: Self, idx: u32) u32 {
        if (idx == 0) {
            return 0;
        }
        var iter = std.unicode.Utf8View.initUnchecked(self.buf.items).iterator();
        var cur_char_idx: u32 = 0;
        var cur_buf_idx: u32 = 0;
        while (iter.nextCodepointSlice()) |cp_slice| {
            cur_char_idx += 1;
            cur_buf_idx += @intCast(u32, cp_slice.len);
            if (cur_char_idx == idx) {
                return cur_buf_idx;
            }
        }
        @panic("error");
    }

    fn getBufferRange(self: Self, start_idx: u32, end_idx: u32) Range {
        var iter = std.unicode.Utf8View.initUnchecked(self.buf.items).iterator();
        var i: u32 = 0;
        var buf_start_idx: u32 = 0;
        var buf_end_idx: u32 = 0;
        var cur_buf_idx: u32 = 0;
        while (iter.nextCodepointSlice()) |cp_slice| {
            if (i == start_idx) {
                buf_start_idx = cur_buf_idx;
            }
            i += 1;
            cur_buf_idx += @intCast(u32, cp_slice.len);
            if (i == end_idx) {
                buf_end_idx = cur_buf_idx;
                break;
            }
        }
        return .{
            .buf_start_idx = buf_start_idx,
            .buf_end_idx = buf_end_idx,
        };
    }
};

const Range = struct {
    buf_start_idx: u32,
    buf_end_idx: u32,
};

test "TextBuffer.clear" {
    var buf = try TextBuffer.init(t.alloc, "ab🫐c");
    defer buf.deinit();
    try t.eq(buf.buf.items.len, 7);
    try t.eq(buf.num_chars, 4);

    buf.clear();
    try t.eq(buf.buf.items.len, 0);
    try t.eq(buf.num_chars, 0);
}

test "TextBuffer.insertCodepoint" {
    var buf = try TextBuffer.init(t.alloc, "");
    defer buf.deinit();

    try buf.insertCodepoint(0, 97);
    try t.eq(buf.num_chars, 1);
    try t.eqStr(buf.buf.items, "a");

    try buf.insertCodepoint(1, 98);
    try t.eq(buf.num_chars, 2);
    try t.eqStr(buf.buf.items, "ab");

    try buf.insertCodepoint(1, 129744);
    try t.eq(buf.num_chars, 3);
    try t.eqStr(buf.buf.items, "a🫐b");

    // This would test for a backwards memory copy since dst and src would overlap.
    try buf.insertCodepoint(1, 97);
    try t.eq(buf.num_chars, 4);
    try t.eqStr(buf.buf.items, "aa🫐b");
}

test "TextBuffer.appendCodepoint" {
    var buf = try TextBuffer.init(t.alloc, "");
    defer buf.deinit();

    try buf.appendCodepoint(97);
    try t.eq(buf.num_chars, 1);
    try t.eqStr(buf.buf.items, "a");

    try buf.appendCodepoint(129744);
    try t.eq(buf.num_chars, 2);
    try t.eqStr(buf.buf.items, "a🫐");
}

test "TextBuffer.appendSubStr" {
    var buf = try TextBuffer.init(t.alloc, "");
    defer buf.deinit();

    try buf.appendSubStr("a");
    try t.eq(buf.num_chars, 1);
    try t.eqStr(buf.buf.items, "a");

    try buf.appendSubStr("b🫐c");
    try t.eq(buf.num_chars, 4);
    try t.eqStr(buf.buf.items, "ab🫐c");
}

test "TextBuffer.appendFmt" {
    var buf = try TextBuffer.init(t.alloc, "");
    defer buf.deinit();

    buf.appendFmt("a", .{});
    try t.eq(buf.num_chars, 1);
    try t.eqStr(buf.buf.items, "a");

    buf.appendFmt("{}", .{123});
    try t.eq(buf.num_chars, 4);
    try t.eqStr(buf.buf.items, "a123");
}

test "TextBuffer.getSubStr" {
    var buf = try TextBuffer.init(t.alloc, "ab🫐c");
    defer buf.deinit();
    try t.eq(buf.buf.items.len, 7);

    try t.eqStr(buf.getSubStr(0, 1), "a");
    try t.eqStr(buf.getSubStr(0, 2), "ab");
    try t.eqStr(buf.getSubStr(0, 3), "ab🫐");
}

test "TextBuffer.removeSubStr" {
    var buf = try TextBuffer.init(t.alloc, "ab🫐c");
    defer buf.deinit();
    try t.eq(buf.buf.items.len, 7);

    buf.removeSubStr(1, 2);
    try t.eq(buf.num_chars, 3);
    try t.eqStr(buf.buf.items, "a🫐c");

    buf.removeSubStr(1, 2);
    try t.eq(buf.num_chars, 2);
    try t.eqStr(buf.buf.items, "ac");
}
