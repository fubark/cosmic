const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub usingnamespace c;

pub inline fn createInstance(pCreateInfo: [*c]const c.VkInstanceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pInstance: [*c]c.VkInstance) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateInstance(pCreateInfo, pAllocator, pInstance);
    } else {
        return c.vkCreateInstance(pCreateInfo, pAllocator, pInstance);
    }
}

pub inline fn enumeratePhysicalDevices(instance: c.VkInstance, pPhysicalDeviceCount: [*c]u32, pPhysicalDevices: [*c]c.VkPhysicalDevice) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkEnumeratePhysicalDevices(instance, pPhysicalDeviceCount, pPhysicalDevices);
    } else {
        return c.vkEnumeratePhysicalDevices(instance, pPhysicalDeviceCount, pPhysicalDevices);
    }
}

pub inline fn getPhysicalDeviceQueueFamilyProperties(physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties) void {
    if (builtin.os.tag == .macos) {
        rtVkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
    } else {
        c.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
    }
}

pub inline fn getPhysicalDeviceSurfaceSupportKHR(physicalDevice: c.VkPhysicalDevice, queueFamilyIndex: u32, surface: c.VkSurfaceKHR, pSupported: [*c]c.VkBool32) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, queueFamilyIndex, surface, pSupported);
    } else {
        return c.vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, queueFamilyIndex, surface, pSupported);
    }
}

pub inline fn enumerateDeviceExtensionProperties(physicalDevice: c.VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]c.VkExtensionProperties) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName, pPropertyCount, pProperties);
    } else {
        return c.vkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName, pPropertyCount, pProperties);
    }
}

pub inline fn getPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceCapabilities: [*c]c.VkSurfaceCapabilitiesKHR) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, pSurfaceCapabilities);
    } else {
        return c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, pSurfaceCapabilities);
    }
}

pub inline fn getPhysicalDeviceSurfacePresentModesKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pPresentModeCount: [*c]u32, pPresentModes: [*c]c.VkPresentModeKHR) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, pPresentModeCount, pPresentModes);
    } else {
        return c.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, pPresentModeCount, pPresentModes);
    }
}

pub inline fn getPhysicalDeviceSurfaceFormatsKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceFormatCount: [*c]u32, pSurfaceFormats: [*c]c.VkSurfaceFormatKHR) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, pSurfaceFormatCount, pSurfaceFormats);
    } else {
        return c.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, pSurfaceFormatCount, pSurfaceFormats);
    }
}

pub inline fn createDevice(physicalDevice: c.VkPhysicalDevice, pCreateInfo: [*c]const c.VkDeviceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pDevice: [*c]c.VkDevice) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
    } else {
        return c.vkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
    }
}

pub inline fn getDeviceQueue(device: c.VkDevice, queueFamilyIndex: u32, queueIndex: u32, pQueue: [*c]c.VkQueue) void {
    if (builtin.os.tag == .macos) {
        rtVkGetDeviceQueue(device, queueFamilyIndex, queueIndex, pQueue);
    } else {
        c.vkGetDeviceQueue(device, queueFamilyIndex, queueIndex, pQueue);
    }
}

pub inline fn createSwapchainKHR(device: c.VkDevice, pCreateInfo: [*c]const c.VkSwapchainCreateInfoKHR, pAllocator: [*c]const c.VkAllocationCallbacks, pSwapchain: [*c]c.VkSwapchainKHR) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateSwapchainKHR(device, pCreateInfo, pAllocator, pSwapchain);
    } else {
        return c.vkCreateSwapchainKHR(device, pCreateInfo, pAllocator, pSwapchain);
    }
}

pub inline fn getSwapchainImagesKHR(device: c.VkDevice, swapchain: c.VkSwapchainKHR, pSwapchainImageCount: [*c]u32, pSwapchainImages: [*c]c.VkImage) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkGetSwapchainImagesKHR(device, swapchain, pSwapchainImageCount, pSwapchainImages);
    } else {
        return c.vkGetSwapchainImagesKHR(device, swapchain, pSwapchainImageCount, pSwapchainImages);
    }
}

pub inline fn createImageView(device: c.VkDevice, pCreateInfo: [*c]const c.VkImageViewCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pView: [*c]c.VkImageView) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateImageView(device, pCreateInfo, pAllocator, pView);
    } else {
        return c.vkCreateImageView(device, pCreateInfo, pAllocator, pView);
    }
}

pub inline fn createRenderPass(device: c.VkDevice, pCreateInfo: [*c]const c.VkRenderPassCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pRenderPass: [*c]c.VkRenderPass) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateRenderPass(device, pCreateInfo, pAllocator, pRenderPass);
    } else {
        return c.vkCreateRenderPass(device, pCreateInfo, pAllocator, pRenderPass);
    }
}

pub inline fn createPipelineLayout(device: c.VkDevice, pCreateInfo: [*c]const c.VkPipelineLayoutCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pPipelineLayout: [*c]c.VkPipelineLayout) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreatePipelineLayout(device, pCreateInfo, pAllocator, pPipelineLayout);
    } else {
        return c.vkCreatePipelineLayout(device, pCreateInfo, pAllocator, pPipelineLayout);
    }
}

pub inline fn createShaderModule(device: c.VkDevice, pCreateInfo: [*c]const c.VkShaderModuleCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pShaderModule: [*c]c.VkShaderModule) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateShaderModule(device, pCreateInfo, pAllocator, pShaderModule);
    } else {
        return c.vkCreateShaderModule(device, pCreateInfo, pAllocator, pShaderModule);
    }
}

pub inline fn createGraphicsPipelines(device: c.VkDevice, pipelineCache: c.VkPipelineCache, createInfoCount: u32, pCreateInfos: [*c]const c.VkGraphicsPipelineCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pPipelines: [*c]c.VkPipeline) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateGraphicsPipelines(device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines);
    } else {
        return c.vkCreateGraphicsPipelines(device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines);
    }
}

pub inline fn destroyShaderModule(device: c.VkDevice, shaderModule: c.VkShaderModule, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyShaderModule(device, shaderModule, pAllocator);
    } else {
        c.vkDestroyShaderModule(device, shaderModule, pAllocator);
    }
}

pub inline fn createFramebuffer(device: c.VkDevice, pCreateInfo: [*c]const c.VkFramebufferCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pFramebuffer: [*c]c.VkFramebuffer) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateFramebuffer(device, pCreateInfo, pAllocator, pFramebuffer);
    } else {
        return c.vkCreateFramebuffer(device, pCreateInfo, pAllocator, pFramebuffer);
    }
}

