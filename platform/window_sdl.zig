const std = @import("std");
const build_options = @import("build_options");
const stdx = @import("stdx");
const t = stdx.testing;
const math = stdx.math;
const Mat4 = math.Mat4;
const sdl = @import("sdl");
const gl = @import("gl");
const vk = @import("vk");
const builtin = @import("builtin");
const Backend = build_options.GraphicsBackend;

const window = @import("window.zig");
const Config = window.Config;
const Mode = window.Mode;
const log = stdx.log.scoped(.window_sdl);

const IsWebGL2 = builtin.target.isWasm();
extern "graphics" fn jsSetCanvasBuffer(width: u32, height: u32) u8;

const IsDesktop = !IsWebGL2;

pub const Window = struct {
    id: u32,
    sdl_window: *sdl.SDL_Window,

    // Since other windows can use the same context, we defer deinit until the last window.
    alloc: std.mem.Allocator,

    inner: switch (Backend) {
        .OpenGL => struct {
            gl_ctx_ref_count: *u32,
            gl_ctx: *anyopaque,
        },
        .Vulkan => struct {
            instance: vk.VkInstance,
            physical_device: vk.VkPhysicalDevice,
            device: vk.VkDevice,
            surface: vk.VkSurfaceKHR,
            queue_family: VkQueueFamilyPair,
        },
        else => @compileError("unsupported"),
    },

    width: u32,
    height: u32,

    // When creating a window with high dpi, the buffer size can differ from
    // the logical window size. (Usually a multiple, eg. 2x)
    buf_width: u32,
    buf_height: u32,

    /// Depth pixel ratio. Buffer size / logical window size.
    /// This isn't always a perfect multiple and SDL determines how big the buffer size is depending on the logical size and display settings.
    dpr: f32,

    // Initialize to the default gl framebuffer.
    // If we are doing MSAA, then we'll need to set this to the multisample framebuffer.
    fbo_id: gl.GLuint = 0,

    msaa: ?MsaaFrameBuffer = null,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: Config) !Self {
        if (IsDesktop) {
            try sdl.ensureVideoInit();
        }

        var res = Window{
            .id = undefined,
            .sdl_window = undefined,
            .alloc = alloc,
            .inner = undefined,
            .width = undefined,
            .height = undefined,
            .buf_width = undefined,
            .buf_height = undefined,
            .dpr = undefined,
        };
        if (IsDesktop) {
            const flags = getSdlWindowFlags(config);
            switch (Backend) {
                .OpenGL => {
                    try initGL_Window(alloc, &res, config, flags);
                    try initGL_Context(&res);
                },
                .Vulkan => {
                    try initVulkanWindow(alloc, &res, config, flags);
                },
                else => stdx.unsupported(),
            }
        } else if (IsWebGL2) {
            const dpr = jsSetCanvasBuffer(config.width, config.height);
            res.width = @intCast(u32, config.width);
            res.height = @intCast(u32, config.height);
            res.buf_width = dpr * res.width;
            res.buf_height = dpr * res.height;
            res.dpr = dpr;
        }

        // Initialize graphics.
        switch (Backend) {
            .OpenGL => {
                res.inner.gl_ctx_ref_count = alloc.create(u32) catch unreachable;
                res.inner.gl_ctx_ref_count.* = 1;
                if (config.anti_alias) {
                    if (createMsaaFrameBuffer(res.buf_width, res.buf_height, res.dpr)) |msaa| {
                        res.fbo_id = msaa.fbo;
                        res.msaa = msaa;
                    }
                }
            },
            else => {},
        }

        return res;
    }

    /// Currently, we share a GL context by simply reusing the same handle.
    /// There is a different concept of sharing a context supported by GL in which textures and internal data are shared
    /// and a new GL context is created to operate on that. SDL can do this with SDL_GL_SHARE_WITH_CURRENT_CONTEXT = 1.
    /// However, it could involve reorganizing how Graphics does rendering because not everything is shared.
    /// There doesn't seem to be a good reason to use GL's shared context so prefer the simpler method and don't create a new context here.
    pub fn initWithSharedContext(alloc: std.mem.Allocator, config: Config, existing_win: Self) !Self {
        try sdl.ensureVideoInit();

        var res = Window{
            .id = undefined,
            .sdl_window = undefined,
            .alloc = alloc,
            .gl_ctx_ref_count = undefined,
            .gl_ctx = undefined,
            .width = undefined,
            .height = undefined,
            .buf_width = undefined,
            .buf_height = undefined,
            .dpr = undefined,
        };
        const flags = getSdlWindowFlags(config);
        switch (Backend) {
            .OpenGL => try initGL_Window(alloc, &res, config, flags),
            else => stdx.unsupported(),
        }
        // Reuse existing window's GL context.
        res.gl_ctx = existing_win.gl_ctx;
        res.alloc = existing_win.alloc;
        res.gl_ctx_ref_count = existing_win.gl_ctx_ref_count;
        res.gl_ctx_ref_count.* += 1;

        res.graphics = existing_win.graphics;

        if (config.anti_alias) {
            if (createMsaaFrameBuffer(res.buf_width, res.buf_height, res.dpr)) |msaa| {
                res.fbo_id = msaa.fbo;
                res.msaa = msaa;
            }
        }

        return res;
    }

    pub fn deinit(self: Self) void {
        switch (Backend) {
            .OpenGL => {
                if (self.inner.gl_ctx_ref_count.* == 1) {
                    if (IsDesktop) {
                        sdl.SDL_GL_DeleteContext(self.inner.gl_ctx);
                    }
                    self.alloc.destroy(self.inner.gl_ctx_ref_count);
                } else {
                    self.inner.gl_ctx_ref_count.* -= 1;
                }
            },
            .Vulkan => {
                vk.destroyDevice(self.inner.device, null);
                vk.destroySurfaceKHR(self.inner.instance, self.inner.surface, null);
                vk.destroyInstance(self.inner.instance, null);
            },
            else => stdx.panicUnsupported(),
        }
        if (IsDesktop) {
            // Destroy window after destroying graphics context.
            sdl.SDL_DestroyWindow(self.sdl_window);
        }
    }

    pub fn handleResize(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;

        if (IsDesktop) {
            var buf_width: c_int = undefined;
            var buf_height: c_int = undefined;
            sdl.SDL_GL_GetDrawableSize(self.sdl_window, &buf_width, &buf_height);
            self.buf_width = @intCast(u32, buf_width);
            self.buf_height = @intCast(u32, buf_height);
        } else {
            self.buf_width = self.dpr * self.width;
            self.buf_height = self.dpr * self.height;
        }

        // The default frame buffer already resizes to the window.
        // The msaa texture was created separately, so it needs to update.
        if (self.msaa) |msaa| {
            resizeMsaaFrameBuffer(msaa, self.buf_width, self.buf_height);
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        if (IsDesktop) {
            sdl.SDL_SetWindowSize(self.sdl_window, @intCast(c_int, width), @intCast(c_int, height));
            var cur_width: c_int = undefined;
            var cur_height: c_int = undefined;
            sdl.SDL_GetWindowSize(self.sdl_window, &cur_width, &cur_height);
            self.width = @intCast(u32, cur_width);
            self.height = @intCast(u32, cur_height);

            var buf_width: c_int = undefined;
            var buf_height: c_int = undefined;
            sdl.SDL_GL_GetDrawableSize(self.sdl_window, &buf_width, &buf_height);
            self.buf_width = @intCast(u32, buf_width);
            self.buf_height = @intCast(u32, buf_height);
        } else {
            _ = jsSetCanvasBuffer(width, height);
            self.width = width;
            self.height = height;
            self.buf_width = width * self.dpr;
            self.buf_height = height * self.dpr;
        }

        if (self.msaa) |msaa| {
            resizeMsaaFrameBuffer(msaa, self.buf_width, self.buf_height);
        }
    }

    pub fn minimize(self: Self) void {
        sdl.SDL_MinimizeWindow(self.sdl_window);
    }

    pub fn maximize(self: Self) void {
        sdl.SDL_MaximizeWindow(self.sdl_window);
    }

    pub fn restore(self: Self) void {
        sdl.SDL_RestoreWindow(self.sdl_window);
    }

    pub fn setMode(self: Self, mode: Mode) void {
        switch (mode) {
            .Windowed => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, 0),
            .PseudoFullscreen => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, sdl.SDL_WINDOW_FULLSCREEN_DESKTOP),
            .Fullscreen => _ = sdl.SDL_SetWindowFullscreen(self.sdl_window, sdl.SDL_WINDOW_FULLSCREEN),
        }
    }

    pub fn setPosition(self: Self, x: i32, y: i32) void {
        sdl.SDL_SetWindowPosition(self.sdl_window, x, y);
    }

    pub fn center(self: Self) void {
        sdl.SDL_SetWindowPosition(self.sdl_window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);
    }

    pub fn focus(self: Self) void {
        sdl.SDL_RaiseWindow(self.sdl_window);
    }

    pub fn makeCurrent(self: Self) void {
        _ = sdl.SDL_GL_MakeCurrent(self.sdl_window, self.gl_ctx);
    }

    pub fn setTitle(self: Self, title: []const u8) void {
        const cstr = std.cstr.addNullByte(self.alloc, title) catch unreachable;
        defer self.alloc.free(cstr);
        sdl.SDL_SetWindowTitle(self.sdl_window, cstr);
    }

    pub fn getTitle(self: Self, alloc: std.mem.Allocator) []const u8 {
        const cstr = sdl.SDL_GetWindowTitle(self.sdl_window);
        return alloc.dupe(u8, std.mem.span(cstr)) catch unreachable;
    }
};

