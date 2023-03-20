const std = @import("std");
const stdx = @import("stdx.zig");
const t = stdx.testing;

pub fn allocCStrings(alloc: std.mem.Allocator, strs: []const []const u8) ![]u8 {
    const PtrSize = @sizeOf(*u8);
    var num_chars: usize = 0;
    for (strs) |str| {
        num_chars += str.len;
    }
    const res = try alloc.alloc(u8, (strs.len+1) * PtrSize + num_chars + strs.len);
    var data_idx = (strs.len+1) * PtrSize;
    for (strs, 0..) |str, i| {
        std.mem.writeIntNative(usize, res[i*PtrSize..(i+1)*PtrSize][0..PtrSize], @ptrToInt(&res[data_idx]));
        const end_idx = data_idx + str.len;
        std.mem.copy(u8, res[data_idx..end_idx], str);
        res[end_idx] = 0;
        data_idx = end_idx+1;
    }
    std.mem.writeIntNative(usize, res[strs.len*PtrSize..(strs.len+1)*PtrSize][0..PtrSize], 0);
    return res;
}

test "allocCStrings" {
    const buf = try allocCStrings(t.alloc, &.{"foo", "bar"});
    defer t.alloc.free(buf);

    const c_arr = stdx.ptrCastAlign([*c][*c]u8, buf.ptr);
    try t.eqStr(c_arr[0][0..4], "foo" ++ &[_]u8{0});
    try t.eqStr(c_arr[1][0..4], "bar" ++ &[_]u8{0});
    try t.eq(c_arr[2], null);
}
 
pub fn spanOrEmpty(s: [*c]const u8) []const u8 {
    if (s == null) {
        return "";
    } else {
        return std.mem.span(s);
    }
}