pub inline fn createCommandPool(device: c.VkDevice, pCreateInfo: [*c]const c.VkCommandPoolCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pCommandPool: [*c]c.VkCommandPool) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateCommandPool(device, pCreateInfo, pAllocator, pCommandPool);
    } else {
        return c.vkCreateCommandPool(device, pCreateInfo, pAllocator, pCommandPool);
    }
}

pub inline fn allocateCommandBuffers(device: c.VkDevice, pAllocateInfo: [*c]const c.VkCommandBufferAllocateInfo, pCommandBuffers: [*c]c.VkCommandBuffer) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkAllocateCommandBuffers(device, pAllocateInfo, pCommandBuffers);
    } else {
        return c.vkAllocateCommandBuffers(device, pAllocateInfo, pCommandBuffers);
    }
}

pub inline fn beginCommandBuffer(commandBuffer: c.VkCommandBuffer, pBeginInfo: [*c]const c.VkCommandBufferBeginInfo) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkBeginCommandBuffer(commandBuffer, pBeginInfo);
    } else {
        return c.vkBeginCommandBuffer(commandBuffer, pBeginInfo);
    }
}

pub inline fn cmdBeginRenderPass(commandBuffer: c.VkCommandBuffer, pRenderPassBegin: [*c]const c.VkRenderPassBeginInfo, contents: c.VkSubpassContents) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdBeginRenderPass(commandBuffer, pRenderPassBegin, contents);
    } else {
        c.vkCmdBeginRenderPass(commandBuffer, pRenderPassBegin, contents);
    }
}

pub inline fn cmdBindPipeline(commandBuffer: c.VkCommandBuffer, pipelineBindPoint: c.VkPipelineBindPoint, pipeline: c.VkPipeline) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdBindPipeline(commandBuffer, pipelineBindPoint, pipeline);
    } else {
        c.vkCmdBindPipeline(commandBuffer, pipelineBindPoint, pipeline);
    }
}

pub inline fn cmdDraw(commandBuffer: c.VkCommandBuffer, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdDraw(commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
    } else {
        c.vkCmdDraw(commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
    }
}

pub inline fn cmdEndRenderPass(commandBuffer: c.VkCommandBuffer) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdEndRenderPass(commandBuffer);
    } else {
        c.VkCmdEndRenderPass(commandBuffer);
    }
}

pub inline fn endCommandBuffer(commandBuffer: c.VkCommandBuffer) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkEndCommandBuffer(commandBuffer);
    } else {
        return c.vkEndCommandBuffer(commandBuffer);
    }
}

pub inline fn createSemaphore(device: c.VkDevice, pCreateInfo: [*c]const c.VkSemaphoreCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSemaphore: [*c]c.VkSemaphore) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateSemaphore(device, pCreateInfo, pAllocator, pSemaphore);
    } else {
        return c.vkCreateSemaphore(device, pCreateInfo, pAllocator, pSemaphore);
    }
}

pub inline fn createFence(device: c.VkDevice, pCreateInfo: [*c]const c.VkFenceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pFence: [*c]c.VkFence) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateFence(device, pCreateInfo, pAllocator, pFence);
    } else {
        return c.vkCreateFence(device, pCreateInfo, pAllocator, pFence);
    }
}

pub inline fn enumerateInstanceLayerProperties(pPropertyCount: [*c]u32, pProperties: [*c]c.VkLayerProperties) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkEnumerateInstanceLayerProperties(pPropertyCount, pProperties);
    } else {
        return c.vkEnumerateInstanceLayerProperties(pPropertyCount, pProperties);
    }
}

pub inline fn mapMemory(device: c.VkDevice, memory: c.VkDeviceMemory, offset: c.VkDeviceSize, size: c.VkDeviceSize, flags: c.VkMemoryMapFlags, ppData: [*c]?*anyopaque) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkMapMemory(device, memory, offset, size, flags, ppData);
    } else {
        return c.vkMapMemory(device, memory, offset, size, flags, ppData);
    }
}

pub inline fn unmapMemory(device: c.VkDevice, memory: c.VkDeviceMemory) void {
    if (builtin.os.tag == .macos) {
        rtVkUnmapMemory(device, memory);
    } else {
        c.vkUnmapMemory(device, memory);
    }
}

pub inline fn createBuffer(device: c.VkDevice, pCreateInfo: [*c]const c.VkBufferCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pBuffer: [*c]c.VkBuffer) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateBuffer(device, pCreateInfo, pAllocator, pBuffer);
    } else {
        return c.vkCreateBuffer(device, pCreateInfo, pAllocator, pBuffer);
    }
}

pub inline fn getBufferMemoryRequirements(device: c.VkDevice, buffer: c.VkBuffer, pMemoryRequirements: [*c]c.VkMemoryRequirements) void {
    if (builtin.os.tag == .macos) {
        rtVkGetBufferMemoryRequirements(device, buffer, pMemoryRequirements);
    } else {
        c.vkGetBufferMemoryRequirements(device, buffer, pMemoryRequirements);
    }
}

pub inline fn allocateMemory(device: c.VkDevice, pAllocateInfo: [*c]const c.VkMemoryAllocateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pMemory: [*c]c.VkDeviceMemory) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    } else {
        return c.vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    }
}

pub inline fn bindBufferMemory(device: c.VkDevice, buffer: c.VkBuffer, memory: c.VkDeviceMemory, memoryOffset: c.VkDeviceSize) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkBindBufferMemory(device, buffer, memory, memoryOffset);
    } else {
        return c.vkBindBufferMemory(device, buffer, memory, memoryOffset);
    }
}

pub inline fn createImage(device: c.VkDevice, pCreateInfo: [*c]const c.VkImageCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pImage: [*c]c.VkImage) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateImage(device, pCreateInfo, pAllocator, pImage);
    } else {
        return c.vkCreateImage(device, pCreateInfo, pAllocator, pImage);
    }
}

pub inline fn getImageMemoryRequirements(device: c.VkDevice, image: c.VkImage, pMemoryRequirements: [*c]c.VkMemoryRequirements) void {
    if (builtin.os.tag == .macos) {
        rtVkGetImageMemoryRequirements(device, image, pMemoryRequirements);
    } else {
        c.vkGetImageMemoryRequirements(device, image, pMemoryRequirements);
    }
}

