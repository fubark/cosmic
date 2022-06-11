const vk = @import("vk");
const memory = @import("memory.zig");

pub fn createDefaultImage(
    physical: vk.VkPhysicalDevice, device: vk.VkDevice,
    width: usize, height: usize,
    format: vk.VkFormat, tiling: vk.VkImageTiling, usage: vk.VkImageUsageFlags,
    properties: vk.VkMemoryPropertyFlags,
    img: *vk.VkImage, image_mem: *vk.VkDeviceMemory
) void {
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
    var res = vk.createImage(device, &create_info, null, img);
    vk.assertSuccess(res);

    var mem_requirements: vk.VkMemoryRequirements = undefined;
    vk.getImageMemoryRequirements(device, img.*, &mem_requirements);

    var alloc_info = vk.VkMemoryAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = memory.findMemoryType(physical, mem_requirements.memoryTypeBits, properties),
        .pNext = null,
    };
    res = vk.allocateMemory(device, &alloc_info, null, image_mem);
    vk.assertSuccess(res);

    res = vk.bindImageMemory(device, img.*, image_mem.*, 0);
    vk.assertSuccess(res);
}

pub fn createDefaultTextureImageView(device: vk.VkDevice, tex_image: vk.VkImage) vk.VkImageView {
    return createDefaultImageView(device, tex_image, vk.VK_FORMAT_R8G8B8A8_SRGB);
}

pub fn createDefaultImageView(device: vk.VkDevice, image: vk.VkImage, format: vk.VkFormat) vk.VkImageView {
    var aspect_mask: u32 = vk.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == vk.VK_FORMAT_D32_SFLOAT) {
        aspect_mask = vk.VK_IMAGE_ASPECT_DEPTH_BIT;
    }
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
            .aspectMask = aspect_mask,
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