const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.dynamic_array_list);

// ArrayList with variable sized items.
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

        data: std.ArrayList(T),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .data = std.ArrayList(T).init(alloc),
            };
        }

        pub fn toOwnedSlice(self: *Self) []const T {
            return self.data.toOwnedSlice();
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        pub fn shrinkRetainingCapacity(self: *Self, len: usize) void {
            self.data.shrinkRetainingCapacity(len);
        }

        pub fn append(self: *Self, item: anytype) !SizedPtr {
            const ItemType = @TypeOf(item);
            const id = @intCast(Id, self.data.items.len);
            var mut_item = item;
            const slice = @ptrCast([*]T, &mut_item)[0..@sizeOf(ItemType)];
            try self.data.appendSlice(slice);
            return SizedPtr.init(id, @sizeOf(ItemType));
        }

        pub fn getPtrCast(self: *Self, comptime ReqPtr: type, ptr: SizedPtr) ReqPtr {
            return stdx.mem.ptrCastAlign(ReqPtr, &self.data.items[ptr.id]);
        }

        pub fn getBytesPtr(self: *Self, ptr: SizedPtr) [*]const T {
            return @ptrCast([*]const T, &self.data.items[ptr.id]);
        }

        pub fn getBytes(self: *Self, ptr: SizedPtr) []const T {
            const end_idx = ptr.id + ptr.len;
            return self.data.items[ptr.id..end_idx];
        }

        pub fn deinit(self: Self) void {
            self.data.deinit();
        }
    };
}
