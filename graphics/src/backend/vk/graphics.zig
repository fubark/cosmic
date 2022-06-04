const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const vk = @import("vk");
const platform = @import("platform");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
pub const SwapChain = @import("swapchain.zig").SwapChain;
pub usingnamespace @import("command.zig");
const log = stdx.log.scoped(.vk);

pub const shader = @import("shader.zig");
pub const framebuffer = @import("framebuffer.zig");
pub const renderpass = @import("renderpass.zig");
pub const image = @import("image.zig");
pub const buffer = @import("buffer.zig");
pub const command = @import("command.zig");
pub const memory = @import("memory.zig");
pub const pipeline = @import("pipeline.zig");
pub const Pipeline = pipeline.Pipeline;
pub const descriptor = @import("descriptor.zig");
const shaders = @import("shaders/shaders.zig");

pub const VkContext = struct {
    alloc: std.mem.Allocator,
    physical: vk.VkPhysicalDevice,
    device: vk.VkDevice,

    graphics_queue: vk.VkQueue,
    present_queue: vk.VkQueue,

    cmd_pool: vk.VkCommandPool,
    cmd_bufs: []vk.VkCommandBuffer,

    pass: vk.VkRenderPass,
    framebuffer_size: vk.VkExtent2D,
    framebuffers: []vk.VkFramebuffer,

    // TODO: Move this into gpu.inner.
    default_linear_sampler: vk.VkSampler,
    default_nearest_sampler: vk.VkSampler,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, win: *platform.Window, swapchain: graphics.SwapChain) Self {
        var ret = graphics.vk.VkContext{
            .alloc = alloc,
            .physical = win.impl.inner.physical_device,
            .device = win.impl.inner.device,
            .cmd_pool = undefined,
            .cmd_bufs = undefined,
            .graphics_queue = undefined,
            .present_queue = undefined,
            .framebuffer_size = swapchain.impl.buf_dim,
            .framebuffers = undefined,
            .pass = undefined,
            .default_linear_sampler = undefined,
            .default_nearest_sampler = undefined,
        };
        const queue_family = win.impl.inner.queue_family;

        vk.getDeviceQueue(ret.device, queue_family.graphics_family.?, 0, &ret.graphics_queue);
        vk.getDeviceQueue(ret.device, queue_family.present_family.?, 0, &ret.present_queue);

        ret.cmd_pool = command.createCommandPool(ret.device, queue_family);
        const num_framebuffers = @intCast(u32, swapchain.impl.images.len);
        ret.cmd_bufs = command.createCommandBuffers(alloc, ret.device, ret.cmd_pool, num_framebuffers);

        ret.pass = renderpass.createRenderPass(ret.device, swapchain.impl.buf_format);

        ret.framebuffers = framebuffer.createFramebuffers(alloc, ret.device, ret.pass, ret.framebuffer_size, swapchain.impl.image_views);

        ret.default_linear_sampler = ret.createDefaultTextureSampler(true);
        ret.default_nearest_sampler = ret.createDefaultTextureSampler(false);

        return ret;
    }

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        for (self.framebuffers) |fb| {
            vk.destroyFramebuffer(self.device, fb, null);
        }
        alloc.free(self.framebuffers);

        vk.destroyCommandPool(self.device, self.cmd_pool, null);
        alloc.free(self.cmd_bufs);

        vk.destroySampler(self.device, self.default_linear_sampler, null);
        vk.destroySampler(self.device, self.default_nearest_sampler, null);

        vk.destroyRenderPass(self.device, self.pass, null);
    }

    pub fn initImage(self: Self, img: *gpu.Image, width: usize, height: usize, mb_data: ?[]const u8, linear_filter: bool) void {
        img.* = .{
            .tex_id = undefined,
            .width = width,
            .height = height,
            .inner = undefined,
            .remove = false,
        };

        var staging_buf: vk.VkBuffer = undefined;
        var staging_buf_mem: vk.VkDeviceMemory = undefined;

        const size = width * height * 4;
        buffer.createBuffer(self.physical, self.device, size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &staging_buf, &staging_buf_mem);

        // Copy to gpu.
        if (mb_data) |data| {
            var gpu_data: ?*anyopaque = null;
            var res = vk.mapMemory(self.device, staging_buf_mem, 0, size, 0, &gpu_data);
            vk.assertSuccess(res);
            std.mem.copy(u8, @ptrCast([*]u8, gpu_data)[0..size], data);
            vk.unmapMemory(self.device, staging_buf_mem);
        }

        var tex_image: vk.VkImage = undefined;
        var tex_image_mem: vk.VkDeviceMemory = undefined;

        self.createVkImage(width, height,
            vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &tex_image, &tex_image_mem);

        // Transition to transfer dst layout.
        self.transitionImageLayout(tex_image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        self.copyBufferToImage(staging_buf, tex_image, width, height);
        // Transition to shader access layout.
        self.transitionImageLayout(tex_image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        // Cleanup.
        vk.destroyBuffer(self.device, staging_buf, null);
        vk.freeMemory(self.device, staging_buf_mem, null);

        const tex_image_view = image.createDefaultTextureImageView(self.device, tex_image);

        img.inner.image = tex_image;
        img.inner.image_mem = tex_image_mem;
        img.inner.image_view = tex_image_view;
        if (linear_filter) {
            img.inner.sampler = self.default_linear_sampler;
        } else {
            img.inner.sampler = self.default_nearest_sampler;
        }
    }

    pub fn createDefaultTextureSampler(self: Self, linear_filter: bool) vk.VkSampler {
        const create_info = vk.VkSamplerCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = if (linear_filter) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST,
            .minFilter = if (linear_filter) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .anisotropyEnable = vk.VK_FALSE,
            .maxAnisotropy = 0,
            .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = vk.VK_FALSE,
            .compareEnable = vk.VK_FALSE,
            .compareOp = vk.VK_COMPARE_OP_ALWAYS,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .mipLodBias = 0,
            .minLod = 0,
            .maxLod = 0,
            .pNext = null,
            .flags = 0,
        };
        var ret: vk.VkSampler = undefined;
        const res = vk.createSampler(self.device, &create_info, null, &ret);
        vk.assertSuccess(res);
        return ret;
    }

    fn createVkImage(self: Self, width: usize, height: usize, format: vk.VkFormat, tiling: vk.VkImageTiling, usage: vk.VkImageUsageFlags, properties: vk.VkMemoryPropertyFlags, img: *vk.VkImage, image_mem: *vk.VkDeviceMemory) void {
        const create_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .extent = .{
                .width = @intCast(u32, width),
                .height = @intCast(u32, height),
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format,
            .tiling = tiling,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .flags = 0,
            .pNext = null,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };
        var res = vk.createImage(self.device, &create_info, null, img);
        vk.assertSuccess(res);

        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.getImageMemoryRequirements(self.device, img.*, &mem_requirements);

        var alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = memory.findMemoryType(self.physical, mem_requirements.memoryTypeBits, properties),
            .pNext = null,
        };
        res = vk.allocateMemory(self.device, &alloc_info, null, image_mem);
        vk.assertSuccess(res);

        res = vk.bindImageMemory(self.device, img.*, image_mem.*, 0);
        vk.assertSuccess(res);
    }

    fn beginSingleTimeCommands(self: Self) vk.VkCommandBuffer {
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

    fn endSingleTimeCommands(self: Self, cmd_buf: vk.VkCommandBuffer) void {
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

    fn copyBuffer(self: Self, src: vk.VkBuffer, dst: vk.VkBuffer, size: vk.VkDeviceSize) void {
        const cmd_buf = self.beginSingleTimeCommands();
        const copy = vk.VkBufferCopy{
            .size = size,
        };
        vk.cmdCopyBuffer(cmd_buf, src, dst, 1, &copy);
        self.endSingleTimeCommands(cmd_buf);
    }

    pub fn transitionImageLayout(self: Self, img: vk.VkImage, format: vk.VkFormat, old_layout: vk.VkImageLayout, new_layout: vk.VkImageLayout) void {
        const cmd_buf = self.beginSingleTimeCommands();

        _ = format;

        var barrier = vk.VkImageMemoryBarrier{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = old_layout,
            .newLayout = new_layout,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = img,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcAccessMask = 0,
            .dstAccessMask = 0,
            .pNext = null,
        };

        var src_stage: vk.VkPipelineStageFlags = undefined;
        var dst_stage: vk.VkPipelineStageFlags = undefined;

        if (old_layout == vk.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            src_stage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
            dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else if (old_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
            src_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
            dst_stage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        } else if (old_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
            barrier.srcAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
            barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            src_stage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
            dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else {
            stdx.fatal();
        }

        vk.cmdPipelineBarrier(cmd_buf, src_stage, dst_stage,
            0,
            0, null,
            0, null,
            1, &barrier
        );

        self.endSingleTimeCommands(cmd_buf);
    }

    pub fn copyBufferToImage(self: Self, buf: vk.VkBuffer, img: vk.VkImage, width: usize, height: usize) void {
        const cmd_buf = self.beginSingleTimeCommands();

        const copy = vk.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,

            .imageSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },

            .imageOffset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .imageExtent = .{
                .width = @intCast(u32, width),
                .height = @intCast(u32, height),
                .depth = 1,
            },
        };
        vk.cmdCopyBufferToImage(cmd_buf, buf, img, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
        self.endSingleTimeCommands(cmd_buf);
    }
};

pub fn createGradientPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = 40,
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = 0,
        },
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .vertexAttributeDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = 16 * 4,
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
        vk.VkPushConstantRange{
            .offset = 16 * 4,
            .size = 4 * 12,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
    };
    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 2,
        .pPushConstantRanges = &push_const_range[0],
        .pNext = null,
        .flags = 0,
    };

    const vert_src align(4) = shaders.gradient_vert_spv;
    const frag_src align(4) = shaders.gradient_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, &vert_src, &frag_src, pvis_info, pl_info);
}

