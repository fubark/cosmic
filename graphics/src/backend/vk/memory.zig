const stdx = @import("stdx");
const vk = @import("vk");

pub fn findMemoryType(physical: vk.VkPhysicalDevice, type_filter: u32, properties: vk.VkMemoryPropertyFlags) u32 {
    var mem_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(physical, &mem_properties);

    var i: u32 = 0;
    while (i < mem_properties.memoryTypeCount) : (i += 1) {
        if (type_filter & (@as(u32, 1) << @intCast(u5, i)) > 0 and (mem_properties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    stdx.fatal();
}
