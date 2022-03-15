const v8 = @import("v8");

// TODO: Move other types here from runtime.zig

// Types for conversion to js.

pub const PromiseSkipJsGen = struct {
    inner: v8.Promise,
};