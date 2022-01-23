const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.meta);

pub fn FunctionArgs(comptime Fn: type) []const std.builtin.TypeInfo.FnArg {
    return @typeInfo(Fn).Fn.args;
}

pub fn FunctionReturnType(comptime Fn: type) type {
    return @typeInfo(Fn).Fn.return_type.?;
}

pub fn FieldType(comptime T: type, comptime Field: std.meta.FieldEnum(T)) type {
    return std.meta.fieldInfo(T, Field).field_type;
}

/// Generate a unique type id.
/// This should work in debug and release modes.
pub fn TypeId(comptime T: type) usize {
    const S = struct {
        fn Type(comptime _: type) type {
            return struct { pub var uniq: u8 = 0; };
        }
    };
    return @ptrToInt(&S.Type(T).uniq);
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
