const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const fatal = stdx.fatal;
const vk = @import("vk");
const platform = @import("platform");

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
const shaders = @import("shaders/shaders.zig");

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

    renderer.endSingleTimeCommands(cmd_buf);
}

pub fn createPlanePipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) Pipeline {
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

    const vert_src align(4) = shaders.plane_vert_spv;
    const frag_src align(4) = shaders.plane_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
        .depth_test = true,
    });
}

pub fn createGradientPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) Pipeline {
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

    const vert_src align(4) = shaders.gradient_vert_spv;
    const frag_src align(4) = shaders.gradient_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
        .depth_test = false,
    });
}

pub fn createTexPbrPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, tex_desc_set_layout: vk.VkDescriptorSetLayout,
    mats_desc_set_layout: vk.VkDescriptorSetLayout, cam_desc_set_layout: vk.VkDescriptorSetLayout, materials_desc_set_layout: vk.VkDescriptorSetLayout) Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        // Pos.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "pos_x"),
        },
        // Normal.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "norm_x"),
        },
        // Uv.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 2,
            .format = vk.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "uv_x"),
        },
        // Color.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 3,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "color_r"),
        },
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

    const vert_src align(4) = shaders.tex_pbr_vert_spv;
    const frag_src align(4) = shaders.tex_pbr_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
        .depth_test = true,
        .line_mode = false,
    });
}

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

pub fn createAnimPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, joints_desc_set_layout: vk.VkDescriptorSetLayout, tex_desc_set_layout: vk.VkDescriptorSetLayout) Pipeline {
    const bind_descriptors = [_]vk.VkVertexInputBindingDescription{
        vk.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(gpu.TexShaderVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    };
    const attr_descriptors = [_]vk.VkVertexInputAttributeDescription{
        // Pos.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "pos_x"),
        },
        // Uv.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "uv_x"),
        },
        // Color.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 2,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "color_r"),
        },
        // Joints.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 3,
            .format = vk.VK_FORMAT_R32_UINT,
            // .format = vk.VK_FORMAT_R32G32B32A32_UINT,
            // .format = vk.VK_FORMAT_R16G16_UINT,
            .offset = @offsetOf(gpu.TexShaderVertex, "joints"),
        },
        // Joint weights.
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 4,
            .format = vk.VK_FORMAT_R32_UINT,
            .offset = @offsetOf(gpu.TexShaderVertex, "weights")
        },
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
            .size = 16 * 4,
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        },
    };

    const desc_set_layouts = [_]vk.VkDescriptorSetLayout{
        tex_desc_set_layout,
        joints_desc_set_layout,
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

    const vert_src align(4) = shaders.anim_vert_spv;
    const frag_src align(4) = shaders.anim_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
        .depth_test = true,
        .line_mode = false,
    });
}

pub fn createTexPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D, desc_set: vk.VkDescriptorSetLayout, depth_test: bool, wireframe: bool) Pipeline {
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
            .offset = @offsetOf(gpu.TexShaderVertex, "pos_x"),
        },
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "uv_x"),
        },
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 2,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "color_r"),
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
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
        .depth_test = depth_test,
        .line_mode = wireframe,
    });
}

pub fn createNormPipeline(device: vk.VkDevice, pass: vk.VkRenderPass, view_dim: vk.VkExtent2D) Pipeline {
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
            .offset = @offsetOf(gpu.TexShaderVertex, "pos_x"),
        },
        vk.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(gpu.TexShaderVertex, "color_r"),
        },
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

    const vert_src align(4) = shaders.norm_vert_spv;
    const frag_src align(4) = shaders.norm_frag_spv;
    return pipeline.createDefaultPipeline(device, pass, view_dim, pvis_info, pl_info, .{
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
        .vert_spv = &vert_src,
        .frag_spv = &frag_src,
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
        // Joints + materials buffer.
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 2,
        },
        // For Camera struct.
        vk.VkDescriptorPoolSize{
            .@"type" = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
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

pub fn createCameraDescriptorSetLayout(device: vk.VkDevice) vk.VkDescriptorSetLayout {
    return descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2, false, true);
}

pub const Pipelines = struct {
    wireframe_pipeline: Pipeline,
    tex_pipeline: Pipeline,
    tex_pipeline_2d: Pipeline,
    tex_pbr_pipeline: Pipeline,
    anim_pipeline: Pipeline,
    gradient_pipeline_2d: Pipeline,
    plane_pipeline: Pipeline,
    norm_pipeline: Pipeline,

    pub fn deinit(self: Pipelines, device: vk.VkDevice) void {
        self.wireframe_pipeline.deinit(device);
        self.tex_pipeline.deinit(device);
        self.tex_pipeline_2d.deinit(device);
        self.tex_pbr_pipeline.deinit(device);
        self.anim_pipeline.deinit(device);
        self.gradient_pipeline_2d.deinit(device);
        self.plane_pipeline.deinit(device);
        self.norm_pipeline.deinit(device);
    }
};

pub const Buffer = buffer.Buffer;