pub inline fn bindImageMemory(device: c.VkDevice, image: c.VkImage, memory: c.VkDeviceMemory, memoryOffset: c.VkDeviceSize) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkBindImageMemory(device, image, memory, memoryOffset);
    } else {
        return c.vkBindImageMemory(device, image, memory, memoryOffset);
    }
}

pub inline fn cmdPipelineBarrier(commandBuffer: c.VkCommandBuffer, srcStageMask: c.VkPipelineStageFlags, dstStageMask: c.VkPipelineStageFlags,
    dependencyFlags: c.VkDependencyFlags, memoryBarrierCount: u32, pMemoryBarriers: [*c]const c.VkMemoryBarrier, bufferMemoryBarrierCount: u32,
    pBufferMemoryBarriers: [*c]const c.VkBufferMemoryBarrier, imageMemoryBarrierCount: u32, pImageMemoryBarriers: [*c]const c.VkImageMemoryBarrier
) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdPipelineBarrier(commandBuffer, srcStageMask, dstStageMask, dependencyFlags, memoryBarrierCount, pMemoryBarriers, bufferMemoryBarrierCount, pBufferMemoryBarriers, imageMemoryBarrierCount, pImageMemoryBarriers);
    } else {
        c.vkCmdPipelineBarrier(commandBuffer, srcStageMask, dstStageMask, dependencyFlags, memoryBarrierCount, pMemoryBarriers, bufferMemoryBarrierCount, pBufferMemoryBarriers, imageMemoryBarrierCount, pImageMemoryBarriers);
    }
}

pub inline fn cmdCopyBufferToImage(commandBuffer: c.VkCommandBuffer, srcBuffer: c.VkBuffer, dstImage: c.VkImage, dstImageLayout: c.VkImageLayout, regionCount: u32, pRegions: [*c]const c.VkBufferImageCopy) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdCopyBufferToImage(commandBuffer, srcBuffer, dstImage, dstImageLayout, regionCount, pRegions);
    } else {
        c.vkCmdCopyBufferToImage(commandBuffer, srcBuffer, dstImage, dstImageLayout, regionCount, pRegions);
    }
}

pub inline fn getPhysicalDeviceMemoryProperties(physicalDevice: c.VkPhysicalDevice, pMemoryProperties: [*c]c.VkPhysicalDeviceMemoryProperties) void {
    if (builtin.os.tag == .macos) {
        rtVkGetPhysicalDeviceMemoryProperties(physicalDevice, pMemoryProperties);
    } else {
        c.vkGetPhysicalDeviceMemoryProperties(physicalDevice, pMemoryProperties);
    }
}

pub inline fn queueSubmit(queue: c.VkQueue, submitCount: u32, pSubmits: [*c]const c.VkSubmitInfo, fence: c.VkFence) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkQueueSubmit(queue, submitCount, pSubmits, fence);
    } else {
        return c.vkQueueSubmit(queue, submitCount, pSubmits, fence);
    }
}

pub inline fn queueWaitIdle(queue: c.VkQueue) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkQueueWaitIdle(queue);
    } else {
        return c.vkQueueWaitIdle(queue);
    }
}

pub inline fn freeCommandBuffers(device: c.VkDevice, commandPool: c.VkCommandPool, commandBufferCount: u32, pCommandBuffers: [*c]const c.VkCommandBuffer) void {
    if (builtin.os.tag == .macos) {
        return rtVkFreeCommandBuffers(device, commandPool, commandBufferCount, pCommandBuffers);
    } else {
        return c.vkFreeCommandBuffers(device, commandPool, commandBufferCount, pCommandBuffers);
    }
}

pub inline fn enumerateInstanceExtensionProperties(pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]c.VkExtensionProperties) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkEnumerateInstanceExtensionProperties(pLayerName, pPropertyCount, pProperties);
    } else {
        return c.vkEnumerateInstanceExtensionProperties(pLayerName, pPropertyCount, pProperties);
    }
}

pub inline fn destroyBuffer(device: c.VkDevice, buffer: c.VkBuffer, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyBuffer(device, buffer, pAllocator);
    } else {
        c.vkDestroyBuffer(device, buffer, pAllocator);
    }
}

pub inline fn freeMemory(device: c.VkDevice, memory: c.VkDeviceMemory, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkFreeMemory(device, memory, pAllocator);
    } else {
        c.vkFreeMemory(device, memory, pAllocator);
    }
}

pub inline fn destroyImage(device: c.VkDevice, image: c.VkImage, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyImage(device, image, pAllocator);
    } else {
        c.vkDestroyImage(device, image, pAllocator);
    }
}

pub inline fn destroyImageView(device: c.VkDevice, imageView: c.VkImageView, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyImageView(device, imageView, pAllocator);
    } else {
        c.vkDestroyImageView(device, imageView, pAllocator);
    }
}

pub inline fn createDescriptorSetLayout(device: c.VkDevice, pCreateInfo: [*c]const c.VkDescriptorSetLayoutCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSetLayout: [*c]c.VkDescriptorSetLayout) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateDescriptorSetLayout(device, pCreateInfo, pAllocator, pSetLayout);
    } else {
        return c.vkCreateDescriptorSetLayout(device, pCreateInfo, pAllocator, pSetLayout);
    }
}

pub inline fn createSampler(device: c.VkDevice, pCreateInfo: [*c]const c.VkSamplerCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSampler: [*c]c.VkSampler) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateSampler(device, pCreateInfo, pAllocator, pSampler);
    } else {
        return c.vkCreateSampler(device, pCreateInfo, pAllocator, pSampler);
    }
}

pub inline fn waitForFences(device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence, waitAll: c.VkBool32, timeout: u64) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkWaitForFences(device, fenceCount, pFences, waitAll, timeout);
    } else {
        return c.vkWaitForFences(device, fenceCount, pFences, waitAll, timeout);
    }
}

pub inline fn resetFences(device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkResetFences(device, fenceCount, pFences);
    } else {
        return c.vkResetFences(device, fenceCount, pFences);
    }
}

pub inline fn acquireNextImageKHR(device: c.VkDevice, swapchain: c.VkSwapchainKHR, timeout: u64, semaphore: c.VkSemaphore, fence: c.VkFence, pImageIndex: [*c]u32) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkAcquireNextImageKHR(device, swapchain, timeout, semaphore, fence, pImageIndex);
    } else {
        return c.vkAcquireNextImageKHR(device, swapchain, timeout, semaphore, fence, pImageIndex);
    }
}

