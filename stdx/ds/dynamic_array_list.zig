const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.dynamic_array_list);

/// ArrayList with variable sized items of multiple of @sizeOf(T).
/// TODO: Allow items that are not a multiple of @sizeOf(T).
pub fn DynamicArrayList(comptime Id: type, comptime T: type) type {
    return struct {
        const Self = @This();

        pub const SizedPtr = struct {
            id: Id,
            len: usize,
            pub fn init(id: Id, len: usize) @This() {
                return .{ .id = id, .len = len };
            }
        };

        buf: std.ArrayList(T),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .buf = std.ArrayList(T).init(alloc),
            };
        }

        pub fn toOwnedSlice(self: *Self) []const T {
            return self.buf.toOwnedSlice();
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.buf.clearRetainingCapacity();
        }

        pub fn shrinkRetainingCapacity(self: *Self, len: usize) void {
            self.buf.shrinkRetainingCapacity(len);
        }

        /// Appends a variable sized item and returns it's index and size.
        /// Item size must be a multiple of @sizeOf(T).
        pub fn append(self: *Self, item: anytype) !SizedPtr {
            // const Item = @TypeOf(item);
            const id = @intCast(Id, self.buf.items.len);
            const slice = @ptrCast([*]const T, &item)[0..@sizeOf(@TypeOf(item))];
            try self.buf.appendSlice(slice);
            return SizedPtr.init(id, slice.len);
        }

        pub fn get(self: *Self, comptime Child: type, ptr: SizedPtr) Child {
            return std.mem.bytesToValue(Child, self.buf.items[ptr.id..ptr.id+ptr.len][0..@sizeOf(Child)]);
        }

        pub fn getPtr(self: *Self, comptime ChildPtr: type, ptr: SizedPtr) *align(@alignOf(T)) std.meta.Child(ChildPtr) {
            const Child = std.meta.Child(ChildPtr);
            return std.mem.bytesAsValue(Child, self.buf.items[ptr.id..ptr.id+ptr.len][0..@sizeOf(Child)]);
        }

        pub fn getBytesPtr(self: *Self, ptr: SizedPtr) [*]const T {
            return @ptrCast([*]const u8, &self.buf.items[ptr.id]);
        }

        pub fn getBytes(self: *Self, ptr: SizedPtr) []const T {
            const end_idx = ptr.id + ptr.len;
            return self.buf.items[ptr.id..end_idx];
        }

        pub fn deinit(self: Self) void {
            self.buf.deinit();
        }
    };
}

test "DynamicArrayList" {
    var arr = DynamicArrayList(u32, u8).init(t.alloc);
    defer arr.deinit();

    var ptr = try arr.append(true);
    try t.eq(ptr, .{ .id = 0, .len = 1 });
    try t.eq(arr.get(bool, ptr), true);
    try t.eq(arr.getPtr(*bool, ptr).*, true);
    ptr = try arr.append(@as(u32, 100));
    try t.eq(ptr, .{ .id = 1, .len = 4 });
    try t.eq(arr.get(u32, ptr), 100);
    try t.eq(arr.getPtr(*u32, ptr).*, 100);
}