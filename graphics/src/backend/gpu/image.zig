const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;
const gl = @import("gl");
pub const GLTextureId = gl.GLuint;
const vk = @import("vk");
const stbi = @import("stbi");

const graphics = @import("../../graphics.zig");
const gpu = graphics.gpu;
const gvk = graphics.vk;
const log = stdx.log.scoped(.image);

const ImageId = graphics.ImageId;
pub const TextureId = u32;

pub const ImageStore = struct {
    alloc: std.mem.Allocator,
    images: stdx.ds.CompactUnorderedList(ImageId, Image),
    gctx: *graphics.gpu.Graphics,

    textures: stdx.ds.CompactUnorderedList(TextureId, Texture),

    /// Images are queued for removal due to multiple frames in flight.
    removals: std.ArrayList(RemoveEntry),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, gctx: *graphics.gpu.Graphics) Self {
        var ret = Self{
            .alloc = alloc,
            .images = stdx.ds.CompactUnorderedList(ImageId, Image).init(alloc),
            .textures = stdx.ds.CompactUnorderedList(TextureId, Texture).init(alloc),
            .gctx = gctx,
            .removals = std.ArrayList(RemoveEntry).init(alloc),
        };
        return ret;
    }

    pub fn deinit(self: Self) void {
        // Delete images after since some deinit could have removed images.
        self.images.deinit();

        var iter = self.textures.iterator();
        while (iter.next()) |tex| {
            if (Backend == .Vulkan) {
                tex.deinitVK(self.gctx.inner.ctx.device);
            } else if (Backend == .OpenGL) {
                tex.deinitGL();
            }
        }
        self.textures.deinit();

        self.removals.deinit();
    }

    /// Cleans up images and their textures that are no longer used.
    pub fn processRemovals(self: *Self) void {
        for (self.removals.items) |*entry, entry_idx| {
            if (entry.frame_age < gpu.MaxActiveFrames) {
                entry.frame_age += 1;
                continue;
            }
            const image = self.images.getNoCheck(entry.image_id);
            const tex_id = image.tex_id;
            const tex = self.textures.getPtrNoCheck(tex_id);

            self.images.remove(entry.image_id);

            // Remove from texture's image list.
            for (tex.inner.cs_images.items) |id, i| {
                if (id == entry.image_id) {
                    _ = tex.inner.cs_images.swapRemove(i);
                }
            }

            // No more images in the texture. Cleanup.
            if (tex.inner.cs_images.items.len == 0) {
                if (Backend == .Vulkan) {
                    tex.deinitVK(self.gctx.inner.ctx.device);
                } else if (Backend == .OpenGL) {
                    tex.deinitGL();
                }
                self.textures.remove(tex_id);
            }
            // Remove the entry.
            _ = self.removals.swapRemove(entry_idx);
        }
    }

    pub fn createImageFromData(self: *Self, data: []const u8) !graphics.Image {
        var src_width: c_int = undefined;
        var src_height: c_int = undefined;
        // This records the original number of channels in the source input.
        var channels: c_int = undefined;
        // Request 4 channels to pass rgba to gpu. If image only has rgb channels, alpha is generated.
        const bitmap = stbi.stbi_load_from_memory(data.ptr, @intCast(c_int, data.len), &src_width, &src_height, &channels, 4);
        defer stbi.stbi_image_free(bitmap);
        if (bitmap == null) {
            log.debug("{s}", .{stbi.stbi_failure_reason()});
            return error.BadImage;
        }
        // log.debug("loaded image: {} {} {} {*}", .{src_width, src_height, channels, bitmap});

        const bitmap_len = @intCast(usize, src_width * src_height * 4);
        const desc = self.createImageFromBitmap(@intCast(usize, src_width), @intCast(usize, src_height), bitmap[0..bitmap_len], true);
        return graphics.Image{
            .id = desc.image_id,
            .width = @intCast(usize, src_width),
            .height = @intCast(usize, src_height),
        };
    }

    // TODO: Each texture resource should be an atlas of images since the number of textures is limited on the gpu.
    /// Assumes rgba data.
    pub fn createImageFromBitmapInto(self: *Self, image: *Image, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) ImageId {
        self.initImage(image, width, height, data, linear_filter);

        if (Backend == .Vulkan) {
            const device = self.gctx.inner.ctx.device;
            const desc_pool = self.gctx.inner.desc_pool;
            const layout = self.gctx.inner.tex_desc_set_layout;
            const desc_set = gvk.descriptor.createDescriptorSet(device, desc_pool, layout);
            const image_infos: []vk.VkDescriptorImageInfo = &[_]vk.VkDescriptorImageInfo{
                vk.VkDescriptorImageInfo{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = image.inner.image_view,
                    .sampler = image.inner.sampler,
                },
            };
            gvk.descriptor.updateImageDescriptorSet(device, desc_set, image_infos);

            // Currently each image allocates a new texture.
            const tex_id = self.textures.add(.{
                .inner = .{
                    .desc_set = desc_set,
                    .image = image.inner.image,
                    .image_view = image.inner.image_view,
                    .image_mem = image.inner.image_mem,
                    .sampler = image.inner.sampler,
                    .cs_images = std.ArrayList(ImageId).init(self.alloc),
                },
            }) catch stdx.fatal();
            image.tex_id = tex_id;
        } else if (Backend == .OpenGL) {
            const tex_id = self.textures.add(.{
                .inner = .{
                    // TODO: initImage shouldn't be set tex_id to gl tex id.
                    .tex_id = image.tex_id,
                },
            }) catch stdx.fatal();
            image.tex_id = tex_id;
        }
        return self.images.add(image.*) catch stdx.fatal();
    }

    // TODO: Rename to initTexture.
    /// Assumes rgba data.
    pub fn initImage(self: *Self, image: *Image, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) void {
        switch (Backend) {
            .OpenGL => {
                graphics.gl.initImage(image, width, height, data, linear_filter);
            },
            .Vulkan => {
                graphics.vk.VkContext.initImage(self.gctx.inner.ctx, image, width, height, data, linear_filter);
            },
            else => stdx.panicUnsupported(),
        }
    }

    pub fn createImageFromBitmap(self: *Self, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) ImageTex {
        var image: Image = undefined;
        const image_id = self.createImageFromBitmapInto(&image, width, height, data, linear_filter);
        return ImageTex{
            .image_id = image_id,
            .tex_id = image.tex_id,
        };
    }

    pub fn markForRemoval(self: *Self, id: ImageId) void {
        const image = self.images.getPtrNoCheck(id);
        if (!image.remove) {
            self.removals.append(.{
                .image_id = id,
                .frame_age = 0,
            }) catch stdx.fatal();
            image.remove = true;
        }
    }

    pub inline fn getTexture(self: Self, id: TextureId) Texture {
        return self.textures.getNoCheck(id);
    }

    pub fn endCmdAndMarkForRemoval(self: *Self, image_id: ImageId) void {
        const image = self.images.getNoCheck(image_id);
        // If we deleted the current tex, flush and reset to default texture.
        if (self.gctx.batcher.cur_image_tex.tex_id == image.tex_id) {
            self.gctx.endCmd();
            self.gctx.batcher.cur_image_tex = self.gctx.white_tex;
        }
        self.markForRemoval(image_id);
    }
};

