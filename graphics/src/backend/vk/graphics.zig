const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const fatal = stdx.fatal;
const vk = @import("vk");
const platform = @import("platform");
const stbi = @import("stbi");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
pub const SwapChain = @import("swapchain.zig").SwapChain;
pub usingnamespace @import("command.zig");
const log = stdx.log.scoped(.vk);

const renderer_ = @import("renderer.zig");
pub const Renderer = renderer_.Renderer;
pub const Frame = renderer_.Frame;

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
pub const shaders = @import("shaders.zig");

// TODO: Remove.
pub const VkContext = struct {
    alloc: std.mem.Allocator,
    physical: vk.VkPhysicalDevice,
    device: vk.VkDevice,

    present_queue: vk.VkQueue,

    pub fn init(alloc: std.mem.Allocator, win: *platform.Window) VkContext {
        var ret = graphics.vk.VkContext{
            .alloc = alloc,
            .physical = win.impl.inner.physical_device,
            .device = win.impl.inner.device,
            .present_queue = undefined,
        };
        const queue_family = win.impl.inner.queue_family;
        const device = ret.device;

        vk.getDeviceQueue(device, queue_family.present_family.?, 0, &ret.present_queue);
        return ret;
    }
};

fn copyBuffer(renderer: *Renderer, src: vk.VkBuffer, dst: vk.VkBuffer, size: vk.VkDeviceSize) void {
    const cmd_buf = renderer.beginSingleTimeCommands();
    const copy = vk.VkBufferCopy{
        .size = size,
    };
    vk.cmdCopyBuffer(cmd_buf, src, dst, 1, &copy);
    renderer.endSingleTimeCommands(cmd_buf);
}

pub fn copyImageToBuffer(renderer: *Renderer, img: vk.VkImage, buf: vk.VkBuffer, width: usize, height: usize, format: vk.VkFormat) void {
    const cmd = renderer.beginSingleTimeCommands();

    var aspect_mask: u32 = vk.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == vk.VK_FORMAT_D16_UNORM or format == vk.VK_FORMAT_D32_SFLOAT) {
        aspect_mask = vk.VK_IMAGE_ASPECT_DEPTH_BIT;
    }
    const copy = vk.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,

        .imageSubresource = .{
            .aspectMask = aspect_mask,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{
            .x = 0,
            .y = 0,
            .z = 0
        },
        .imageExtent = .{
            .width = @intCast(u32, width),
            .height = @intCast(u32, height),
            .depth = 1,
        },
    };
    vk.cmdCopyImageToBuffer(cmd, img, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, 1, &copy);
    renderer.endSingleTimeCommands(cmd);
}

pub fn copyBufferToImage(renderer: *Renderer, buf: vk.VkBuffer, img: vk.VkImage, width: usize, height: usize) void {
    const cmd_buf = renderer.beginSingleTimeCommands();

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
    renderer.endSingleTimeCommands(cmd_buf);
}

/// Assumes rgba mb_data.
pub fn initImage(renderer: *Renderer, img: *gpu.Image, width: usize, height: usize, mb_data: ?[]const u8, linear_filter: bool) void {
    img.* = .{
        .tex_id = undefined,
        .width = width,
        .height = height,
        .inner = undefined,
        .remove = false,
    };

    const size = width * height * 4;
    const staging_buf = buffer.createBuffer(renderer.physical, renderer.device, size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    // Copy to gpu.
    if (mb_data) |data| {
        var gpu_data: ?*anyopaque = null;
        var res = vk.mapMemory(renderer.device, staging_buf.mem, 0, size, 0, &gpu_data);
        vk.assertSuccess(res);
        std.mem.copy(u8, @ptrCast([*]u8, gpu_data)[0..size], data);
        vk.unmapMemory(renderer.device, staging_buf.mem);
    }

    const tex_image = image.createDefaultImage(renderer.physical, renderer.device, width, height,
        vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_TILING_OPTIMAL,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    // Transition to transfer dst layout.
    transitionImageLayout(renderer, tex_image.image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    copyBufferToImage(renderer, staging_buf.buf, tex_image.image, width, height);
    // Transition to shader access layout.
    transitionImageLayout(renderer, tex_image.image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    // Cleanup.
    vk.destroyBuffer(renderer.device, staging_buf.buf, null);
    vk.freeMemory(renderer.device, staging_buf.mem, null);

    const tex_image_view = image.createDefaultTextureImageView(renderer.device, tex_image.image);

    img.inner.image = tex_image.image;
    img.inner.image_mem = tex_image.mem;
    img.inner.image_view = tex_image_view;
    if (linear_filter) {
        img.inner.sampler = renderer.linear_sampler;
    } else {
        img.inner.sampler = renderer.nearest_sampler;
    }
}

pub fn transitionImageLayout(renderer: *Renderer, img: vk.VkImage, format: vk.VkFormat, old_layout: vk.VkImageLayout, new_layout: vk.VkImageLayout) void {
    const cmd_buf = renderer.beginSingleTimeCommands();

    var aspect_mask: u32 = vk.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == vk.VK_FORMAT_D16_UNORM or format == vk.VK_FORMAT_D32_SFLOAT) {
        aspect_mask = vk.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    var barrier = vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = .{
            .aspectMask = aspect_mask,
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
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
        barrier.srcAccessMask = vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_READ_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
    } else {
        stdx.fatal();
    }

    vk.cmdPipelineBarrier(cmd_buf, src_stage, dst_stage,
        0,
        0, null,
        0, null,
        1, &barrier
    );

    renderer.endSingleTimeCommands(cmd_buf);
}

pub fn createPlanePipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) !Pipeline {
    // const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
    //     vk.VkVertexInputBindingDescription{
    //         .binding = 0,
    //         .stride = 0,
    //         .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
    //     },
    // };
    // const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        // vk.VkVertexInputAttributeDescription{
        //     .binding = 0,
        //     .location = 0,
        //     .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
        //     .offset = 0,
        // },
    // };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .vertexAttributeDescriptionCount = 0,
        // .pVertexBindingDescriptions = &bind_descriptors,
        .pVertexBindingDescriptions = null,
        // .pVertexAttributeDescriptions = &attr_descriptors,
        .pVertexAttributeDescriptions = null,
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
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range[0],
        .pNext = null,
        .flags = 0,
    };

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.plane_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.plane_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
    });
}

