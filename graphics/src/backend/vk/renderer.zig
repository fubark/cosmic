const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const vk = @import("vk");
const platform = @import("platform");
const glslang = @import("glslang");

const graphics = @import("../../graphics.zig");
const gvk = graphics.vk;
const gpu = graphics.gpu;

/// Having 2 frames "in flight" to draw on allows the cpu and gpu to work in parallel. More than 2 is not recommended right now.
/// This doesn't have to match the number of swap chain images/framebuffers. This indicates the max number of frames that can be active at any moment.
/// Once this limit is reached, the cpu will block until the gpu is done with the oldest frame.
/// Currently used explicitly by the Vulkan implementation.
pub const MaxActiveFrames = 2;

var inited_global = false;

fn initGlobal() !void {
    if (!inited_global) {
        const res = glslang.glslang_initialize_process();
        if (res == 0) {
            return error.GlslangInitFailed;
        }
        inited_global = true;
    }
}

fn deinitGlobal() void {
    if (inited_global) {
        glslang.glslang_finalize_process();
        inited_global = false;
    }
}

/// Resources needed to render a frame.
pub const Frame = struct {
    main_cmd_buf: vk.VkCommandBuffer,

    /// Shadows.
    shadow_cmd_buf: vk.VkCommandBuffer,
    shadow_framebuffer: vk.VkFramebuffer,
    shadow_image: gvk.image.Image,
    shadow_image_view: vk.VkImageView,
    shadowmap_desc_set: vk.VkDescriptorSet,

    u_cam_buf: gvk.Buffer,
    cam_desc_set: vk.VkDescriptorSet,

    fn deinit(self: Frame, device: vk.VkDevice) void {
        self.u_cam_buf.deinit(device);

        // Shadows deinit.
        vk.destroyFramebuffer(device, self.shadow_framebuffer, null);
        self.shadow_image.deinit(device);
        vk.destroyImageView(device, self.shadow_image_view, null);
    }
};

