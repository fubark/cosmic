const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const vk = @import("vk");

pub fn updateImageDescriptorSet(device: vk.VkDevice, desc_set: vk.VkDescriptorSet, binding: u32, image_infos: []vk.VkDescriptorImageInfo) void {
    const write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = desc_set,
        .dstBinding = binding,
        .dstArrayElement = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = @intCast(u32, image_infos.len),
        .pImageInfo = image_infos.ptr,
        .pNext = null,
        .pBufferInfo = null,
        .pTexelBufferView = null,
    };
    vk.updateDescriptorSets(device, 1, &write, 0, null);
}

pub fn updateUniformBufferDescriptorSet(device: vk.VkDevice, desc_set: vk.VkDescriptorSet, buffer: vk.VkBuffer, binding: u32, comptime Uniform: type) void {
    const buffer_info = vk.VkDescriptorBufferInfo{
        .buffer = buffer,
        .offset = 0,
        .range = @sizeOf(Uniform),
    };
    const write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = desc_set,
        .dstBinding = binding,
        .dstArrayElement = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .pImageInfo = null,
        .pNext = null,
        .pBufferInfo = &buffer_info,
        .pTexelBufferView = null,
    };
    vk.updateDescriptorSets(device, 1, &write, 0, null);
}

pub fn updateStorageBufferDescriptorSet(device: vk.VkDevice, desc_set: vk.VkDescriptorSet, buffer: vk.VkBuffer, binding: u32, offset: u32, size: usize) void {
    const buffer_info = vk.VkDescriptorBufferInfo{
        .buffer = buffer,
        .offset = offset,
        .range = size,
    };
    const write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = desc_set,
        .dstBinding = binding,
        .dstArrayElement = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .pImageInfo = null,
        .pNext = null,
        .pBufferInfo = &buffer_info,
        .pTexelBufferView = null,
    };
    vk.updateDescriptorSets(device, 1, &write, 0, null);
}

pub fn createDescriptorSets(alloc: std.mem.Allocator, device: vk.VkDevice, pool: vk.VkDescriptorPool, n: u32, layout: vk.VkDescriptorSetLayout) []vk.VkDescriptorSet {
    const layouts = alloc.alloc(vk.VkDescriptorSetLayout, n) catch fatal();
    defer alloc.free(layouts);
    for (layouts, 0..) |_, i| {
        layouts[i] = layout;
    }
    var sets = alloc.alloc(vk.VkDescriptorSet, n) catch fatal();
    const alloc_info = vk.VkDescriptorSetAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool,
        .descriptorSetCount = n,
        .pSetLayouts = layouts.ptr,
        .pNext = null,
    };
    const res = vk.allocateDescriptorSets(device, &alloc_info, sets.ptr);
    vk.assertSuccess(res);
    return sets;
}

pub fn createDescriptorSet(device: vk.VkDevice, pool: vk.VkDescriptorPool, layout: vk.VkDescriptorSetLayout) vk.VkDescriptorSet {
    var ret: vk.VkDescriptorSet = undefined;
    const alloc_info = vk.VkDescriptorSetAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &layout,
        .pNext = null,
    };
    const res = vk.allocateDescriptorSets(device, &alloc_info, &ret);
    vk.assertSuccess(res);
    return ret;
}

/// Creates a set layout for just one binding.
pub fn createDescriptorSetLayout(device: vk.VkDevice, desc_type: vk.VkDescriptorType, binding: u32, vertex_stage: bool, fragment_stage: bool) vk.VkDescriptorSetLayout {
    var stage_flags: u32 = 0;
    if (vertex_stage) {
        stage_flags |= vk.VK_SHADER_STAGE_VERTEX_BIT;
    }
    if (fragment_stage) {
        stage_flags |= vk.VK_SHADER_STAGE_FRAGMENT_BIT;
    }
    const layout_binding = vk.VkDescriptorSetLayoutBinding{
        .binding = binding,
        .descriptorCount = 1,
        .descriptorType = desc_type,
        .pImmutableSamplers = null,
        .stageFlags = stage_flags,
    };

    const bindings = [_]vk.VkDescriptorSetLayoutBinding{
        layout_binding,
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