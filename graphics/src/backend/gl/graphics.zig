const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const stbi = @import("stbi");
const math = stdx.math;
const Vec2 = math.Vec2;
const vec2 = math.Vec2.init;
const Mat4 = math.Mat4;
const geom = math.geom;
const gl = @import("gl");
pub const GLTextureId = gl.GLuint;
const builtin = @import("builtin");
const build_options = @import("build_options");
const lyon = @import("lyon");
const tess2 = @import("tess2");
const pt = lyon.initPt;
const t = stdx.testing;
const trace = stdx.debug.tracy.trace;

const graphics = @import("../../graphics.zig");
const QuadBez = graphics.curve.QuadBez;
const SubQuadBez = graphics.curve.SubQuadBez;
const CubicBez = graphics.curve.CubicBez;
const Color = graphics.Color;
const BlendMode = graphics.BlendMode;
const Transform = graphics.transform.Transform;
const VMetrics = graphics.font.VMetrics;
const TextMetrics = graphics.TextMetrics;
const Font = graphics.font.Font;
const Glyph = graphics.font.Glyph;
pub const font_cache = @import("font_cache.zig");
pub const FontCache = font_cache.FontCache;
const ImageId = graphics.ImageId;
const TextAlign = graphics.TextAlign;
const TextBaseline = graphics.TextBaseline;
const FontId = graphics.font.FontId;
const FontGroupId = graphics.font.FontGroupId;
const log = stdx.log.scoped(.graphics_gl);
const mesh = @import("mesh.zig");
const VertexData = mesh.VertexData;
const TexShaderVertex = mesh.TexShaderVertex;
const Shader = @import("shader.zig").Shader;
const Batcher = @import("batcher.zig").Batcher;
const text_renderer = @import("text_renderer.zig");
pub const MeasureTextIterator = text_renderer.MeasureTextIterator;
const RenderTextContext = text_renderer.RenderTextContext;
const svg = graphics.svg;
const stroke = @import("stroke.zig");
const tessellator = @import("../../tessellator.zig");
const Tessellator = tessellator.Tessellator;

const tex_vert = @embedFile("../../shaders/tex_vert.glsl");
const tex_frag = @embedFile("../../shaders/tex_frag.glsl");

const tex_vert_webgl2 = @embedFile("../../shaders/tex_vert_webgl2.glsl");
const tex_frag_webgl2 = @embedFile("../../shaders/tex_frag_webgl2.glsl");

const vera_ttf = @embedFile("../../../../assets/vera.ttf");

const IsWasm = builtin.target.isWasm();

