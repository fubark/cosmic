const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const vk = @import("vk");
const platform = @import("platform");
const graphics = @import("../../graphics.zig");
const gvk = graphics.vk;

pub const Frame = struct {
    main_cmd_buf: vk.VkCommandBuffer,
    shadow_cmd_buf: vk.VkCommandBuffer,
    framebuffer: vk.VkFramebuffer,
    submit_shadow_cmd: bool,

    fn deinit(self: Frame, device: vk.VkDevice) void {
        vk.destroyFramebuffer(device, self.framebuffer, null);
    }
};

pub const Renderer = struct {
    physical: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    cmd_pool: vk.VkCommandPool,
    frames: []Frame,
    fb_size: vk.VkExtent2D,
    main_pass: vk.VkRenderPass,

    graphics_queue: vk.VkQueue,

    /// Default samplers.
    linear_sampler: vk.VkSampler,
    nearest_sampler: vk.VkSampler,

    pub fn init(alloc: std.mem.Allocator, win: *platform.Window, swapchain: graphics.SwapChain) Renderer {
        const physical = win.impl.inner.physical_device;
        const device = win.impl.inner.device;
        const queue_family = win.impl.inner.queue_family;
        const num_frame_images = @intCast(u32, swapchain.impl.images.len);

        var ret = Renderer{
            .physical = physical,
            .device = device,
            .cmd_pool = gvk.command.createCommandPool(device, queue_family),
            .frames = alloc.alloc(Frame, num_frame_images) catch fatal(),
            .fb_size = swapchain.impl.buf_dim,
            .main_pass = gvk.renderpass.createRenderPass(device, swapchain.impl.buf_format),
            .linear_sampler = gvk.image.createDefaultTextureSampler(device, true),
            .nearest_sampler = gvk.image.createDefaultTextureSampler(device, false),
            .graphics_queue = undefined,
        };

        vk.getDeviceQueue(device, queue_family.graphics_family.?, 0, &ret.graphics_queue);

        const cmd_bufs = gvk.command.createCommandBuffers(alloc, device, ret.cmd_pool, num_frame_images * 2);
        defer alloc.free(cmd_bufs);
        for (ret.frames) |_, i| {
            ret.frames[i].main_cmd_buf = cmd_bufs[i * 2];
            ret.frames[i].shadow_cmd_buf = cmd_bufs[i * 2 + 1];
            const attachments = &[_]vk.VkImageView{
                swapchain.impl.image_views[i],
                swapchain.impl.depth_image_views[i],
            };
            ret.frames[i].framebuffer = gvk.framebuffer.createFramebuffer(device, ret.main_pass, ret.fb_size.width, ret.fb_size.height, attachments);
            ret.frames[i].submit_shadow_cmd = false;
        }
        return ret;
    }

    pub fn deinit(self: Renderer, alloc: std.mem.Allocator) void {
        for (self.frames) |frame| {
            frame.deinit(self.device);
        }
        vk.destroyCommandPool(self.device, self.cmd_pool, null);
        alloc.free(self.frames);
        vk.destroyRenderPass(self.device, self.main_pass, null);
        vk.destroySampler(self.device, self.linear_sampler, null);
        vk.destroySampler(self.device, self.nearest_sampler, null);
    }

    pub fn beginSingleTimeCommands(self: Renderer) vk.VkCommandBuffer {
        const alloc_info = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.cmd_pool,
            .commandBufferCount = 1,
            .pNext = null,
        };

        var ret: vk.VkCommandBuffer = undefined;
        var res = vk.allocateCommandBuffers(self.device, &alloc_info, &ret);
        vk.assertSuccess(res);

        const begin_info = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pNext = null,
            .pInheritanceInfo = null,
        };
        res = vk.beginCommandBuffer(ret, &begin_info);
        vk.assertSuccess(res);
        return ret;
    }

    pub fn endSingleTimeCommands(self: Renderer, cmd_buf: vk.VkCommandBuffer) void {
        var res = vk.endCommandBuffer(cmd_buf);
        vk.assertSuccess(res);

        const submit_info = vk.VkSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &cmd_buf,
            .pNext = null,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
            .pWaitDstStageMask = 0,
        };
        res = vk.queueSubmit(self.graphics_queue, 1, &submit_info, null);
        vk.assertSuccess(res);
        res = vk.queueWaitIdle(self.graphics_queue);
        vk.assertSuccess(res);

        vk.freeCommandBuffers(self.device, self.cmd_pool, 1, &cmd_buf);
    }
};