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