/// Should be agnostic to viewport dimensions so it can be reused to draw on different viewports.
pub const Graphics = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    white_tex: ImageDesc,
    tex_shader: Shader,
    batcher: Batcher,
    font_cache: FontCache,

    cur_proj_transform: Transform,
    view_transform: Transform,
    initial_mvp: Mat4,
    cur_buf_width: u32,
    cur_buf_height: u32,

    default_font_id: FontId,
    default_font_gid: FontGroupId,
    cur_font_gid: FontGroupId,
    cur_font_size: f32,
    cur_text_align: TextAlign,
    cur_text_baseline: TextBaseline,

    cur_fill_color: Color,
    cur_stroke_color: Color,
    cur_line_width: f32,
    cur_line_width_half: f32,

    // Depth pixel ratio:
    // This is used to fetch a higher res font bitmap for high dpi displays.
    // eg. 18px user font size would normally use a 32px backed font bitmap but with dpr=2,
    // it would use a 64px bitmap font instead.
    cur_dpr: u8,

    // Images are handles to textures.
    images: ds.CompactUnorderedList(ImageId, Image),

    // Draw state stack.
    state_stack: std.ArrayList(DrawState),

    cur_clip_rect: geom.Rect,
    cur_scissors: bool,
    cur_blend_mode: BlendMode,

    vec2_helper_buf: std.ArrayList(Vec2),
    vec2_slice_helper_buf: std.ArrayList([]const Vec2),
    qbez_helper_buf: std.ArrayList(SubQuadBez),
    tessellator: Tessellator,

    // We can initialize without gl calls for use in tests.
    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .alloc = alloc,
            .white_tex = undefined,
            .tex_shader = undefined,
            .batcher = undefined,
            .font_cache = undefined,
            .default_font_id = undefined,
            .default_font_gid = undefined,
            .cur_buf_width = 0,
            .cur_buf_height = 0,
            .cur_font_gid = undefined,
            .cur_font_size = undefined,
            .cur_fill_color = Color.Black,
            .cur_stroke_color = Color.Black,
            .cur_blend_mode = ._undefined,
            .cur_line_width = undefined,
            .cur_line_width_half = undefined,
            .cur_proj_transform = undefined,
            .view_transform = undefined,
            .initial_mvp = undefined,
            .images = ds.CompactUnorderedList(ImageId, Image).init(alloc),
            .state_stack = std.ArrayList(DrawState).init(alloc),
            .cur_clip_rect = undefined,
            .cur_scissors = undefined,
            .cur_text_align = .Left,
            .cur_text_baseline = .Top,
            .cur_dpr = 1,
            .vec2_helper_buf = std.ArrayList(Vec2).init(alloc),
            .vec2_slice_helper_buf = std.ArrayList([]const Vec2).init(alloc),
            .qbez_helper_buf = std.ArrayList(SubQuadBez).init(alloc),
            .tessellator = undefined,
        };
        self.tessellator.init(alloc);

        const max_total_textures = gl.getMaxTotalTextures();
        const max_fragment_textures = gl.getMaxFragmentTextures();
        log.debug("max frag textures: {}, max total textures: {}", .{ max_fragment_textures, max_total_textures });

        // Initialize shaders.
        if (IsWasm) {
            self.tex_shader = Shader.init(tex_vert_webgl2, tex_frag_webgl2) catch unreachable;
        } else {
            self.tex_shader = Shader.init(tex_vert, tex_frag) catch unreachable;
        }

        // Generate basic solid color texture.
        var buf: [16]u32 = undefined;
        std.mem.set(u32, &buf, 0xFFFFFFFF);
        self.white_tex = self.createImageFromBitmap(4, 4, std.mem.sliceAsBytes(buf[0..]), false, .{});

        self.batcher = Batcher.init(alloc, self.tex_shader);
        // Set the initial texture without triggering any flushing.
        self.batcher.setCurrentTexture(self.white_tex);

        // Setup tex shader vao.
        gl.bindVertexArray(self.tex_shader.vao_id);
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.batcher.vert_buf_id);
        // a_pos
        gl.enableVertexAttribArray(0);
        vertexAttribPointer(0, 4, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(0));
        // a_uv
        gl.enableVertexAttribArray(1);
        vertexAttribPointer(1, 2, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(4 * 4));
        // a_color
        gl.enableVertexAttribArray(2);
        vertexAttribPointer(2, 4, gl.GL_FLOAT, 10 * 4, u32ToVoidPtr(6 * 4));
        gl.bindVertexArray(0);

        self.font_cache.init(alloc, self);

        // TODO: Embed a default bitmap font.
        // TODO: Embed a default ttf monospace font.

        self.default_font_id = self.addTTF_Font(vera_ttf);
        self.default_font_gid = self.font_cache.getOrLoadFontGroup(&.{self.default_font_id});
        self.setFont(self.default_font_id);

        // Set default font size.
        self.setFontSize(20);

        // View transform can be changed by user transforms.
        self.view_transform = Transform.initIdentity();

        self.setLineWidth(1);

        if (build_options.has_lyon) {
            lyon.init();
        }

        // Clear color. Default to white.
        gl.clearColor(1, 1, 1, 1.0);
        // gl.clearColor(0.1, 0.2, 0.3, 1.0);
        // gl.clearColor(0, 0, 0, 1.0);

        // 2D graphics for now. Turn off 3d options.
        gl.disable(gl.GL_DEPTH_TEST);
        gl.disable(gl.GL_CULL_FACE);

        // Enable blending by default.
        gl.enable(gl.GL_BLEND);
    }

    pub fn deinit(self: *Self) void {
        self.tex_shader.deinit();
        self.batcher.deinit();
        self.font_cache.deinit();
        self.state_stack.deinit();

        if (build_options.has_lyon) {
            lyon.deinit();
        }

        // Delete images after since some deinit could have removed images.
        var iter = self.images.iterator();
        while (iter.next()) |image| {
            self.deinitImage(image);
        }
        self.images.deinit();

        self.vec2_helper_buf.deinit();
        self.vec2_slice_helper_buf.deinit();
        self.qbez_helper_buf.deinit();
        self.tessellator.deinit();
    }

    pub fn addTTF_Font(self: *Self, data: []const u8) FontId {
        return self.font_cache.addFont(data);
    }

    pub fn addFallbackFont(self: *Self, font_id: FontId) void {
        self.font_cache.addSystemFont(font_id) catch unreachable;
    }

    pub fn clipRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        // log.debug("clipRect {} {} {} {}", .{x, y, width, height});

        self.cur_clip_rect = .{
            .x = x,
            // clip-y starts at bottom.
            .y = @intToFloat(f32, self.cur_buf_height) - (y + height),
            .width = width,
            .height = height,
        };
        self.cur_scissors = true;
        const r = self.cur_clip_rect;

        // Execute current draw calls before we alter state.
        self.flushDraw();

        gl.scissor(@floatToInt(c_int, r.x), @floatToInt(c_int, r.y), @floatToInt(c_int, r.width), @floatToInt(c_int, r.height));
        gl.enable(gl.GL_SCISSOR_TEST);
    }

    pub fn resetTransform(self: *Self) void {
        self.view_transform.reset();
        const mvp = math.Mul4x4_4x4(self.cur_proj_transform.mat, self.view_transform.mat);

        // Need to flush before changing view transform.
        self.flushDraw();
        self.batcher.setMvp(mvp);
    }

    pub fn pushState(self: *Self) void {
        self.state_stack.append(.{
            .clip_rect = self.cur_clip_rect,
            .use_scissors = self.cur_scissors,
            .blend_mode = self.cur_blend_mode,
            .view_transform = self.view_transform,
        }) catch unreachable;
    }

    pub fn popState(self: *Self) void {
        // log.debug("popState", .{});

        // Execute current draw calls before altering state.
        self.flushDraw();

        const state = self.state_stack.pop();
        if (state.use_scissors) {
            const r = state.clip_rect;
            self.clipRect(r.x, r.y, r.width, r.height);
        } else {
            // log.debug("disable scissors", .{});
            self.cur_scissors = false;
            gl.disable(gl.GL_SCISSOR_TEST);
        }
        if (state.blend_mode != self.cur_blend_mode) {
            self.setBlendMode(state.blend_mode);
        }
        if (!std.meta.eql(self.view_transform.mat, state.view_transform.mat)) {
            self.view_transform = state.view_transform;
            const mvp = math.Mul4x4_4x4(self.cur_proj_transform.mat, self.view_transform.mat);
            self.batcher.setMvp(mvp);
        }
    }

    pub fn getViewTransform(self: Self) Transform {
        return self.view_transform;
    }

    pub fn getLineWidth(self: Self) f32 {
        return self.cur_line_width;
    }

    pub fn setLineWidth(self: *Self, width: f32) void {
        self.cur_line_width = width;
        self.cur_line_width_half = width * 0.5;
    }

    pub fn setFont(self: *Self, font_id: FontId) void {
        // Lookup font group single font.
        const font_gid = self.font_cache.getOrLoadFontGroup(&.{font_id});
        self.setFontGroup(font_gid);
    }

    pub fn setFontGroup(self: *Self, font_gid: FontGroupId) void {
        if (font_gid != self.cur_font_gid) {
            self.cur_font_gid = font_gid;
        }
    }

    pub fn setClearColor(self: *Self, color: Color) void {
        _ = self;
        const r = @intToFloat(f32, color.channels.r) / 255;
        const g = @intToFloat(f32, color.channels.g) / 255;
        const b = @intToFloat(f32, color.channels.b) / 255;
        const a = @intToFloat(f32, color.channels.a) / 255;
        gl.clearColor(r, g, b, a);
    }

    pub fn getFillColor(self: Self) Color {
        return self.cur_fill_color;
    }

    pub fn setFillColor(self: *Self, color: Color) void {
        self.cur_fill_color = color;
    }

    pub fn getStrokeColor(self: Self) Color {
        return self.cur_stroke_color;
    }

    pub fn setStrokeColor(self: *Self, color: Color) void {
        self.cur_stroke_color = color;
    }

    pub fn getFontSize(self: Self) f32 {
        return self.cur_font_size;
    }

    pub fn setFontSize(self: *Self, size: f32) void {
        if (self.cur_font_size != size) {
            self.cur_font_size = size;
        }
    }

    pub fn setTextAlign(self: *Self, align_: TextAlign) void {
        self.cur_text_align = align_;
    }

    pub fn setTextBaseline(self: *Self, baseline: TextBaseline) void {
        self.cur_text_baseline = baseline;
    }

    pub fn initImage(self: *Self, image: *Image, width: usize, height: usize, data: ?[]const u8, linear_filter: bool, props: anytype) void {
        _ = self;
        image.* = .{
            .tex_id = undefined,
            .width = width,
            .height = height,
            .needs_update = false,
            .ctx = undefined,
            .update_fn = undefined,
        };
        if (@hasField(@TypeOf(props), "update")) {
            image.ctx = @field(props, "ctx");
            image.update_fn = @field(props, "update");
        }

        gl.genTextures(1, &image.tex_id);
        gl.activeTexture(gl.GL_TEXTURE0 + 0);
        gl.bindTexture(gl.GL_TEXTURE_2D, image.tex_id);

        // A GLint specifying the level of detail. Level 0 is the base image level and level n is the nth mipmap reduction level.
        const level = 0;
        // A GLint specifying the width of the border. Usually 0.
        const border = 0;
        // Data type of the texel data.
        const data_type = gl.GL_UNSIGNED_BYTE;

        // Set the filtering so we don't need mips.
        // TEXTURE_MIN_FILTER - filter for scaled down texture
        // TEXTURE_MAG_FILTER - filter for scaled up texture
        // Linear filter is better for anti-aliased font bitmaps.
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, if (linear_filter) gl.GL_LINEAR else gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, if (linear_filter) gl.GL_LINEAR else gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        const data_ptr = if (data != null) data.?.ptr else null;
        gl.texImage2D(gl.GL_TEXTURE_2D, level, gl.GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height), border, gl.GL_RGBA, data_type, data_ptr);

        gl.bindTexture(gl.GL_TEXTURE_2D, 0);
    }

    pub fn createImageFromData(self: *Self, data: []const u8) !graphics.Image {
        var src_width: c_int = undefined;
        var src_height: c_int = undefined;
        var channels: c_int = undefined;
        const bitmap = stbi.stbi_load_from_memory(data.ptr, @intCast(c_int, data.len), &src_width, &src_height, &channels, 0);
        defer stbi.stbi_image_free(bitmap);
        // log.debug("loaded image: {} {} {} ", .{src_width, src_height, channels});

        const bitmap_len = @intCast(usize, src_width * src_height * channels);
        const desc = self.createImageFromBitmap(@intCast(usize, src_width), @intCast(usize, src_height), bitmap[0..bitmap_len], true, .{});
        return graphics.Image{
            .id = desc.image_id,
            .width = @intCast(usize, src_width),
            .height = @intCast(usize, src_height),
        };
    }

    pub fn createImageFromBitmapInto(self: *Self, image: *Image, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) !ImageId {
        self.initImage(&image, width, height, data, linear_filter, .{ .update = undefined });
        return self.images.add(image);
    }

    pub fn createImageFromBitmap(self: *Self, width: usize, height: usize, data: ?[]const u8, linear_filter: bool, props: anytype) ImageDesc {
        var image: Image = undefined;
        self.initImage(&image, width, height, data, linear_filter, props);
        const image_id = self.images.add(image) catch unreachable;
        return ImageDesc{
            .image_id = image_id,
            .tex_id = image.tex_id,
        };
    }

    pub fn removeImage(self: *Self, id: ImageId) void {
        const image = self.images.getNoCheck(id);
        self.deinitImage(image);
        _ = self.images.remove(id);
    }

    // Used to deinit image without removing the image. Useful for recreating a texture under the same ImageId.
    pub fn deinitImage(self: *Self, image: Image) void {
        // log.debug("deleting texture {}", .{tex_id});

        // If we deleted the current tex, flush and reset to default texture.
        if (self.batcher.cur_tex_image.tex_id == image.tex_id) {
            self.flushDraw();
            self.batcher.setCurrentTexture(self.white_tex);
        }
        image.deinit();
    }

    pub fn measureText(self: *Self, str: []const u8, res: *TextMetrics) void {
        text_renderer.measureText(self, self.cur_font_gid, self.cur_font_size, self.cur_dpr, str, res, true);
    }

    pub fn measureFontText(self: *Self, group_id: FontGroupId, size: f32, str: []const u8, res: *TextMetrics) void {
        text_renderer.measureText(self, group_id, size, self.cur_dpr, str, res, true);
    }

    // Since MeasureTextIterator init needs to do a fieldParentPtr, we pass the res pointer in.
    pub fn measureFontTextIter(self: *Self, group_id: FontGroupId, size: f32, str: []const u8, res: *MeasureTextIterator) void {
        text_renderer.measureTextIter(self, group_id, size, self.cur_dpr, str, res);
    }

    pub fn fillText(self: *Self, x: f32, y: f32, str: []const u8) void {
        // log.info("draw text '{s}'", .{str});
        var vert: TexShaderVertex = undefined;

        var quad: text_renderer.TextureQuad = undefined;
        var vdata: VertexData(4, 6) = undefined;

        var start_x = x;
        var start_y = y;

        if (self.cur_text_align != .Left) {
            var metrics: TextMetrics = undefined;
            self.measureText(str, &metrics);
            switch (self.cur_text_align) {
                .Left => {},
                .Right => start_x = x-metrics.width,
                .Center => start_x = x-metrics.width/2,
            }
        }
        if (self.cur_text_baseline != .Top) {
            const vmetrics = self.font_cache.getPrimaryFontVMetrics(self.cur_font_gid, self.cur_font_size);
            switch (self.cur_text_baseline) {
                .Top => {},
                .Middle => start_y = y - vmetrics.height / 2,
                .Alphabetic => start_y = y - vmetrics.ascender,
                .Bottom => start_y = y - vmetrics.height,
            }
        }
        var ctx = text_renderer.startRenderText(self, self.cur_font_gid, self.cur_font_size, self.cur_dpr, start_x, start_y, str);

        while (text_renderer.renderNextCodepoint(&ctx, &quad, true)) {
            self.setCurrentTexture(quad.image);

            if (quad.is_color_bitmap) {
                vert.setColor(Color.White);
            } else {
                vert.setColor(self.cur_fill_color);
            }

            // top left
            vert.setXY(quad.x0, quad.y0);
            vert.setUV(quad.u0, quad.v0);
            vdata.verts[0] = vert;

            // top right
            vert.setXY(quad.x1, quad.y0);
            vert.setUV(quad.u1, quad.v0);
            vdata.verts[1] = vert;

            // bottom right
            vert.setXY(quad.x1, quad.y1);
            vert.setUV(quad.u1, quad.v1);
            vdata.verts[2] = vert;

            // bottom left
            vert.setXY(quad.x0, quad.y1);
            vert.setUV(quad.u0, quad.v1);
            vdata.verts[3] = vert;

            // indexes
            vdata.setRect(0, 0, 1, 2, 3);

            self.pushVertexData(4, 6, &vdata);
        }
    }

    pub fn setCurrentTexture(self: *Self, desc: ImageDesc) void {
        if (self.batcher.shouldFlushBeforeSetCurrentTexture(desc.tex_id)) {
            self.flushDraw();
        }
        self.batcher.setCurrentTexture(desc);
    }

    fn ensureUnusedBatchCapacity(self: *Self, vert_inc: usize, index_inc: usize) void {
        if (!self.batcher.ensureUnusedBuffer(vert_inc, index_inc)) {
            self.flushDraw();
        }
    }

    fn pushLyonVertexData(self: *Self, data: *lyon.VertexData, color: Color) void {
        self.ensureUnusedBatchCapacity(data.vertex_len, data.index_len);
        self.batcher.pushLyonVertexData(data, color);
    }

    fn pushVertexData(self: *Self, comptime num_verts: usize, comptime num_indices: usize, data: *VertexData(num_verts, num_indices)) void {
        self.ensureUnusedBatchCapacity(num_verts, num_indices);
        self.batcher.pushVertexData(num_verts, num_indices, data);
    }

    pub fn drawRectVec(self: *Self, pos: Vec2, width: f32, height: f32) void {
        self.drawRect(pos.x, pos.y, width, height);
    }

    pub fn drawRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        // Top border.
        self.fillRectColor(x - self.cur_line_width_half, y - self.cur_line_width_half, width + self.cur_line_width, self.cur_line_width, self.cur_stroke_color);
        // Right border.
        self.fillRectColor(x + width - self.cur_line_width_half, y + self.cur_line_width_half, self.cur_line_width, height - self.cur_line_width, self.cur_stroke_color);
        // Bottom border.
        self.fillRectColor(x - self.cur_line_width_half, y + height - self.cur_line_width_half, width + self.cur_line_width, self.cur_line_width, self.cur_stroke_color);
        // Left border.
        self.fillRectColor(x - self.cur_line_width_half, y + self.cur_line_width_half, self.cur_line_width, height - self.cur_line_width, self.cur_stroke_color);
    }

    // Uses path rendering.
    pub fn strokeRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        // log.debug("strokeRect {d:.2} {d:.2} {d:.2} {d:.2}", .{pos.x, pos.y, width, height});
        const b = lyon.initBuilder();
        lyon.addRectangle(b, &.{ .x = x, .y = y, .width = width, .height = height });
        var data = lyon.buildStroke(b, self.cur_line_width);

        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.cur_stroke_color);
    }

    pub fn fillRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        // Top left corner.
        self.fillCircleSectorN(x + radius, y + radius, radius, math.pi, math.pi_half, 90);
        // Left side.
        self.fillRect(x, y + radius, radius, height - radius * 2);
        // Bottom left corner.
        self.fillCircleSectorN(x + radius, y + height - radius, radius, math.pi_half, math.pi_half, 90);
        // Middle.
        self.fillRect(x + radius, y, width - radius * 2, height);
        // Top right corner.
        self.fillCircleSectorN(x + width - radius, y + radius, radius, -math.pi_half, math.pi_half, 90);
        // Right side.
        self.fillRect(x + width - radius, y + radius, radius, height - radius * 2);
        // Bottom right corner.
        self.fillCircleSectorN(x + width - radius, y + height - radius, radius, 0, math.pi_half, 90);
    }

    pub fn drawRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        // Top left corner.
        self.drawCircleArcN(x + radius, y + radius, radius, math.pi, math.pi_half, 90);
        // Left side.
        self.fillRectColor(x - self.cur_line_width_half, y + radius, self.cur_line_width, height - radius * 2, self.cur_stroke_color);
        // Bottom left corner.
        self.drawCircleArcN(x + radius, y + height - radius, radius, math.pi_half, math.pi_half, 90);
        // Top.
        self.fillRectColor(x + radius, y - self.cur_line_width_half, width - radius * 2, self.cur_line_width, self.cur_stroke_color);
        // Bottom.
        self.fillRectColor(x + radius, y + height - self.cur_line_width_half, width - radius * 2, self.cur_line_width, self.cur_stroke_color);
        // Top right corner.
        self.drawCircleArcN(x + width - radius, y + radius, radius, -math.pi_half, math.pi_half, 90);
        // Right side.
        self.fillRectColor(x + width - self.cur_line_width_half, y + radius, self.cur_line_width, height - radius * 2, self.cur_stroke_color);
        // Bottom right corner.
        self.drawCircleArcN(x + width - radius, y + height - radius, radius, 0, math.pi_half, 90);
    }

    pub fn fillRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        self.fillRectColor(x, y, width, height, self.cur_fill_color);
    }

    // Sometimes we want to override the color (eg. rendering part of a stroke.)
    fn fillRectColor(self: *Self, x: f32, y: f32, width: f32, height: f32, color: Color) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(color);

        const start_idx = self.batcher.mesh.getNextIndexId();

        // top left
        vert.setXY(x, y);
        vert.setUV(0, 0);
        self.batcher.mesh.addVertex(&vert);

        // top right
        vert.setXY(x + width, y);
        vert.setUV(1, 0);
        self.batcher.mesh.addVertex(&vert);

        // bottom right
        vert.setXY(x + width, y + height);
        vert.setUV(1, 1);
        self.batcher.mesh.addVertex(&vert);

        // bottom left
        vert.setXY(x, y + height);
        vert.setUV(0, 1);
        self.batcher.mesh.addVertex(&vert);

        // add rect
        self.batcher.mesh.addQuad(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc sector per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.drawCircleArcN(x, y, radius, start_rad, sweep_rad, n);
    }

    // n is the number of sections in the arc we will draw.
    pub fn drawCircleArcN(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(2 + n * 2, n * 3 * 2);

        const inner_rad = radius - self.cur_line_width_half;
        const outer_rad = radius + self.cur_line_width_half;

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_stroke_color);
        vert.setUV(0, 0); // Currently we don't do uv mapping for strokes.

        // Add first two vertices.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setXY(x + cos * inner_rad, y + sin * inner_rad);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x + cos * outer_rad, y + sin * outer_rad);
        self.batcher.mesh.addVertex(&vert);

        const rad_per_n = sweep_rad / @intToFloat(f32, n);
        var cur_vert_idx = self.batcher.mesh.getNextIndexId();
        var i: u32 = 1;
        while (i <= n) : (i += 1) {
            const rad = start_rad + rad_per_n * @intToFloat(f32, i);

            // Add inner/outer vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setXY(x + cos * inner_rad, y + sin * inner_rad);
            self.batcher.mesh.addVertex(&vert);
            vert.setXY(x + cos * outer_rad, y + sin * outer_rad);
            self.batcher.mesh.addVertex(&vert);

            // Add arc sector.
            self.batcher.mesh.addQuad(cur_vert_idx + 1, cur_vert_idx - 1, cur_vert_idx - 2, cur_vert_idx);
            cur_vert_idx += 2;
        }
    }

    pub fn fillCircleSectorN(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32, num_tri: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(num_tri + 2, num_tri * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_fill_color);

        // Add center.
        const center = self.batcher.mesh.getNextIndexId();
        vert.setUV(0.5, 0.5);
        vert.setXY(x, y);
        self.batcher.mesh.addVertex(&vert);

        // Add first circle vertex.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setUV(0.5 + cos, 0.5 + sin);
        vert.setXY(x + cos * radius, y + sin * radius);
        self.batcher.mesh.addVertex(&vert);

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
            self.batcher.mesh.addVertex(&vert);

            // Add triangle.
            const next_idx = last_vert_idx + 1;
            self.batcher.mesh.addTriangle(center, last_vert_idx, next_idx);
            last_vert_idx = next_idx;
        }
    }

    pub fn fillCircleSector(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 triangle per degree.
        var num_tri = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.fillCircleSectorN(x, y, radius, start_rad, sweep_rad, num_tri);
    }

    // Same implementation as fillEllipse when h_radius = v_radius.
    pub fn fillCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        self.fillCircleSectorN(x, y, radius, 0, math.pi_2, 360);
    }

    // Same implementation as drawEllipse when h_radius = v_radius. Might be slightly faster since we use fewer vars.
    pub fn drawCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        self.drawCircleArcN(x, y, radius, 0, math.pi_2, 360);
    }

    pub fn fillEllipseSectorN(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(n + 2, n * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_fill_color);

        // Add center.
        const center = self.batcher.mesh.getNextIndexId();
        vert.setUV(0.5, 0.5);
        vert.setXY(x, y);
        self.batcher.mesh.addVertex(&vert);

        // Add first circle vertex.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setUV(0.5 + cos, 0.5 + sin);
        vert.setXY(x + cos * h_radius, y + sin * v_radius);
        self.batcher.mesh.addVertex(&vert);

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
            self.batcher.mesh.addVertex(&vert);

            // Add triangle.
            const next_idx = last_vert_idx + 1;
            self.batcher.mesh.addTriangle(center, last_vert_idx, next_idx);
            last_vert_idx = next_idx;
        }
    }

    pub fn fillEllipseSector(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc section per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.fillEllipseSectorN(x, y, h_radius, v_radius, start_rad, sweep_rad, n);
    }

    pub fn fillEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        self.fillEllipseSectorN(x, y, h_radius, v_radius, 0, math.pi_2, 360);
    }

    pub fn drawEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        if (builtin.mode == .Debug) {
            stdx.debug.assertInRange(start_rad, -math.pi_2, math.pi_2);
            stdx.debug.assertInRange(sweep_rad, -math.pi_2, math.pi_2);
        }
        // Approx 1 arc sector per degree.
        var n = @floatToInt(u32, @ceil(@fabs(sweep_rad) / math.pi_2 * 360));
        self.drawEllipseArcN(x, y, h_radius, v_radius, start_rad, sweep_rad, n);
    }

    // n is the number of sections in the arc we will draw.
    pub fn drawEllipseArcN(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32, n: u32) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(2 + n * 2, n * 3 * 2);

        const inner_h_rad = h_radius - self.cur_line_width_half;
        const inner_v_rad = v_radius - self.cur_line_width_half;
        const outer_h_rad = h_radius + self.cur_line_width_half;
        const outer_v_rad = v_radius + self.cur_line_width_half;

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_stroke_color);
        vert.setUV(0, 0); // Currently we don't do uv mapping for strokes.

        // Add first two vertices.
        var cos = @cos(start_rad);
        var sin = @sin(start_rad);
        vert.setXY(x + cos * inner_h_rad, y + sin * inner_v_rad);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x + cos * outer_h_rad, y + sin * outer_v_rad);
        self.batcher.mesh.addVertex(&vert);

        const rad_per_n = sweep_rad / @intToFloat(f32, n);
        var cur_vert_idx = self.batcher.mesh.getNextIndexId();
        var i: u32 = 1;
        while (i <= n) : (i += 1) {
            const rad = start_rad + rad_per_n * @intToFloat(f32, i);

            // Add inner/outer vertex.
            cos = @cos(rad);
            sin = @sin(rad);
            vert.setXY(x + cos * inner_h_rad, y + sin * inner_v_rad);
            self.batcher.mesh.addVertex(&vert);
            vert.setXY(x + cos * outer_h_rad, y + sin * outer_v_rad);
            self.batcher.mesh.addVertex(&vert);

            // Add arc sector.
            self.batcher.mesh.addQuad(cur_vert_idx + 1, cur_vert_idx - 1, cur_vert_idx - 2, cur_vert_idx);
            cur_vert_idx += 2;
        }
    }

    pub fn drawEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        self.drawEllipseArcN(x, y, h_radius, v_radius, 0, math.pi_2, 360);
    }

    pub fn drawPoint(self: *Self, x: f32, y: f32) void {
        self.fillRectColor(x - self.cur_line_width_half, y - self.cur_line_width_half, self.cur_line_width, self.cur_line_width, self.cur_stroke_color);
    }

    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32) void {
        if (x1 == x2) {
            self.fillRectColor(x1 - self.cur_line_width_half, y1, self.cur_line_width, y2 - y1, self.cur_stroke_color);
        } else {
            const normal = vec2(y2 - y1, x2 - x1).toLength(self.cur_line_width_half);
            self.fillQuad(
                x1 + normal.x,
                y1 - normal.y,
                x1 - normal.x,
                y1 + normal.y,
                x2 - normal.x,
                y2 + normal.y,
                x2 + normal.x,
                y2 - normal.y,
                self.cur_stroke_color,
            );
        }
    }

    pub fn drawQuadraticBezierCurve(self: *Self, x0: f32, y0: f32, cx: f32, cy: f32, x1: f32, y1: f32) void {
        self.setCurrentTexture(self.white_tex);
        const q_bez = QuadBez{
            .x0 = x0,
            .y0 = y0,
            .cx = cx,
            .cy = cy,
            .x1 = x1,
            .y1 = y1,
        };
        self.vec2_helper_buf.clearRetainingCapacity();
        stroke.strokeQuadBez(&self.batcher.mesh, &self.vec2_helper_buf, q_bez, self.cur_line_width_half, self.cur_stroke_color);
    }

    pub fn drawQuadraticBezierCurveLyon(self: *Self, x0: f32, y0: f32, cx: f32, cy: f32, x1: f32, y1: f32) void {
        const b = lyon.initBuilder();
        lyon.begin(b, &pt(x0, y0));
        lyon.quadraticBezierTo(b, &pt(cx, cy), &pt(x1, y1));
        lyon.end(b, false);
        var data = lyon.buildStroke(b, self.cur_line_width);
        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.cur_stroke_color);
    }

    pub fn drawCubicBezierCurve(self: *Self, x0: f32, y0: f32, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x1: f32, y1: f32) void {
        self.setCurrentTexture(self.white_tex);
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
        stroke.strokeCubicBez(&self.batcher.mesh, &self.vec2_helper_buf, &self.qbez_helper_buf, c_bez, self.cur_line_width_half, self.cur_stroke_color);
    }

    pub fn drawCubicBezierCurveLyon(self: *Self, x0: f32, y0: f32, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x1: f32, y1: f32) void {
        const b = lyon.initBuilder();
        lyon.begin(b, &pt(x0, y0));
        lyon.cubicBezierTo(b, &pt(cx0, cy0), &pt(cx1, cy1), &pt(x1, y1));
        lyon.end(b, false);
        var data = lyon.buildStroke(b, self.cur_line_width);
        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.cur_stroke_color);
    }

    // Points are given in ccw order. Currently doesn't map uvs.
    pub fn fillQuad(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, x4: f32, y4: f32, color: Color) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();
        vert.setXY(x1, y1);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x2, y2);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x3, y3);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x4, y4);
        self.batcher.mesh.addVertex(&vert);
        self.batcher.mesh.addQuad(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn fillSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
        const t_ = trace(@src());
        defer t_.end();
        self.drawSvgPath(x, y, path, true);
    }

    pub fn fillSvgPathLyon(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
        const t_ = trace(@src());
        defer t_.end();
        self.drawSvgPathLyon(x, y, path, true);
    }

    pub fn fillSvgPathTess2(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
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
                        self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
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
                        self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
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
            self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
        }
        if (self.vec2_slice_helper_buf.items.len == 0) {
            return;
        }

        for (self.vec2_slice_helper_buf.items) |polygon| {
            var tess = getTess2Handle();
            tess2.tessAddContour(tess, 2, &polygon[0], 8, @intCast(c_int, polygon.len));
            const res = tess2.tessTesselate(tess, tess2.TESS_WINDING_ODD, tess2.TESS_POLYGONS, 3, 2, null);
            if (res == 0) {
                unreachable;
            }

            var gpu_vert: TexShaderVertex = undefined;
            gpu_vert.setColor(self.cur_fill_color);
            const vert_offset_id = self.batcher.mesh.getNextIndexId();
            var nverts = tess2.tessGetVertexCount(tess);
            var verts = tess2.tessGetVertices(tess);
            const nelems = tess2.tessGetElementCount(tess);

            // log.debug("poly: {}, {}, {}", .{polygon.len, nverts, nelems});

            self.setCurrentTexture(self.white_tex);
            self.ensureUnusedBatchCapacity(@intCast(u32, nverts), @intCast(usize, nelems * 3));

            var i: u32 = 0;
            while (i < nverts) : (i += 1) {
                gpu_vert.setXY(verts[i*2], verts[i*2+1]);
                // log.debug("{},{}", .{gpu_vert.pos_x, gpu_vert.pos_y});
                gpu_vert.setUV(0, 0);
                _ = self.batcher.mesh.addVertex(&gpu_vert);
            }
            const elems = tess2.tessGetElements(tess);
            i = 0;
            while (i < nelems) : (i += 1) {
                self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3+2]));
                self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3+1]));
                self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3]));
                // log.debug("idx {}", .{elems[i]});
            }
        }
    }

    pub fn strokeSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
        self.drawSvgPath(x, y, path, false);
    }

    fn drawSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath, fill: bool) void {
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
                        self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
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
                        self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
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
            self.vec2_slice_helper_buf.append(self.vec2_helper_buf.items[cur_poly_start..]) catch unreachable;
        }
        if (self.vec2_slice_helper_buf.items.len == 0) {
            return;
        }

        if (fill) {
            // dumpPolygons(self.alloc, self.vec2_slice_helper_buf.items);
            self.tessellator.clearBuffers();
            self.tessellator.triangulatePolygons(self.vec2_slice_helper_buf.items);
            self.setCurrentTexture(self.white_tex);
            const out_verts = self.tessellator.out_verts.items;
            const out_idxes = self.tessellator.out_idxes.items;
            self.ensureUnusedBatchCapacity(out_verts.len, out_idxes.len);
            self.batcher.pushVertIdxBatch(out_verts, out_idxes, self.cur_fill_color);
        } else {
            unreachable;
        //     var data = lyon.buildStroke(b, self.cur_line_width);
        //     self.setCurrentTexture(self.white_tex);
        //     self.pushLyonVertexData(&data, self.cur_stroke_color);
        }
    }

    fn drawSvgPathLyon(self: *Self, x: f32, y: f32, path: *const svg.SvgPath, fill: bool) void {
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
            self.pushLyonVertexData(&data, self.cur_fill_color);
        } else {
            var data = lyon.buildStroke(b, self.cur_line_width);
            self.setCurrentTexture(self.white_tex);
            self.pushLyonVertexData(&data, self.cur_stroke_color);
        }
    }

    // Assumes pts are in ccw order.
    pub fn fillTriangle(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(3, 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();
        vert.setXY(x1, y1);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x2, y2);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(x3, y3);
        self.batcher.mesh.addVertex(&vert);
        self.batcher.mesh.addTriangle(start_idx, start_idx + 1, start_idx + 2);
    }

    // Assumes pts are in ccw order.
    pub fn fillConvexPolygon(self: *Self, pts: []const Vec2) void {
        self.setCurrentTexture(self.white_tex);
        self.ensureUnusedBatchCapacity(pts.len, (pts.len - 2) * 3);

        var vert: TexShaderVertex = undefined;
        vert.setColor(self.cur_fill_color);
        vert.setUV(0, 0); // Don't map uvs for now.

        const start_idx = self.batcher.mesh.getNextIndexId();

        // Add first two vertices.
        vert.setXY(pts[0].x, pts[0].y);
        self.batcher.mesh.addVertex(&vert);
        vert.setXY(pts[1].x, pts[1].y);
        self.batcher.mesh.addVertex(&vert);

        var i: u16 = 2;
        while (i < pts.len) : (i += 1) {
            vert.setXY(pts[i].x, pts[i].y);
            self.batcher.mesh.addVertex(&vert);
            self.batcher.mesh.addTriangle(start_idx, start_idx + i - 1, start_idx + i);
        }
    }

    pub fn fillPolygon(self: *Self, pts: []const Vec2) void {
        self.tessellator.clearBuffers();
        self.tessellator.triangulatePolygon(pts);
        self.setCurrentTexture(self.white_tex);
        const out_verts = self.tessellator.out_verts.items;
        const out_idxes = self.tessellator.out_idxes.items;
        self.ensureUnusedBatchCapacity(out_verts.len, out_idxes.len);
        self.batcher.pushVertIdxBatch(out_verts, out_idxes, self.cur_fill_color);
    }

    pub fn fillPolygonLyon(self: *Self, pts: []const Vec2) void {
        const b = lyon.initBuilder();
        lyon.addPolygon(b, pts, true);
        var data = lyon.buildFill(b);

        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.cur_fill_color);
    }

    pub fn fillPolygonTess2(self: *Self, pts: []const Vec2) void {
        var tess = getTess2Handle();
        tess2.tessAddContour(tess, 2, &pts[0], 0, @intCast(c_int, pts.len));
        const res = tess2.tessTesselate(tess, tess2.TESS_WINDING_ODD, tess2.TESS_POLYGONS, 3, 2, null);
        if (res == 0) {
            unreachable;
        }

        var gpu_vert: TexShaderVertex = undefined;
        gpu_vert.setColor(self.cur_fill_color);
        const vert_offset_id = self.batcher.mesh.getNextIndexId();
        var nverts = tess2.tessGetVertexCount(tess);
        var verts = tess2.tessGetVertices(tess);
        const nelems = tess2.tessGetElementCount(tess);

        self.ensureUnusedBatchCapacity(@intCast(u32, nverts), @intCast(usize, nelems * 3));

        var i: u32 = 0;
        while (i < nverts) : (i += 1) {
            gpu_vert.setXY(verts[i*2], verts[i*2+1]);
            gpu_vert.setUV(0, 0);
            _ = self.batcher.mesh.addVertex(&gpu_vert);
        }
        const elems = tess2.tessGetElements(tess);
        i = 0;
        while (i < nelems) : (i += 1) {
            self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3+2]));
            self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3+1]));
            self.batcher.mesh.addIndex(@intCast(u16, vert_offset_id + elems[i*3]));
        }
    }

    pub fn drawPolygon(self: *Self, pts: []const Vec2) void {
        const b = lyon.initBuilder();
        lyon.addPolygon(b, pts, true);
        var data = lyon.buildStroke(b, self.cur_line_width);

        self.setCurrentTexture(self.white_tex);
        self.pushLyonVertexData(&data, self.cur_stroke_color);
    }

    pub fn drawSubImage(self: *Self, src_x: f32, src_y: f32, src_width: f32, src_height: f32, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        const image = self.images.get(image_id);
        self.setCurrentTexture(ImageDesc{ .image_id = image_id, .tex_id = image.tex_id });
        self.ensureUnusedBatchCapacity(4, 6);

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
        self.batcher.mesh.addVertex(&vert);

        // top right
        vert.setXY(x + width, y);
        vert.setUV(u_end, v_start);
        self.batcher.mesh.addVertex(&vert);

        // bottom right
        vert.setXY(x + width, y + height);
        vert.setUV(u_end, v_end);
        self.batcher.mesh.addVertex(&vert);

        // bottom left
        vert.setXY(x, y + height);
        vert.setUV(u_start, v_end);
        self.batcher.mesh.addVertex(&vert);

        // add rect
        self.batcher.mesh.addQuad(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawImageSized(self: *Self, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        const image = self.images.getNoCheck(image_id);
        self.setCurrentTexture(ImageDesc{ .image_id = image_id, .tex_id = image.tex_id });
        self.ensureUnusedBatchCapacity(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);

        const start_idx = self.batcher.mesh.getNextIndexId();

        // top left
        vert.setXY(x, y);
        vert.setUV(0, 0);
        self.batcher.mesh.addVertex(&vert);

        // top right
        vert.setXY(x + width, y);
        vert.setUV(1, 0);
        self.batcher.mesh.addVertex(&vert);

        // bottom right
        vert.setXY(x + width, y + height);
        vert.setUV(1, 1);
        self.batcher.mesh.addVertex(&vert);

        // bottom left
        vert.setXY(x, y + height);
        vert.setUV(0, 1);
        self.batcher.mesh.addVertex(&vert);

        // add rect
        self.batcher.mesh.addQuad(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    pub fn drawImage(self: *Self, x: f32, y: f32, image_id: ImageId) void {
        const image = self.images.get(image_id);
        self.setCurrentTexture(ImageDesc{ .image_id = image_id, .tex_id = image.tex_id });
        self.ensureUnusedBatchCapacity(4, 6);

        var vert: TexShaderVertex = undefined;
        vert.setColor(Color.White);

        const start_idx = self.batcher.mesh.getNextIndexId();

        // top left
        vert.setXY(x, y);
        vert.setUV(0, 0);
        self.batcher.mesh.addVertex(&vert);

        // top right
        vert.setXY(x + @intToFloat(f32, image.width), y);
        vert.setUV(1, 0);
        self.batcher.mesh.addVertex(&vert);

        // bottom right
        vert.setXY(x + @intToFloat(f32, image.width), y + @intToFloat(f32, image.height));
        vert.setUV(1, 1);
        self.batcher.mesh.addVertex(&vert);

        // bottom left
        vert.setXY(x, y + @intToFloat(f32, image.height));
        vert.setUV(0, 1);
        self.batcher.mesh.addVertex(&vert);

        // add rect
        self.batcher.mesh.addQuad(start_idx, start_idx + 1, start_idx + 2, start_idx + 3);
    }

    /// Begin frame sets up the context before any other draw call.
    /// This should be agnostic to the view port dimensions so this context can be reused by different windows.
    pub fn beginFrame(self: *Self, buf_width: u32, buf_height: u32, custom_fbo: gl.GLuint, proj_transform: Transform, initial_mvp: Mat4) void {
        // log.debug("beginFrame", .{});

        self.cur_buf_width = buf_width;
        self.cur_buf_height = buf_height;

        // Projection transform is different depending on viewport but is needed for user transforms to recompute the mvp.
        self.cur_proj_transform = proj_transform;

        // TODO: Viewport only needs to be set on window resize or multiple windows are active.
        gl.viewport(0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height));

        // Reset view transform.
        self.view_transform = Transform.initIdentity();
        self.batcher.setMvp(initial_mvp);

        // Scissor affects glClear so reset it first.
        self.cur_clip_rect = .{
            .x = 0,
            .y = 0,
            .width = @intToFloat(f32, buf_width),
            .height = @intToFloat(f32, buf_height),
        };
        self.cur_scissors = false;
        gl.disable(gl.GL_SCISSOR_TEST);

        if (custom_fbo == 0) {
            // This clears the main framebuffer that is swapped to window.
            gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, 0);
            gl.clear(gl.GL_COLOR_BUFFER_BIT);
        } else {
            // Set the frame buffer we are drawing to.
            gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, custom_fbo);
            // Clears the custom frame buffer.
            gl.clear(gl.GL_COLOR_BUFFER_BIT);
        }

        // Straight alpha by default.
        self.setBlendMode(.StraightAlpha);
    }

    pub fn endFrame(self: *Self, buf_width: u32, buf_height: u32, custom_fbo: gl.GLuint) void {
        // log.debug("endFrame", .{});
        self.flushDraw();
        if (custom_fbo != 0) {
            // If we were drawing to custom framebuffer such as msaa buffer, then blit the custom buffer into the default ogl buffer.
            gl.bindFramebuffer(gl.GL_READ_FRAMEBUFFER, custom_fbo);
            gl.bindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, 0);
            // blit's filter is only used when the sizes between src and dst buffers are different.
            gl.blitFramebuffer(0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height), 0, 0, @intCast(c_int, buf_width), @intCast(c_int, buf_height), gl.GL_COLOR_BUFFER_BIT, gl.GL_NEAREST);
        }
    }

    pub fn translate(self: *Self, x: f32, y: f32) void {
        self.view_transform.translate(x, y);
        const mvp = math.Mul4x4_4x4(self.cur_proj_transform.mat, self.view_transform.mat);

        // Need to flush before changing view transform.
        self.flushDraw();
        self.batcher.setMvp(mvp);
    }

    pub fn scale(self: *Self, x: f32, y: f32) void {
        self.view_transform.scale(x, y);
        const mvp = math.Mul4x4_4x4(self.cur_proj_transform.mat, self.view_transform.mat);

        self.flushDraw();
        self.batcher.setMvp(mvp);
    }

    pub fn rotate(self: *Self, rad: f32) void {
        self.view_transform.rotateZ(rad);
        const mvp = math.Mul4x4_4x4(self.cur_proj_transform.mat, self.view_transform.mat);

        self.flushDraw();
        self.batcher.setMvp(mvp);
    }

    // GL Only.
    pub fn setBlendModeCustom(self: *Self, src: gl.GLenum, dst: gl.GLenum, eq: gl.GLenum) void {
        _ = self;
        gl.blendFunc(src, dst);
        gl.blendEquation(eq);
    }

    pub fn setBlendMode(self: *Self, mode: BlendMode) void {
        if (self.cur_blend_mode != mode) {
            self.flushDraw();
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
            self.cur_blend_mode = mode;
        }
    }

    pub fn flushDraw(self: *Self) void {
        // Custom logic to run before flushing batcher.
        // log.debug("tex {}", .{self.batcher.cur_tex_id});
        const image = self.images.getPtrNoCheck(self.batcher.cur_tex_image.image_id);
        if (image.needs_update) {
            image.update();
            image.needs_update = false;
        }
        self.batcher.flushDraw();
    }

    pub fn updateTextureData(self: *const Self, image: *const Image, buf: []const u8) void {
        _ = self;
        gl.activeTexture(gl.GL_TEXTURE0 + 0);
        gl.bindTexture(gl.GL_TEXTURE_2D, image.tex_id);
        gl.texSubImage2D(gl.GL_TEXTURE_2D, 0, 0, 0, @intCast(c_int, image.width), @intCast(c_int, image.height), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, buf.ptr);
        gl.bindTexture(gl.GL_TEXTURE_2D, 0);
    }
};

