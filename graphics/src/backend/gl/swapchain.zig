const builtin = @import("builtin");
const IsWebGL2 = builtin.target.isWasm();
const IsDesktop = !IsWebGL2;
const platform = @import("platform");
const sdl = @import("sdl");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;

pub const SwapChain = struct {
    w: *platform.Window,
    g: *gpu.Graphics,

    const Self = @This();

    pub fn init(self: *Self, w: *platform.Window, g: *graphics.Graphics) void {
        self.* = .{
            .w = w,
            .g = &g.impl,
        };
    }

    /// In OpenGL, glClear can block if there there are too many commands in the queue.
    pub fn beginFrame(self: Self, cam: graphics.Camera) void {
        gpu.Graphics.beginFrame(self.g, self.w.inner.buf_width, self.w.inner.buf_height, self.w.inner.fbo_id);
        gpu.Graphics.setCamera(self.g, cam);
    }

    pub fn endFrame(self: Self) void {
        gpu.Graphics.endFrame(self.g, self.w.inner.buf_width, self.w.inner.buf_height, self.w.inner.fbo_id);
        if (IsDesktop) {
            // Copy over opengl buffer to window. Also flushes any opengl commands that might be queued.
            // If vsync is enabled, it will also block wait to achieve the target refresh rate (eg. 60fps).
            sdl.SDL_GL_SwapWindow(self.w.inner.sdl_window);
        }
    }
};