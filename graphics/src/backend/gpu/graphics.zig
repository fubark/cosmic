const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const ds = stdx.ds;
const platform = @import("platform");
const cgltf = @import("cgltf");
const stbi = @import("stbi");
const math = stdx.math;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.Vec2.init;
const Mat4 = math.Mat4;
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const geom = math.geom;
const gl = @import("gl");
const vk = @import("vk");
const builtin = @import("builtin");
const lyon = @import("lyon");
const tess2 = @import("tess2");
const pt = lyon.initPt;
const t = stdx.testing;
const trace = stdx.debug.tracy.trace;
const build_options = @import("build_options");
const Backend = build_options.GraphicsBackend;

const graphics = @import("../../graphics.zig");
const QuadBez = graphics.curve.QuadBez;
const SubQuadBez = graphics.curve.SubQuadBez;
const CubicBez = graphics.curve.CubicBez;
const Color = graphics.Color;
const BlendMode = graphics.BlendMode;
const VMetrics = graphics.font.VMetrics;
const TextMetrics = graphics.TextMetrics;
const Font = graphics.font.Font;
pub const font_cache = @import("font_cache.zig");
pub const FontCache = font_cache.FontCache;
const ImageId = graphics.ImageId;
const TextAlign = graphics.TextAlign;
const TextBaseline = graphics.TextBaseline;
const FontId = graphics.FontId;
const FontGroupId = graphics.FontGroupId;
const mesh_ = @import("mesh.zig");
pub const Mesh = mesh_.Mesh;
const VertexData = mesh_.VertexData;
const vertex = @import("vertex.zig");
pub const TexShaderVertex = vertex.TexShaderVertex;
const batcher = @import("batcher.zig");
const Batcher = batcher.Batcher;
const text_renderer = @import("text_renderer.zig");
pub const TextGlyphIterator = text_renderer.TextGlyphIterator;
const RenderTextIterator = text_renderer.RenderTextIterator;
const svg = graphics.svg;
const stroke = @import("stroke.zig");
const tessellator = @import("../../tessellator.zig");
const Tessellator = tessellator.Tessellator;
pub const RenderFont = @import("render_font.zig").RenderFont;
pub const Glyph = @import("glyph.zig").Glyph;
const gvk = graphics.vk;
const ggl = graphics.gl;
const VkContext = gvk.VkContext;
const image = @import("image.zig");
pub const ImageStore = image.ImageStore;
pub const Image = image.Image;
pub const ImageTex = image.ImageTex;
pub const TextureId = image.TextureId;
pub const shader = @import("shader.zig");
const log = stdx.log.scoped(.gpu_graphics);

const vera_ttf = @embedFile("../../../../assets/vera.ttf");

const IsWasm = builtin.target.isWasm();
const NullId = std.math.maxInt(u32);

