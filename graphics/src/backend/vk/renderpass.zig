const vk = @import("vk");

pub fn createRenderPass(device: vk.VkDevice, format: vk.VkFormat) vk.VkRenderPass {
    const attachment = vk.VkAttachmentDescription{
        .format = format,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .flags = 0,
    };

    const attachment_ref = [1]vk.VkAttachmentReference{vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    }};

    const depth_attachment = vk.VkAttachmentDescription{
        .format = vk.VK_FORMAT_D32_SFLOAT,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .flags = 0,
    };
    const depth_attachment_ref = vk.VkAttachmentReference{
        .attachment = 1,
        .layout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    const subpass = [_]vk.VkSubpassDescription{vk.VkSubpassDescription{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = @as(*const [1]vk.VkAttachmentReference, &attachment_ref),
        .flags = 0,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = &depth_attachment_ref,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    }};

    const dependency = [_]vk.VkSubpassDependency{vk.VkSubpassDependency{
        .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .srcAccessMask = 0,
        .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    }};

    const attachments = [_]vk.VkAttachmentDescription{ attachment, depth_attachment };
    const info = vk.VkRenderPassCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = attachments.len,
        .pAttachments = &attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
        .pNext = null,
        .flags = 0,
    };

    var ret: vk.VkRenderPass = undefined;
    const res = vk.createRenderPass(device, &info, null, &ret);
    vk.assertSuccess(res);
    return ret;
}