pub inline fn queuePresentKHR(queue: c.VkQueue, pPresentInfo: [*c]const c.VkPresentInfoKHR) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkQueuePresentKHR(queue, pPresentInfo);
    } else {
        return c.vkQueuePresentKHR(queue, pPresentInfo);
    }
}

pub inline fn cmdBindVertexBuffers(commandBuffer: c.VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: [*c]const c.VkBuffer, pOffsets: [*c]const c.VkDeviceSize) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdBindVertexBuffers(commandBuffer, firstBinding, bindingCount, pBuffers, pOffsets);
    } else {
        c.vkCmdBindVertexBuffers(commandBuffer, firstBinding, bindingCount, pBuffers, pOffsets);
    }
}

pub inline fn cmdBindIndexBuffer(commandBuffer: c.VkCommandBuffer, buffer: c.VkBuffer, offset: c.VkDeviceSize, indexType: c.VkIndexType) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdBindIndexBuffer(commandBuffer, buffer, offset, indexType);
    } else {
        c.vkCmdBindIndexBuffer(commandBuffer, buffer, offset, indexType);
    }
}

pub inline fn cmdDrawIndexed(commandBuffer: c.VkCommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdDrawIndexed(commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
    } else {
        c.vkCmdDrawIndexed(commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
    }
}

pub inline fn cmdPushConstants(commandBuffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, stageFlags: c.VkShaderStageFlags, offset: u32, size: u32, pValues: ?*const anyopaque) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdPushConstants(commandBuffer, layout, stageFlags, offset, size, pValues);
    } else {
        c.vkCmdPushConstants(commandBuffer, layout, stageFlags, offset, size, pValues);
    }
}

pub inline fn cmdBindDescriptorSets(commandBuffer: c.VkCommandBuffer, pipelineBindPoint: c.VkPipelineBindPoint, layout: c.VkPipelineLayout, firstSet: u32, descriptorSetCount: u32, pDescriptorSets: [*c]const c.VkDescriptorSet, dynamicOffsetCount: u32, pDynamicOffsets: [*c]const u32) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdBindDescriptorSets(commandBuffer, pipelineBindPoint, layout, firstSet, descriptorSetCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
    } else {
        c.vkCmdBindDescriptorSets(commandBuffer, pipelineBindPoint, layout, firstSet, descriptorSetCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
    }
}

pub inline fn createDescriptorPool(device: c.VkDevice, pCreateInfo: [*c]const c.VkDescriptorPoolCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pDescriptorPool: [*c]c.VkDescriptorPool) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkCreateDescriptorPool(device, pCreateInfo, pAllocator, pDescriptorPool);
    } else {
        return c.vkCreateDescriptorPool(device, pCreateInfo, pAllocator, pDescriptorPool);
    }
}

pub inline fn allocateDescriptorSets(device: c.VkDevice, pAllocateInfo: [*c]const c.VkDescriptorSetAllocateInfo, pDescriptorSets: [*c]c.VkDescriptorSet) c.VkResult {
    if (builtin.os.tag == .macos) {
        return rtVkAllocateDescriptorSets(device, pAllocateInfo, pDescriptorSets);
    } else {
        return c.vkAllocateDescriptorSets(device, pAllocateInfo, pDescriptorSets);
    }
}

pub inline fn updateDescriptorSets(device: c.VkDevice, descriptorWriteCount: u32, pDescriptorWrites: [*c]const c.VkWriteDescriptorSet, descriptorCopyCount: u32, pDescriptorCopies: [*c]const c.VkCopyDescriptorSet) void {
    if (builtin.os.tag == .macos) {
        return rtVkUpdateDescriptorSets(device, descriptorWriteCount, pDescriptorWrites, descriptorCopyCount, pDescriptorCopies);
    } else {
        return c.vkUpdateDescriptorSets(device, descriptorWriteCount, pDescriptorWrites, descriptorCopyCount, pDescriptorCopies);
    }
}

pub inline fn getPhysicalDeviceFeatures(physicalDevice: c.VkPhysicalDevice, pFeatures: [*c]c.VkPhysicalDeviceFeatures) void {
    if (builtin.os.tag == .macos) {
        rtVkGetPhysicalDeviceFeatures(physicalDevice, pFeatures);
    } else {
        c.vkGetPhysicalDeviceFeatures(physicalDevice, pFeatures);
    }
}

pub inline fn destroyInstance(instance: c.VkInstance, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyInstance(instance, pAllocator);
    } else {
        c.vkDestroyInstance(instance, pAllocator);
    }
}

pub inline fn destroyDevice(device: c.VkDevice, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyDevice(device, pAllocator);
    } else {
        c.vkDestroyDevice(device, pAllocator);
    }
}

pub inline fn destroySurfaceKHR(instance: c.VkInstance, surface: c.VkSurfaceKHR, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroySurfaceKHR(instance, surface, pAllocator);
    } else {
        c.vkDestroySurfaceKHR(instance, surface, pAllocator);
    }
}

pub inline fn destroySemaphore(device: c.VkDevice, semaphore: c.VkSemaphore, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroySemaphore(device, semaphore, pAllocator);
    } else {
        c.vkDestroySemaphore(device, semaphore, pAllocator);
    }
}

pub inline fn destroyFence(device: c.VkDevice, fence: c.VkFence, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyFence(device, fence, pAllocator);
    } else {
        c.vkDestroyFence(device, fence, pAllocator);
    }
}

pub inline fn destroyPipeline(device: c.VkDevice, pipeline: c.VkPipeline, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyPipeline(device, pipeline, pAllocator);
    } else {
        c.vkDestroyPipeline(device, pipeline, pAllocator);
    }
}

pub inline fn destroyPipelineLayout(device: c.VkDevice, pipelineLayout: c.VkPipelineLayout, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyPipelineLayout(device, pipelineLayout, pAllocator);
    } else {
        c.vkDestroyPipelineLayout(device, pipelineLayout, pAllocator);
    }
}

pub inline fn destroySwapchainKHR(device: c.VkDevice, swapchain: c.VkSwapchainKHR, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroySwapchainKHR(device, swapchain, pAllocator);
    } else {
        c.vkDestroySwapchainKHR(device, swapchain, pAllocator);
    }
}

