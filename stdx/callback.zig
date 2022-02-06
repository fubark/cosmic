
/// Like a closure except the context isn't allocated.
pub fn Callback(comptime Context: type, comptime Param: type) type {
    return struct {
        const Self = @This();

        user_fn: fn (Context, Param) void,
        ctx: Context,

        pub fn init(ctx: Context, user_fn: fn (Context, Param) void) Self {
            return .{
                .user_fn = user_fn,
                .ctx = ctx,
            };
        }

        pub fn call(self: Self, arg: Param) void {
            self.user_fn(self.ctx, arg);
        }
    };
}