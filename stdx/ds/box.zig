const std = @import("std");
const ds = @import("ds.zig");

// Stores allocator with data ptr.
pub fn Box(comptime T: type) type {
    if (@typeInfo(T) == .Pointer and @typeInfo(T).Pointer.size == .Slice) {
        return BoxSlice(T);
    } else if (@typeInfo(T) == .Struct) {
        return BoxPtr(T);
    }
    @compileError("not supported");
}

fn BoxSlice(comptime T: type) type {
    return struct {
        const Self = @This();

        slice: T,
        alloc: *std.mem.Allocator,

        pub fn init(alloc: *std.mem.Allocator, slice: T) Self {
            return .{
                .alloc = alloc,
                .slice = slice,
            };
        }

        pub fn deinit(self: *const Self) void {
            self.alloc.free(self.slice);
        }
    };
}

fn BoxPtr(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: *T,
        alloc: *std.mem.Allocator,

        pub fn init(alloc: *std.mem.Allocator, ptr: *T) Self {
            return .{
                .alloc = alloc,
                .ptr = ptr,
            };
        }

        pub fn create(alloc: *std.mem.Allocator) !Self {
            return Self{
                .alloc = alloc,
                .ptr = try alloc.create(T),
            };
        }

        pub fn createInit(alloc: *std.mem.Allocator, _init: T) !Self {
            const new = Self{
                .alloc = alloc,
                .ptr = try alloc.create(T),
            };
            new.ptr.* = _init;
            return new;
        }

        pub fn deinit(self: *Self) void {
            // Contained item deinit is called if it exists.
            if (@hasDecl(T, "deinit")) {
                self.ptr.deinit();
            }
            self.alloc.destroy(self.ptr);
        }

        pub fn deinitOuter(self: *Self) void {
            self.alloc.destroy(self.ptr);
        }

        pub fn toSized(self: Self) SizedBox {
            return .{
                .ptr = ds.Opaque.fromPtr(*T, self.ptr),
                .size = @sizeOf(T),
                .alloc = self.alloc,
            };
        }
    };
}

pub const SizedBox = struct {
    const Self = @This();

    ptr: *ds.Opaque,
    alloc: *std.mem.Allocator,
    size: u32,

    pub fn deinit(self: *const Self) void {
        const slice = ds.Opaque.toPtr([*]u8, self.ptr)[0..self.size];
        self.alloc.free(slice);
    }
};
