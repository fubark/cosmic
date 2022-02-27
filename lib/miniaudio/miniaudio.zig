const std = @import("std");

const log = std.log.scoped(.miniaudio);

const c = @cImport({
    @cInclude("miniaudio.h");
});

pub usingnamespace c;

pub fn assertNoError(res: c.ma_result) void {
    if (res != c.MA_SUCCESS) {
        log.debug("miniaudio: {} {s}", .{res, c.ma_result_description(res)});
        unreachable;
    }
}