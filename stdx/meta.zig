const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

pub fn FunctionArgs(comptime Fn: type) []const std.builtin.TypeInfo.FnArg {
    return @typeInfo(Fn).Fn.args;
}

pub fn FunctionReturnType(comptime Fn: type) type {
    return @typeInfo(Fn).Fn.return_type.?;
}

/// Generate a unique type id.
pub fn TypeId(comptime T: type) usize {
    _ = T;
    const S = struct {
        const id: u8 = undefined;
    };
    return @ptrToInt(&S.id);
}

test "typeId" {
    const S = struct {};
    const a = S;
    const b = S;
    try t.eq(TypeId(a), TypeId(b));
    try t.neq(TypeId(a), TypeId(struct {}));
}

pub fn TupleLen(comptime T: type) usize {
    return @typeInfo(T).Struct.fields.len;
}
