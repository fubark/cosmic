const stdx = @import("stdx");
const vk = @import("vk");

const gvk = @import("graphics.zig");
const log = stdx.log.scoped(.buffer);

pub fn createUniformBuffer(physical: vk.VkPhysicalDevice, device: vk.VkDevice, comptime Uniform: type) Buffer {
    return createBuffer(physical, device, @sizeOf(Uniform),
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
}

pub fn createStorageBuffer(physical: vk.VkPhysicalDevice, device: vk.VkDevice, size: vk.VkDeviceSize) Buffer {
    return createBuffer(physical, device, size,
        vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
}

pub fn createVertexBuffer(physical: vk.VkPhysicalDevice, device: vk.VkDevice, size: vk.VkDeviceSize) Buffer {
    return createBuffer(physical, device, size,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        // HOST_COHERENT_BIT forces writes to flush.
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
}

pub fn createIndexBuffer(physical: vk.VkPhysicalDevice, device: vk.VkDevice, size: vk.VkDeviceSize) Buffer {
    return createBuffer(physical, device, size,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
}

pub fn createBuffer(physical: vk.VkPhysicalDevice, device: vk.VkDevice, size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags) Buffer {
    const create_info = vk.VkBufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .pNext = null,
        .flags = 0,
    };
    var buffer: vk.VkBuffer = undefined;
    var res = vk.createBuffer(device, &create_info, null, &buffer);
    vk.assertSuccess(res);

    var mem_requirements: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(device, buffer, &mem_requirements);

    const alloc_info = vk.VkMemoryAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = gvk.memory.findMemoryType(physical, mem_requirements.memoryTypeBits, properties),
        .pNext = null,
    };

    var mem: vk.VkDeviceMemory = undefined;
    res = vk.allocateMemory(device, &alloc_info, null, &mem);
    vk.assertSuccess(res);

    res = vk.bindBufferMemory(device, buffer, mem, 0);
    vk.assertSuccess(res);

    return .{
        .buf = buffer,
        .mem = mem,
        .size = size,
    };
}

pub const Buffer = struct {
    buf: vk.VkBuffer,
    mem: vk.VkDeviceMemory,
    size: vk.VkDeviceSize,

    pub fn deinit(self: Buffer, device: vk.VkDevice) void {
        vk.destroyBuffer(device, self.buf, null);
        vk.freeMemory(device, self.mem, null);
    }
};