const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;
const log = stdx.log.scoped(.meta);

pub fn ChildOrStruct(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Struct => T,
        .Optional => |info| info.child,
        else => @compileError("Unsupported: " ++ @typeName(T)),
    };
}

pub fn assertPointerType(comptime T: type) void {
    if (@typeInfo(T) != .Pointer) {
        @compileError("Expected Pointer type.");
    }
}

pub fn assertFunctionType(comptime T: type) void {
    if (@typeInfo(T) != .Fn) {
        @compileError("Expected Function type.");
    }
}

pub fn hasFunctionSignature(comptime ExpFunc: type, comptime Func: type) bool {
    if (FnNumParams(ExpFunc) != FnNumParams(Func)) {
        return false;
    }
    return stdx.mem.eql(std.builtin.Type.Fn.Param, FnParams(ExpFunc), FnParams(Func));
}

pub fn isFunc(comptime Fn: type) bool {
    return @typeInfo(Fn) == .Fn;
}

pub fn FnParamAt(comptime Fn: type, comptime idx: u32) type {
    assertFunctionType(Fn);
    const Params = comptime FnParams(Fn);
    if (Params.len <= idx) {
        @compileError(std.fmt.comptimePrint("Expected {} params for function.", .{idx + 1}));
    }
    return Params[idx].type.?;
}

pub const FnParamsTuple = std.meta.ArgsTuple;

pub fn FnParams(comptime Fn: type) []const std.builtin.Type.Fn.Param {
    return @typeInfo(Fn).Fn.params;
}

pub fn FnNumParams(comptime Fn: type) u32 {
    return @typeInfo(Fn).Fn.params.len;
}

pub fn FnReturn(comptime Fn: type) type {
    return @typeInfo(Fn).Fn.return_type.?;
}

pub fn FnWithPrefixParam(comptime Fn: type, comptime Param: type) type {
    assertFunctionType(Fn);
    const FnParam = std.builtin.Type.Fn.Param{
        .is_generic = false,
        .is_noalias = false,
        .type = Param,
    };
    return @Type(.{
        .Fn = .{
            .calling_convention = .Unspecified,
            .alignment = 0,
            .is_generic = false,
            .is_var_args = false,
            .return_type = FnReturn(Fn),
            .params = &[_]std.builtin.Type.Fn.Param{FnParam} ++ @typeInfo(Fn).Fn.params,
        },
    });
}

pub fn FnAfterFirstParam(comptime Fn: type) type {
    assertFunctionType(Fn);
    return @Type(.{
        .Fn = .{
            .calling_convention = .Unspecified,
            .alignment = 0,
            .is_generic = false,
            .is_var_args = false,
            .return_type = FnReturn(Fn),
            .params = &[_]std.builtin.Type.Fn.Param{} ++ @typeInfo(Fn).Fn.params[1..],
        },
    });
}

pub fn FieldType(comptime T: type, comptime Field: std.meta.FieldEnum(T)) type {
    return std.meta.fieldInfo(T, Field).type;
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

/// Generate a unique id for an enum literal.
/// This should work in debug and release modes.
pub fn enumLiteralId(comptime T: @Type(.EnumLiteral)) usize {
    _ = T;
    const S = struct {
        pub var id: u8 = 0;
    };
    return @ptrToInt(&S.id);
}

test "enumLiteralId" {
    try t.eq(enumLiteralId(.foo), enumLiteralId(.foo));
    try t.neq(enumLiteralId(.foo), enumLiteralId(.bar));
}

pub fn TupleLen(comptime T: type) usize {
    return @typeInfo(T).Struct.fields.len;
}

pub fn CanCoalesceToSlice(comptime SliceItem: type, comptime T: type) bool {
    if (T == []const SliceItem) {
        return true;
    }
    if (@typeInfo(T) == .Pointer) {
        const ChildInfo = @typeInfo(@typeInfo(T).Pointer.child);
        if (ChildInfo == .Array and ChildInfo.Array.child == SliceItem) {
            return true;
        }
    }
    return false;
}