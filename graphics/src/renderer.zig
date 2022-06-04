const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const platform = @import("platform");
const vk = @import("vk");

const graphics = @import("graphics.zig");
const gpu = graphics.gpu;
const gvk = graphics.vk;

/// A Renderer abstracts how and where a frame is drawn to and provides:
/// 1. An interface to begin/end a frame.
/// 2. A graphics context to paint things to a frame.
/// 3. TODO: If the window resizes, it is responsible for adjusting the framebuffers and graphics context.
/// 4. TODO: Measuring fps should probably be here.
pub const Renderer = struct {
    swapchain: graphics.SwapChain,
    gctx: graphics.Graphics,
    win: *platform.Window,
    inner: switch (Backend) {
        .Vulkan => struct {
            ctx: gvk.VkContext,
        },
        .OpenGL => struct {},
        else => @compileError("unsupported"),
    },

    const Self = @This();

    /// Creates a renderer that targets a window.
    pub fn init(self: *Self, alloc: std.mem.Allocator, win: *platform.Window) void {
        self.win = win;
        if (Backend == .Vulkan) {
            self.swapchain.initVK(alloc, win);
            
            const vk_ctx = gvk.VkContext.init(alloc, win, self.swapchain);
            self.inner.ctx = vk_ctx;

            self.gctx.initVK(alloc, win.impl.dpr, vk_ctx);
        } else {
            self.swapchain.init(alloc, win);
            self.gctx.init(alloc, win.impl.dpr);
        }
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        // Deinit swapchain first to make sure there aren't any pending resources in use.
        self.swapchain.deinit(alloc);
        self.gctx.deinit();
        if (Backend == .Vulkan) {
            self.inner.ctx.deinit(alloc);
        }
    }

    pub fn getGraphics(self: *Self) *graphics.Graphics {
        return &self.gctx;
    }
    
    /// Start of frame with a camera view.
    pub inline fn beginFrame(self: *Self, cam: graphics.Camera) void {
        self.swapchain.beginFrame();
        switch (Backend) {
            .Vulkan => {
                const cur_image_idx = self.swapchain.impl.cur_image_idx;
                const cur_frame_idx = self.swapchain.impl.cur_frame_idx;
                gpu.Graphics.beginFrameVK(&self.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, cur_image_idx, cur_frame_idx);
            },
            .OpenGL => {
                // In OpenGL, glClear can block if there there are too many commands in the queue.
                gpu.Graphics.beginFrame(&self.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, self.win.impl.fbo_id);
            },
            else => stdx.unsupported(),
        }
        gpu.Graphics.setCamera(&self.gctx.impl, cam);
    }

    /// End of frame, flush to framebuffer.
    pub inline fn endFrame(self: *Self) void {
        switch (Backend) {
            .Vulkan => {
                gpu.Graphics.endFrameVK(&self.gctx.impl);

                const cur_image_idx = self.swapchain.impl.cur_image_idx;
                const cur_frame_idx = self.swapchain.impl.cur_frame_idx;

                // Submit command.
                const wait_stage_flag = @intCast(u32, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
                const submit_info = vk.VkSubmitInfo{
                    .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .waitSemaphoreCount = 1,
                    .pWaitSemaphores = &self.swapchain.impl.image_available_semas[cur_frame_idx],
                    .pWaitDstStageMask = &wait_stage_flag,
                    .commandBufferCount = 1,
                    .pCommandBuffers = &self.inner.ctx.cmd_bufs[cur_image_idx],
                    .signalSemaphoreCount = 1,
                    .pSignalSemaphores = &self.swapchain.impl.render_finished_semas[cur_frame_idx],
                    .pNext = null,
                };
                const res = vk.queueSubmit(self.inner.ctx.graphics_queue, 1, &submit_info, self.swapchain.impl.inflight_fences[cur_frame_idx]);
                vk.assertSuccess(res);
            },
            .OpenGL => {
                gpu.Graphics.endFrame(&self.gctx.impl, self.win.impl.buf_width, self.win.impl.buf_height, self.win.impl.fbo_id);
            },
            else => stdx.unsupported(),
        }
        self.swapchain.endFrame();
    }
};
