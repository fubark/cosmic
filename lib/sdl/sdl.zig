const std = @import("std");

// c header imports should be wrapped in a common zig file that others import. See: https://github.com/ziglang/zig/issues/3394
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cDefine("GL_GLEXT_PROTOTYPES", ""); // Includes ext functions, eg. glGenVertexArrays
    @cInclude("SDL2/SDL_opengl.h");
});

pub usingnamespace c;

// Convenience entry point that takes in a slice assumed to end with null char.
pub fn createWindow(alloc: *std.mem.Allocator, title: []const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: c.Uint32) ?*c.SDL_Window {
    const title_null = std.cstr.addNullByte(alloc, title) catch unreachable;
    defer alloc.free(title_null);
    return c.SDL_CreateWindow(title_null, x, y, w, h, flags);
}
