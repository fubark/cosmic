const std = @import("std");
const stdx = @import("stdx");
const vk = @import("vk");

pub fn createFramebuffers(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, extent: vk.VkExtent2D,
    image_views: []const vk.VkImageView,
    depth_image_views: []const vk.VkImageView,
) []vk.VkFramebuffer {
    const ret = alloc.alloc(vk.VkFramebuffer, image_views.len) catch stdx.fatal();
    for (image_views, 0..) |view, i| {
        const attachments = &[_]vk.VkImageView{
            view,
            depth_image_views[i],
        };
        ret[i] = createFramebuffer(device, pass, extent.width, extent.height, attachments);
    }
    return ret;
}

pub fn createFramebuffer(device: vk.VkDevice, pass: vk.VkRenderPass, width: usize, height: usize, attachments: []const vk.VkImageView) vk.VkFramebuffer {
    const create_info = vk.VkFramebufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = pass,
        .attachmentCount = @intCast(u32, attachments.len),
        .pAttachments = attachments.ptr,
        .width = @intCast(u32, width),
        .height = @intCast(u32, height),
        .layers = 1,
        .pNext = null,
        .flags = 0,
    };
    var ret: vk.VkFramebuffer = undefined;
    const res = vk.createFramebuffer(device, &create_info, null, &ret);
    vk.assertSuccess(res);
    return ret;
}