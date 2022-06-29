const std = @import("std");
const vk = @import("vk");
const gvk = @import("graphics.zig");

pub const Pipeline = struct {
    pipeline: vk.VkPipeline,
    layout: vk.VkPipelineLayout,

    pub fn deinit(self: Pipeline, device: vk.VkDevice) void {
        vk.destroyPipeline(device, self.pipeline, null);
        vk.destroyPipelineLayout(device, self.layout, null);
    }
};

const PipelineOptions = struct {
    topology: vk.VkPrimitiveTopology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    vert_spv: []const u32,
    frag_spv: []const u32,
    geom_spv: []const u32 = &.{},

    depth_test: bool = true,

    // Only for drawing lines over a triangle topology. eg. LINES topology doesn't need this.
    line_mode: bool = false,
};

pub fn createDefaultPipeline(
    device: vk.VkDevice,
    pass: vk.VkRenderPass,
    view_dim: vk.VkExtent2D,
    pvis_info: vk.VkPipelineVertexInputStateCreateInfo,
    pl_info: vk.VkPipelineLayoutCreateInfo,
    opts: PipelineOptions,
) Pipeline {
    const vert_mod = gvk.shader.createShaderModule(device, opts.vert_spv);
    defer vk.destroyShaderModule(device, vert_mod, null);
    const frag_mod = gvk.shader.createShaderModule(device, opts.frag_spv);
    defer vk.destroyShaderModule(device, frag_mod, null);

    // ShaderStages
    const vert_pss_info = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_mod,
        .pName = "main",
        .pNext = null,
        .flags = 0,
        .pSpecializationInfo = null,
    };
    const frag_pss_info = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_mod,
        .pName = "main",
        .pNext = null,
        .flags = 0,
        .pSpecializationInfo = null,
    };

    var stages: []const vk.VkPipelineShaderStageCreateInfo = &.{
        vert_pss_info,
        frag_pss_info,
    };
    var geom_mod: vk.VkShaderModule = undefined;
    if (opts.geom_spv.len > 0) {
        geom_mod = gvk.shader.createShaderModule(device, opts.geom_spv);
        stages = &[_]vk.VkPipelineShaderStageCreateInfo{
            vert_pss_info,
            frag_pss_info,
            vk.VkPipelineShaderStageCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
                .module = geom_mod,
                .pName = "main",
                .pNext = null,
                .flags = 0,
                .pSpecializationInfo = null,
            },
        };
    }
    defer {
        if (opts.geom_spv.len > 0) {
            defer vk.destroyShaderModule(device, geom_mod, null);
        }
    }

    // InputAssemblyState
    const pias_info = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = opts.topology,
        .primitiveRestartEnable = vk.VK_FALSE,
        .pNext = null,
        .flags = 0,
    };

    // ViewportState
    const viewport = [_]vk.VkViewport{vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @intToFloat(f32, view_dim.width),
        .height = @intToFloat(f32, view_dim.height),
        .minDepth = 0,
        .maxDepth = 1,
    }};
    const scissor = [_]vk.VkRect2D{vk.VkRect2D{
        .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
        .extent = view_dim,
    }};
    const pvs_info = vk.VkPipelineViewportStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
        .pNext = null,
        .flags = 0,
    };

    // RasterizationState
    const prs_info = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = if (opts.line_mode) vk.VK_POLYGON_MODE_LINE else vk.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .pNext = null,
        .flags = 0,
        .depthBiasConstantFactor = 0,
        .depthBiasClamp = 0,
        .depthBiasSlopeFactor = 0,
    };

    // MultisampleState
    const pms_info = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = vk.VK_FALSE,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        .pNext = null,
        .flags = 0,
        .minSampleShading = 0,
        .pSampleMask = null,
        .alphaToCoverageEnable = 0,
        .alphaToOneEnable = 0,
    };

    // ColorBlendAttachmentState
    // For now default to transparent blending.
    const pcba_state = vk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        // .blendEnable = vk.VK_FALSE,
        // .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        // .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        // .colorBlendOp = vk.VK_BLEND_OP_ADD,
        // .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        // .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        // .alphaBlendOp = vk.VK_BLEND_OP_ADD,
    };

    // ColorBlendState
    const pcbs_info = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &pcba_state,
        .blendConstants = [_]f32{ 0, 0, 0, 0 },
        .pNext = null,
        .flags = 0,
    };

    // DynamicState, allow these states to by dynamically set in command buffers.
    const dynamic_states = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_SCISSOR,
        // VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE isn't widely supported.
    };
    const dynamic_state_info = vk.VkPipelineDynamicStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .flags = 0,
        .pDynamicStates = &dynamic_states,
        .pNext = null,
    };

    // DepthStencilState
    const depth_stencil_state = vk.VkPipelineDepthStencilStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthTestEnable = vk.fromBool(opts.depth_test),
        .depthWriteEnable = vk.fromBool(opts.depth_test),
        // Note that this will overwrite fragments if the depth is greater than what's in the buffer.
        // This implies that 0 is the far side and should be the clear value while 1 is the near side.
        .depthCompareOp = vk.VK_COMPARE_OP_GREATER,
        .depthBoundsTestEnable = vk.VK_FALSE,
        .minDepthBounds = 0,
        .maxDepthBounds = 1,
        .stencilTestEnable = vk.VK_FALSE,
        .front = std.mem.zeroInit(vk.VkStencilOpState, .{}),
        .back = std.mem.zeroInit(vk.VkStencilOpState, .{}),
    };

    var pipeline_layout: vk.VkPipelineLayout = undefined;
    var res = vk.createPipelineLayout(device, &pl_info, null, &pipeline_layout);

    const g_pipelines = [_]vk.VkGraphicsPipelineCreateInfo{vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = @intCast(u32, stages.len),
        .pStages = stages.ptr,
        .pVertexInputState = &pvis_info,
        .pInputAssemblyState = &pias_info,
        .pViewportState = &pvs_info,
        .pRasterizationState = &prs_info,
        .pMultisampleState = &pms_info,
        .pColorBlendState = &pcbs_info,
        .layout = pipeline_layout,
        .renderPass = pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .pNext = null,
        .flags = 0,
        .pTessellationState = null,
        .pDepthStencilState = &depth_stencil_state,
        .pDynamicState = &dynamic_state_info,
        .basePipelineIndex = 0,
    }};

    var pipeln: vk.VkPipeline = undefined;
    res = vk.createGraphicsPipelines(device, null, @intCast(u32, g_pipelines.len), &g_pipelines, null, &pipeln);
    vk.assertSuccess(res);
    return .{
        .pipeline = pipeln,
        .layout = pipeline_layout,
    };
}