/// Should be agnostic to viewport dimensions so it can be reused to draw on different viewports.
pub const Graphics = struct {
    alloc: std.mem.Allocator,

    white_tex: image.ImageTex,
    inner: switch (Backend) {
        .Vulkan => struct {
            ctx: VkContext,
            renderer: *gvk.Renderer,
            pipelines: gvk.Pipelines,
            tex_desc_set_layout: vk.VkDescriptorSetLayout,
            mats_desc_set_layout: vk.VkDescriptorSetLayout,
            materials_desc_set_layout: vk.VkDescriptorSetLayout,
            cur_frame: gvk.Frame,
        },
        .OpenGL => struct {
            renderer: *ggl.Renderer,
        },
        else => void,
    },
    batcher: Batcher,
    font_cache: FontCache,

    /// The main paint state.
    main_ps: *PaintState,

    /// The current paint state.
    ps: *PaintState,

    /// The binded framebuffer dimensions.
    buf_width: u32,
    buf_height: u32,

    /// Feed the camera location to pbr shader.
    cur_cam_world_pos: Vec3,

    default_font_id: FontId,
    default_font_gid: FontGroupId,

    tmp_joint_idxes: [50]u16,

    image_store: image.ImageStore,

    // Depth pixel ratio:
    // This is used to fetch a higher res font bitmap for high dpi displays.
    // eg. 18px user font size would normally use a 32px backed font bitmap but with dpr=2,
    // it would use a 64px bitmap font instead.
    dpr: f32,
    dpr_ceil: u8,

    vec2_helper_buf: std.ArrayList(Vec2),
    vec2_slice_helper_buf: std.ArrayList(stdx.IndexSlice(u32)),
    qbez_helper_buf: std.ArrayList(SubQuadBez),
    tessellator: Tessellator,

    /// Temporary buffer used to rasterize a glyph by a backend (eg. stbtt).
    raster_glyph_buffer: std.ArrayList(u8),

    /// Currently one directional light. HDR light intensity.
    light_color: Vec3 = Vec3.init(5, 5, 5),
    light_vec: Vec3 = Vec3.init(-1, -1, 0).normalize(),

    pub fn initGL(self: *Graphics, alloc: std.mem.Allocator, renderer: *ggl.Renderer, dpr: f32) !void {
        self.initDefault(alloc, dpr);
        try self.initCommon(alloc);
        self.inner.renderer = renderer;
        self.batcher = Batcher.initGL(alloc, renderer, &self.image_store);
    }

    pub fn initVK(self: *Graphics, alloc: std.mem.Allocator, dpr: f32, renderer: *gvk.Renderer, vk_ctx: VkContext) !void {
        const physical = vk_ctx.physical;
        const device = vk_ctx.device;
        const fb_size = renderer.fb_size;
        const pass = renderer.main_pass;

        self.initDefault(alloc, dpr);
        self.inner.ctx = vk_ctx;
        self.inner.renderer = renderer;
        self.inner.tex_desc_set_layout = gvk.createTexDescriptorSetLayout(device);
        const desc_pool = renderer.desc_pool;
        try self.initCommon(alloc);

        const vert_buf = gvk.buffer.createVertexBuffer(physical, device, 40 * 80000);
        const index_buf = gvk.buffer.createIndexBuffer(physical, device, 2 * 120000 * 3);
        // TODO: Move buffer management into Batcher.
        const mats_buf = gvk.buffer.createStorageBuffer(physical, device, batcher.MatBufferInitialSizeBytes);
        const materials_buf = gvk.buffer.createStorageBuffer(physical, device, batcher.MaterialBufferInitialSizeBytes);

        self.inner.mats_desc_set_layout = gvk.descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, true, false);
        const mats_desc_set = gvk.descriptor.createDescriptorSet(device, desc_pool, self.inner.mats_desc_set_layout);
        gvk.descriptor.updateStorageBufferDescriptorSet(device, mats_desc_set, mats_buf.buf, 1, 0, mats_buf.size);

        self.inner.materials_desc_set_layout = gvk.descriptor.createDescriptorSetLayout(device, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3, true, false);
        const materials_desc_set = gvk.descriptor.createDescriptorSet(device, desc_pool, self.inner.materials_desc_set_layout);
        gvk.descriptor.updateStorageBufferDescriptorSet(device, materials_desc_set, materials_buf.buf, 3, 0, materials_buf.size);

        {
            const vert_spv = try shader.compileGLSL(alloc, .Vertex, gvk.shaders.tex_vert_glsl, .{});
            defer alloc.free(vert_spv);
            const frag_spv = try shader.compileGLSL(alloc, .Fragment, gvk.shaders.tex_frag_glsl, .{});
            defer alloc.free(frag_spv);
            self.inner.pipelines.tex_pipeline = gvk.createTexPipeline(device, pass, fb_size, self.inner.tex_desc_set_layout, self.inner.mats_desc_set_layout, vert_spv, frag_spv, true, false);
            self.inner.pipelines.tex_pipeline_2d = gvk.createTexPipeline(device, pass, fb_size, self.inner.tex_desc_set_layout, self.inner.mats_desc_set_layout, vert_spv, frag_spv, false, false);
            self.inner.pipelines.wireframe_pipeline = gvk.createTexPipeline(device, pass, fb_size, self.inner.tex_desc_set_layout, self.inner.mats_desc_set_layout, vert_spv, frag_spv, true, true);
        }
        self.inner.pipelines.norm_pipeline = try gvk.createNormPipeline(alloc, device, pass, fb_size);
        self.inner.pipelines.anim_pipeline = try gvk.createAnimPipeline(alloc, device, pass, fb_size, self.inner.mats_desc_set_layout, self.inner.tex_desc_set_layout);
        self.inner.pipelines.anim_pbr_pipeline = try gvk.createAnimPbrPipeline(alloc, device, pass, fb_size, self.inner.tex_desc_set_layout, renderer.shadowmap_desc_set_layout, self.inner.mats_desc_set_layout, renderer.cam_desc_set_layout, self.inner.materials_desc_set_layout);
        self.inner.pipelines.gradient_pipeline_2d = try gvk.createGradientPipeline(alloc, device, pass, fb_size);
        self.inner.pipelines.plane_pipeline = try gvk.createPlanePipeline(alloc, device, pass, fb_size);
        self.inner.pipelines.tex_pbr_pipeline = try gvk.createTexPbrPipeline(alloc, device, pass, fb_size, self.inner.tex_desc_set_layout, renderer.shadowmap_desc_set_layout, self.inner.mats_desc_set_layout, renderer.cam_desc_set_layout, self.inner.materials_desc_set_layout);
        const shadow_pass = renderer.shadow_pass;
        const shadow_dim = vk.VkExtent2D{ .width = gvk.Renderer.ShadowMapSize, .height = gvk.Renderer.ShadowMapSize };
        self.inner.pipelines.shadow_pipeline = try gvk.createShadowPipeline(alloc, device, shadow_pass, shadow_dim, self.inner.tex_desc_set_layout, self.inner.mats_desc_set_layout);
        self.inner.pipelines.anim_shadow_pipeline = try gvk.createAnimShadowPipeline(alloc, device, shadow_pass, shadow_dim, self.inner.tex_desc_set_layout, self.inner.mats_desc_set_layout);

        try self.batcher.initVK(alloc, vert_buf, index_buf, mats_buf, mats_desc_set, materials_buf, materials_desc_set, vk_ctx, renderer, self.inner.pipelines, &self.image_store);
        for (self.batcher.inner.batcher_frames) |frame| {
            frame.host_cam_buf.light_color = self.light_color;
            frame.host_cam_buf.light_vec = self.light_vec;
        }
    }

    fn initDefault(self: *Graphics, alloc: std.mem.Allocator, dpr: f32) void {
        self.* = .{
            .alloc = alloc,
            .white_tex = undefined,
            .inner = undefined,
            .batcher = undefined,
            .font_cache = undefined,
            .buf_width = undefined,
            .buf_height = undefined,
            .default_font_id = undefined,
            .default_font_gid = undefined,
            .main_ps = undefined,
            .ps = undefined,
            .cur_cam_world_pos = undefined,
            .tmp_joint_idxes = undefined,
            .image_store = image.ImageStore.init(alloc, self),
            .dpr = dpr,
            .dpr_ceil = @floatToInt(u8, std.math.ceil(dpr)),
            .vec2_helper_buf = std.ArrayList(Vec2).init(alloc),
            .vec2_slice_helper_buf = std.ArrayList(stdx.IndexSlice(u32)).init(alloc),
            .qbez_helper_buf = std.ArrayList(SubQuadBez).init(alloc),
            .tessellator = undefined,
            .raster_glyph_buffer = std.ArrayList(u8).init(alloc),
        };
    }

    fn initCommon(self: *Graphics, alloc: std.mem.Allocator) !void {
        self.tessellator.init(alloc);

        // Generate basic solid color texture.
        var buf: [16]u32 = undefined;
        std.mem.set(u32, &buf, 0xFFFFFFFF);
        self.white_tex = self.image_store.createImageFromBitmap(4, 4, std.mem.sliceAsBytes(buf[0..]), .{
            .linear_filter = false,
        });

        self.font_cache.init(alloc, self);

        // TODO: Embed a default bitmap font.
        // TODO: Embed a default ttf monospace font.

        self.default_font_id = self.addFontTTF(vera_ttf);
        self.default_font_gid = self.font_cache.getOrLoadFontGroup(&.{self.default_font_id});

        self.main_ps = try alloc.create(PaintState);
        self.main_ps.* = PaintState.init(self.default_font_gid);
        self.ps = self.main_ps;

        if (build_options.has_lyon) {
            lyon.init();
        }

        // Clear color. Default to white.
        self.setClearColor(Color.White);
        // gl.clearColor(0.1, 0.2, 0.3, 1.0);
        // gl.clearColor(0, 0, 0, 1.0);
    }

    pub fn deinit(self: *Graphics) void {
        switch (Backend) {
            .Vulkan => {
                const device = self.inner.ctx.device;
                self.inner.pipelines.deinit(device);

                vk.destroyDescriptorSetLayout(device, self.inner.tex_desc_set_layout, null);
                vk.destroyDescriptorSetLayout(device, self.inner.mats_desc_set_layout, null);
                vk.destroyDescriptorSetLayout(device, self.inner.materials_desc_set_layout, null);
            },
            else => {},
        }
        self.batcher.deinit(self.alloc);
        self.font_cache.deinit();

        self.main_ps.deinit(self.alloc);
        self.alloc.destroy(self.main_ps);

        if (build_options.has_lyon) {
            lyon.deinit();
        }

        self.image_store.deinit();

        self.vec2_helper_buf.deinit();
        self.vec2_slice_helper_buf.deinit();
        self.qbez_helper_buf.deinit();
        self.tessellator.deinit();
        self.raster_glyph_buffer.deinit();
    }

    pub fn addFontOTB(self: *Graphics, data: []const graphics.BitmapFontData) FontId {
        return self.font_cache.addFontOTB(data);
    }

    pub fn addFontTTF(self: *Graphics, data: []const u8) FontId {
        return self.font_cache.addFontTTF(data);
    }

    pub fn addFallbackFont(self: *Graphics, font_id: FontId) void {
        self.font_cache.addSystemFont(font_id) catch unreachable;
    }

    pub fn clipRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL => {
                self.ps.clip_rect = .{
                    .x = x,
                    // clip-y starts at bottom.
                    .y = @intToFloat(f32, self.buf_height) - (y + height),
                    .width = width,
                    .height = height,
                };
            },
            .Vulkan => {
                self.ps.clip_rect = .{
                    .x = x * self.dpr,
                    .y = y * self.dpr,
                    .width = width * self.dpr,
                    .height = height * self.dpr,
                };
            },
            else => {},
        }
        self.ps.using_scissors = true;

        // Execute current draw calls before we alter state.
        self.endCmd();

        self.clipRectCmd(self.ps.clip_rect);
    }

    fn clipRectCmd(self: Graphics, rect: geom.Rect) void {
        switch (Backend) {
            .OpenGL => {
                gl.scissor(@floatToInt(c_int, rect.x), @floatToInt(c_int, rect.y), @floatToInt(c_int, rect.width), @floatToInt(c_int, rect.height));
                gl.enable(gl.GL_SCISSOR_TEST);
            },
            .Vulkan => {
                const vk_rect = vk.VkRect2D{
                    .offset = .{
                        .x = @floatToInt(i32, rect.x),
                        .y = @floatToInt(i32, rect.y),
                    },
                    .extent = .{
                        .width = @floatToInt(u32, rect.width),
                        .height = @floatToInt(u32, rect.height),
                    },
                };
                vk.cmdSetScissor(self.inner.cur_frame.main_cmd_buf, 0, 1, &vk_rect);
            },
            else => {},
        }
    }

    pub fn resetTransform(self: *Graphics) void {
        self.ps.view_xform.reset();
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn pushState(self: *Graphics) void {
        self.ps.state_stack.append(self.alloc, .{
            .clip_rect = self.ps.clip_rect,
            .use_scissors = self.ps.using_scissors,
            .blend_mode = self.ps.blend_mode,
            .view_xform = self.ps.view_xform,
        }) catch fatal();
    }

    pub fn popState(self: *Graphics) void {
        // log.debug("popState", .{});

        // Execute current draw calls before altering state.
        self.endCmd();

        const state = self.ps.state_stack.pop();
        if (state.use_scissors) {
            const r = state.clip_rect;
            self.clipRect(r.x, r.y, r.width, r.height);
        } else {
            self.ps.using_scissors = false;
            switch (Backend) {
                .OpenGL => {
                    gl.disable(gl.GL_SCISSOR_TEST);
                },
                .Vulkan => {
                    const r = state.clip_rect;
                    self.clipRect(r.x, r.y, r.width, r.height);
                },
                else => {},
            }
        }
        if (state.blend_mode != self.ps.blend_mode) {
            self.setBlendMode(state.blend_mode);
        }
        if (!std.meta.eql(self.ps.view_xform.mat, state.view_xform.mat)) {
            self.ps.view_xform = state.view_xform;
            const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
            self.batcher.mvp = mvp;
        }
    }

    pub fn getViewTransform(self: Graphics) Transform {
        return self.ps.view_xform;
    }

    pub fn getLineWidth(self: Graphics) f32 {
        return self.ps.line_width;
    }

    pub fn setLineWidth(self: *Graphics, width: f32) void {
        self.ps.line_width = width;
        self.ps.line_width_half = width * 0.5;
    }

    pub fn setPaintState(self: *Graphics, ps: *PaintState) void {
        self.ps = ps;
    }

    pub fn setMainPaintState(self: *Graphics) void {
        self.ps = self.main_ps;
    }

    pub fn setFont(self: *Graphics, font_id: FontId) void {
        // Lookup font group single font.
        const font_gid = self.font_cache.getOrLoadFontGroup(&.{font_id});
        self.setFontGroup(font_gid);
    }

    pub fn setFontGroup(self: *Graphics, font_gid: FontGroupId) void {
        if (font_gid != self.ps.font_gid) {
            self.ps.font_gid = font_gid;
        }
    }

    pub inline fn clear(_: Graphics) void {
        gl.clear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
    }

    pub fn setClearColor(self: *Graphics, color: Color) void {
        self.ps.clear_color = color;
        if (Backend == .OpenGL) {
            const f = color.toFloatArray();
            gl.clearColor(f[0], f[1], f[2], f[3]);
        }
    }

    pub fn getFillColor(self: Graphics) Color {
        return self.ps.fill_color;
    }

    pub fn setFillColor(self: *Graphics, color: Color) void {
        self.batcher.beginTex(self.white_tex);
        self.ps.fill_color = color;
    }

    pub fn setFillGradient(self: *Graphics, start_x: f32, start_y: f32, start_color: Color, end_x: f32, end_y: f32, end_color: Color) void {
        // Convert to buffer coords on cpu.
        if (Backend == .OpenGL and IsWasm) {
            // Use bottom left coords.
            const start_screen_pos = self.ps.view_xform.interpolatePt(vec2(start_x, @intToFloat(f32, self.buf_height) - start_y)).mul(self.dpr);
            const end_screen_pos = self.ps.view_xform.interpolatePt(vec2(end_x, @intToFloat(f32, self.buf_height) - end_y)).mul(self.dpr);
            self.batcher.beginGradient(start_screen_pos, start_color, end_screen_pos, end_color);
        } else {
            const start_screen_pos = self.ps.view_xform.interpolatePt(vec2(start_x, start_y)).mul(self.dpr);
            const end_screen_pos = self.ps.view_xform.interpolatePt(vec2(end_x, end_y)).mul(self.dpr);
            self.batcher.beginGradient(start_screen_pos, start_color, end_screen_pos, end_color);
        }
    }

    pub fn getStrokeColor(self: Graphics) Color {
        return self.ps.stroke_color;
    }

    pub fn setStrokeColor(self: *Graphics, color: Color) void {
        self.ps.stroke_color = color;
    }

    pub fn getFontSize(self: Graphics) f32 {
        return self.ps.font_size;
    }

    pub fn getOrLoadFontGroupByFamily(self: *Graphics, family: graphics.FontFamily) FontGroupId {
        switch (family) {
            .Name => {
                return self.font_cache.getOrLoadFontGroupByNameSeq(&.{family.Name}).?;
            },
            .FontGroup => return family.FontGroup,
            .Font => return self.font_cache.getOrLoadFontGroup(&.{ family.Font }),
            .Default => return self.default_font_gid,
        }
    }

    pub fn setFontSize(self: *Graphics, size: f32) void {
        if (self.ps.font_size != size) {
            self.ps.font_size = size;
        }
    }

    pub fn setTextAlign(self: *Graphics, align_: TextAlign) void {
        self.ps.text_align = align_;
    }

    pub fn setTextBaseline(self: *Graphics, baseline: TextBaseline) void {
        self.ps.text_baseline = baseline;
    }

    pub fn measureText(self: *Graphics, str: []const u8, res: *TextMetrics) void {
        text_renderer.measureText(self, self.ps.font_gid, self.ps.font_size, self.dpr_ceil, str, res, true);
    }

    pub fn measureFontText(self: *Graphics, group_id: FontGroupId, size: f32, str: []const u8, res: *TextMetrics) void {
        text_renderer.measureText(self, group_id, size, self.dpr_ceil, str, res, true);
    }

    pub inline fn textGlyphIter(self: *Graphics, font_gid: FontGroupId, size: f32, str: []const u8) graphics.TextGlyphIterator {
        return text_renderer.textGlyphIter(self, font_gid, size, self.dpr_ceil, str);
    }

    pub inline fn fillText(self: *Graphics, x: f32, y: f32, str: []const u8) void {
        self.fillTextExt(x, y, str, .{
            .@"align" = self.ps.text_align,
            .baseline = self.ps.text_baseline,
        });
    }

    pub fn fillTextExt(self: *Graphics, x: f32, y: f32, str: []const u8, opts: graphics.TextOptions) void {
        // log.info("draw text '{s}'", .{str});
        var vert: TexShaderVertex = undefined;

        var vdata: VertexData(4, 6) = undefined;

        var start_x = x;
        var start_y = y;

        if (opts.@"align" != .Left) {
            var metrics: TextMetrics = undefined;
            self.measureText(str, &metrics);
            switch (opts.@"align") {
                .Left => {},
                .Right => start_x = x-metrics.width,
                .Center => start_x = x-metrics.width/2,
            }
        }
        if (opts.baseline != .Top) {
            const vmetrics = self.font_cache.getPrimaryFontVMetrics(self.ps.font_gid, self.ps.font_size);
            switch (opts.baseline) {
                .Top => {},
                .Middle => start_y = y - vmetrics.height / 2,
                .Alphabetic => start_y = y - vmetrics.ascender,
                .Bottom => start_y = y - vmetrics.height,
            }
        }
        var iter = text_renderer.RenderTextIterator.init(self, self.ps.font_gid, self.ps.font_size, self.dpr_ceil, start_x, start_y, str);

        while (iter.nextCodepointQuad(true)) {
            self.setCurrentTexture(iter.quad.image);

            if (iter.quad.is_color_bitmap) {
                vert.setColor(Color.White);
            } else {
                vert.setColor(self.ps.fill_color);
            }

            // top left
            vert.setXY(iter.quad.x0, iter.quad.y0);
            vert.setUV(iter.quad.u0, iter.quad.v0);
            vdata.verts[0] = vert;

            // top right
            vert.setXY(iter.quad.x1, iter.quad.y0);
            vert.setUV(iter.quad.u1, iter.quad.v0);
            vdata.verts[1] = vert;

            // bottom right
            vert.setXY(iter.quad.x1, iter.quad.y1);
            vert.setUV(iter.quad.u1, iter.quad.v1);
            vdata.verts[2] = vert;

            // bottom left
            vert.setXY(iter.quad.x0, iter.quad.y1);
            vert.setUV(iter.quad.u0, iter.quad.v1);
            vdata.verts[3] = vert;

            // indexes
            vdata.setRect(0, 0, 1, 2, 3);

            self.pushVertexData(4, 6, &vdata);
        }
    }

    pub inline fn setCurrentTexture(self: *Graphics, image_tex: image.ImageTex) void {
        self.batcher.beginTexture(image_tex);
    }

    fn pushLyonVertexData(self: *Graphics, data: *lyon.VertexData, color: Color) void {
        self.batcher.ensureUnusedBuffer(data.vertex_len, data.index_len);
        self.batcher.pushLyonVertexData(data, color);
    }

    fn pushVertexData(self: *Graphics, comptime num_verts: usize, comptime num_indices: usize, data: *VertexData(num_verts, num_indices)) void {
        self.batcher.ensureUnusedBuffer(num_verts, num_indices);
        self.batcher.pushVertexData(num_verts, num_indices, data);
    }

    pub fn drawRectVec(self: *Graphics, pos: Vec2, width: f32, height: f32) void {
        self.drawRect(pos.x, pos.y, width, height);
    }

    pub fn drawRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
        self.drawRectBounds(x, y, x + width, y + height);
    }

    pub fn drawRectBounds(self: *Graphics, x0: f32, y0: f32, x1: f32, y1: f32) void {
        self.batcher.beginTex(self.white_tex);
        // Top border.
        self.fillRectBoundsColor(x0 - self.ps.line_width_half, y0 - self.ps.line_width_half, x1 + self.ps.line_width_half, y0 + self.ps.line_width_half, self.ps.stroke_color);
        // Right border.
        self.fillRectBoundsColor(x1 - self.ps.line_width_half, y0 + self.ps.line_width_half, x1 + self.ps.line_width_half, y1 - self.ps.line_width_half, self.ps.stroke_color);
        // Bottom border.
        self.fillRectBoundsColor(x0 - self.ps.line_width_half, y1 - self.ps.line_width_half, x1 + self.ps.line_width_half, y1 + self.ps.line_width_half, self.ps.stroke_color);
        // Left border.
        self.fillRectBoundsColor(x0 - self.ps.line_width_half, y0 + self.ps.line_width_half, x0 + self.ps.line_width_half, y1 - self.ps.line_width_half, self.ps.stroke_color);
    }

    // Uses path rendering.
    pub fn strokeRectLyon(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
        self.batcher.beginTex(self.white_tex);
        // log.debug("strokeRect {d:.2} {d:.2} {d:.2} {d:.2}", .{pos.x, pos.y, width, height});
        const b = lyon.initBuilder();
        lyon.addRectangle(b, &.{ .x = x, .y = y, .width = width, .height = height });
        var data = lyon.buildStroke(b, self.ps.line_width);

        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.ps.stroke_color);
    }

    pub fn fillRoundRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        self.fillRoundRectBounds(x, y, x + width, y + height, radius);
    }

    pub fn fillRoundRectBounds(self: *Graphics, x0: f32, y0: f32, x1: f32, y1: f32, radius: f32) void {
        // Top left corner.
        self.fillCircleSectorN(x0 + radius, y0 + radius, radius, math.pi, math.pi_half, 90);
        // Left side.
        self.fillRectBounds(x0, y0 + radius, x0 + radius, y1 - radius);
        // Bottom left corner.
        self.fillCircleSectorN(x0 + radius, y1 - radius, radius, math.pi_half, math.pi_half, 90);
        // Middle.
        self.fillRectBounds(x0 + radius, y0, x1 - radius, y1);
        // Top right corner.
        self.fillCircleSectorN(x1 - radius, y0 + radius, radius, -math.pi_half, math.pi_half, 90);
        // Right side.
        self.fillRectBounds(x1 - radius, y0 + radius, x1, y1 - radius);
        // Bottom right corner.
        self.fillCircleSectorN(x1 - radius, y1 - radius, radius, 0, math.pi_half, 90);
    }

    pub fn drawRoundRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        self.drawRoundRectBounds(x, y, x + width, y + height, radius);
    }

    pub fn drawRoundRectBounds(self: *Graphics, x0: f32, y0: f32, x1: f32, y1: f32, radius: f32) void {
        self.batcher.beginTex(self.white_tex);
        // Top left corner.
        self.drawCircleArcN(x0 + radius, y0 + radius, radius, math.pi, math.pi_half, 90);
        // Left side.
        self.fillRectBoundsColor(x0 - self.ps.line_width_half, y0 + radius, x0 + self.ps.line_width_half, y1 - radius, self.ps.stroke_color);
        // Bottom left corner.
        self.drawCircleArcN(x0 + radius, y1 - radius, radius, math.pi_half, math.pi_half, 90);
        // Top.
        self.fillRectBoundsColor(x0 + radius, y0 - self.ps.line_width_half, x1 - radius, y0 + self.ps.line_width_half, self.ps.stroke_color);
        // Bottom.
        self.fillRectBoundsColor(x0 + radius, y1 - self.ps.line_width_half, x1 - radius, y1 + self.ps.line_width_half, self.ps.stroke_color);
        // Top right corner.
        self.drawCircleArcN(x1 - radius, y0 + radius, radius, -math.pi_half, math.pi_half, 90);
        // Right side.
        self.fillRectBoundsColor(x1 - self.ps.line_width_half, y0 + radius, x1 + self.ps.line_width_half, y1 - radius, self.ps.stroke_color);
        // Bottom right corner.
        self.drawCircleArcN(x1 - radius, y1 - radius, radius, 0, math.pi_half, 90);
    }

    pub fn drawPlane(self: *Graphics) void {
        self.batcher.endCmd();
        self.batcher.cur_shader_type = .Plane;

        self.batcher.ensureUnusedBuffer(4, 6);
        var vert: TexShaderVertex = undefined;
        const start_idx = self.batcher.mesh.getNextIndexId();
        if (Backend == .OpenGL) {
            vert.setXYZ(-1, 1, -1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(1, 1, -1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(1, -1, -1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(-1, -1, -1);
            self.batcher.mesh.pushVertex(vert);
        } else {
            vert.setXYZ(-1, -1, 1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(1, -1, 1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(1, 1, 1);
            self.batcher.mesh.pushVertex(vert);
            vert.setXYZ(-1, 1, 1);
            self.batcher.mesh.pushVertex(vert);
        }
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
        self.batcher.endCmdForce();
    }

    pub fn fillRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
        self.fillRectBoundsColor(x, y, x + width, y + height, self.ps.fill_color);
    }

    pub fn fillRectBounds(self: *Graphics, x0: f32, y0: f32, x1: f32, y1: f32) void {
        self.fillRectBoundsColor(x0, y0, x1, y1, self.ps.fill_color);
    }

    // Sometimes we want to override the color (eg. rendering part of a stroke.)
    fn fillRectBoundsColor(self: *Graphics, x0: f32, y0: f32, x1: f32, y1: f32, color: Color) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(color);

        const start_idx = self.batcher.mesh.getNextIndexId();

        // top left
        vert.setXY(x0, y0);
        vert.setUV(0, 0);
        self.batcher.mesh.pushVertex(vert);

        // top right
        vert.setXY(x1, y0);
        vert.setUV(1, 0);
        self.batcher.mesh.pushVertex(vert);

        // bottom right
        vert.setXY(x1, y1);
        vert.setUV(1, 1);
        self.batcher.mesh.pushVertex(vert);

        // bottom left
        vert.setXY(x0, y1);
        vert.setUV(0, 1);
        self.batcher.mesh.pushVertex(vert);

        // add rect
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawCircleArc(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        self.batcher.beginTex(self.white_tex);
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc sector per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.drawCircleArcN(x, y, radius, start_rad, sweep_rad, n);
    }

    // n is the number of sections in the arc we will draw.
    pub fn drawCircleArcN(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.batcher.beginTex(self.white_tex);
        self.batcher.ensureUnusedBuffer(2 + n * 2, n * 3 * 2);

        const inner_rad = radius - self.ps.line_width_half;
        const outer_rad = radius + self.ps.line_width_half;

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.stroke_color);
        vert.setUV(0, 0); // Currently we don't do uv mapping for strokes.

        // Add first two vertices.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setXY(x + cos * inner_rad, y + sin * inner_rad);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x + cos * outer_rad, y + sin * outer_rad);
        self.batcher.mesh.pushVertex(vert);

        const rad_per_n = sweep_rad / @intToFloat(f32, n);
        var cur_vert_idx = self.batcher.mesh.getNextIndexId();
        var i: u32 = 1;
        while (i <= n) : (i += 1) {
            const rad = start_rad + rad_per_n * @intToFloat(f32, i);

            // Add inner/outer vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setXY(x + cos * inner_rad, y + sin * inner_rad);
            self.batcher.mesh.pushVertex(vert);
            vert.setXY(x + cos * outer_rad, y + sin * outer_rad);
            self.batcher.mesh.pushVertex(vert);

            // Add arc sector.
            self.batcher.mesh.pushQuadIndexes(cur_vert_idx - 1, cur_vert_idx + 1, cur_vert_idx, cur_vert_idx - 2);
            cur_vert_idx += 2;
        }
    }

    pub fn fillCircleSectorN(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32, num_tri: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(num_tri + 2, num_tri * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.fill_color);

        // Add center.
        const center = self.batcher.mesh.getNextIndexId();
        vert.setUV(0.5, 0.5);
        vert.setXY(x, y);
        self.batcher.mesh.pushVertex(vert);

        // Add first circle vertex.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setUV(0.5 + cos, 0.5 + sin);
        vert.setXY(x + cos * radius, y + sin * radius);
        self.batcher.mesh.pushVertex(vert);

        const rad_per_tri = sweep_rad / @intToFloat(f32, num_tri);
        var last_vert_idx = center + 1;
        var i: u32 = 1;
        while (i <= num_tri) : (i += 1) {
            const rad = start_rad + rad_per_tri * @intToFloat(f32, i);

            // Add next circle vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setUV(0.5 + cos, 0.5 + sin);
            vert.setXY(x + cos * radius, y + sin * radius);
            self.batcher.mesh.pushVertex(vert);

            // Add triangle.
            const next_idx = last_vert_idx + 1;
            self.batcher.mesh.pushTriangle(center, last_vert_idx, next_idx);
            last_vert_idx = next_idx;
        }
    }

    pub fn fillCircleSector(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 triangle per degree.
        var num_tri = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.fillCircleSectorN(x, y, radius, start_rad, sweep_rad, num_tri);
    }

    // Same implementation as fillEllipse when h_radius = v_radius.
    pub fn fillCircle(self: *Graphics, x: f32, y: f32, radius: f32) void {
        self.fillCircleSectorN(x, y, radius, 0, math.pi_2, 360);
    }

    // Same implementation as drawEllipse when h_radius = v_radius. Might be slightly faster since we use fewer vars.
    pub fn drawCircle(self: *Graphics, x: f32, y: f32, radius: f32) void {
        self.drawCircleArcN(x, y, radius, 0, math.pi_2, 360);
    }

    pub fn fillEllipseSectorN(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(n + 2, n * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.fill_color);

        // Add center.
        const center = self.batcher.mesh.getNextIndexId();
        vert.setUV(0.5, 0.5);
        vert.setXY(x, y);
        self.batcher.mesh.pushVertex(vert);

        // Add first circle vertex.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setUV(0.5 + cos, 0.5 + sin);
        vert.setXY(x + cos * h_radius, y + sin * v_radius);
        self.batcher.mesh.pushVertex(vert);

        const rad_per_tri = sweep_rad / @intToFloat(f32, n);
        var last_vert_idx = center + 1;
        var i: u32 = 1;
        while (i <= n) : (i += 1) {
            const rad = start_rad + rad_per_tri * @intToFloat(f32, i);

            // Add next circle vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setUV(0.5 + cos, 0.5 + sin);
            vert.setXY(x + cos * h_radius, y + sin * v_radius);
            self.batcher.mesh.pushVertex(vert);

            // Add triangle.
            const next_idx = last_vert_idx + 1;
            self.batcher.mesh.pushTriangle(center, last_vert_idx, next_idx);
            last_vert_idx = next_idx;
        }
    }

    pub fn fillEllipseSector(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc section per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.fillEllipseSectorN(x, y, h_radius, v_radius, start_rad, sweep_rad, n);
    }

    pub fn fillEllipse(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        self.fillEllipseSectorN(x, y, h_radius, v_radius, 0, math.pi_2, 360);
    }

    pub fn drawEllipseArc(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc sector per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.drawEllipseArcN(x, y, h_radius, v_radius, start_rad, sweep_rad, n);
    }

    // n is the number of sections in the arc we will draw.
    pub fn drawEllipseArcN(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.batcher.beginTex(self.white_tex);
        self.batcher.ensureUnusedBuffer(2 + n * 2, n * 3 * 2);

        const inner_h_rad = h_radius - self.ps.line_width_half;
        const inner_v_rad = v_radius - self.ps.line_width_half;
        const outer_h_rad = h_radius + self.ps.line_width_half;
        const outer_v_rad = v_radius + self.ps.line_width_half;

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.stroke_color);
        vert.setUV(0, 0); // Currently we don't do uv mapping for strokes.

        // Add first two vertices.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setXY(x + cos * inner_h_rad, y + sin * inner_v_rad);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x + cos * outer_h_rad, y + sin * outer_v_rad);
        self.batcher.mesh.pushVertex(vert);

        const rad_per_n = sweep_rad / @intToFloat(f32, n);
        var cur_vert_idx = self.batcher.mesh.getNextIndexId();
        var i: u32 = 1;
        while (i <= n) : (i += 1) {
            const rad = start_rad + rad_per_n * @intToFloat(f32, i);

            // Add inner/outer vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setXY(x + cos * inner_h_rad, y + sin * inner_v_rad);
            self.batcher.mesh.pushVertex(vert);
            vert.setXY(x + cos * outer_h_rad, y + sin * outer_v_rad);
            self.batcher.mesh.pushVertex(vert);

            // Add arc sector.
            self.batcher.mesh.pushQuadIndexes(cur_vert_idx + 1, cur_vert_idx - 1, cur_vert_idx - 2, cur_vert_idx);
            cur_vert_idx += 2;
        }
    }

    pub fn drawEllipse(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        self.drawEllipseArcN(x, y, h_radius, v_radius, 0, math.pi_2, 360);
    }

    pub fn drawPoint(self: *Graphics, x: f32, y: f32) void {
        self.batcher.beginTex(self.white_tex);
        self.fillRectBoundsColor(x - self.ps.line_width_half, y - self.ps.line_width_half, x + self.ps.line_width_half, y + self.ps.line_width_half, self.ps.stroke_color);
    }

    pub fn drawLine(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32) void {
        self.batcher.beginTex(self.white_tex);
        if (x1 == x2) {
            self.fillRectBoundsColor(x1 - self.ps.line_width_half, y1, x1 + self.ps.line_width_half, y2, self.ps.stroke_color);
        } else {
            const normal = vec2(y2 - y1, x2 - x1).toLength(self.ps.line_width_half);
            self.fillQuad(
                x1 - normal.x, y1 + normal.y,
                x1 + normal.x, y1 - normal.y,
                x2 + normal.x, y2 - normal.y,
                x2 - normal.x, y2 + normal.y,
                self.ps.stroke_color,
            );
        }
    }

    pub fn drawQuadraticBezierCurve(self: *Graphics, x0: f32, y0: f32, cx: f32, cy: f32, x1: f32, y1: f32) void {
        self.batcher.beginTex(self.white_tex);
        const q_bez = QuadBez{
            .x0 = x0,
            .y0 = y0,
            .cx = cx,
            .cy = cy,
            .x1 = x1,
            .y1 = y1,
        };
        self.vec2_helper_buf.clearRetainingCapacity();
        stroke.strokeQuadBez(self.batcher.mesh, &self.vec2_helper_buf, q_bez, self.ps.line_width_half, self.ps.stroke_color);
    }

    pub fn drawQuadraticBezierCurveLyon(self: *Graphics, x0: f32, y0: f32, cx: f32, cy: f32, x1: f32, y1: f32) void {
        self.batcher.beginTex(self.white_tex);
        const b = lyon.initBuilder();
        lyon.begin(b, &pt(x0, y0));
        lyon.quadraticBezierTo(b, &pt(cx, cy), &pt(x1, y1));
        lyon.end(b, false);
        var data = lyon.buildStroke(b, self.ps.line_width);
        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.ps.stroke_color);
    }

    pub fn drawCubicBezierCurve(self: *Graphics, x0: f32, y0: f32, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x1: f32, y1: f32) void {
        self.batcher.beginTex(self.white_tex);
        const c_bez = CubicBez{
            .x0 = x0,
            .y0 = y0,
            .cx0 = cx0,
            .cy0 = cy0,
            .cx1 = cx1,
            .cy1 = cy1,
            .x1 = x1,
            .y1 = y1,
        };
        self.qbez_helper_buf.clearRetainingCapacity();
        self.vec2_helper_buf.clearRetainingCapacity();
        stroke.strokeCubicBez(self.batcher.mesh, &self.vec2_helper_buf, &self.qbez_helper_buf, c_bez, self.ps.line_width_half, self.ps.stroke_color);
    }

    pub fn drawCubicBezierCurveLyon(self: *Graphics, x0: f32, y0: f32, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x1: f32, y1: f32) void {
        self.batcher.beginTex(self.white_tex);
        const b = lyon.initBuilder();
        lyon.begin(b, &pt(x0, y0));
        lyon.cubicBezierTo(b, &pt(cx0, cy0), &pt(cx1, cy1), &pt(x1, y1));
        lyon.end(b, false);
        var data = lyon.buildStroke(b, self.ps.line_width);
        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.ps.stroke_color);
    }

    // Points are given in ccw order. Currently doesn't map uvs.
    pub fn fillQuad(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, x4: f32, y4: f32, color: Color) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();
        vert.setXY(x1, y1);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x2, y2);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x3, y3);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x4, y4);
        self.batcher.mesh.pushVertex(vert);
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn fillSvgPath(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath) void {
        const t_ = trace(@src());
        defer t_.end();
        self.drawSvgPath(x, y, path, true);
    }

    pub fn fillSvgPathLyon(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath) void {
        const t_ = trace(@src());
        defer t_.end();
        self.drawSvgPathLyon(x, y, path, true);
    }

    pub fn fillSvgPathTess2(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath) void {
        const t_ = trace(@src());
        defer t_.end();
        _ = x;
        _ = y;

        // Accumulate polygons.
        self.vec2_helper_buf.clearRetainingCapacity();
        self.vec2_slice_helper_buf.clearRetainingCapacity();
        self.qbez_helper_buf.clearRetainingCapacity();

        var last_cmd_was_curveto = false;
        var last_control_pt = vec2(0, 0);
        var cur_data_idx: u32 = 0;
        var cur_pt = vec2(0, 0);
        var cur_poly_start: u32 = 0;

        for (path.cmds) |cmd| {
            var cmd_is_curveto = false;
            switch (cmd) {
                .MoveTo => {
                    if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
                        self.vec2_slice_helper_buf.append(.{
                            .start = cur_poly_start,
                            .end = @intCast(u32, self.vec2_helper_buf.items.len),
                        }) catch fatal();
                    } else if (self.vec2_helper_buf.items.len == cur_poly_start + 1) {
                        // Only one unused point. Remove it.
                        _ = self.vec2_helper_buf.pop();
                    }
                    const data = path.getData(.MoveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveTo)) / 4;
                    cur_pt = .{
                        .x = data.x,
                        .y = data.y,
                    };
                    cur_poly_start = @intCast(u32, self.vec2_helper_buf.items.len);
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .MoveToRel => {
                    if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
                        self.vec2_slice_helper_buf.append(.{
                            .start = cur_poly_start,
                            .end = @intCast(u32, self.vec2_helper_buf.items.len),
                        }) catch fatal();
                    } else if (self.vec2_helper_buf.items.len == cur_poly_start + 1) {
                        // Only one unused point. Remove it.
                        _ = self.vec2_helper_buf.pop();
                    }
                    const data = path.getData(.MoveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveToRel)) / 4;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    cur_poly_start = @intCast(u32, self.vec2_helper_buf.items.len);
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .CurveToRel => {
                    const data = path.getData(.CurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.CurveToRel)) / 4;

                    last_control_pt = .{
                        .x = cur_pt.x + data.cb_x,
                        .y = cur_pt.y + data.cb_y,
                    };
                    const prev_pt = cur_pt;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    const c_bez = CubicBez{
                        .x0 = prev_pt.x,
                        .y0 = prev_pt.y,
                        .cx0 = prev_pt.x + data.ca_x,
                        .cy0 = prev_pt.y + data.ca_y,
                        .cx1 = last_control_pt.x,
                        .cy1 = last_control_pt.y,
                        .x1 = cur_pt.x,
                        .y1 = cur_pt.y,
                    };
                    c_bez.flatten(0.5, &self.vec2_helper_buf, &self.qbez_helper_buf);
                    cmd_is_curveto = true;
                },
                .LineTo => {
                    const data = path.getData(.LineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineTo)) / 4;

                    cur_pt = .{
                        .x = data.x,
                        .y = data.y,
                    };
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .LineToRel => {
                    const data = path.getData(.LineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineToRel)) / 4;

                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .SmoothCurveToRel => {
                    const data = path.getData(.SmoothCurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveToRel)) / 4;

                    var cx0: f32 = undefined;
                    var cy0: f32 = undefined;
                    if (last_cmd_was_curveto) {
                        // Reflection of last control point over current pos.
                        cx0 = cur_pt.x + (cur_pt.x - last_control_pt.x);
                        cy0 = cur_pt.y + (cur_pt.y - last_control_pt.y);
                    } else {
                        cx0 = cur_pt.x;
                        cy0 = cur_pt.y;
                    }
                    last_control_pt = .{
                        .x = cur_pt.x + data.c2_x,
                        .y = cur_pt.y + data.c2_y,
                    };
                    const prev_pt = cur_pt;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    const c_bez = CubicBez{
                        .x0 = prev_pt.x,
                        .y0 = prev_pt.y,
                        .cx0 = cx0,
                        .cy0 = cy0,
                        .cx1 = last_control_pt.x,
                        .cy1 = last_control_pt.y,
                        .x1 = cur_pt.x,
                        .y1 = cur_pt.y,
                    };
                    c_bez.flatten(0.5, &self.vec2_helper_buf, &self.qbez_helper_buf);
                    cmd_is_curveto = true;
                },
                .VertLineToRel => {
                    const data = path.getData(.VertLineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineToRel)) / 4;
                    cur_pt.y += data.y;
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .ClosePath => {
                    // if (fill) {
                    //     // For fills, this is a no-op.
                    // } else {
                    //     // For strokes, this would form a seamless connection to the first point.
                    // }
                },
                else => {
                    stdx.panicFmt("unsupported: {}", .{cmd});
                },
            }
            last_cmd_was_curveto = cmd_is_curveto;
        }

        if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
            // Push the current polygon.
            self.vec2_slice_helper_buf.append(.{
                .start = cur_poly_start,
                .end = @intCast(u32, self.vec2_helper_buf.items.len),
            }) catch fatal();
        }
        if (self.vec2_slice_helper_buf.items.len == 0) {
            return;
        }

        for (self.vec2_slice_helper_buf.items) |polygon_slice| {
            var tess = getTess2Handle();
            const polygon = self.vec2_helper_buf.items[polygon_slice.start..polygon_slice.end];
            tess2.tessAddContour(tess, 2, &polygon[0], 8, @intCast(c_int, polygon.len));
            const res = tess2.tessTesselate(tess, tess2.TESS_WINDING_ODD, tess2.TESS_POLYGONS, 3, 2, null);
            if (res == 0) {
                unreachable;
            }

            var gpu_vert: TexShaderVertex = undefined;
            gpu_vert.setColor(self.ps.fill_color);
            const vert_offset_id = self.batcher.mesh.getNextIndexId();
            var nverts = tess2.tessGetVertexCount(tess);
            var verts = tess2.tessGetVertices(tess);
            const nelems = tess2.tessGetElementCount(tess);

            // log.debug("poly: {}, {}, {}", .{polygon.len, nverts, nelems});

            self.setCurrentTexture(self.white_tex);
            self.batcher.ensureUnusedBuffer(@intCast(u32, nverts), @intCast(usize, nelems * 3));

            var i: u32 = 0;
            while (i < nverts) : (i += 1) {
                gpu_vert.setXY(verts[i*2], verts[i*2+1]);
                // log.debug("{},{}", .{gpu_vert.pos_x, gpu_vert.pos_y});
                gpu_vert.setUV(0, 0);
                _ = self.batcher.mesh.pushVertex(gpu_vert);
            }
            const elems = tess2.tessGetElements(tess);
            i = 0;
            while (i < nelems) : (i += 1) {
                self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3+2]));
                self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3+1]));
                self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3]));
                // log.debug("idx {}", .{elems[i]});
            }
        }
    }

    pub fn strokeSvgPath(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath) void {
        self.drawSvgPath(x, y, path, false);
    }

    fn drawSvgPath(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath, fill: bool) void {
        // log.debug("drawSvgPath {} {}", .{path.cmds.len, fill});

        _ = x;
        _ = y;

        // Accumulate polygons.
        self.vec2_helper_buf.clearRetainingCapacity();
        self.vec2_slice_helper_buf.clearRetainingCapacity();
        self.qbez_helper_buf.clearRetainingCapacity();

        var last_cmd_was_curveto = false;
        var last_control_pt = vec2(0, 0);
        var cur_data_idx: u32 = 0;
        var cur_pt = vec2(0, 0);
        var cur_poly_start: u32 = 0;

        for (path.cmds) |cmd| {
            var cmd_is_curveto = false;
            switch (cmd) {
                .MoveTo => {
                    if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
                        self.vec2_slice_helper_buf.append(.{
                            .start = cur_poly_start,
                            .end = @intCast(u32, self.vec2_helper_buf.items.len),
                        }) catch fatal();
                    } else if (self.vec2_helper_buf.items.len == cur_poly_start + 1) {
                        // Only one unused point. Remove it.
                        _ = self.vec2_helper_buf.pop();
                    }
                    const data = path.getData(.MoveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveTo)) / 4;
                    cur_pt = .{
                        .x = data.x,
                        .y = data.y,
                    };
                    cur_poly_start = @intCast(u32, self.vec2_helper_buf.items.len);
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .MoveToRel => {
                    if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
                        self.vec2_slice_helper_buf.append(.{
                            .start = cur_poly_start,
                            .end = @intCast(u32, self.vec2_helper_buf.items.len),
                        }) catch fatal();
                    } else if (self.vec2_helper_buf.items.len == cur_poly_start + 1) {
                        // Only one unused point. Remove it.
                        _ = self.vec2_helper_buf.pop();
                    }
                    const data = path.getData(.MoveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveToRel)) / 4;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    cur_poly_start = @intCast(u32, self.vec2_helper_buf.items.len);
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .CurveToRel => {
                    const data = path.getData(.CurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.CurveToRel)) / 4;

                    last_control_pt = .{
                        .x = cur_pt.x + data.cb_x,
                        .y = cur_pt.y + data.cb_y,
                    };
                    const prev_pt = cur_pt;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    const c_bez = CubicBez{
                        .x0 = prev_pt.x,
                        .y0 = prev_pt.y,
                        .cx0 = prev_pt.x + data.ca_x,
                        .cy0 = prev_pt.y + data.ca_y,
                        .cx1 = last_control_pt.x,
                        .cy1 = last_control_pt.y,
                        .x1 = cur_pt.x,
                        .y1 = cur_pt.y,
                    };
                    c_bez.flatten(0.5, &self.vec2_helper_buf, &self.qbez_helper_buf);
                    cmd_is_curveto = true;
                },
                .LineTo => {
                    const data = path.getData(.LineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineTo)) / 4;

                    cur_pt = .{
                        .x = data.x,
                        .y = data.y,
                    };
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .LineToRel => {
                    const data = path.getData(.LineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineToRel)) / 4;

                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .SmoothCurveToRel => {
                    const data = path.getData(.SmoothCurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveToRel)) / 4;

                    var cx0: f32 = undefined;
                    var cy0: f32 = undefined;
                    if (last_cmd_was_curveto) {
                        // Reflection of last control point over current pos.
                        cx0 = cur_pt.x + (cur_pt.x - last_control_pt.x);
                        cy0 = cur_pt.y + (cur_pt.y - last_control_pt.y);
                    } else {
                        cx0 = cur_pt.x;
                        cy0 = cur_pt.y;
                    }
                    last_control_pt = .{
                        .x = cur_pt.x + data.c2_x,
                        .y = cur_pt.y + data.c2_y,
                    };
                    const prev_pt = cur_pt;
                    cur_pt = .{
                        .x = cur_pt.x + data.x,
                        .y = cur_pt.y + data.y,
                    };
                    const c_bez = CubicBez{
                        .x0 = prev_pt.x,
                        .y0 = prev_pt.y,
                        .cx0 = cx0,
                        .cy0 = cy0,
                        .cx1 = last_control_pt.x,
                        .cy1 = last_control_pt.y,
                        .x1 = cur_pt.x,
                        .y1 = cur_pt.y,
                    };
                    c_bez.flatten(0.5, &self.vec2_helper_buf, &self.qbez_helper_buf);
                    cmd_is_curveto = true;
                },
                .VertLineToRel => {
                    const data = path.getData(.VertLineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineToRel)) / 4;
                    cur_pt.y += data.y;
                    self.vec2_helper_buf.append(cur_pt) catch unreachable;
                },
                .ClosePath => {
                    if (fill) {
                        // For fills, this is a no-op.
                    } else {
                        // For strokes, this would form a seamless connection to the first point.
                    }
                },
                else => {
                    stdx.panicFmt("unsupported: {}", .{cmd});
                },
            }
        //         .VertLineTo => {
        //             const data = path.getData(.VertLineTo, cur_data_idx);
        //             cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineTo)) / 4;
        //             cur_pos.y = data.y;
        //             lyon.lineTo(b, &cur_pos);
        //         },
        //         .CurveTo => {
        //             const data = path.getData(.CurveTo, cur_data_idx);
        //             cur_data_idx += @sizeOf(svg.PathCommandData(.CurveTo)) / 4;
        //             cur_pos.x = data.x;
        //             cur_pos.y = data.y;
        //             last_control_pos.x = data.cb_x;
        //             last_control_pos.y = data.cb_y;
        //             cmd_is_curveto = true;
        //             lyon.cubicBezierTo(b, &pt(data.ca_x, data.ca_y), &last_control_pos, &cur_pos);
        //         },
        //         .SmoothCurveTo => {
        //             const data = path.getData(.SmoothCurveTo, cur_data_idx);
        //             cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveTo)) / 4;

        //             // Reflection of last control point over current pos.
        //             var c1_x: f32 = undefined;
        //             var c1_y: f32 = undefined;
        //             if (last_cmd_was_curveto) {
        //                 c1_x = cur_pos.x + (cur_pos.x - last_control_pos.x);
        //                 c1_y = cur_pos.y + (cur_pos.y - last_control_pos.y);
        //             } else {
        //                 c1_x = cur_pos.x;
        //                 c1_y = cur_pos.y;
        //             }

        //             cur_pos.x = data.x;
        //             cur_pos.y = data.y;
        //             last_control_pos.x = data.c2_x;
        //             last_control_pos.y = data.c2_y;
        //             cmd_is_curveto = true;
        //             lyon.cubicBezierTo(b, &pt(c1_x, c1_y), &last_control_pos, &cur_pos);
        //         },
        //     }
            last_cmd_was_curveto = cmd_is_curveto;
        }

        if (self.vec2_helper_buf.items.len > cur_poly_start + 1) {
            // Push the current polygon.
            self.vec2_slice_helper_buf.append(.{
                .start = cur_poly_start,
                .end = @intCast(u32, self.vec2_helper_buf.items.len),
            }) catch fatal();
        }
        if (self.vec2_slice_helper_buf.items.len == 0) {
            return;
        }

        if (fill) {
            // dumpPolygons(self.alloc, self.vec2_slice_helper_buf.items);
            self.tessellator.clearBuffers();
            self.tessellator.triangulatePolygons2(self.vec2_helper_buf.items, self.vec2_slice_helper_buf.items);
            self.setCurrentTexture(self.white_tex);
            const out_verts = self.tessellator.out_verts.items;
            const out_idxes = self.tessellator.out_idxes.items;
            self.batcher.ensureUnusedBuffer(out_verts.len, out_idxes.len);
            self.batcher.pushVertIdxBatch(out_verts, out_idxes, self.ps.fill_color);
        } else {
            unreachable;
        //     var data = lyon.buildStroke(b, self.ps.line_width);
        //     self.setCurrentTexture(self.white_tex);
        //     self.pushLyonVertexData(&data, self.ps.stroke_color);
        }
    }

    fn drawSvgPathLyon(self: *Graphics, x: f32, y: f32, path: *const svg.SvgPath, fill: bool) void {
        // log.debug("drawSvgPath {}", .{path.cmds.len});
        _ = x;
        _ = y;
        const b = lyon.initBuilder();
        var cur_pos = pt(0, 0);
        var cur_data_idx: u32 = 0;
        var last_control_pos = pt(0, 0);
        var cur_path_ended = true;
        var last_cmd_was_curveto = false;

        for (path.cmds) |it| {
            var cmd_is_curveto = false;
            switch (it) {
                .MoveTo => {
                    if (!cur_path_ended) {
                        // End previous subpath.
                        lyon.end(b, false);
                    }
                    // log.debug("lyon begin", .{});
                    const data = path.getData(.MoveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    lyon.begin(b, &cur_pos);
                    cur_path_ended = false;
                },
                .MoveToRel => {
                    if (!cur_path_ended) {
                        // End previous subpath.
                        lyon.end(b, false);
                    }
                    const data = path.getData(.MoveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveToRel)) / 4;
                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    lyon.begin(b, &cur_pos);
                    cur_path_ended = false;
                },
                .VertLineTo => {
                    const data = path.getData(.VertLineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineTo)) / 4;
                    cur_pos.y = data.y;
                    lyon.lineTo(b, &cur_pos);
                },
                .VertLineToRel => {
                    const data = path.getData(.VertLineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineToRel)) / 4;
                    cur_pos.y += data.y;
                    lyon.lineTo(b, &cur_pos);
                },
                .LineTo => {
                    const data = path.getData(.LineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    lyon.lineTo(b, &cur_pos);
                },
                .LineToRel => {
                    const data = path.getData(.LineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineToRel)) / 4;
                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    lyon.lineTo(b, &cur_pos);
                },
                .CurveTo => {
                    const data = path.getData(.CurveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.CurveTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    last_control_pos.x = data.cb_x;
                    last_control_pos.y = data.cb_y;
                    cmd_is_curveto = true;
                    lyon.cubicBezierTo(b, &pt(data.ca_x, data.ca_y), &last_control_pos, &cur_pos);
                },
                .CurveToRel => {
                    const data = path.getData(.CurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.CurveToRel)) / 4;
                    const prev_x = cur_pos.x;
                    const prev_y = cur_pos.y;
                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    last_control_pos.x = prev_x + data.cb_x;
                    last_control_pos.y = prev_y + data.cb_y;
                    cmd_is_curveto = true;
                    lyon.cubicBezierTo(b, &pt(prev_x + data.ca_x, prev_y + data.ca_y), &last_control_pos, &cur_pos);
                },
                .SmoothCurveTo => {
                    const data = path.getData(.SmoothCurveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveTo)) / 4;

                    // Reflection of last control point over current pos.
                    var c1_x: f32 = undefined;
                    var c1_y: f32 = undefined;
                    if (last_cmd_was_curveto) {
                        c1_x = cur_pos.x + (cur_pos.x - last_control_pos.x);
                        c1_y = cur_pos.y + (cur_pos.y - last_control_pos.y);
                    } else {
                        c1_x = cur_pos.x;
                        c1_y = cur_pos.y;
                    }

                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    last_control_pos.x = data.c2_x;
                    last_control_pos.y = data.c2_y;
                    cmd_is_curveto = true;
                    lyon.cubicBezierTo(b, &pt(c1_x, c1_y), &last_control_pos, &cur_pos);
                },
                .SmoothCurveToRel => {
                    const data = path.getData(.SmoothCurveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.SmoothCurveToRel)) / 4;
                    const prev_x = cur_pos.x;
                    const prev_y = cur_pos.y;

                    var c1_x: f32 = undefined;
                    var c1_y: f32 = undefined;
                    if (last_cmd_was_curveto) {
                        // Reflection of last control point over current pos.
                        c1_x = cur_pos.x + (cur_pos.x - last_control_pos.x);
                        c1_y = cur_pos.y + (cur_pos.y - last_control_pos.y);
                    } else {
                        c1_x = cur_pos.x;
                        c1_y = cur_pos.y;
                    }

                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    last_control_pos.x = prev_x + data.c2_x;
                    last_control_pos.y = prev_y + data.c2_y;
                    cmd_is_curveto = true;
                    lyon.cubicBezierTo(b, &pt(c1_x, c1_y), &last_control_pos, &cur_pos);
                },
                .ClosePath => {
                    lyon.close(b);
                    cur_path_ended = true;
                },
            }
            last_cmd_was_curveto = cmd_is_curveto;
        }
        if (fill) {
            var data = lyon.buildFill(b);
            self.setCurrentTexture(self.white_tex);
            self.pushLyonVertexData(&data, self.ps.fill_color);
        } else {
            var data = lyon.buildStroke(b, self.ps.line_width);
            self.setCurrentTexture(self.white_tex);
            self.pushLyonVertexData(&data, self.ps.stroke_color);
        }
    }

    /// Points of front face is in ccw order.
    pub fn fillTriangle3D(self: *Graphics, x1: f32, y1: f32, z1: f32, x2: f32, y2: f32, z2: f32, x3: f32, y3: f32, z3: f32) void {
        self.batcher.beginTex3D(self.white_tex);
        self.batcher.ensureUnusedBuffer(3, 3);

        self.batcher.model_idx = 0;

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();
        vert.setXYZ(x1, y1, z1);
        self.batcher.mesh.pushVertex(vert);
        vert.setXYZ(x2, y2, z2);
        self.batcher.mesh.pushVertex(vert);
        vert.setXYZ(x3, y3, z3);
        self.batcher.mesh.pushVertex(vert);
        self.batcher.mesh.pushTriangle(start_idx, start_idx + 1, start_idx + 2);
    }

    pub fn fillTriangle(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(3, 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();
        vert.setXY(x1, y1);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x2, y2);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(x3, y3);
        self.batcher.mesh.pushVertex(vert);
        self.batcher.mesh.pushTriangle(start_idx, start_idx + 1, start_idx + 2);
    }

    /// Assumes pts are in ccw order.
    pub fn fillConvexPolygon(self: *Graphics, pts: []const Vec2) void {
        self.setCurrentTexture(self.white_tex);
        self.batcher.ensureUnusedBuffer(pts.len, (pts.len - 2) * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.ps.fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();

        // Add first two vertices.
        vert.setXY(pts[0].x, pts[0].y);
        self.batcher.mesh.pushVertex(vert);
        vert.setXY(pts[1].x, pts[1].y);
        self.batcher.mesh.pushVertex(vert);

        var i: u16 = 2;
        while (i < pts.len) : (i += 1) {
            vert.setXY(pts[i].x, pts[i].y);
            self.batcher.mesh.pushVertex(vert);
            self.batcher.mesh.pushTriangle(start_idx, start_idx + i - 1, start_idx + i);
        }
    }

    pub fn fillPolygon(self: *Graphics, pts: []const Vec2) void {
        self.tessellator.clearBuffers();
        self.tessellator.triangulatePolygon(pts);
        self.setCurrentTexture(self.white_tex);
        const out_verts = self.tessellator.out_verts.items;
        const out_idxes = self.tessellator.out_idxes.items;
        self.batcher.ensureUnusedBuffer(out_verts.len, out_idxes.len);
        self.batcher.pushVertIdxBatch(out_verts, out_idxes, self.ps.fill_color);
    }

    pub fn fillPolygonLyon(self: *Graphics, pts: []const Vec2) void {
        const b = lyon.initBuilder();
        lyon.addPolygon(b, pts, true);
        var data = lyon.buildFill(b);

        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.ps.fill_color);
    }

    pub fn fillPolygonTess2(self: *Graphics, pts: []const Vec2) void {
        var tess = getTess2Handle();
        tess2.tessAddContour(tess, 2, &pts[0], 0, @intCast(c_int, pts.len));
        const res = tess2.tessTesselate(tess, tess2.TESS_WINDING_ODD, tess2.TESS_POLYGONS, 3, 2, null);
        if (res == 0) {
            unreachable;
        }

        var gpu_vert: TexShaderVertex = undefined;
        gpu_vert.setColor(self.ps.fill_color);
        const vert_offset_id = self.batcher.mesh.getNextIndexId();
        var nverts = tess2.tessGetVertexCount(tess);
        var verts = tess2.tessGetVertices(tess);
        const nelems = tess2.tessGetElementCount(tess);

        self.batcher.ensureUnusedBuffer(@intCast(u32, nverts), @intCast(usize, nelems * 3));

        var i: u32 = 0;
        while (i < nverts) : (i += 1) {
            gpu_vert.setXY(verts[i*2], verts[i*2+1]);
            gpu_vert.setUV(0, 0);
            _ = self.batcher.mesh.pushVertex(gpu_vert);
        }
        const elems = tess2.tessGetElements(tess);
        i = 0;
        while (i < nelems) : (i += 1) {
            self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3+2]));
            self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3+1]));
            self.batcher.mesh.pushIndex(@intCast(u16, vert_offset_id + elems[i*3]));
        }
    }

    pub fn drawTintedScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene, color: Color) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            self.drawTintedMesh3D(xform, node.mesh, color);
        }
    }

    /// Vertices are duped so that each side reflects light without interpolating the normals.
    pub fn drawCuboidPbr3D(self: *Graphics, xform: Transform, material: graphics.Material) void {
        self.batcher.beginTexPbr3D(self.white_tex, self.cur_cam_world_pos);
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(vp);

        // Compute normal matrix for lighting.
        self.batcher.normal = xform.toRotationMat();

        self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
        self.batcher.mesh.pushMatrix(xform.mat);

        self.batcher.material_idx = self.batcher.mesh.cur_materials_buf_size;
        self.batcher.mesh.pushMaterial(material);

        self.batcher.ensureUnusedBuffer(6*4, 6*6);
        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);
        vert.setUV(0, 0);
        const far_top_left = Vec4.init(-0.5, 0.5, -0.5, 1.0);
        const far_top_right = Vec4.init(0.5, 0.5, -0.5, 1.0);
        const far_bot_right = Vec4.init(0.5, -0.5, -0.5, 1.0);
        const far_bot_left = Vec4.init(-0.5, -0.5, -0.5, 1.0);
        const near_top_left = Vec4.init(-0.5, 0.5, 0.5, 1.0);
        const near_top_right = Vec4.init(0.5, 0.5, 0.5, 1.0);
        const near_bot_right = Vec4.init(0.5, -0.5, 0.5, 1.0);
        const near_bot_left = Vec4.init(-0.5, -0.5, 0.5, 1.0);

        // Far face.
        vert.setNormal(Vec3.init(0, 0, -1));
        self.batcher.mesh.pushQuad(far_top_right, far_top_left, far_bot_left, far_bot_right, vert);

        // Left face.
        vert.setNormal(Vec3.init(-1, 0, 0));
        self.batcher.mesh.pushQuad(far_top_left, near_top_left, near_bot_left, far_bot_left, vert);

        // Right face.
        vert.setNormal(Vec3.init(1, 0, 0));
        self.batcher.mesh.pushQuad(near_top_right, far_top_right, far_bot_right, near_bot_right, vert);

        // Near face.
        vert.setNormal(Vec3.init(0, 0, 1));
        self.batcher.mesh.pushQuad(near_top_left, near_top_right, near_bot_right, near_bot_left, vert);

        // Bottom face.
        vert.setNormal(Vec3.init(0, -1, 0));
        self.batcher.mesh.pushQuad(far_bot_right, far_bot_left, near_bot_left, near_bot_right, vert);

        // Top face.
        vert.setNormal(Vec3.init(0, 1, 0));
        self.batcher.mesh.pushQuad(far_top_left, far_top_right, near_top_right, near_top_left, vert);

        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            self.drawMesh3D(xform, node.mesh);
        }
    }

    pub fn drawScenePbr3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            self.drawMeshPbr3D(xform, node.mesh);
        }
    }

    pub fn drawScenePbrCustom3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene, mat: graphics.Material) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.drawMeshPbrCustom3D(xform, prim, mat);
            }
        }
    }

    pub fn drawTintedMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D, color: Color) void {
        if (mesh.image_id) |image_id| {
            const img = self.image_store.images.getNoCheck(image_id);
            self.batcher.beginTex3D(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id });
        } else {
            self.batcher.beginTex3D(self.white_tex);
        }
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        const mvp = xform.getAppliedTransform(vp);
        self.batcher.beginMvp(mvp);
        self.batcher.ensureUnusedBuffer(mesh.verts.len, mesh.indexes.len);
        const vert_start = self.batcher.mesh.getNextIndexId();
        for (mesh.verts) |vert| {
            var new_vert = vert;
            new_vert.setColor(color);
            self.batcher.mesh.pushVertex(new_vert);
        }
        self.batcher.mesh.pushDeltaIndexes(vert_start, mesh.indexes);
        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawSceneNormals3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            self.drawMeshNormals3D(xform, node.mesh);
        }
    }

    pub fn drawMeshNormals3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        self.batcher.beginNormal();
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        const mvp = xform.getAppliedTransform(vp);
        self.batcher.beginMvp(mvp);

        self.batcher.ensureUnusedBuffer(mesh.verts.len*2, mesh.verts.len*2);
        const vert_start = self.batcher.mesh.getNextIndexId();
        const norm_len = 1;
        for (mesh.verts) |vert, i| {
            var new_vert = vert;
            new_vert.setColor(Color.Blue);
            self.batcher.mesh.pushVertex(new_vert);
            new_vert.setColor(Color.Red);
            new_vert.setXYZ(new_vert.pos_x + new_vert.normal.x * norm_len, new_vert.pos_y + new_vert.normal.y * norm_len, new_vert.pos_z + new_vert.normal.z * norm_len);
            self.batcher.mesh.pushVertex(new_vert);
            self.batcher.mesh.pushIndex(vert_start + 2*@intCast(u16, i));
            self.batcher.mesh.pushIndex(vert_start + 2*@intCast(u16, i) + 1);
        }

        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        if (mesh.image_id) |image_id| {
            const img = self.image_store.images.getNoCheck(image_id);
            self.batcher.beginTex3D(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id });
        } else {
            self.batcher.beginTex3D(self.white_tex);
        }
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        const mvp = xform.getAppliedTransform(vp);
        self.batcher.beginMvp(mvp);
        self.batcher.pushMeshData(mesh.verts, mesh.indexes);
        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawMeshPbrCustom3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D, mat: graphics.Material) void {
        if (mesh.image_id) |image_id| {
            const img = self.image_store.images.getNoCheck(image_id);
            self.batcher.beginTexPbr3D(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id }, self.cur_cam_world_pos);
        } else {
            self.batcher.beginTexPbr3D(self.white_tex, self.cur_cam_world_pos);
        }
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(vp);

        // Compute normal matrix for lighting.
        self.batcher.normal = xform.toRotationUniformScaleMat();

        self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
        self.batcher.mesh.pushMatrix(xform.mat);

        self.batcher.material_idx = self.batcher.mesh.cur_materials_buf_size;
        self.batcher.mesh.pushMaterial(mat);

        self.batcher.ensurePushMeshData(mesh.verts, mesh.indexes);
        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawMeshPbr3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        if (mesh.image_id) |image_id| {
            const img = self.image_store.images.getNoCheck(image_id);
            self.batcher.beginTexPbr3D(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id }, self.cur_cam_world_pos);
        } else {
            self.batcher.beginTexPbr3D(self.white_tex, self.cur_cam_world_pos);
        }
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(vp);

        // Compute normal matrix for lighting.
        self.batcher.normal = xform.toRotationUniformScaleMat();

        self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
        self.batcher.mesh.pushMatrix(xform.mat);

        self.batcher.material_idx = self.batcher.mesh.cur_materials_buf_size;
        self.batcher.mesh.pushMaterial(mesh.material);

        self.batcher.pushMeshData(mesh.verts, mesh.indexes);
        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawAnimatedMesh3D(self: *Graphics, model_xform: Transform, amesh: graphics.AnimatedMesh, custom_mat: ?graphics.Material, comptime fill: bool, comptime pbr: bool) void {
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);

        // Apply animation.
        for (amesh.transition_markers) |marker, i| {
            const tt = marker.time_t;
            const time_idx = marker.time_idx;
            const transition = amesh.anim.transitions[i];
            for (transition.properties.items) |prop| {
                switch (prop.data) {
                    .rotations => |rotations| {
                        const from = Quaternion.init(rotations[time_idx]);
                        const to = Quaternion.init(rotations[time_idx+1]);
                        amesh.scene.nodes[prop.node_id].rotate = from.slerp(to, tt);
                    },
                    .scales => |scales| {
                        const from = scales[time_idx];
                        const to = scales[time_idx+1];
                        amesh.scene.nodes[prop.node_id].scale = from.lerp(to, tt);
                    },
                    .translations => |translations| {
                        const from = translations[time_idx];
                        const to = translations[time_idx+1];
                        amesh.scene.nodes[prop.node_id].translate = from.lerp(to, tt);
                    },
                }
            }
        }

        self.batcher.beginMvp(vp);

        for (amesh.scene.mesh_nodes) |id| {
            const node = &amesh.scene.nodes[id];

            var mesh_model = model_xform;
            // Compute mesh model by working up the tree.
            var cur_id = id;
            while (cur_id != NullId) {
                const cur_node = amesh.scene.nodes[cur_id];
                var node_mat = cur_node.toTransform();
                mesh_model = node_mat.getAppliedTransform(mesh_model);
                cur_id = cur_node.parent;
            }
                
            self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
            self.batcher.mesh.pushMatrix(mesh_model.mat);

            // Compute normal matrix for lighting.
            self.batcher.normal = mesh_model.toRotationUniformScaleMat();

            for (node.primitives) |prim| {
                const tex = if (fill) self.white_tex else b: {
                    if (prim.image_id) |image_id| {
                        const img = self.image_store.images.getNoCheck(image_id);
                        break :b image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id };
                    } else {
                        break :b self.white_tex;
                    }
                };

                // Derive final joint matrices and non skin transform. 
                if (node.skin.len > 0) {
                    if (pbr) {
                        self.batcher.beginAnimPbr3D(tex, self.cur_cam_world_pos);
                    } else {
                        self.batcher.beginAnim3D(tex);
                    }
                    const mat_idx = self.batcher.mesh.cur_mats_buf_size;
                    for (node.skin) |joint, i| {
                        var xform = Transform.initRowMajor(joint.inv_bind_mat);
                        cur_id = joint.node_id;
                        while (cur_id != NullId) {
                            const joint_node = amesh.scene.nodes[cur_id];
                            var joint_mat = joint_node.toTransform();
                            xform.applyTransform(joint_mat);
                            cur_id = joint_node.parent;
                        }
                        self.batcher.mesh.pushMatrix(xform.mat);
                        self.tmp_joint_idxes[i] = @intCast(u16, mat_idx + i);
                    }
                } else {
                    self.batcher.beginTex3D(tex);
                }

                self.batcher.ensureUnusedBuffer(prim.verts.len, prim.indexes.len);
                const vert_start = self.batcher.mesh.getNextIndexId();
                if (node.skin.len > 0) {
                    for (prim.verts) |vert| {
                        var new_vert = vert;
                        if (fill) {
                            new_vert.setColor(self.ps.fill_color);
                        }
                        // Update joint idx to point to dynamic joint buffer. Also encode into 2 u32s.
                        new_vert.joints.compact.joint_0 = self.tmp_joint_idxes[new_vert.joints.components.joint_0] | (@as(u32, self.tmp_joint_idxes[new_vert.joints.components.joint_1]) << 16);
                        new_vert.joints.compact.joint_1 = self.tmp_joint_idxes[new_vert.joints.components.joint_2] | (@as(u32, self.tmp_joint_idxes[new_vert.joints.components.joint_3]) << 16);
                        self.batcher.mesh.pushVertex(new_vert);
                    }
                } else {
                    for (prim.verts) |vert| {
                        var new_vert = vert;
                        if (fill) {
                            new_vert.setColor(self.ps.fill_color);
                        }
                        self.batcher.mesh.pushVertex(new_vert);
                    }
                }
                self.batcher.mesh.pushDeltaIndexes(vert_start, prim.indexes);

                if (custom_mat) |material| {
                    self.batcher.material_idx = self.batcher.mesh.cur_materials_buf_size;
                    self.batcher.mesh.pushMaterial(material);
                } else {
                    self.batcher.material_idx = self.batcher.mesh.cur_materials_buf_size;
                    self.batcher.mesh.pushMaterial(prim.material);
                }

                self.endCmd();
            }
        }

        self.batcher.beginMvp(cur_mvp);
    }

    pub fn fillScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.fillMesh3D(xform, prim);
            }
        }
    }

    pub fn fillMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        self.batcher.beginTex3D(self.white_tex);
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);

        self.batcher.beginMvp(vp);
        self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
        self.batcher.mesh.pushMatrix(xform.mat);

        self.batcher.ensureUnusedBuffer(mesh.verts.len, mesh.indexes.len);
        const vert_start = self.batcher.mesh.getNextIndexId();
        for (mesh.verts) |vert| {
            var new_vert = vert;
            new_vert.setColor(self.ps.fill_color);
            self.batcher.mesh.pushVertex(new_vert);
        }
        self.batcher.mesh.pushDeltaIndexes(vert_start, mesh.indexes);

        self.batcher.beginMvp(cur_mvp);
    }

    pub fn strokeScene3D(self: *Graphics, xform: Transform, scene: graphics.GLTFscene) void {
        for (scene.mesh_nodes) |id| {
            const node = scene.nodes[id];
            for (node.primitives) |prim| {
                self.strokeMesh3D(xform, prim);
            }
        }
    }

    pub fn strokeMesh3D(self: *Graphics, xform: Transform, mesh: graphics.Mesh3D) void {
        self.batcher.beginWireframe();
        const cur_mvp = self.batcher.mvp;
        // Create temp mvp.
        const vp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(vp);

        self.batcher.model_idx = self.batcher.mesh.cur_mats_buf_size;
        self.batcher.mesh.pushMatrix(xform.mat);

        // TODO: stroke color should pushed as a constant.
        self.batcher.ensureUnusedBuffer(mesh.verts.len, mesh.indexes.len);
        const vert_start = self.batcher.mesh.getNextIndexId();
        for (mesh.verts) |vert| {
            var new_vert = vert;
            new_vert.setColor(self.ps.stroke_color);
            self.batcher.mesh.pushVertex(new_vert);
        }
        self.batcher.mesh.pushDeltaIndexes(vert_start, mesh.indexes);

        self.batcher.beginMvp(cur_mvp);
    }

    pub fn drawPolygon(self: *Graphics, pts: []const Vec2) void {
        _ = self;
        _ = pts;
        self.batcher.beginTex(self.white_tex);
        // TODO: Implement this.
    }

    pub fn drawPolygonLyon(self: *Graphics, pts: []const Vec2) void {
        self.batcher.beginTex(self.white_tex);
        const b = lyon.initBuilder();
        lyon.addPolygon(b, pts, true);
        var data = lyon.buildStroke(b, self.ps.line_width);

        self.pushLyonVertexData(&data, self.ps.stroke_color);
    }

    pub fn drawSubImage(self: *Graphics, src_x: f32, src_y: f32, src_width: f32, src_height: f32, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        const img = self.image_store.images.get(image_id);
        self.batcher.beginTex(image.ImageDesc{ .image_id = image_id, .tex_id = img.tex_id });
        self.batcher.ensureUnusedBuffer(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);

        const start_idx = self.batcher.mesh.getNextIndexId();

        const u_start = src_x / width;
        const u_end = (src_x + src_width) / width;
        const v_start = src_y / height;
        const v_end = (src_y + src_height) / height;

        // top left
        vert.setXY(x, y);
        vert.setUV(u_start, v_start);
        self.batcher.mesh.pushVertex(vert);

        // top right
        vert.setXY(x + width, y);
        vert.setUV(u_end, v_start);
        self.batcher.mesh.pushVertex(vert);

        // bottom right
        vert.setXY(x + width, y + height);
        vert.setUV(u_end, v_end);
        self.batcher.mesh.pushVertex(vert);

        // bottom left
        vert.setXY(x, y + height);
        vert.setUV(u_start, v_end);
        self.batcher.mesh.pushVertex(vert);

        // add rect
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawImageSized(self: *Graphics, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        const img = self.image_store.images.getNoCheck(image_id);
        self.batcher.beginTex(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id });
        self.batcher.ensureUnusedBuffer(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);

        const start_idx = self.batcher.mesh.getNextIndexId();

        if (Backend == .OpenGL) {
            // top left
            vert.setXY(x, y);
            vert.setUV(0, 1);
            self.batcher.mesh.pushVertex(vert);

            // top right
            vert.setXY(x + width, y);
            vert.setUV(1, 1);
            self.batcher.mesh.pushVertex(vert);

            // bottom right
            vert.setXY(x + width, y + height);
            vert.setUV(1, 0);
            self.batcher.mesh.pushVertex(vert);

            // bottom left
            vert.setXY(x, y + height);
            vert.setUV(0, 0);
            self.batcher.mesh.pushVertex(vert);
        } else {
            // top left
            vert.setXY(x, y);
            vert.setUV(0, 0);
            self.batcher.mesh.pushVertex(vert);

            // top right
            vert.setXY(x + width, y);
            vert.setUV(1, 0);
            self.batcher.mesh.pushVertex(vert);

            // bottom right
            vert.setXY(x + width, y + height);
            vert.setUV(1, 1);
            self.batcher.mesh.pushVertex(vert);

            // bottom left
            vert.setXY(x, y + height);
            vert.setUV(0, 1);
            self.batcher.mesh.pushVertex(vert);
        }

        // add rect
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawImage(self: *Graphics, x: f32, y: f32, image_id: ImageId) void {
        const img = self.image_store.images.getNoCheck(image_id);
        self.batcher.beginTex(image.ImageTex{ .image_id = image_id, .tex_id = img.tex_id });
        self.batcher.ensureUnusedBuffer(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);

        const start_idx = self.batcher.mesh.getNextIndexId();

        if (Backend == .OpenGL) {
            // top left
            vert.setXY(x, y);
            vert.setUV(0, 1);
            self.batcher.mesh.pushVertex(vert);

            // top right
            vert.setXY(x + @intToFloat(f32, img.width), y);
            vert.setUV(1, 1);
            self.batcher.mesh.pushVertex(vert);

            // bottom right
            vert.setXY(x + @intToFloat(f32, img.width), y + @intToFloat(f32, img.height));
            vert.setUV(1, 0);
            self.batcher.mesh.pushVertex(vert);

            // bottom left
            vert.setXY(x, y + @intToFloat(f32, img.height));
            vert.setUV(0, 0);
            self.batcher.mesh.pushVertex(vert);
        } else {
            // top left
            vert.setXY(x, y);
            vert.setUV(0, 0);
            self.batcher.mesh.pushVertex(vert);

            // top right
            vert.setXY(x + @intToFloat(f32, img.width), y);
            vert.setUV(1, 0);
            self.batcher.mesh.pushVertex(vert);

            // bottom right
            vert.setXY(x + @intToFloat(f32, img.width), y + @intToFloat(f32, img.height));
            vert.setUV(1, 1);
            self.batcher.mesh.pushVertex(vert);

            // bottom left
            vert.setXY(x, y + @intToFloat(f32, img.height));
            vert.setUV(0, 1);
            self.batcher.mesh.pushVertex(vert);
        }

        // add rect
        self.batcher.mesh.pushQuadIndexes(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    /// Like beginFrame but only adjusts the viewport and binds the fbo.
    pub fn bindFramebuffer(self: *Graphics, buf_width: u32, buf_height: u32, fbo: gl.GLuint) void {
        self.endCmd();
        self.inner.renderer.bindDrawFramebuffer(fbo);
        gl.viewport(0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height));
        self.buf_width = buf_width;
        self.buf_height = buf_height;
    }

    /// Binds an image to the write buffer. 
    pub fn bindOffscreenImage(self: *Graphics, image_id: ImageId) void {
        self.endCmd();
        var img = self.image_store.images.getPtrNoCheck(image_id);
        if (img.fbo_id == null) {
            const tex = self.image_store.getTexture(img.tex_id);
            img.fbo_id = self.createTextureFramebuffer(tex.inner.tex_id);
        }
        self.inner.renderer.bindDrawFramebuffer(img.fbo_id.?);
        gl.viewport(0, 0, @intCast(c_int, img.width), @intCast(c_int, img.height));
        self.ps.proj_xform = graphics.initTextureProjection(@intToFloat(f32, img.width), @intToFloat(f32, img.height));
        self.ps.view_xform = Transform.initIdentity();
        self.buf_width = @intCast(u32, img.width);
        self.buf_height = @intCast(u32, img.height);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn createTextureFramebuffer(self: Graphics, tex_id: gl.GLuint) gl.GLuint {
        _ = self;
        var fbo_id: gl.GLuint = 0;
        gl.genFramebuffers(1, &fbo_id);
        gl.bindFramebuffer(gl.GL_FRAMEBUFFER, fbo_id);

        gl.bindTexture(gl.GL_TEXTURE_2D, tex_id);
        gl.framebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex_id, 0);
        const status = gl.checkFramebufferStatus(gl.GL_FRAMEBUFFER);
        if (status != gl.GL_FRAMEBUFFER_COMPLETE) {
            log.debug("unexpected status: {}", .{status});
            unreachable;
        }
        return fbo_id;
    }

    pub fn beginFrameVK(self: *Graphics, buf_width: u32, buf_height: u32, frame_idx: u8, framebuffer: vk.VkFramebuffer) void {
        self.buf_width = buf_width;
        self.buf_height = buf_height;
        self.inner.cur_frame = self.inner.renderer.frames[frame_idx];
        self.batcher.resetStateVK(self.white_tex, frame_idx, framebuffer, self.ps.clear_color);

        self.ps.clip_rect = .{
            .x = 0,
            .y = 0,
            .width = @intToFloat(f32, buf_width),
            .height = @intToFloat(f32, buf_height),
        };
        self.ps.using_scissors = false;

        self.clipRectCmd(self.ps.clip_rect);
    }

    /// Begin frame sets up the context before any other draw call.
    /// This should be agnostic to the view port dimensions so this context can be reused by different windows.
    pub fn beginFrame(self: *Graphics, buf_width: u32, buf_height: u32, custom_fbo: gl.GLuint) void {
        // log.debug("beginFrame", .{});

        self.buf_width = buf_width;
        self.buf_height = buf_height;

        // TODO: Viewport only needs to be set on window resize or multiple windows are active.
        gl.viewport(0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height));

        self.batcher.resetState(self.white_tex);

        // Scissor affects glClear so reset it first.
        self.ps.clip_rect = .{
            .x = 0,
            .y = 0,
            .width = @intToFloat(f32, buf_width),
            .height = @intToFloat(f32, buf_height),
        };
        self.ps.using_scissors = false;
        gl.disable(gl.GL_SCISSOR_TEST);

        if (custom_fbo == 0) {
            // This clears the main framebuffer that is swapped to window.
            self.inner.renderer.bindDrawFramebuffer(0);
            self.clear();
        } else {
            // Set the frame buffer we are drawing to.
            self.inner.renderer.bindDrawFramebuffer(custom_fbo);
            // Clears the custom frame buffer.
            self.clear();
        }

        // Straight alpha by default.
        self.setBlendMode(.StraightAlpha);
    }

    pub fn endFrameVK(self: *Graphics) graphics.FrameResultVK {
        self.endCmd();
        self.image_store.processRemovals();
        return self.batcher.endFrameVK();
    }

    pub fn endFrame(self: *Graphics, buf_width: u32, buf_height: u32, custom_fbo: gl.GLuint) void {
        // log.debug("endFrame", .{});
        self.endCmd();
        if (custom_fbo != 0) {
            // If we were drawing to custom framebuffer such as msaa buffer, then blit the custom buffer into the default ogl buffer.
            gl.bindFramebuffer(gl.GL_READ_FRAMEBUFFER, custom_fbo);
            self.inner.renderer.bindDrawFramebuffer(0);
            // blit's filter is only used when the sizes between src and dst buffers are different.
            gl.blitFramebuffer(0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height), 0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height), gl.GL_COLOR_BUFFER_BIT, gl.GL_NEAREST);
        }
    }

    pub fn setCamera(self: *Graphics, cam: graphics.Camera) void {
        self.endCmd();
        self.ps.proj_xform = cam.proj_transform;
        self.ps.view_xform = cam.view_transform;
        self.batcher.mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.cur_cam_world_pos = cam.world_pos;
    }

    pub fn prepareShadows(self: *Graphics, cam: graphics.Camera) void {
        // Setup shadow mapping view point from directional light.
        const corners = cam.computePartitionCorners(cam.near, (cam.near + cam.far) * 0.3);

        var center = Vec3.init(0, 0, 0);
        for (corners) |corner| {
            center = center.add3(corner.x, corner.y, corner.z);
        }
        center = center.mul(@as(f32, 1)/@as(f32, 8));

        // Compute ortho projection for directional light.
        const light_view = graphics.camera.initLookAt(center.add3(-self.light_vec.x, -self.light_vec.y, -self.light_vec.z), center, Vec3.init(0, 1, 0));
        var min_x: f32 = std.math.f32_max;
        var min_y: f32 = std.math.f32_max;
        var min_z: f32 = std.math.f32_max;
        var max_x: f32 = std.math.f32_min;
        var max_y: f32 = std.math.f32_min;
        var max_z: f32 = std.math.f32_min;
        for (corners) |corner| {
            const view_pos = light_view.interpolate3(corner.x, corner.y, corner.z);
            min_x = std.math.min(min_x, view_pos.x);
            max_x = std.math.max(max_x, view_pos.x);
            min_y = std.math.min(min_y, view_pos.y);
            max_y = std.math.max(max_y, view_pos.y);
            min_z = std.math.min(min_z, view_pos.z);
            max_z = std.math.max(max_z, view_pos.z);
        }
        const z_scale = 10.0;
        if (min_z < 0) {
            min_z *= z_scale;
        }
        if (max_z > 0) {
            max_z *= z_scale;
        }

        const proj = graphics.camera.initOrthographicProjection(min_x, max_x, max_y, min_y, max_z, min_z);
        const light_vp = light_view.getAppliedTransform(proj);
        self.batcher.prepareShadowPass(light_vp);
    }

    pub fn translate(self: *Graphics, x: f32, y: f32) void {
        self.ps.view_xform.translate(x, y);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn translate3D(self: *Graphics, x: f32, y: f32, z: f32) void {
        self.ps.view_xform.translate3D(x, y, z);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn scale(self: *Graphics, x: f32, y: f32) void {
        self.ps.view_xform.scale(x, y);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn rotateZ(self: *Graphics, rad: f32) void {
        self.ps.view_xform.rotateZ(rad);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn rotateX(self: *Graphics, rad: f32) void {
        self.ps.view_xform.rotateX(rad);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    pub fn rotateY(self: *Graphics, rad: f32) void {
        self.ps.view_xform.rotateY(rad);
        const mvp = self.ps.view_xform.getAppliedTransform(self.ps.proj_xform);
        self.batcher.beginMvp(mvp);
    }

    // GL Only.
    pub fn setBlendModeCustom(self: *Graphics, src: gl.GLenum, dst: gl.GLenum, eq: gl.GLenum) void {
        _ = self;
        gl.blendFunc(src, dst);
        gl.blendEquation(eq);
    }

    // TODO: Implement this in Vulkan.
    pub fn setBlendMode(self: *Graphics, mode: BlendMode) void {
        if (self.ps.blend_mode != mode) {
            self.endCmd();
            switch (mode) {
                .StraightAlpha => gl.blendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA),
                .Add, .Glow => {
                    gl.blendFunc(gl.GL_ONE, gl.GL_ONE);
                    gl.blendEquation(gl.GL_FUNC_ADD);
                },
                .Subtract => {
                    gl.blendFunc(gl.GL_ONE, gl.GL_ONE);
                    gl.blendEquation(gl.GL_FUNC_SUBTRACT);
                },
                .Multiplied => {
                    gl.blendFunc(gl.GL_DST_COLOR, gl.GL_ONE_MINUS_SRC_ALPHA);
                    gl.blendEquation(gl.GL_FUNC_ADD);
                },
                .Opaque => {
                    gl.blendFunc(gl.GL_ONE, gl.GL_ZERO);
                    gl.blendEquation(gl.GL_FUNC_ADD);
                },
                .Additive => {
                    gl.blendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE);
                    gl.blendEquation(gl.GL_FUNC_ADD);
                },
                .PremultipliedAlpha => {
                    gl.blendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
                    gl.blendEquation(gl.GL_FUNC_ADD);
                },
                else => @panic("unsupported"),
            }
            self.ps.blend_mode = mode;
        }
    }

    pub fn endCmd(self: *Graphics) void {
        self.batcher.endCmd();
    }

    pub fn updateTextureData(self: *const Graphics, img: image.Image, buf: []const u8) void {
        switch (Backend) {
            .OpenGL => {
                gl.activeTexture(gl.GL_TEXTURE0 + 0);
                const gl_tex_id = self.image_store.getTexture(img.tex_id).inner.tex_id;
                gl.bindTexture(gl.GL_TEXTURE_2D, gl_tex_id);
                gl.texSubImage2D(gl.GL_TEXTURE_2D, 0, 0, 0, @intCast(c_int, img.width), @intCast(c_int, img.height), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, buf.ptr);
                gl.bindTexture(gl.GL_TEXTURE_2D, 0);
            },
            .Vulkan => {
                const renderer = self.inner.renderer;
                const ctx = self.inner.ctx;
                const size = @intCast(u32, buf.len);
                const staging_buf = gvk.buffer.createBuffer(ctx.physical, ctx.device, size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

                // Copy to gpu.
                var gpu_data: ?*anyopaque = null;
                var res = vk.mapMemory(ctx.device, staging_buf.mem, 0, size, 0, &gpu_data);
                vk.assertSuccess(res);
                std.mem.copy(u8, @ptrCast([*]u8, gpu_data)[0..size], buf);
                vk.unmapMemory(ctx.device, staging_buf.mem);

                // Transition to transfer dst layout.
                gvk.transitionImageLayout(renderer, img.inner.image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
                gvk.copyBufferToImage(renderer, staging_buf.buf, img.inner.image, img.width, img.height);
                // Transition to shader access layout.
                gvk.transitionImageLayout(renderer, img.inner.image, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

                // Cleanup.
                staging_buf.deinit(ctx.device);
            },
            else => {},
        }
    }
};

const DrawState = struct {
    clip_rect: geom.Rect,
    use_scissors: bool,
    blend_mode: BlendMode,
    view_xform: Transform,
};

fn dumpPolygons(alloc: std.mem.Allocator, polys: []const []const Vec2) void {
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    const writer = buf.writer();

    for (polys) |poly, i| {
        std.fmt.format(writer, "polygon {} ", .{i}) catch unreachable;
        for (poly) |pt_| {
            std.fmt.format(writer, "{d:.2}, {d:.2},", .{pt_.x, pt_.y}) catch unreachable;
        }
        std.fmt.format(writer, "\n", .{}) catch unreachable;
    }

    log.debug("{s}", .{buf.items});
}

var tess_: ?*tess2.TESStesselator = null;

fn getTess2Handle() *tess2.TESStesselator {
    if (tess_ == null) {
        tess_ = tess2.tessNewTess(null);
    }
    return tess_.?;
}

/// Currently holds the camera pos and the global directional light. Eventually the light params will be decoupled once multiple lights are supported.
pub const ShaderCamera = struct {
    cam_pos: Vec3,
    pad_0: f32 = 0,
    light_vec: Vec3,
    pad_1: f32 = 0,
    light_color: Vec3,
    pad_2: f32 = 0,
    light_vp: Mat4,
    enable_shadows: bool,
};

pub const PaintState = struct {
    /// Projection transform.
    proj_xform: Transform,
    /// View transform can be changed by user transforms.
    view_xform: Transform,

    /// Text rendering.
    font_gid: FontGroupId,
    font_size: f32,
    text_align: TextAlign,
    text_baseline: TextBaseline,

    /// Shape rendering.
    fill_color: Color,
    stroke_color: Color,
    line_width: f32,
    line_width_half: f32,

    clear_color: Color,

    // Draw state stack.
    state_stack: std.ArrayListUnmanaged(DrawState),

    clip_rect: geom.Rect,
    using_scissors: bool,
    blend_mode: BlendMode,

    pub fn init(font_gid: FontGroupId) PaintState {
        return .{
            .proj_xform = Transform.initIdentity(),
            .view_xform = Transform.initIdentity(),

            .font_gid = font_gid,
            .font_size = 18,
            .text_align = .Left,
            .text_baseline = .Top,

            .fill_color = Color.Black,
            .stroke_color = Color.Black,
            .line_width = 1,
            .line_width_half = 0.5,

            .state_stack = .{},

            .clip_rect = undefined,
            .using_scissors = undefined,
            .blend_mode = ._undefined,
            .clear_color = undefined,
        };
    }

    pub fn deinit(self: *PaintState, alloc: std.mem.Allocator) void {
        self.state_stack.deinit(alloc);
    }
};