pub fn createGradientPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
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

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.gradient_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.gradient_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = false,
    });
}

pub fn createAnimShadowPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set_layout: vk.VkDescriptorSetLayout, mats_desc_set_layout: vk.VkDescriptorSetLayout) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "joints", vk.VK_FORMAT_R32G32_UINT, 1),
        initAttrDesc(gpu.TexShaderVertex, "weights", vk.VK_FORMAT_R32_UINT, 2),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(ShadowVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        mats_desc_set_layout,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.anim_shadow_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.anim_shadow_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
        .line_mode = false,
    });
}

pub fn createShadowPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set_layout: vk.VkDescriptorSetLayout, mats_desc_set_layout: vk.VkDescriptorSetLayout) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(ShadowVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        mats_desc_set_layout,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.shadow_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.shadow_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
        .line_mode = false,
    });
}

pub fn createAnimPbrPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set_layout: vk.VkDescriptorSetLayout, shadowmap_desc_set_layout: vk.VkDescriptorSetLayout,
    mats_desc_set_layout: vk.VkDescriptorSetLayout, cam_desc_set_layout: vk.VkDescriptorSetLayout, materials_desc_set_layout: vk.VkDescriptorSetLayout) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "normal", vk.VK_FORMAT_R32G32B32_SFLOAT, 1),
        initAttrDesc(gpu.TexShaderVertex, "uv", vk.VK_FORMAT_R32G32_SFLOAT, 2),
        initAttrDesc(gpu.TexShaderVertex, "joints", vk.VK_FORMAT_R32G32_UINT, 3),
        initAttrDesc(gpu.TexShaderVertex, "weights", vk.VK_FORMAT_R32_UINT, 4),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(TexLightingVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        mats_desc_set_layout,
        cam_desc_set_layout,
        materials_desc_set_layout,
        shadowmap_desc_set_layout,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    var include_map = std.StringHashMap([]const u8).init(alloc);
    defer include_map.deinit();
    try include_map.put("pbr.glsl", shaders.pbr_glsl);
    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.anim_pbr_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.anim_pbr_frag_glsl, .{ .include_map = include_map.unmanaged });
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
        .line_mode = false,
    });
}

pub fn createTexPbrPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set_layout: vk.VkDescriptorSetLayout, shadowmap_desc_set_layout: vk.VkDescriptorSetLayout,
    mats_desc_set_layout: vk.VkDescriptorSetLayout, cam_desc_set_layout: vk.VkDescriptorSetLayout, materials_desc_set_layout: vk.VkDescriptorSetLayout) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "normal", vk.VK_FORMAT_R32G32B32_SFLOAT, 1),
        initAttrDesc(gpu.TexShaderVertex, "uv", vk.VK_FORMAT_R32G32_SFLOAT, 2),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(TexLightingVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        mats_desc_set_layout,
        cam_desc_set_layout,
        materials_desc_set_layout,
        shadowmap_desc_set_layout,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    var include_map = std.StringHashMap([]const u8).init(alloc);
    defer include_map.deinit();
    try include_map.put("pbr.glsl", shaders.pbr_glsl);
    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.tex_pbr_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.tex_pbr_frag_glsl, .{ .include_map = include_map.unmanaged });
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
        .line_mode = false,
    });
}