pub inline fn destroyFramebuffer(device: c.VkDevice, framebuffer: c.VkFramebuffer, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyFramebuffer(device, framebuffer, pAllocator);
    } else {
        c.vkDestroyFramebuffer(device, framebuffer, pAllocator);
    }
}

pub inline fn destroyDescriptorSetLayout(device: c.VkDevice, descriptorSetLayout: c.VkDescriptorSetLayout, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyDescriptorSetLayout(device, descriptorSetLayout, pAllocator);
    } else {
        c.vkDestroyDescriptorSetLayout(device, descriptorSetLayout, pAllocator);
    }
}

pub inline fn destroyDescriptorPool(device: c.VkDevice, descriptorPool: c.VkDescriptorPool, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyDescriptorPool(device, descriptorPool, pAllocator);
    } else {
        c.vkDestroyDescriptorPool(device, descriptorPool, pAllocator);
    }
}

pub inline fn destroySampler(device: c.VkDevice, sampler: c.VkSampler, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroySampler(device, sampler, pAllocator);
    } else {
        c.vkDestroySampler(device, sampler, pAllocator);
    }
}

pub inline fn destroyRenderPass(device: c.VkDevice, renderPass: c.VkRenderPass, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyRenderPass(device, renderPass, pAllocator);
    } else {
        c.vkDestroyRenderPass(device, renderPass, pAllocator);
    }
}

pub inline fn destroyCommandPool(device: c.VkDevice, commandPool: c.VkCommandPool, pAllocator: [*c]const c.VkAllocationCallbacks) void {
    if (builtin.os.tag == .macos) {
        rtVkDestroyCommandPool(device, commandPool, pAllocator);
    } else {
        c.vkDestroyCommandPool(device, commandPool, pAllocator);
    }
}

pub inline fn cmdSetScissor(commandBuffer: c.VkCommandBuffer, firstScissor: u32, scissorCount: u32, pScissors: [*c]const c.VkRect2D) void {
    if (builtin.os.tag == .macos) {
        rtVkCmdSetScissor(commandBuffer, firstScissor, scissorCount, pScissors);
    } else {
        c.vkCmdSetScissor(commandBuffer, firstScissor, scissorCount, pScissors);
    }
}