// TODO: Gradually move renderer resources like buffers, desc layouts, desc sets, pipelines here.
pub const Renderer = struct {
    physical: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    cmd_pool: vk.VkCommandPool,
    frames: []Frame,

    desc_pool: vk.VkDescriptorPool,

    cam_desc_set_layout: vk.VkDescriptorSetLayout,

    /// Number of final framebuffers match number of swapchain images.
    framebuffers: []vk.VkFramebuffer,
    fb_size: vk.VkExtent2D,

    main_pass: vk.VkRenderPass,

    graphics_queue: vk.VkQueue,

    /// Shadows.
    shadow_pass: vk.VkRenderPass,
    shadow_sampler: vk.VkSampler, // Clamps to border so out of bounds returns no shadows.
    shadowmap_desc_set_layout: vk.VkDescriptorSetLayout,

    /// Default samplers.
    linear_sampler: vk.VkSampler,
    nearest_sampler: vk.VkSampler,

    pub const ShadowMapSize = 2048;
    const ShadowMapFormat = vk.VK_FORMAT_D32_SFLOAT; // 16bit depth value. May need to increase.

    pub fn init(alloc: std.mem.Allocator, win: *platform.Window, swapchain: graphics.SwapChain) !Renderer {
        try initGlobal();

        const physical = win.impl.inner.physical_device;
        const device = win.impl.inner.device;
        const queue_family = win.impl.inner.queue_family;
        const num_framebuffers = @intCast(u32, swapchain.impl.images.len);

        var ret = Renderer{
            .physical = physical,
            .device = device,
            .cmd_pool = gvk.command.createCommandPool(device, queue_family),
            .desc_pool = gvk.createDescriptorPool(device),
            .frames = try alloc.alloc(Frame, MaxActiveFrames),
            .framebuffers = try alloc.alloc(vk.VkFramebuffer, num_framebuffers),
            .fb_size = swapchain.impl.buf_dim,
            .main_pass = gvk.renderpass.createRenderPass(device, swapchain.impl.buf_format),
            .linear_sampler = gvk.image.createTextureSampler(device, .{ .linear_filter = true }),
            .nearest_sampler = gvk.image.createTextureSampler(device, .{ .linear_filter = false }),
            .shadow_sampler = gvk.image.createTextureSampler(device, .{ .linear_filter = true, .address_mode = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER }),
            .shadowmap_desc_set_layout = gvk.createShadowMapDescriptorSetLayout(device),
            .cam_desc_set_layout = gvk.createCameraDescriptorSetLayout(device),
            .graphics_queue = undefined,
            .shadow_pass = undefined,
        };

        vk.getDeviceQueue(device, queue_family.graphics_family.?, 0, &ret.graphics_queue);

        ret.shadow_pass = gvk.renderpass.createShadowRenderPass(device, ShadowMapFormat);

        const cmd_bufs = gvk.command.createCommandBuffers(alloc, device, ret.cmd_pool, MaxActiveFrames * 2);
        defer alloc.free(cmd_bufs);
        for (ret.frames, 0..) |*frame, i| {
            frame.main_cmd_buf = cmd_bufs[i * 2];
            frame.shadow_cmd_buf = cmd_bufs[i * 2 + 1];
            frame.shadow_image = gvk.image.createDepthImage(physical, device, ShadowMapSize, ShadowMapSize, ShadowMapFormat);
            frame.shadow_image_view = gvk.image.createDefaultImageView(device, frame.shadow_image.image, ShadowMapFormat);
            frame.shadow_framebuffer = gvk.framebuffer.createFramebuffer(device, ret.shadow_pass, ShadowMapSize, ShadowMapSize, &.{ frame.shadow_image_view });
            frame.shadowmap_desc_set = gvk.descriptor.createDescriptorSet(device, ret.desc_pool, ret.shadowmap_desc_set_layout);
            var image_infos = [_]vk.VkDescriptorImageInfo{
                vk.VkDescriptorImageInfo{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
                    // .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = frame.shadow_image_view,
                    .sampler = ret.shadow_sampler,
                },
            };
            gvk.descriptor.updateImageDescriptorSet(device, frame.shadowmap_desc_set, 4, &image_infos);
            frame.u_cam_buf = gvk.buffer.createUniformBuffer(physical, device, gpu.ShaderCamera);
            frame.cam_desc_set = gvk.descriptor.createDescriptorSet(device, ret.desc_pool, ret.cam_desc_set_layout);
            gvk.descriptor.updateUniformBufferDescriptorSet(device, frame.cam_desc_set, frame.u_cam_buf.buf, 2, gpu.ShaderCamera);
        }

        for (ret.framebuffers, 0..) |_, i| {
            const attachments = &[_]vk.VkImageView{
                swapchain.impl.image_views[i],
                swapchain.impl.depth_image_views[i],
            };
            ret.framebuffers[i] = gvk.framebuffer.createFramebuffer(device, ret.main_pass, ret.fb_size.width, ret.fb_size.height, attachments);
        }

        return ret;
    }

    pub fn deinit(self: *Renderer, alloc: std.mem.Allocator) void {
        // gvk.dumpImageBmp(alloc, self, self.shadow_image.image, ShadowMapSize, ShadowMapSize, vk.VK_FORMAT_D32_SFLOAT, "shadow_map.bmp");

        const device = self.device;

        vk.destroyDescriptorSetLayout(device, self.cam_desc_set_layout, null);
        vk.destroyDescriptorPool(device, self.desc_pool, null);

        for (self.frames) |frame| {
            frame.deinit(device);
        }
        vk.destroyCommandPool(device, self.cmd_pool, null);
        alloc.free(self.frames);
        vk.destroyRenderPass(device, self.main_pass, null);
        vk.destroySampler(device, self.linear_sampler, null);
        vk.destroySampler(device, self.nearest_sampler, null);

        for (self.framebuffers) |framebuffer| {
            vk.destroyFramebuffer(device, framebuffer, null);
        }
        alloc.free(self.framebuffers);

        // Shadows deinit.
        vk.destroyRenderPass(device, self.shadow_pass, null);
        vk.destroySampler(device, self.shadow_sampler, null);
        vk.destroyDescriptorSetLayout(device, self.shadowmap_desc_set_layout, null);

        deinitGlobal();
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