pub fn disableVSync() !void {
    if (sdl.SDL_GL_SetSwapInterval(0) != 0) {
        log.warn("unable to turn off vsync: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

fn glSetAttr(attr: sdl.SDL_GLattr, val: c_int) !void {
    if (sdl.SDL_GL_SetAttribute(attr, val) != 0) {
        log.warn("sdl set attribute: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

fn initVulkanWindow(alloc: std.mem.Allocator, win: *Window, config: Config, flags: c_int) !void {
    var window_flags = flags | sdl.SDL_WINDOW_VULKAN;
    win.sdl_window = sdl.createWindow(alloc, config.title, sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, config.width), @intCast(c_int, config.height), @bitCast(u32, window_flags)) orelse {
        log.err("Unable to create window: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    };

    if (builtin.os.tag == .macos) {
        vk.initMacVkInstanceFuncs();
    }

    if (vk_enable_validation_layers and !vkCheckValidationLayerSupport(alloc)) {
        stdx.panic("validation layers requested, but not available.");
    }

    // SDL will query platform specific extensions.
    var count: c_uint = undefined;
    if (sdl.SDL_Vulkan_GetInstanceExtensions(win.sdl_window, &count, null) == 0) {
        log.err("SDL_Vulkan_GetInstanceExtensions: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
    var enabled_extensions = std.ArrayList([*:0]const u8).init(alloc);
    defer enabled_extensions.deinit();

    const extensions = alloc.alloc([*:0]const u8, count) catch @panic("error");
    defer alloc.free(extensions);
    if (sdl.SDL_Vulkan_GetInstanceExtensions(win.sdl_window, &count, @ptrCast([*c][*c]const u8, extensions.ptr)) == 0) {
        log.err("SDL_Vulkan_GetInstanceExtensions: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
    enabled_extensions.appendSlice(extensions) catch stdx.fatal();

    if (builtin.os.tag == .macos) {
        // Macos needs VK_KHR_get_physical_device_properties2 for device extension: VK_KHR_portability_subset.
        enabled_extensions.append("VK_KHR_get_physical_device_properties2") catch stdx.fatal();
    }

    var instance: vk.VkInstance = undefined;

    // Create instance.
    const app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "App",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_0,
        .pNext = null,
    };
    const create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(u32, enabled_extensions.items.len),
        .ppEnabledExtensionNames = enabled_extensions.items.ptr,
        // Validation layer disabled.
        .enabledLayerCount = if (vk_enable_validation_layers) @intCast(u32, VkRequiredValidationLayers.len) else 0,
        .ppEnabledLayerNames = if (vk_enable_validation_layers) &VkRequiredValidationLayers else null,
        .pNext = null,
        .flags = 0,
    };
    var res = vk.createInstance(&create_info, null, &instance);
    vk.assertSuccess(res);
    win.inner.instance = instance;

    if (builtin.os.tag == .macos) {
        vk.initMacVkFunctions(instance);
    }

    // Create surface.
    var surface: vk.VkSurfaceKHR = undefined;
    if (sdl.SDL_Vulkan_CreateSurface(win.sdl_window, @ptrCast(sdl.VkInstance, instance), @ptrCast(*sdl.VkSurfaceKHR, &surface)) == 0)  {
        log.err("SDL_Vulkan_CreateSurface: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
    win.inner.surface = surface;

    // Get physical device.
    var num_devices: u32 = 0;
    res = vk.enumeratePhysicalDevices(instance, &num_devices, null);
    vk.assertSuccess(res);
    if (num_devices == 0) {
        return error.NoVulkanDevice;
    }

    const devices = alloc.alloc(vk.VkPhysicalDevice, num_devices) catch @panic("error");
    defer alloc.free(devices);
    res = vk.enumeratePhysicalDevices(instance, &num_devices, devices.ptr);
    vk.assertSuccess(res);

    const physical_device = for (devices) |device| {
        if (try isVkDeviceSuitable(alloc, device, surface)) {
            break device;
        }
    } else return error.NoSuitableDevice;
    win.inner.physical_device = physical_device;

    // Create logical device.
    const q_family = queryQueueFamily(alloc, physical_device, surface);
    if (q_family.graphics_family.? != q_family.present_family.?) {
        return error.UnsupportedQueueFamily;
    }
    win.inner.queue_family = q_family;

    const uniq_families: []const u32 = &.{ q_family.graphics_family.? };
    var queue_priority: f32 = 1;

    var queue_create_infos = std.ArrayList(vk.VkDeviceQueueCreateInfo).init(alloc);
    defer queue_create_infos.deinit();

    const queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = uniq_families[0],
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
        .pNext = null,
        .flags = 0,
    };
    try queue_create_infos.append(queue_create_info);

    var enabled_dextensions = std.ArrayList([*:0]const u8).init(alloc);
    defer enabled_dextensions.deinit();
    enabled_dextensions.appendSlice(&VkRequiredDeviceExtensions) catch stdx.fatal();

    const device_extensions = getDeviceExtensionProperties(alloc, physical_device);
    defer alloc.free(device_extensions);
    for (device_extensions) |ext| {
        const name_slice = std.mem.span(@ptrCast([*:0]const u8, &ext.extensionName));
        if (std.mem.eql(u8, name_slice, "VK_KHR_portability_subset")) {
            // If the device reports this extension it wants to translate to a non Vulkan API. eg. Translate to Metal on macos.
            enabled_dextensions.append("VK_KHR_portability_subset") catch stdx.fatal();
        }
    }

    var device_features: vk.VkPhysicalDeviceFeatures = undefined;
    vk.getPhysicalDeviceFeatures(physical_device, &device_features);
    if (device_features.shaderSampledImageArrayDynamicIndexing == vk.VK_FALSE) {
        return error.MissingRequiredFeature;
    }

    var enabled_features = std.mem.zeroInit(vk.VkPhysicalDeviceFeatures, .{});
    enabled_features.shaderSampledImageArrayDynamicIndexing = vk.VK_TRUE;
    enabled_features.fillModeNonSolid = vk.VK_TRUE;
    const d_create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @intCast(u32, queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .pEnabledFeatures = &enabled_features,
        .enabledExtensionCount = @intCast(u32, enabled_dextensions.items.len),
        .ppEnabledExtensionNames = enabled_dextensions.items.ptr,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .pNext = null,
        .flags = 0,
    };

    res = vk.createDevice(physical_device, &d_create_info, null, &win.inner.device);
    vk.assertSuccess(res);

    win.id = sdl.SDL_GetWindowID(win.sdl_window);
    win.width = @intCast(u32, config.width);
    win.height = @intCast(u32, config.height);

    var buf_width: c_int = undefined;
    var buf_height: c_int = undefined;
    
    switch (Backend) {
        .OpenGL => sdl.SDL_GL_GetDrawableSize(win.sdl_window, &buf_width, &buf_height),
        .Vulkan => sdl.SDL_Vulkan_GetDrawableSize(win.sdl_window, &buf_width, &buf_height),
        else => stdx.unsupported(),
    }
    win.buf_width = @intCast(u32, buf_width);
    win.buf_height = @intCast(u32, buf_height);

    win.dpr = @intToFloat(f32, win.buf_width) / @intToFloat(f32, win.width);
}

const SwapChainInfo = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    present_modes: []vk.VkPresentModeKHR,

    pub fn deinit(self: SwapChainInfo, alloc: std.mem.Allocator) void {
        alloc.free(self.formats);
        alloc.free(self.present_modes);
    }

    pub fn getDefaultExtent(self: SwapChainInfo) vk.VkExtent2D {
        if (self.capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return self.capabilities.currentExtent;
        } else {
            var extent = vk.VkExtent2D{
                .width = 800,
                .height = 600,
            };
            extent.width = std.math.max(self.capabilities.minImageExtent.width, std.math.min(self.capabilities.maxImageExtent.width, extent.width));
            extent.height = std.math.max(self.capabilities.minImageExtent.height, std.math.min(self.capabilities.maxImageExtent.height, extent.height));
            return extent;
        }
    }

    pub fn getDefaultSurfaceFormat(self: SwapChainInfo) vk.VkSurfaceFormatKHR {
        if (self.formats.len == 1 and self.formats[0].format == vk.VK_FORMAT_UNDEFINED) {
            return vk.VkSurfaceFormatKHR{
                .format = vk.VK_FORMAT_B8G8R8A8_UNORM,
                .colorSpace = vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            };
        }
        for (self.formats) |format| {
            if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return format;
            }
        }
        return self.formats[0];
    }

    pub fn getDefaultPresentMode(self: SwapChainInfo) vk.VkPresentModeKHR {
        var best: vk.VkPresentModeKHR = vk.VK_PRESENT_MODE_FIFO_KHR;
        for (self.present_modes) |mode| {
            if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
                return mode;
            } else if (mode == vk.VK_PRESENT_MODE_IMMEDIATE_KHR) {
                best = mode;
            }
        }
        return best;
    }
};

/// Currently in the platform module to find a suitable physical device.
pub fn vkQuerySwapChainSupport(alloc: std.mem.Allocator, device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) SwapChainInfo {
    var new = SwapChainInfo{
        .capabilities = undefined,
        .formats = undefined,
        .present_modes = undefined,
    };

    var res = vk.getPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &new.capabilities);
    vk.assertSuccess(res);

    var format_count: u32 = undefined;
    res = vk.getPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null);
    vk.assertSuccess(res);
    new.formats = alloc.alloc(vk.VkSurfaceFormatKHR, format_count) catch @panic("error");
    res = vk.getPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, new.formats.ptr);
    vk.assertSuccess(res);

    var present_mode_count: u32 = undefined;
    res = vk.getPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null);
    vk.assertSuccess(res);
    new.present_modes = alloc.alloc(vk.VkPresentModeKHR, present_mode_count) catch @panic("error");
    res = vk.getPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, new.present_modes.ptr);
    vk.assertSuccess(res);

    return new;
}

const VkRequiredDeviceExtensions = [_][*:0]const u8{
    vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};
const VkRequiredValidationLayers = [_][*:0]const u8{
    // "VK_LAYER_LUNARG_standard_validation",
    "VK_LAYER_KHRONOS_validation", // Available with MoltenVK
};
const vk_enable_validation_layers = true and builtin.mode == .Debug;

pub const VkQueueFamilyPair = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    fn isValid(self: VkQueueFamilyPair) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

fn queryQueueFamily(alloc: std.mem.Allocator, device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) VkQueueFamilyPair {
    // Check queue family.
    var family_count: u32 = 0;
    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, null);

    const families = alloc.alloc(vk.VkQueueFamilyProperties, family_count) catch @panic("error");
    defer alloc.free(families);
    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, families.ptr);

    var new = VkQueueFamilyPair{
        .graphics_family = null,
        .present_family = null,
    };

    for (families) |family, idx| {
        if (family.queueCount > 0 and family.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
            new.graphics_family = @intCast(u32, idx);
        }

        var present_support: vk.VkBool32 = 0;
        const res = vk.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(u32, idx), surface, &present_support);
        vk.assertSuccess(res);

        if (family.queueCount > 0 and present_support != 0) {
            new.present_family = @intCast(u32, idx);
        }

        if (new.isValid()) {
            break;
        }
    }

    return new;
}