var rtVkGetInstanceProcAddr: fn (instance: c.VkInstance, pName: [*c]const u8) c.PFN_vkVoidFunction = undefined;
var rtVkCreateInstance: fn (pCreateInfo: [*c]const c.VkInstanceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pInstance: [*c]c.VkInstance) c.VkResult = undefined;
var rtVkEnumeratePhysicalDevices: fn (instance: c.VkInstance, pPhysicalDeviceCount: [*c]u32, pPhysicalDevices: [*c]c.VkPhysicalDevice) c.VkResult = undefined;
var rtVkGetPhysicalDeviceQueueFamilyProperties: fn (physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties) void = undefined;
var rtVkGetPhysicalDeviceSurfaceSupportKHR: fn (physicalDevice: c.VkPhysicalDevice, queueFamilyIndex: u32, surface: c.VkSurfaceKHR, pSupported: [*c]c.VkBool32) c.VkResult = undefined;
var rtVkEnumerateDeviceExtensionProperties: fn (physicalDevice: c.VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]c.VkExtensionProperties) c.VkResult = undefined;
var rtVkGetPhysicalDeviceSurfaceCapabilitiesKHR: fn (physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceCapabilities: [*c]c.VkSurfaceCapabilitiesKHR) c.VkResult = undefined;
var rtVkGetPhysicalDeviceSurfacePresentModesKHR: fn (physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pPresentModeCount: [*c]u32, pPresentModes: [*c]c.VkPresentModeKHR) c.VkResult = undefined;
var rtVkGetPhysicalDeviceSurfaceFormatsKHR: fn (physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceFormatCount: [*c]u32, pSurfaceFormats: [*c]c.VkSurfaceFormatKHR) c.VkResult = undefined;
var rtVkCreateDevice: fn (physicalDevice: c.VkPhysicalDevice, pCreateInfo: [*c]const c.VkDeviceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pDevice: [*c]c.VkDevice) c.VkResult = undefined;
var rtVkGetDeviceQueue: fn (device: c.VkDevice, queueFamilyIndex: u32, queueIndex: u32, pQueue: [*c]c.VkQueue) void = undefined;
var rtVkCreateSwapchainKHR: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkSwapchainCreateInfoKHR, pAllocator: [*c]const c.VkAllocationCallbacks, pSwapchain: [*c]c.VkSwapchainKHR) c.VkResult = undefined;
var rtVkGetSwapchainImagesKHR: fn (device: c.VkDevice, swapchain: c.VkSwapchainKHR, pSwapchainImageCount: [*c]u32, pSwapchainImages: [*c]c.VkImage) c.VkResult = undefined;
var rtVkCreateImageView: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkImageViewCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pView: [*c]c.VkImageView) c.VkResult = undefined;
var rtVkCreateRenderPass: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkRenderPassCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pRenderPass: [*c]c.VkRenderPass) c.VkResult = undefined;
var rtVkCreatePipelineLayout: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkPipelineLayoutCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pPipelineLayout: [*c]c.VkPipelineLayout) c.VkResult = undefined;
var rtVkCreateShaderModule: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkShaderModuleCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pShaderModule: [*c]c.VkShaderModule) c.VkResult = undefined;
var rtVkCreateGraphicsPipelines: fn (device: c.VkDevice, pipelineCache: c.VkPipelineCache, createInfoCount: u32, pCreateInfos: [*c]const c.VkGraphicsPipelineCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pPipelines: [*c]c.VkPipeline) c.VkResult = undefined;
var rtVkDestroyShaderModule: fn (device: c.VkDevice, shaderModule: c.VkShaderModule, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkCreateFramebuffer: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkFramebufferCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pFramebuffer: [*c]c.VkFramebuffer) c.VkResult = undefined;
var rtVkCreateCommandPool: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkCommandPoolCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pCommandPool: [*c]c.VkCommandPool) c.VkResult = undefined;
var rtVkAllocateCommandBuffers: fn (device: c.VkDevice, pAllocateInfo: [*c]const c.VkCommandBufferAllocateInfo, pCommandBuffers: [*c]c.VkCommandBuffer) c.VkResult = undefined;
var rtVkBeginCommandBuffer: fn (commandBuffer: c.VkCommandBuffer, pBeginInfo: [*c]const c.VkCommandBufferBeginInfo) c.VkResult = undefined;
var rtVkCmdBeginRenderPass: fn (commandBuffer: c.VkCommandBuffer, pRenderPassBegin: [*c]const c.VkRenderPassBeginInfo, contents: c.VkSubpassContents) void = undefined;
var rtVkCmdBindPipeline: fn (commandBuffer: c.VkCommandBuffer, pipelineBindPoint: c.VkPipelineBindPoint, pipeline: c.VkPipeline) void = undefined;
var rtVkCmdDraw: fn (commandBuffer: c.VkCommandBuffer, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void = undefined;
var rtVkCmdEndRenderPass: fn (commandBuffer: c.VkCommandBuffer) void = undefined;
var rtVkEndCommandBuffer: fn (commandBuffer: c.VkCommandBuffer) c.VkResult = undefined;
var rtVkCreateSemaphore: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkSemaphoreCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSemaphore: [*c]c.VkSemaphore) c.VkResult = undefined;
var rtVkCreateFence: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkFenceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pFence: [*c]c.VkFence) c.VkResult = undefined;
var rtVkEnumerateInstanceLayerProperties: fn (pPropertyCount: [*c]u32, pProperties: [*c]c.VkLayerProperties) c.VkResult = undefined;
var rtVkMapMemory: fn (device: c.VkDevice, memory: c.VkDeviceMemory, offset: c.VkDeviceSize, size: c.VkDeviceSize, flags: c.VkMemoryMapFlags, ppData: [*c]?*anyopaque) c.VkResult = undefined;
var rtVkUnmapMemory: fn (device: c.VkDevice, memory: c.VkDeviceMemory) void = undefined;
var rtVkCreateBuffer: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkBufferCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pBuffer: [*c]c.VkBuffer) c.VkResult = undefined;
var rtVkGetBufferMemoryRequirements: fn (device: c.VkDevice, buffer: c.VkBuffer, pMemoryRequirements: [*c]c.VkMemoryRequirements) void = undefined;
var rtVkAllocateMemory: fn (device: c.VkDevice, pAllocateInfo: [*c]const c.VkMemoryAllocateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pMemory: [*c]c.VkDeviceMemory) c.VkResult = undefined;
var rtVkBindBufferMemory: fn (device: c.VkDevice, buffer: c.VkBuffer, memory: c.VkDeviceMemory, memoryOffset: c.VkDeviceSize) c.VkResult = undefined;
var rtVkCreateImage: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkImageCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pImage: [*c]c.VkImage) c.VkResult = undefined;
var rtVkGetImageMemoryRequirements: fn (device: c.VkDevice, image: c.VkImage, pMemoryRequirements: [*c]c.VkMemoryRequirements) void = undefined;
var rtVkBindImageMemory: fn (device: c.VkDevice, image: c.VkImage, memory: c.VkDeviceMemory, memoryOffset: c.VkDeviceSize) c.VkResult = undefined;
var rtVkCmdPipelineBarrier: fn (commandBuffer: c.VkCommandBuffer, srcStageMask: c.VkPipelineStageFlags, dstStageMask: c.VkPipelineStageFlags, dependencyFlags: c.VkDependencyFlags, memoryBarrierCount: u32, pMemoryBarriers: [*c]const c.VkMemoryBarrier, bufferMemoryBarrierCount: u32, pBufferMemoryBarriers: [*c]const c.VkBufferMemoryBarrier, imageMemoryBarrierCount: u32, pImageMemoryBarriers: [*c]const c.VkImageMemoryBarrier) void = undefined;
var rtVkCmdCopyBufferToImage: fn (commandBuffer: c.VkCommandBuffer, srcBuffer: c.VkBuffer, dstImage: c.VkImage, dstImageLayout: c.VkImageLayout, regionCount: u32, pRegions: [*c]const c.VkBufferImageCopy) void = undefined;
var rtVkGetPhysicalDeviceMemoryProperties: fn (physicalDevice: c.VkPhysicalDevice, pMemoryProperties: [*c]c.VkPhysicalDeviceMemoryProperties) void = undefined;
var rtVkQueueSubmit: fn (queue: c.VkQueue, submitCount: u32, pSubmits: [*c]const c.VkSubmitInfo, fence: c.VkFence) c.VkResult = undefined;
var rtVkQueueWaitIdle: fn (queue: c.VkQueue) c.VkResult = undefined;
var rtVkFreeCommandBuffers: fn (device: c.VkDevice, commandPool: c.VkCommandPool, commandBufferCount: u32, pCommandBuffers: [*c]const c.VkCommandBuffer) void = undefined;
var rtVkEnumerateInstanceExtensionProperties: fn (pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]c.VkExtensionProperties) c.VkResult = undefined;
var rtVkDestroyBuffer: fn (device: c.VkDevice, buffer: c.VkBuffer, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkFreeMemory: fn (device: c.VkDevice, memory: c.VkDeviceMemory, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyImage: fn (device: c.VkDevice, image: c.VkImage, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyImageView: fn (device: c.VkDevice, imageView: c.VkImageView, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkCreateDescriptorSetLayout: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkDescriptorSetLayoutCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSetLayout: [*c]c.VkDescriptorSetLayout) c.VkResult = undefined;
var rtVkCreateSampler: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkSamplerCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSampler: [*c]c.VkSampler) c.VkResult = undefined;
var rtVkWaitForFences: fn (device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence, waitAll: c.VkBool32, timeout: u64) c.VkResult = undefined;
var rtVkResetFences: fn (device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence) c.VkResult = undefined;
var rtVkAcquireNextImageKHR: fn (device: c.VkDevice, swapchain: c.VkSwapchainKHR, timeout: u64, semaphore: c.VkSemaphore, fence: c.VkFence, pImageIndex: [*c]u32) c.VkResult = undefined;
var rtVkQueuePresentKHR: fn (queue: c.VkQueue, pPresentInfo: [*c]const c.VkPresentInfoKHR) c.VkResult = undefined;
var rtVkCmdBindVertexBuffers: fn (commandBuffer: c.VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: [*c]const c.VkBuffer, pOffsets: [*c]const c.VkDeviceSize) void = undefined;
var rtVkCmdBindIndexBuffer: fn (commandBuffer: c.VkCommandBuffer, buffer: c.VkBuffer, offset: c.VkDeviceSize, indexType: c.VkIndexType) void = undefined;
var rtVkCmdDrawIndexed: fn (commandBuffer: c.VkCommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32) void = undefined;
var rtVkCmdPushConstants: fn (commandBuffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, stageFlags: c.VkShaderStageFlags, offset: u32, size: u32, pValues: ?*const anyopaque) void = undefined;
var rtVkCmdBindDescriptorSets: fn (commandBuffer: c.VkCommandBuffer, pipelineBindPoint: c.VkPipelineBindPoint, layout: c.VkPipelineLayout, firstSet: u32, descriptorSetCount: u32, pDescriptorSets: [*c]const c.VkDescriptorSet, dynamicOffsetCount: u32, pDynamicOffsets: [*c]const u32) void = undefined;
var rtVkCreateDescriptorPool: fn (device: c.VkDevice, pCreateInfo: [*c]const c.VkDescriptorPoolCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pDescriptorPool: [*c]c.VkDescriptorPool) c.VkResult = undefined;
var rtVkAllocateDescriptorSets: fn (device: c.VkDevice, pAllocateInfo: [*c]const c.VkDescriptorSetAllocateInfo, pDescriptorSets: [*c]c.VkDescriptorSet) c.VkResult = undefined;
var rtVkUpdateDescriptorSets: fn (device: c.VkDevice, descriptorWriteCount: u32, pDescriptorWrites: [*c]const c.VkWriteDescriptorSet, descriptorCopyCount: u32, pDescriptorCopies: [*c]const c.VkCopyDescriptorSet) void = undefined;
var rtVkGetPhysicalDeviceFeatures: fn (physicalDevice: c.VkPhysicalDevice, pFeatures: [*c]c.VkPhysicalDeviceFeatures) void = undefined;
var rtVkDestroyInstance: fn (instance: c.VkInstance, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyDevice: fn (device: c.VkDevice, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroySurfaceKHR: fn (instance: c.VkInstance, surface: c.VkSurfaceKHR, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroySemaphore: fn (device: c.VkDevice, semaphore: c.VkSemaphore, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyFence: fn (device: c.VkDevice, fence: c.VkFence, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyPipeline: fn (device: c.VkDevice, pipeline: c.VkPipeline, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyPipelineLayout: fn (device: c.VkDevice, pipelineLayout: c.VkPipelineLayout, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroySwapchainKHR: fn (device: c.VkDevice, swapchain: c.VkSwapchainKHR, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyFramebuffer: fn (device: c.VkDevice, framebuffer: c.VkFramebuffer, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyDescriptorSetLayout: fn (device: c.VkDevice, descriptorSetLayout: c.VkDescriptorSetLayout, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyDescriptorPool: fn (device: c.VkDevice, descriptorPool: c.VkDescriptorPool, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroySampler: fn (device: c.VkDevice, sampler: c.VkSampler, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyRenderPass: fn (device: c.VkDevice, renderPass: c.VkRenderPass, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkDestroyCommandPool: fn (device: c.VkDevice, commandPool: c.VkCommandPool, pAllocator: [*c]const c.VkAllocationCallbacks) void = undefined;
var rtVkCmdSetScissor: fn (commandBuffer: c.VkCommandBuffer, firstScissor: u32, scissorCount: u32, pScissors: [*c]const c.VkRect2D) void = undefined;

/// Vulkan is translated to Metal on macOS through MoltenVK. After SDL_Vulkan_LoadLibrary or creating a sdl window with SDL_WINDOW_VULKAN,
/// this should be invoked to bind the vk functions at runtime.
pub fn initMacVkInstanceFuncs() void {
    rtVkGetInstanceProcAddr = @ptrCast(@TypeOf(rtVkGetInstanceProcAddr), sdl.SDL_Vulkan_GetVkGetInstanceProcAddr());
    loadVkFunc(&rtVkCreateInstance, null, "vkCreateInstance");
    loadVkFunc(&rtVkEnumerateInstanceLayerProperties, null, "vkEnumerateInstanceLayerProperties");
    loadVkFunc(&rtVkEnumerateInstanceExtensionProperties, null, "vkEnumerateInstanceExtensionProperties");
}
pub fn initMacVkFunctions(instance: c.VkInstance) void {
    loadVkFunc(&rtVkEnumeratePhysicalDevices, instance, "vkEnumeratePhysicalDevices");
    loadVkFunc(&rtVkGetPhysicalDeviceQueueFamilyProperties, instance, "vkGetPhysicalDeviceQueueFamilyProperties");
    loadVkFunc(&rtVkGetPhysicalDeviceSurfaceSupportKHR, instance, "vkGetPhysicalDeviceSurfaceSupportKHR");
    loadVkFunc(&rtVkEnumerateDeviceExtensionProperties, instance, "vkEnumerateDeviceExtensionProperties");
    loadVkFunc(&rtVkGetPhysicalDeviceSurfaceCapabilitiesKHR, instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    loadVkFunc(&rtVkGetPhysicalDeviceSurfacePresentModesKHR, instance, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    loadVkFunc(&rtVkGetPhysicalDeviceSurfaceFormatsKHR, instance, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    loadVkFunc(&rtVkCreateDevice, instance, "vkCreateDevice");
    loadVkFunc(&rtVkGetDeviceQueue, instance, "vkGetDeviceQueue");
    loadVkFunc(&rtVkCreateSwapchainKHR, instance, "vkCreateSwapchainKHR");
    loadVkFunc(&rtVkGetSwapchainImagesKHR, instance, "vkGetSwapchainImagesKHR");
    loadVkFunc(&rtVkCreateImageView, instance, "vkCreateImageView");
    loadVkFunc(&rtVkCreateRenderPass, instance, "vkCreateRenderPass");
    loadVkFunc(&rtVkCreatePipelineLayout, instance, "vkCreatePipelineLayout");
    loadVkFunc(&rtVkCreateShaderModule, instance, "vkCreateShaderModule");
    loadVkFunc(&rtVkCreateGraphicsPipelines, instance, "vkCreateGraphicsPipelines");
    loadVkFunc(&rtVkDestroyShaderModule, instance, "vkDestroyShaderModule");
    loadVkFunc(&rtVkCreateFramebuffer, instance, "vkCreateFramebuffer");
    loadVkFunc(&rtVkCreateCommandPool, instance, "vkCreateCommandPool");
    loadVkFunc(&rtVkAllocateCommandBuffers, instance, "vkAllocateCommandBuffers");
    loadVkFunc(&rtVkBeginCommandBuffer, instance, "vkBeginCommandBuffer");
    loadVkFunc(&rtVkCmdBeginRenderPass, instance, "vkCmdBeginRenderPass");
    loadVkFunc(&rtVkCmdBindPipeline, instance, "vkCmdBindPipeline");
    loadVkFunc(&rtVkCmdDraw, instance, "vkCmdDraw");
    loadVkFunc(&rtVkCmdEndRenderPass, instance, "vkCmdEndRenderPass");
    loadVkFunc(&rtVkEndCommandBuffer, instance, "vkEndCommandBuffer");
    loadVkFunc(&rtVkCreateSemaphore, instance, "vkCreateSemaphore");
    loadVkFunc(&rtVkCreateFence, instance, "vkCreateFence");
    loadVkFunc(&rtVkEnumerateDeviceExtensionProperties, instance, "vkEnumerateDeviceExtensionProperties");
    loadVkFunc(&rtVkMapMemory, instance, "vkMapMemory");
    loadVkFunc(&rtVkUnmapMemory, instance, "vkUnmapMemory");
    loadVkFunc(&rtVkCreateBuffer, instance, "vkCreateBuffer");
    loadVkFunc(&rtVkGetBufferMemoryRequirements, instance, "vkGetBufferMemoryRequirements");
    loadVkFunc(&rtVkAllocateMemory, instance, "vkAllocateMemory");
    loadVkFunc(&rtVkBindBufferMemory, instance, "vkBindBufferMemory");
    loadVkFunc(&rtVkCreateImage, instance, "vkCreateImage");
    loadVkFunc(&rtVkGetImageMemoryRequirements, instance, "vkGetImageMemoryRequirements");
    loadVkFunc(&rtVkBindImageMemory, instance, "vkBindImageMemory");
    loadVkFunc(&rtVkCmdPipelineBarrier, instance, "vkCmdPipelineBarrier");
    loadVkFunc(&rtVkCmdCopyBufferToImage, instance, "vkCmdCopyBufferToImage");
    loadVkFunc(&rtVkGetPhysicalDeviceMemoryProperties, instance, "vkGetPhysicalDeviceMemoryProperties");
    loadVkFunc(&rtVkQueueSubmit, instance, "vkQueueSubmit");
    loadVkFunc(&rtVkQueueWaitIdle, instance, "vkQueueWaitIdle");
    loadVkFunc(&rtVkFreeCommandBuffers, instance, "vkFreeCommandBuffers");
    loadVkFunc(&rtVkDestroyBuffer, instance, "vkDestroyBuffer");
    loadVkFunc(&rtVkFreeMemory, instance, "vkFreeMemory");
    loadVkFunc(&rtVkDestroyImage, instance, "vkDestroyImage");
    loadVkFunc(&rtVkDestroyImageView, instance, "vkDestroyImageView");
    loadVkFunc(&rtVkCreateDescriptorSetLayout, instance, "vkCreateDescriptorSetLayout");
    loadVkFunc(&rtVkCreateSampler, instance, "vkCreateSampler");
    loadVkFunc(&rtVkWaitForFences, instance, "vkWaitForFences");
    loadVkFunc(&rtVkResetFences, instance, "vkResetFences");
    loadVkFunc(&rtVkAcquireNextImageKHR, instance, "vkAcquireNextImageKHR");
    loadVkFunc(&rtVkQueuePresentKHR, instance, "vkQueuePresentKHR");
    loadVkFunc(&rtVkCmdBindVertexBuffers, instance, "vkCmdBindVertexBuffers");
    loadVkFunc(&rtVkCmdBindIndexBuffer, instance, "vkCmdBindIndexBuffer");
    loadVkFunc(&rtVkCmdDrawIndexed, instance, "vkCmdDrawIndexed");
    loadVkFunc(&rtVkCmdPushConstants, instance, "vkCmdPushConstants");
    loadVkFunc(&rtVkCmdBindDescriptorSets, instance, "vkCmdBindDescriptorSets");
    loadVkFunc(&rtVkCreateDescriptorPool, instance, "vkCreateDescriptorPool");
    loadVkFunc(&rtVkAllocateDescriptorSets, instance, "vkAllocateDescriptorSets");
    loadVkFunc(&rtVkUpdateDescriptorSets, instance, "vkUpdateDescriptorSets");
    loadVkFunc(&rtVkGetPhysicalDeviceFeatures, instance, "vkGetPhysicalDeviceFeatures");
    loadVkFunc(&rtVkDestroyInstance, instance, "vkDestroyInstance");
    loadVkFunc(&rtVkDestroyDevice, instance, "vkDestroyDevice");
    loadVkFunc(&rtVkDestroySurfaceKHR, instance, "vkDestroySurfaceKHR");
    loadVkFunc(&rtVkDestroySemaphore, instance, "vkDestroySemaphore");
    loadVkFunc(&rtVkDestroyFence, instance, "vkDestroyFence");
    loadVkFunc(&rtVkDestroyPipeline, instance, "vkDestroyPipeline");
    loadVkFunc(&rtVkDestroyPipelineLayout, instance, "vkDestroyPipelineLayout");
    loadVkFunc(&rtVkDestroySwapchainKHR, instance, "vkDestroySwapchainKHR");
    loadVkFunc(&rtVkDestroyFramebuffer, instance, "vkDestroyFramebuffer");
    loadVkFunc(&rtVkDestroyDescriptorSetLayout, instance, "vkDestroyDescriptorSetLayout");
    loadVkFunc(&rtVkDestroyDescriptorPool, instance, "vkDestroyDescriptorPool");
    loadVkFunc(&rtVkDestroySampler, instance, "vkDestroySampler");
    loadVkFunc(&rtVkDestroyRenderPass, instance, "vkDestroyRenderPass");
    loadVkFunc(&rtVkDestroyCommandPool, instance, "vkDestroyCommandPool");
    loadVkFunc(&rtVkCmdSetScissor, instance, "vkCmdSetScissor");
}

fn loadVkFunc(ptr_to_fn: anytype, instance: c.VkInstance, name: [:0]const u8) void {
    if (rtVkGetInstanceProcAddr(instance, name)) |ptr| {
        const Ptr = std.meta.Child(@TypeOf(ptr_to_fn));
        ptr_to_fn.* = @ptrCast(Ptr, ptr);
    } else {
        std.debug.panic("Failed to load: {s}", .{name});
    }
}

pub fn assertSuccess(res: c.VkResult) void {
    if (res != c.VK_SUCCESS) {
        @panic("expected success");
    }
}
