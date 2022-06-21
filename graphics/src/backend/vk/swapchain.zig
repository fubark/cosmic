const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const platform = @import("platform");
const vk = @import("vk");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const gvk = graphics.vk;
const log = stdx.log.scoped(.swapchain);

pub const SwapChain = struct {
    w: *platform.Window,

    swapchain: vk.VkSwapchainKHR,

    image_available_semas: [gpu.MaxActiveFrames]vk.VkSemaphore,
    render_finished_semas: [gpu.MaxActiveFrames]vk.VkSemaphore,
    inflight_fences: [gpu.MaxActiveFrames]vk.VkFence,

    images: []vk.VkImage,
    image_views: []vk.VkImageView,

    depth_images: []vk.VkImage,
    depth_images_mem: []vk.VkDeviceMemory,
    depth_image_views: []vk.VkImageView,

    buf_format: vk.VkFormat,
    buf_dim: vk.VkExtent2D,

    device: vk.VkDevice,
    cur_frame_idx: u32,
    cur_image_idx: u32,
    present_queue: vk.VkQueue,

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator, w: *platform.Window) void {
        self.* = .{
            .w = w,
            .image_available_semas = undefined,
            .render_finished_semas = undefined,
            .inflight_fences = undefined,
            .buf_format = undefined,
            .buf_dim = undefined,
            .images = undefined,
            .image_views = undefined,
            .depth_images = undefined,
            .depth_images_mem = undefined,
            .depth_image_views = undefined,
            .cur_frame_idx = 0,
            .device = w.impl.inner.device,
            .swapchain = undefined,
            .cur_image_idx = 0,
            .present_queue = undefined,
        };

        const physical = w.impl.inner.physical_device;
        const surface = w.impl.inner.surface;
        const device = w.impl.inner.device;
        const queue_family = w.impl.inner.queue_family;

        vk.getDeviceQueue(device, queue_family.present_family.?, 0, &self.present_queue);

        const swapc_info = platform.window_sdl.vkQuerySwapChainSupport(alloc, physical, surface);
        defer swapc_info.deinit(alloc);

        const surface_format = swapc_info.getDefaultSurfaceFormat();
        self.buf_format = surface_format.format;
        const present_mode = swapc_info.getDefaultPresentMode();
        self.buf_dim = swapc_info.getDefaultExtent();

        var image_count: u32 = swapc_info.capabilities.minImageCount + 1;
        if (swapc_info.capabilities.maxImageCount > 0 and image_count > swapc_info.capabilities.maxImageCount) {
            image_count = swapc_info.capabilities.maxImageCount;
        }

        const queue_family_idxes = [_]u32{ queue_family.graphics_family.?, queue_family.present_family.? };
        // const different_families = indices.graphicsFamily.? != indices.presentFamily.?;
        const different_families = false;

        var swapc_create_info = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = w.impl.inner.surface,
            .minImageCount = image_count,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = self.buf_dim,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = if (different_families) vk.VK_SHARING_MODE_CONCURRENT else vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = if (different_families) @as(u32, 2) else @as(u32, 0),
            .pQueueFamilyIndices = if (different_families) &queue_family_idxes else &([_]u32{ 0, 0 }),
            .preTransform = swapc_info.capabilities.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = vk.VK_TRUE,
            .oldSwapchain = null,
            .pNext = null,
            .flags = 0,
        };

        var res = vk.createSwapchainKHR(device, &swapc_create_info, null, &self.swapchain);
        vk.assertSuccess(res);

        res = vk.getSwapchainImagesKHR(device, self.swapchain, &image_count, null);
        vk.assertSuccess(res);
        self.images = alloc.alloc(vk.VkImage, image_count) catch fatal();
        res = vk.getSwapchainImagesKHR(device, self.swapchain, &image_count, self.images.ptr);
        vk.assertSuccess(res);

        // Create image views.
        self.image_views = alloc.alloc(vk.VkImageView, self.images.len) catch fatal();
        for (self.images) |image, i| {
            self.image_views[i] = gvk.image.createDefaultImageView(device, image, self.buf_format);
        }

        self.depth_images = alloc.alloc(vk.VkImage, image_count) catch fatal();
        self.depth_images_mem = alloc.alloc(vk.VkDeviceMemory, image_count) catch fatal();
        self.depth_image_views = alloc.alloc(vk.VkImageView, image_count) catch fatal();
        for (self.depth_images) |_, i| {
            const image = gvk.image.createDefaultImage(physical, device, self.buf_dim.width, self.buf_dim.height, vk.VK_FORMAT_D32_SFLOAT, vk.VK_IMAGE_TILING_OPTIMAL,
                vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
            self.depth_images[i] = image.image;
            self.depth_images_mem[i] = image.mem;
            self.depth_image_views[i] = gvk.image.createDefaultImageView(device, self.depth_images[i], vk.VK_FORMAT_D32_SFLOAT);
        }

        createSyncObjects(self);
    }

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        // Wait on all frame fences first.
        const res = vk.waitForFences(self.device, self.inflight_fences.len, &self.inflight_fences, vk.VK_TRUE, std.math.maxInt(u64));
        vk.assertSuccess(res);

        for (self.image_available_semas) |sema| {
            vk.destroySemaphore(self.device, sema, null);
        }

        for (self.render_finished_semas) |sema| {
            vk.destroySemaphore(self.device, sema, null);
        }

        for (self.inflight_fences) |fence| {
            vk.destroyFence(self.device, fence, null);
        }

        for (self.depth_image_views) |image_view| {
            vk.destroyImageView(self.device, image_view, null);
        }
        alloc.free(self.depth_image_views);

        for (self.depth_images) |image| {
            vk.destroyImage(self.device, image, null);
        }
        alloc.free(self.depth_images);

        for (self.depth_images_mem) |mem| {
            vk.freeMemory(self.device, mem, null);
        }
        alloc.free(self.depth_images_mem);

        for (self.image_views) |image_view| {
            vk.destroyImageView(self.device, image_view, null);
        }
        alloc.free(self.image_views);

        // images are destroyed from destroySwapchainKHR.
        alloc.free(self.images);

        vk.destroySwapchainKHR(self.device, self.swapchain, null);
    }

    /// Waits to get the next available swapchain image idx.
    pub fn beginFrame(self: *Self) void {
        var res = vk.waitForFences(self.device, 1, &self.inflight_fences[self.cur_frame_idx], vk.VK_TRUE, std.math.maxInt(u64));
        vk.assertSuccess(res);
        res = vk.resetFences(self.device, 1, &self.inflight_fences[self.cur_frame_idx]);
        vk.assertSuccess(res);

        res = vk.acquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64), self.image_available_semas[self.cur_frame_idx], null, &self.cur_image_idx);
        vk.assertSuccess(res);
    }

    pub fn endFrame(self: *Self) void {
        const present_info = vk.VkPresentInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.render_finished_semas[self.cur_frame_idx],
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &self.cur_image_idx,
            .pNext = null,
            .pResults = null,
        };
        const res = vk.queuePresentKHR(self.present_queue, &present_info);
        vk.assertSuccess(res);
        self.cur_frame_idx = (self.cur_frame_idx + 1) % gpu.MaxActiveFrames;
    }
};

fn createSyncObjects(swapchain: *SwapChain) void {
    const sema_info = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    const fence_info = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
        .pNext = null,
    };

    const device = swapchain.w.impl.inner.device;

    var i: usize = 0;
    var res: vk.VkResult = undefined;
    while (i < gpu.MaxActiveFrames) : (i += 1) {
        res = vk.createSemaphore(device, &sema_info, null, &swapchain.image_available_semas[i]);
        vk.assertSuccess(res);
        res = vk.createSemaphore(device, &sema_info, null, &swapchain.render_finished_semas[i]);
        vk.assertSuccess(res);
        res = vk.createFence(device, &fence_info, null, &swapchain.inflight_fences[i]);
        vk.assertSuccess(res);
    }
}