fn getDeviceExtensionProperties(alloc: std.mem.Allocator, device: vk.VkPhysicalDevice) []const vk.VkExtensionProperties {
    var extension_count: u32 = undefined;
    var res = vk.enumerateDeviceExtensionProperties(device, null, &extension_count, null);
    vk.assertSuccess(res);
    const extensions = alloc.alloc(vk.VkExtensionProperties, extension_count) catch stdx.fatal();
    res = vk.enumerateDeviceExtensionProperties(device, null, &extension_count, extensions.ptr);
    vk.assertSuccess(res);
    return extensions;
}

fn isVkDeviceSuitable(alloc: std.mem.Allocator, device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !bool {
    const q_family = queryQueueFamily(alloc, device, surface);
    if (!q_family.isValid()) {
        return false;
    }

    // Check required extensions.
    const extensions = getDeviceExtensionProperties(alloc, device);
    defer alloc.free(extensions);

    var req_exts = std.StringHashMap(void).init(alloc);
    defer req_exts.deinit();
    for (VkRequiredDeviceExtensions) |ext| {
        const ext_slice = std.mem.span(ext);
        req_exts.put(ext_slice, {}) catch @panic("error");
    }
    for (extensions) |ext| {
        const name_slice = std.mem.span(@ptrCast([*:0]const u8, &ext.extensionName));
        _ = req_exts.remove(name_slice);
    }
    if (req_exts.count() != 0) {
        return false;
    }

    // Check swap chain.
    const swap_chain = vkQuerySwapChainSupport(alloc, device, surface);
    defer swap_chain.deinit(alloc);
    if (swap_chain.formats.len == 0 or swap_chain.present_modes.len == 0) {
        return false;
    }
    return true;
}

fn vkCheckValidationLayerSupport(alloc: std.mem.Allocator) bool {
    var layer_count: u32 = undefined;

    var res = vk.enumerateInstanceLayerProperties(&layer_count, null);
    vk.assertSuccess(res);

    const available_layers = alloc.alloc(vk.VkLayerProperties, layer_count) catch stdx.fatal();
    defer alloc.free(available_layers);

    res = vk.enumerateInstanceLayerProperties(&layer_count, available_layers.ptr);
    vk.assertSuccess(res);

    for (VkRequiredValidationLayers) |layer| {
        var found = false;
        for (available_layers) |it| {
            if (std.cstr.cmp(layer, @ptrCast([*:0]const u8, &it.layerName)) == 0) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

fn initGL_Window(alloc: std.mem.Allocator, win: *Window, config: Config, flags: c_int) !void {
    try glSetAttr(sdl.SDL_GL_CONTEXT_FLAGS, sdl.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
    try glSetAttr(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);

    // Use GL 3.3 to stay close to GLES.
    try glSetAttr(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    try glSetAttr(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);

    try glSetAttr(sdl.SDL_GL_DOUBLEBUFFER, 1);
    try glSetAttr(sdl.SDL_GL_DEPTH_SIZE, 24);
    try glSetAttr(sdl.SDL_GL_STENCIL_SIZE, 8);

    var window_flags = flags | sdl.SDL_WINDOW_OPENGL;
    win.sdl_window = sdl.createWindow(alloc, config.title, sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, config.width), @intCast(c_int, config.height), @bitCast(u32, window_flags)) orelse {
        log.err("Unable to create window: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    };

    win.id = sdl.SDL_GetWindowID(win.sdl_window);
    win.width = @intCast(u32, config.width);
    win.height = @intCast(u32, config.height);

    var buf_width: c_int = undefined;
    var buf_height: c_int = undefined;
    sdl.SDL_GL_GetDrawableSize(win.sdl_window, &buf_width, &buf_height);
    win.buf_width = @intCast(u32, buf_width);
    win.buf_height = @intCast(u32, buf_height);

    win.dpr = @intToFloat(f32, win.buf_width) / @intToFloat(f32, win.width);
}

fn initGL_Context(win: *Window) !void {
    if (sdl.SDL_GL_CreateContext(win.sdl_window)) |ctx| {
        win.inner.gl_ctx = ctx;

        // GL version on some platforms is only available after the context is created and made current.
        // This also means it's better to start initing opengl functions (GetProcAddress) on windows after an opengl context is created.
        var major: i32 = undefined;
        var minor: i32 = undefined;
        gl.getIntegerv(gl.GL_MAJOR_VERSION, &major);
        gl.getIntegerv(gl.GL_MINOR_VERSION, &minor);
        _ = minor;
        if (major < 3) {
            log.err("OpenGL Version Unsupported: {s}", .{gl.glGetString(gl.GL_VERSION)});
            return error.OpenGLUnsupported;
        }
        if (builtin.os.tag == .windows) {
            gl.initWinGL_Functions();
        }
        log.debug("OpenGL: {s}", .{gl.glGetString(gl.GL_VERSION)});
    } else {
        log.err("Create GLContext: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }

    // Not necessary but better to be explicit.
    if (sdl.SDL_GL_MakeCurrent(win.sdl_window, win.inner.gl_ctx) != 0) {
        log.err("Unable to attach gl context to window: {s}", .{sdl.SDL_GetError()});
        return error.Failed;
    }
}

// Should be called for cleanup before app exists.
pub fn quit() void {
    sdl.SDL_Quit();
}

fn getSdlWindowFlags(config: Config) c_int {
    var flags: c_int = 0;
    if (config.resizable) flags |= sdl.SDL_WINDOW_RESIZABLE;
    // TODO: Implement high dpi if it doesn't work on windows: https://nlguillemot.wordpress.com/2016/12/11/high-dpi-rendering/
    if (config.high_dpi) flags |= sdl.SDL_WINDOW_ALLOW_HIGHDPI;
    if (config.mode == .PseudoFullscreen) {
        flags |= sdl.SDL_WINDOW_FULLSCREEN_DESKTOP;
    } else if (config.mode == .Fullscreen) {
        flags |= sdl.SDL_WINDOW_FULLSCREEN;
    }
    return flags;
}

fn resizeMsaaFrameBuffer(msaa: MsaaFrameBuffer, width: u32, height: u32) void {
    gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, msaa.fbo);
    if (IsDesktop) {
        gl.bindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, msaa.tex.?);
        gl.texImage2DMultisample(gl.GL_TEXTURE_2D_MULTISAMPLE, @intCast(c_int, msaa.num_samples), gl.GL_RGB, @intCast(c_int, width), @intCast(c_int, height), gl.GL_TRUE);
        gl.framebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D_MULTISAMPLE, msaa.tex.?, 0);
        gl.bindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, 0);
    } else {
        gl.bindRenderbuffer(gl.GL_RENDERBUFFER, msaa.rbo.?);
        gl.renderbufferStorageMultisample(gl.GL_RENDERBUFFER, @intCast(c_int, msaa.num_samples), gl.GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height));
        gl.framebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_RENDERBUFFER, msaa.rbo.?);
    }
}

pub fn createMsaaFrameBuffer(width: u32, height: u32, dpr: f32) ?MsaaFrameBuffer {
    // Setup multisampling anti alias.
    // See: https://learnopengl.com/Advanced-OpenGL/Anti-Aliasing
    const max_samples = gl.getMaxSamples();
    log.debug("max samples: {}", .{max_samples});
    if (max_samples >= 2) {
        const dpr_ceil = @floatToInt(u8, std.math.ceil(dpr));
        const msaa_preferred_samples: u32 = switch (dpr_ceil) {
            1 => 8,
            // Since the draw buffer is already a supersample, we don't need much msaa samples.
            2 => 4,
            else => 2,
        };
        const num_samples = std.math.min(max_samples, msaa_preferred_samples);

        var ms_fbo: gl.GLuint = 0;
        gl.genFramebuffers(1, &ms_fbo);
        gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, ms_fbo);

        if (IsDesktop) {
            var ms_tex: gl.GLuint = undefined;
            gl.genTextures(1, &ms_tex);

            gl.enable(gl.GL_MULTISAMPLE);
            // gl.glHint(gl.GL_MULTISAMPLE_FILTER_HINT_NV, gl.GL_NICEST);
            gl.bindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, ms_tex);
            gl.texImage2DMultisample(gl.GL_TEXTURE_2D_MULTISAMPLE, @intCast(c_int, num_samples), gl.GL_RGB, @intCast(c_int, width), @intCast(c_int, height), gl.GL_TRUE);
            gl.framebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D_MULTISAMPLE, ms_tex, 0);
            gl.bindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, 0);
            log.debug("msaa framebuffer created with {} samples", .{num_samples});
            return MsaaFrameBuffer{
                .fbo = ms_fbo,
                .tex = ms_tex,
                .rbo = null,
                .num_samples = num_samples,
            };
        } else if (IsWebGL2) {
            // webgl2 does not support texture multisampling but it does support renderbuffer multisampling.
            var rbo: gl.GLuint = undefined;
            gl.genRenderbuffers(1, &rbo);
            gl.bindRenderbuffer(gl.GL_RENDERBUFFER, rbo);
            gl.renderbufferStorageMultisample(gl.GL_RENDERBUFFER, @intCast(c_int, num_samples), gl.GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height));
            gl.framebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_RENDERBUFFER, rbo);
            const status = gl.checkFramebufferStatus(gl.GL_FRAMEBUFFER);
            if (status != gl.GL_FRAMEBUFFER_COMPLETE) {
                log.debug("unexpected status: {}", .{status});
                unreachable;
            }
            return MsaaFrameBuffer{
                .fbo = ms_fbo,
                .tex = null,
                .rbo = rbo,
                .num_samples = num_samples,
            };
        } else unreachable;
    } else {
        return null;
    }
}

const MsaaFrameBuffer = struct {
    fbo: gl.GLuint,

    // For desktop.
    tex: ?gl.GLuint,

    // For webgl2.
    rbo: ?gl.GLuint,

    num_samples: u32,
};