pub const ModelVertexConstant = struct {
    vp: stdx.math.Mat4,
    model_idx: u32,
};

pub const ShadowVertexConstant = struct {
    vp: stdx.math.Mat4,
    model_idx: u32,
};

pub const TexLightingVertexConstant = struct {
    mvp: stdx.math.Mat4,
    // 3x3 mat is layed out with padding in glsl.
    normal_0: [3]f32,
    padding_0: f32 = 0,
    normal_1: [3]f32,
    padding_1: f32 = 0,
    normal_2: [3]f32,
    padding_2: f32 = 0,
    model_idx: u32,
    material_idx: u32,
};

test "TexLightingVertexConstant" {
    try t.eq(@sizeOf(TexLightingVertexConstant), 16*4 + 12*4 + 4 + 4);
}

fn initAttrDesc(comptime Vertex: type, comptime field_name: []const u8, comptime format: vk.VkFormat, location: u32) vk.VkVertexInputAttributeDescription {
    // Check format size matches the field.
    const format_size = switch (format) {
        vk.VK_FORMAT_R32_UINT => 4,
        vk.VK_FORMAT_R32G32_UINT => 8,
        vk.VK_FORMAT_R32G32_SFLOAT => 8,
        vk.VK_FORMAT_R32G32B32_SFLOAT => 12,
        vk.VK_FORMAT_R32G32B32A32_SFLOAT => 16,
        else => @compileError("unsupported: " ++ format),
    };
    const FieldEnum = comptime std.meta.stringToEnum(std.meta.FieldEnum(Vertex), field_name).?;
    if (format_size != @sizeOf(stdx.meta.FieldType(Vertex, FieldEnum))) {
        @compileError("Attribute size mismatch.");
    }
    return .{
        .binding = 0,
        .location = location,
        .format = format,
        .offset = @offsetOf(Vertex, field_name),
    };
}

pub fn createAnimPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, mats_desc_set_layout: vk.VkDescriptorSetLayout, tex_desc_set_layout: vk.VkDescriptorSetLayout) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "uv", vk.VK_FORMAT_R32G32_SFLOAT, 1),
        initAttrDesc(gpu.TexShaderVertex, "color", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 2),
        initAttrDesc(gpu.TexShaderVertex, "joints", vk.VK_FORMAT_R32G32_UINT, 3),
        initAttrDesc(gpu.TexShaderVertex, "weights", vk.VK_FORMAT_R32_UINT, 4),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(ModelVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        mats_desc_set_layout,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.anim_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.anim_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = true,
        .line_mode = false,
    });
}

pub fn createTexPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set: vk.VkDescriptorSetLayout, mats_desc_set: vk.VkDescriptorSetLayout, vert_spirv: []const u32, frag_spirv: []const u32, depth_test: bool, wireframe: bool) Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "uv", vk.VK_FORMAT_R32G32_SFLOAT, 1),
        initAttrDesc(gpu.TexShaderVertex, "color", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 2),
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
            .size = @sizeOf(ModelVertexConstant),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set,
        mats_desc_set,
    };

    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = desc_set_layouts.len,
        .pSetLayouts = &desc_set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = vert_spirv,
        .frag_spv = frag_spirv,
        .depth_test = depth_test,
        .line_mode = wireframe,
    });
}

pub fn createNormPipeline(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) !Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        initAttrDesc(gpu.TexShaderVertex, "pos", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 0),
        initAttrDesc(gpu.TexShaderVertex, "color", vk.VK_FORMAT_R32G32B32A32_SFLOAT, 1),
    };
    const pvis_info = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = bind_descriptors.len,
        .pVertexBindingDescriptions = &bind_descriptors,
        .vertexAttributeDescriptionCount = attr_descriptors.len,
        .pVertexAttributeDescriptions = &attr_descriptors,
        .pNext = null,
        .flags = 0,
    };

    const push_const_range = [_]vk.VkPushConstantRange{
        vk.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(stdx.math.Mat4),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };
    const pl_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_const_range,
        .pNext = null,
        .flags = 0,
    };

    const vert_spv = try gpu.shader.compileGLSL(alloc, .Vertex, shaders.norm_vert_glsl, .{});
    defer alloc.free(vert_spv);
    const frag_spv = try gpu.shader.compileGLSL(alloc, .Fragment, shaders.norm_frag_glsl, .{});
    defer alloc.free(frag_spv);
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
        .vert_spv = vert_spv,
        .frag_spv = frag_spv,
        .depth_test = false,
        .line_mode = false,
    });
}

