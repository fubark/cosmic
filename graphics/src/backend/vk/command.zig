const std = @import("std");
const stdx = @import("stdx");
const platform = @import("platform");
const vk = @import("vk");

const graphics = @import("../../graphics.zig");

pub fn createCommandPool(device: vk.VkDevice, q_family: platform.window_sdl.VkQueueFamilyPair) vk.VkCommandPool {
    const info = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = q_family.graphics_family.?,
        .pNext = null,
        // Allow commands to be reset.
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
    };
    var pool: vk.VkCommandPool = undefined;
    const res = vk.createCommandPool(device, &info, null, &pool);
    vk.assertSuccess(res);
    return pool;
}

pub fn createCommandBuffers(alloc: std.mem.Allocator, device: vk.VkDevice, pool: vk.VkCommandPool, num_bufs: u32) []vk.VkCommandBuffer {
    var ret = alloc.alloc(vk.VkCommandBuffer, num_bufs) catch stdx.fatal();
    const alloc_info = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, ret.len),
        .pNext = null,
    };
    var res = vk.allocateCommandBuffers(device, &alloc_info, ret.ptr);
    vk.assertSuccess(res);
    return ret;
}

pub fn beginCommandBuffer(cmd_buf: vk.VkCommandBuffer) void {
    const begin_info = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        .pNext = null,
        .pInheritanceInfo = null,
    };
    const res = vk.beginCommandBuffer(cmd_buf, &begin_info);
    vk.assertSuccess(res);
}

pub fn beginRenderPass(cmd_buf: vk.VkCommandBuffer, pass: vk.VkRenderPass, framebuffer: vk.VkFramebuffer, extent: vk.VkExtent2D, clear_color: graphics.Color) void {
    const clear_vals = [_]vk.VkClearValue{
        vk.VkClearValue{
            .color = vk.VkClearColorValue{ .float32 = clear_color.toFloatArray() },
        },
        vk.VkClearValue{
            .depthStencil = vk.VkClearDepthStencilValue{
                .depth = 0,
                .stencil = 0,
            },
        },
    };
    const begin_info = vk.VkRenderPassBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = pass,
        .framebuffer = framebuffer,
        .renderArea = vk.VkRect2D{
            .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
            .extent = extent,
        },
        .clearValueCount = clear_vals.len,
        .pClearValues = &clear_vals,
        .pNext = null,
    };
    vk.cmdBeginRenderPass(cmd_buf, &begin_info, vk.VK_SUBPASS_CONTENTS_INLINE);
}

pub fn endRenderPass(cmd_buf: vk.VkCommandBuffer) void {
    vk.cmdEndRenderPass(cmd_buf);
}

pub fn endCommandBuffer(cmd_buf: vk.VkCommandBuffer) void {
    const res = vk.endCommandBuffer(cmd_buf);
    vk.assertSuccess(res);
}