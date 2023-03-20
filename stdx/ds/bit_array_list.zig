const std = @import("std");

// std.DynamicBitSet doesn't behave like std.ArrayList, it will realloc on every resize.
// For now provide a bitset api and use std.ArrayList(bool) as the implementation.
pub const BitArrayList = struct {
    buf: std.ArrayList(bool),

    pub fn init(alloc: std.mem.Allocator) BitArrayList {
        return .{
            .buf = std.ArrayList(bool).init(alloc),
        };
    }

    pub fn deinit(self: BitArrayList) void {
        self.buf.deinit();
    }

    pub fn ensureUnusedCapacity(self: *BitArrayList, cap: usize) !void {
        try self.buf.ensureUnusedCapacity(cap);
    }

    pub fn clearRetainingCapacity(self: *BitArrayList) void {
        self.buf.clearRetainingCapacity();
    }

    pub fn appendUnset(self: *BitArrayList) !void {
        try self.buf.append(false);
    }

    pub fn appendSet(self: *BitArrayList) !void {
        try self.buf.append(true);
    }

    pub fn isSet(self: BitArrayList, idx: usize) bool {
        return self.buf.items[idx];
    }

    pub fn set(self: *BitArrayList, idx: usize) void {
        self.buf.items[idx] = true;
    }

    pub fn unset(self: *BitArrayList, idx: usize) void {
        self.buf.items[idx] = false;
    }

    pub fn setRange(self: *BitArrayList, start: usize, end: usize) void {
        std.mem.set(bool, self.buf.items[start..end], true);
    }

    pub fn unsetRange(self: *BitArrayList, start: usize, end: usize) void {
        std.mem.set(bool, self.buf.items[start..end], false);
    }

    pub fn resize(self: *BitArrayList, size: usize) !void {
        try self.buf.resize(size);
    }

    pub fn resizeFillNew(self: *BitArrayList, size: usize, comptime fill: bool) !void {
        const start = self.buf.items.len;
        try self.resize(size);
        if (self.buf.items.len > start) {
            if (fill) {
                self.setRange(start, self.buf.items.len);
            } else {
                self.unsetRange(start, self.buf.items.len);
            }
        }
    }
};
