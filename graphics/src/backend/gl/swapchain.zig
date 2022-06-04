const builtin = @import("builtin");
const IsWebGL2 = builtin.target.isWasm();
const IsDesktop = !IsWebGL2;
const platform = @import("platform");
const sdl = @import("sdl");

pub const SwapChain = struct {
    win: *platform.Window,

    const Self = @This();

    pub fn init(self: *Self, win: *platform.Window) void {
        self.* = .{
            .win = win,
        };
    }

    pub fn beginFrame(_: Self) void {
    }

    pub fn endFrame(self: Self) void {
        if (IsDesktop) {
            // Copy over opengl buffer to window. Also flushes any opengl commands that might be queued.
            // If vsync is enabled, it will also block wait to achieve the target refresh rate (eg. 60fps).
            sdl.SDL_GL_SwapWindow(self.win.impl.sdl_window);
        }
    }
};