pub fn createTexPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, desc_set: vk.VkDescriptorSetLayout) Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = 40,
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = 0,
        },
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32G32_SFLOAT,
            .offset = 16,
        },
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 2,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = 24,
        },
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .vertexAttributeDescriptionCount = 3,
        .pVertexBindingDescriptions = &bind_descriptors,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = 16 * 4,
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };
    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &desc_set,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    const vert_src align(4) = shaders.tex_vert_spv;
    const frag_src align(4) = shaders.tex_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, &vert_src, &frag_src, pvis_info, pl_info);
}

// TODO: Implement a list of pools. Once a pool runs out of space a new one is created.
/// Currently a fixed max of 100 textures.
pub fn createTexDescriptorPool(device: vk.VkDevice) vk.VkDescriptorPool {
    const pool_sizes = [_]vk.VkDescriptorPoolSize{
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 100,
        },
    };

    const create_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes,
        .maxSets = 100,
        .pNext = null,
        .flags = 0,
    };

    var ret: vk.VkDescriptorPool = undefined;
    const res = vk.createDescriptorPool(device, &create_info, null, &ret);
    vk.assertSuccess(res);
    return ret;
}

pub fn createTexDescriptorSetLayout(device: vk.VkDevice) vk.VkDescriptorSetLayout {
    // mvp uniform.
    // const mvp_layout_binding = vk.VkDescriptorSetLayoutBinding{
    //     .binding = 0,
    //     .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    //     .descriptorCount = 1,
    //     .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
    //     .pImmutableSamplers = null,
    // };

    const sampler_layout_binding = vk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImmutableSamplers = null,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]vk.VkDescriptorSetLayoutBinding{
        //mvp_layout_binding,
        sampler_layout_binding,
    };

    const create_info = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
        .pNext = null,
        .flags = 0,
    };

    var set_layout: vk.VkDescriptorSetLayout = undefined;
    const res = vk.createDescriptorSetLayout(device, &create_info, null, &set_layout);
    vk.assertSuccess(res);
    return set_layout;
}