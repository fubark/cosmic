const std = @import("std");
const vk = @import("vk");

pub const Pipeline = struct {
    pipeline: vk.VkPipeline,
    layout: vk.VkPipelineLayout,

    pub fn deinit(self: Pipeline, device: vk.VkDevice) void {
        vk.destroyPipeline(device, self.pipeline, null);
        vk.destroyPipelineLayout(device, self.layout, null);
    }
};
