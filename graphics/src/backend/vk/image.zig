const vk = @import("vk");

pub fn createDefaultTextureImageView(device: vk.VkDevice, tex_image: vk.VkImage) vk.VkImageView {
    return createDefaultImageView(device, tex_image, vk.VK_FORMAT_R8G8B8A8_SRGB);
}

pub fn createDefaultImageView(device: vk.VkDevice, image: vk.VkImage, format: vk.VkFormat) vk.VkImageView {
    const create_info = vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = vk.VkComponentMapping{
            .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = vk.VkImageSubresourceRange{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .pNext = null,
        .flags = 0,
    };
    var ret: vk.VkImageView = undefined;
    const res = vk.createImageView(device, &create_info, null, &ret);
    vk.assertSuccess(res);
    return ret;
}