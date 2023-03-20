const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;
const assert = std.debug.assert;
const mem = std.mem;
const log = stdx.log.scoped(.unicode);

// Adapted from std.unicode.utf16lToUtf8Alloc
pub fn utf16beToUtf8Alloc(alloc: mem.Allocator, utf16be: []const u16) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    // optimistically guess that it will all be ascii.
    try result.ensureTotalCapacity(utf16be.len);
    var out_index: usize = 0;
    var it = Utf16BeIterator.init(utf16be);
    while (try it.nextCodepoint()) |codepoint| {
        const utf8_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        try result.resize(result.items.len + utf8_len);
        assert((std.unicode.utf8Encode(codepoint, result.items[out_index..]) catch unreachable) == utf8_len);
        out_index += utf8_len;
    }
    return result.toOwnedSlice();
}

pub const Utf16BeIterator = struct {
    bytes: []const u8,
    i: usize,

    pub fn init(s: []const u16) Utf16BeIterator {
        return Utf16BeIterator{
            .bytes = mem.sliceAsBytes(s),
            .i = 0,
        };
    }

    pub fn nextCodepoint(it: *@This()) !?u21 {
        assert(it.i <= it.bytes.len);
        if (it.i == it.bytes.len) return null;
        const c0: u21 = mem.readIntBig(u16, it.bytes[it.i..][0..2]);
        if (c0 & ~@as(u21, 0x03ff) == 0xd800) {
            // surrogate pair
            it.i += 2;
            if (it.i >= it.bytes.len) return error.DanglingSurrogateHalf;
            const c1: u21 = mem.readIntBig(u16, it.bytes[it.i..][0..2]);
            if (c1 & ~@as(u21, 0x03ff) != 0xdc00) return error.ExpectedSecondSurrogateHalf;
            it.i += 2;
            return 0x10000 + (((c0 & 0x03ff) << 10) | (c1 & 0x03ff));
        } else if (c0 & ~@as(u21, 0x03ff) == 0xdc00) {
            return error.UnexpectedSecondSurrogateHalf;
        } else {
            it.i += 2;
            return c0;
        }
    }
};

// TODO: Check unicode spaces too.
pub fn isSpace(cp: u21) bool {
    if (cp < 128) {
        return std.ascii.isWhitespace(@intCast(u8, cp));
    }
    return false;
}

pub fn printCodepoint(cp: u21) void {
    const buf: []u8 = undefined;
    _ = std.unicode.utf8Encode(cp, buf) catch unreachable;
    log.debug("codepoint: {} {s}", .{ cp, buf[0..std.unicode.utf8CodepointSequenceLength(cp)] });
}

/// Like std.ascii.toLowerString but for unicode.
pub fn toLowerString(out: []u8, input: []const u8) ![]u8 {
    const view = try std.unicode.Utf8View.init(input);
    var iter = view.iterator();
    var i: u32 = 0;
    while (iter.nextCodepointSlice()) |cp_slice| {
        const cp = std.unicode.utf8Decode(cp_slice) catch unreachable;
        if (cp <= std.math.maxInt(u8)) {
            const lower = std.ascii.toLower(@intCast(u8, cp));
            out[i] = lower;
            i += 1;
        } else {
            std.mem.copy(u8, out[i..i+cp_slice.len], cp_slice);
            i += @intCast(u32, cp_slice.len);
        }
    }
    return out[0..i];
}

test "toLowerString" {
    var buf: [100]u8 = undefined;
    try t.eqSlice(u8, try toLowerString(&buf, "FOO"), "foo");
    try t.eqSlice(u8, try toLowerString(&buf, "FO🐥O"), "fo🐥o");
}