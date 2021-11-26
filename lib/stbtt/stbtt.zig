const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub usingnamespace c;

pub const fontinfo = c.stbtt_fontinfo;

// Convenience entry point that takes in a slice assumed to end with null char.
pub fn InitFont(info: [*c]fontinfo, data: []const u8, offset: c_int) !void {
    if (data[data.len-1] != 0) {
        return error.BadDataInput;
    }
    const ptr = @ptrCast([*c]const u8, data.ptr);
    if (c.stbtt_InitFont(info, ptr, offset) == 0) {
        return error.InitError;
    }
}