/// It's often useful to pass around the image id and texture id.
pub const ImageTex = struct {
    image_id: ImageId,
    tex_id: TextureId,
};

pub const Image = struct {
    /// Texture resource this image belongs to.
    tex_id: TextureId,
    width: usize,
    height: usize,
    inner: switch (Backend) {
        .OpenGL => struct {},
        .Vulkan => struct {
            // TODO: Remove this since Texture should own these.
            image: vk.VkImage,
            image_view: vk.VkImageView,
            image_mem: vk.VkDeviceMemory,
            sampler: vk.VkSampler,
        },
        else => void,
    },
    /// Framebuffer used to draw to the texture.
    fbo_id: ?gl.GLuint = null,
    remove: bool, 
};

pub const Texture = struct {
    inner: switch (Backend) {
        .OpenGL => struct {
            tex_id: GLTextureId,
        },
        .Vulkan => struct {
            /// Used to bind to this texture for draw commands.
            desc_set: vk.VkDescriptorSet,
            image: vk.VkImage,
            image_view: vk.VkImageView,
            image_mem: vk.VkDeviceMemory,

            // Not owned by the texture.
            sampler: vk.VkSampler,

            cs_images: std.ArrayList(ImageId),
        },
        else => struct {},
    },

    fn deinitGL(self: Texture) void {
        gl.deleteTextures(1, &self.inner.tex_id);
    }

    fn deinitVK(self: Texture, device: vk.VkDevice) void {
        vk.destroyImageView(device, self.inner.image_view, null);
        vk.destroyImage(device, self.inner.image, null);
        vk.freeMemory(device, self.inner.image_mem, null);
        self.inner.cs_images.deinit();
    }
};

const RemoveEntry = struct {
    image_id: ImageId,
    frame_age: u32,
};