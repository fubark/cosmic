const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const platform = @import("platform");
const vk = @import("vk");

const graphics = @import("graphics.zig");
const gpu = graphics.gpu;
const gvk = graphics.vk;
const ggl = graphics.gl;

pub const Renderer = struct {
    gctx: graphics.Graphics,
    inner: switch (Backend) {
        .Vulkan => struct {
            ctx: gvk.VkContext,
            vk: gvk.Renderer,
        },
        .OpenGL => struct {
            renderer: ggl.Renderer,
        },
        else => void,
    },

    // TODO: Remove swapchain and window dependency.
    pub fn initVK(self: *Renderer, alloc: std.mem.Allocator, swapc: graphics.SwapChain, win: *platform.Window) !void {
        self.inner.vk = try gvk.Renderer.init(alloc, win, swapc);
        const vk_ctx = gvk.VkContext.init(alloc, win);
        self.inner.ctx = vk_ctx;
        self.gctx.initVK(alloc, win.impl.dpr, &self.inner.vk, vk_ctx);
    }

    pub fn init(self: *Renderer, alloc: std.mem.Allocator, dpr: f32) !void {
        switch (Backend) {
            .OpenGL => {
                try self.inner.renderer.init(alloc);
                try self.gctx.init(alloc, dpr, &self.inner.renderer);
            },
            else => {},
        }
    }

    pub fn deinit(self: *Renderer, alloc: std.mem.Allocator) void {
        self.gctx.deinit();
        switch (Backend) {
            .Vulkan => self.inner.vk.deinit(alloc),
            .OpenGL => {
                self.inner.renderer.deinit(alloc);
            },
            else => {},
        }
    }

    pub fn getGraphics(self: *Renderer) *graphics.Graphics {
        return &self.gctx;
    }
};

/// A WindowRenderer abstracts how and where a frame is drawn to and provides:
/// 1. An interface to begin/end a frame.
/// 2. A graphics context to paint things to a frame.
/// 3. TODO: If the window resizes, it is responsible for adjusting the framebuffers and graphics context.
/// 4. TODO: Measuring fps should probably be here.
pub const WindowRenderer = struct {
    swapchain: graphics.SwapChain,
    renderer: Renderer,
    win: *platform.Window,

    /// Creates a renderer that targets a window.
    pub fn init(self: *WindowRenderer, alloc: std.mem.Allocator, win: *platform.Window) !void {
        self.win = win;
        switch (Backend) {
            .Vulkan => {
                self.swapchain.initVK(alloc, win);
                try self.renderer.initVK(alloc, self.swapchain, win);
            },
            .OpenGL => {
                self.swapchain.init(alloc, win);
                try self.renderer.init(alloc, win.impl.dpr);
            },
            else => {},
        }
    }

    pub fn deinit(self: *WindowRenderer, alloc: std.mem.Allocator) void {
        // Deinit swapchain first to make sure there aren't any pending resources in use.
        self.swapchain.deinit(alloc);
        self.renderer.deinit(alloc);
    }

    pub fn getGraphics(self: *WindowRenderer) *graphics.Graphics {
        return self.renderer.getGraphics();
    }
    
    /// Start of frame with a camera view.
    pub inline fn beginFrame(self: *WindowRenderer, cam: graphics.Camera) void {
        self.swapchain.beginFrame();
        switch (Backend) {
            .Vulkan => {
                const cur_image_idx = self.swapchain.impl.cur_image_idx;
                const cur_frame_idx = self.swapchain.impl.cur_frame_idx;
                const framebuffer = self.inner.vk.framebuffers[cur_image_idx];
                gpu.Graphics.beginFrameVK(&self.renderer.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, cur_frame_idx, framebuffer);
            },
            .OpenGL => {
                // In OpenGL, glClear can block if there there are too many commands in the queue.
                gpu.Graphics.beginFrame(&self.renderer.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, self.win.impl.fbo_id);
            },
            else => stdx.unsupported(),
        }
        gpu.Graphics.setCamera(&self.renderer.gctx.impl, cam);
    }

    /// End of frame, flush to framebuffer.
    pub inline fn endFrame(self: *WindowRenderer) void {
        switch (Backend) {
            .Vulkan => {
                const frame_res = gpu.Graphics.endFrameVK(&self.gctx.impl);

                const cur_frame_idx = self.swapchain.impl.cur_frame_idx;

                // Submit command.
                const wait_stage_flag = @intCast(u32, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
                const frame = self.inner.vk.frames[cur_frame_idx];

                // Only submit shadow command if work was recorded.
                const cmd_bufs: []const vk.VkCommandBuffer = if (frame_res.submit_shadow_cmd) &[_]vk.VkCommandBuffer{
                    frame.shadow_cmd_buf,
                    frame.main_cmd_buf,
                } else &[_]vk.VkCommandBuffer{
                    frame.main_cmd_buf,
                };
                const submit_info = vk.VkSubmitInfo{
                    .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .waitSemaphoreCount = 1,
                    .pWaitSemaphores = &self.swapchain.impl.image_available_semas[cur_frame_idx],
                    .pWaitDstStageMask = &wait_stage_flag,
                    .commandBufferCount = @intCast(u32, cmd_bufs.len),
                    .pCommandBuffers = cmd_bufs.ptr,
                    .signalSemaphoreCount = 1,
                    .pSignalSemaphores = &self.swapchain.impl.render_finished_semas[cur_frame_idx],
                    .pNext = null,
                };
                const res = vk.queueSubmit(self.inner.vk.graphics_queue, 1, &submit_info, self.swapchain.impl.inflight_fences[cur_frame_idx]);
                vk.assertSuccess(res);
            },
            .OpenGL => {
                gpu.Graphics.endFrame(&self.renderer.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, self.win.impl.fbo_id);
            },
            else => stdx.unsupported(),
        }
        self.swapchain.endFrame();
    }
};

pub const FrameResultVK = struct {
    submit_shadow_cmd: bool,
};