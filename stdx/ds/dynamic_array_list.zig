const std = @import("std");
const stdx = @import("../stdx.zig");
const t = stdx.testing;

const log = stdx.log.scoped(.dynamic_array_list);

// ArrayList with variable sized items.
pub const DynamicArrayList = struct {
    const Self = @This();
    const Id = usize;
    pub const Ptr = struct {
        id: Id,
        len: usize,
        pub fn init(id: Id, len: usize) @This() {
            return .{ .id = id, .len = len };
        }
    };

    data: std.ArrayList(u8),

    pub fn init(alloc: *std.mem.Allocator) Self {
        return .{
            .data = std.ArrayList(u8).init(alloc),
        };
    }

    pub fn shrinkRetainingCapacity(self: *Self, len: usize) void {
        self.data.shrinkRetainingCapacity(len);
    }

    pub fn append(self: *Self, item: anytype) !Ptr {
        const ItemType = @TypeOf(item);
        const id = self.data.items.len;
        var mut_item = item;
        const slice = @ptrCast([*]u8, &mut_item)[0..@sizeOf(ItemType)];
        try self.data.appendSlice(slice);
        return Ptr.init(id, @sizeOf(ItemType));
    }

    pub fn getBytes(self: *Self, ptr: Ptr) []const u8 {
        const end_idx = ptr.id + ptr.len;
        return self.data.items[ptr.id..end_idx];
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};
