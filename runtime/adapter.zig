const std = @import("std");
const v8 = @import("v8");

const runtime = @import("runtime.zig");

// TODO: Move other types here from runtime.zig

// ------
// Types used to import into native code.
// ------

/// Contains the v8.Object of the js function's this.
pub const This = struct {
    obj: v8.Object,
};

/// Contains the v8.Object and the matching value type.
pub fn ThisValue(comptime T: type) type {
    return struct {
        pub const ThisValue = true;

        obj: v8.Object,
        val: T,
    };
}

/// Contains the v8.Object of the js function's this and the resource that it is bound to (id from the first internal field).
pub fn ThisResource(comptime Tag: runtime.ResourceTag) type {
    return struct {
        pub const ThisResource = true;

        res_id: runtime.ResourceId,
        res: *runtime.Resource(Tag),
        obj: v8.Object,
    };
}

/// Contains the v8.Object of the js function's this and the weak handle that it is bound to (id from the first internal field).
pub fn ThisHandle(comptime Tag: runtime.WeakHandleTag) type {
    return struct {
        pub const ThisHandle = true;

        id: runtime.WeakHandleId,
        ptr: runtime.WeakHandlePtr(Tag),
        obj: v8.Object,
    };
}

/// Contains the v8.Object of an arg and the weak handle that it is bound to (id from the first internal field).
pub fn Handle(comptime Tag: runtime.WeakHandleTag) type {
    return struct {
        pub const Handle = true;

        id: runtime.WeakHandleId,
        ptr: runtime.WeakHandlePtr(Tag),
        obj: v8.Object,
    };
}

/// Contains the v8.Function data unconverted.
pub const FuncData = struct {
    val: v8.Value,
};

/// Contains a pointer converted from v8.Function data's second internal field.
/// The first internal field is reserved for the rt pointer.
pub fn FuncDataUserPtr(comptime Ptr: type) type {
    return struct {
        pub const FuncDataUserPtr = true;

        ptr: Ptr,
    };
}

// ------
// Types used to export to js.
// ------

/// Contains a v8.Promise that will be returned to js.
/// Auto generation for async function wrappers will exclude functions with this return type.
pub const PromiseSkipJsGen = struct {
    inner: v8.Promise,
};

/// A temp struct that will call deinit with the runtime's allocator after converting to js.
pub fn RtTempStruct(comptime T: type) type {
    return struct {
        pub const RtTempStruct = true;

        inner: T,

        pub fn init(inner: T) @This() {
            return .{ .inner = inner };
        }

        pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
            self.inner.deinit(alloc);
        }
    };
}

/// A slice that knows how to deinit itself and it's items.
pub fn ManagedSlice(comptime T: type) type {
    return struct {
        pub const ManagedSlice = true;

        alloc: std.mem.Allocator,
        slice: []const T,

        pub fn deinit(self: @This()) void {
            for (self.slice) |it| {
                it.deinit(self.alloc);
            }
            self.alloc.free(self.slice);
        }
    };
}
/// A struct that knows how to deinit itself.
pub fn ManagedStruct(comptime T: type) type {
    return struct {
        pub const ManagedStruct = true;

        alloc: std.mem.Allocator,
        val: T,

        pub fn init(alloc: std.mem.Allocator, val: T) @This() {
            return .{ .alloc = alloc, .val = val };
        }

        pub fn deinit(self: @This()) void {
            self.val.deinit(self.alloc);
        }
    };
}