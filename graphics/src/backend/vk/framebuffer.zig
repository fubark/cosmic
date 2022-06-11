const std = @import("std");
const stdx = @import("stdx");
const vk = @import("vk");

pub fn createFramebuffers(alloc: std.mem.Allocator, device: vk.VkDevice, pass: vk.VkRenderPass, extent: vk.VkExtent2D,
    image_views: []const vk.VkImageView,
    depth_image_views: []const vk.VkImageView,
) []vk.VkFramebuffer {
    const ret = alloc.alloc(vk.VkFramebuffer, image_views.len) catch stdx.fatal();
    for (image_views) |view, i| {
        ret[i] = createFramebuffer(device, pass, extent, view, depth_image_views[i]);
    }
    return ret;
}

fn createFramebuffer(device: vk.VkDevice, pass: vk.VkRenderPass, extent: vk.VkExtent2D, image_view: vk.VkImageView, depth_image_view: vk.VkImageView) vk.VkFramebuffer {
    const attachments = [_]vk.VkImageView{
        image_view,
        depth_image_view,
    };
    const create_info = vk.VkFramebufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = pass,
        .attachmentCount = attachments.len,
        .pAttachments = &attachments,
        .width = extent.width,
        .height = extent.height,
        .layers = 1,
        .pNext = null,
        .flags = 0,
    };
    var ret: vk.VkFramebuffer = undefined;
    const res = vk.createFramebuffer(device, &create_info, null, &ret);
    vk.assertSuccess(res);
    return ret;
}