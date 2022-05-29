const std = @import("std");
const stdx = @import("stdx");
const log_ = stdx.log.scoped(.sdl);

const build_options = @import("build_options");

// c header imports should be wrapped in a common zig file that others import. See: https://github.com/ziglang/zig/issues/3394
const c = @cImport({
    @cInclude("SDL.h");
    @cDefine("GL_GLEXT_PROTOTYPES", ""); // Includes ext functions, eg. glGenVertexArrays
    @cInclude("SDL_opengl.h");
    @cInclude("SDL_vulkan.h");
});

pub usingnamespace c;

// Convenience entry point that takes in a slice assumed to end with null char.
pub fn createWindow(alloc: std.mem.Allocator, title: []const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: c.Uint32) ?*c.SDL_Window {
    const title_null = std.cstr.addNullByte(alloc, title) catch unreachable;
    defer alloc.free(title_null);
    return c.SDL_CreateWindow(title_null, x, y, w, h, flags);
}

var inited_video = false;

pub fn ensureVideoInit() !void {
    if (!inited_video) {
        if (c.SDL_InitSubSystem(c.SDL_INIT_VIDEO) != 0) {
            log_.err("SDL_InitSubSystem Video: {s}", .{c.SDL_GetError()});
            return error.FailedSdlInit;
        }
        inited_video = true;
    }
}