// Define how to get attribute data out of vertex buffer. Eg. an attribute a_pos could be a vec4 meaning 4 components.
// size - num of components for the attribute.
// type - component data type.
// normalized - normally false, only relevant for non GL_FLOAT types anyway.
// stride - number of bytes for each vertex. 0 indicates that the stride is size * sizeof(type)
// offset - offset in bytes of the first component of first vertex.
fn vertexAttribPointer(attr_idx: gl.GLuint, size: gl.GLint, data_type: gl.GLenum, stride: gl.GLsizei, offset: ?*const gl.GLvoid) void {
    gl.vertexAttribPointer(attr_idx, size, data_type, gl.GL_FALSE, stride, offset);
}

fn u32ToVoidPtr(val: u32) ?*const gl.GLvoid {
    return @intToPtr(?*const gl.GLvoid, val);
}

// It's often useful to have both the image id and gl texture id.
pub const ImageDesc = struct {
    image_id: ImageId,
    tex_id: GLTextureId,
};

pub const Image = struct {
    const Self = @This();

    tex_id: GLTextureId,
    width: usize,
    height: usize,

    // Whether this texture needs to be updated in the gpu the next time we draw with it.
    needs_update: bool,

    ctx: *anyopaque,
    update_fn: fn (*Self) void,

    pub fn deinit(self: Self) void {
        gl.deleteTextures(1, &self.tex_id);
    }

    fn update(self: *Self) void {
        self.update_fn(self);
    }
};

const DrawState = struct {
    clip_rect: geom.Rect,
    use_scissors: bool,
    blend_mode: BlendMode,
    view_transform: Transform,
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