// TODO: Implement a list of pools. Once a pool runs out of space a new one is created.
/// Currently a fixed max of 100 textures.
pub fn createDescriptorPool(device: vk.VkDevice) vk.VkDescriptorPool {
    const pool_sizes = [_]vk.VkDescriptorPoolSize{
        // For textures.
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 100,
        },
        // Matrix + materials buffer.
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 2,
        },
        // For Camera struct.
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1 * gpu.MaxActiveFrames,
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
    return descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 0, false, true);
}

pub fn createShadowMapDescriptorSetLayout(device: vk.VkDevice) vk.VkDescriptorSetLayout {
    return descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4, false, true);
}

pub fn createCameraDescriptorSetLayout(device: vk.VkDevice) vk.VkDescriptorSetLayout {
    return descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2, true, true);
}

pub const Pipelines = struct {
    wireframe_pipeline: Pipeline,
    tex_pipeline: Pipeline,
    tex_pipeline_2d: Pipeline,
    tex_pbr_pipeline: Pipeline,
    anim_pipeline: Pipeline,
    anim_pbr_pipeline: Pipeline,
    gradient_pipeline_2d: Pipeline,
    plane_pipeline: Pipeline,
    norm_pipeline: Pipeline,
    shadow_pipeline: Pipeline,
    anim_shadow_pipeline: Pipeline,

    pub fn deinit(self: Pipelines, device: vk.VkDevice) void {
        self.wireframe_pipeline.deinit(device);
        self.tex_pipeline.deinit(device);
        self.tex_pipeline_2d.deinit(device);
        self.tex_pbr_pipeline.deinit(device);
        self.anim_pipeline.deinit(device);
        self.anim_pbr_pipeline.deinit(device);
        self.gradient_pipeline_2d.deinit(device);
        self.plane_pipeline.deinit(device);
        self.norm_pipeline.deinit(device);
        self.shadow_pipeline.deinit(device);
        self.anim_shadow_pipeline.deinit(device);
    }
};

pub const Buffer = buffer.Buffer;

pub fn getImageData(alloc: std.mem.Allocator, renderer: *Renderer, img: vk.VkImage, width: usize, height: usize, format: vk.VkFormat) []const u8 {
    var pixel_size: u32 = 4 * 3;
    if (format == vk.VK_FORMAT_D16_UNORM) {
        pixel_size = 2;
    } else if (format == vk.VK_FORMAT_D32_SFLOAT) {
        pixel_size = 4;
    }
    const size = width * height * pixel_size;
    const buf = buffer.createBuffer(renderer.physical, renderer.device, size, vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    defer buf.deinit(renderer.device);

    // Transition to transfer dst layout.
    transitionImageLayout(renderer, img, format, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    copyImageToBuffer(renderer, img, buf.buf, width, height, format);
    // Transition to shader access layout.
    transitionImageLayout(renderer, img, format, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);

    var data: [*]u8 = undefined;
    const res = vk.mapMemory(renderer.device, buf.mem, 0, size, 0, @ptrCast([*c]?*anyopaque, &data));
    vk.assertSuccess(res);
    defer vk.unmapMemory(renderer.device, buf.mem);

    return alloc.dupe(u8, data[0..size]) catch fatal();
}

pub fn dumpImageBmp(alloc: std.mem.Allocator, renderer: *Renderer, img: vk.VkImage, width: usize, height: usize, format: vk.VkFormat, filename: [:0]const u8) void {
    const data = getImageData(alloc, renderer, img, width, height, format);
    defer alloc.free(data);
    const bmp_data = alloc.alloc(u8, width * height) catch fatal();
    defer alloc.free(bmp_data);
    var i: u32 = 0;
    while (i < width * height) : (i += 1) {
        if (format == vk.VK_FORMAT_D16_UNORM) {
            const val = std.mem.readIntNative(u16, data[i*2..i*2+2][0..2]);
            bmp_data[i] = @floatToInt(u8, (@intToFloat(f32, val) / @intToFloat(f32, std.math.maxInt(u16))) * 255);
        } else if (format == vk.VK_FORMAT_D32_SFLOAT) {
            const val = @bitCast(f32, std.mem.readIntNative(u32, data[i*4..i*4+4][0..4]));
            bmp_data[i] = @floatToInt(u8, val * 255);
        }
    }
    _ = stbi.stbi_write_bmp(filename, @intCast(c_int, width), @intCast(c_int, height), 1, bmp_data.ptr);
}