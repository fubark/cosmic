const std = @import("std");
const build_options = @import("build_options");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const unsupported = stdx.unsupported;
const math = stdx.math;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const builtin = @import("builtin");
const t = stdx.testing;
const sdl = @import("sdl");
const ft = @import("freetype");
const platform = @import("platform");
const cgltf = @import("cgltf");
const NullId = std.math.maxInt(u32);
const stbi = @import("stbi");

pub const transform = @import("transform.zig");
pub const Transform = transform.Transform;
pub const Quaternion = transform.Quaternion;
pub const svg = @import("svg.zig");
const SvgPath = svg.SvgPath;
const draw_cmd = @import("draw_cmd.zig");
pub const DrawCommandList = draw_cmd.DrawCommandList;
const _ttf = @import("ttf.zig");
const _color = @import("color.zig");
pub const Color = _color.Color;
const fps = @import("fps.zig");
pub const FpsLimiter = fps.FpsLimiter;
pub const DefaultFpsLimiter = fps.DefaultFpsLimiter;
const text_renderer = @import("backend/gpu/text_renderer.zig");
const FontCache = gpu.FontCache;
const log = stdx.log.scoped(.graphics);
pub const curve = @import("curve.zig");
const camera = @import("camera.zig");
pub const Camera = camera.Camera;
pub const CameraModule = camera.CameraModule;
pub const initTextureProjection = camera.initTextureProjection;
pub const initPerspectiveProjection = camera.initPerspectiveProjection;

pub const tessellator = @import("tessellator.zig");
pub const RectBinPacker = @import("rect_bin_packer.zig").RectBinPacker;
pub const SwapChain = @import("swapchain.zig").SwapChain;
pub const Renderer = @import("renderer.zig").Renderer;

const _text = @import("text.zig");
pub const TextMeasure = _text.TextMeasure;
pub const TextMetrics = _text.TextMetrics;
pub const TextGlyphIterator = _text.TextGlyphIterator;
pub const TextLayout = _text.TextLayout;

const FontRendererBackendType = enum(u1) {
    /// Default renderer for desktop.
    Freetype = 0,
    Stbtt = 1,
};

pub const FontRendererBackend: FontRendererBackendType = b: {
    break :b .Freetype;
};

const Backend = build_options.GraphicsBackend;

pub const FontId = u32;
// Maybe this should be renamed to FontFamilyId. FontGroup renamed to FontFamily.
pub const FontGroupId = u32;
pub const OpenTypeFont = _ttf.OpenTypeFont;
const font_ = @import("font.zig");
pub const Font = font_.Font;
pub const FontType = font_.FontType;
const font_group_ = @import("font_group.zig");
pub const FontGroup = font_group_.FontGroup;
pub const FontDesc = font_.FontDesc;
pub const BitmapFontStrike = font_.BitmapFontStrike;

pub const canvas = @import("backend/canvas/graphics.zig");
pub const gpu = @import("backend/gpu/graphics.zig");
pub const vk = @import("backend/vk/graphics.zig");
pub const gl = @import("backend/gl/graphics.zig");
pub const testg = @import("backend/test/graphics.zig");

/// Global freetype library handle.
pub var ft_library: ft.FT_Library = undefined;

pub const Graphics = struct {
    impl: switch (Backend) {
        .OpenGL, .Vulkan => gpu.Graphics,
        .WasmCanvas => canvas.Graphics,
        .Test => testg.Graphics,
        else => stdx.unsupported(),
    },
    alloc: std.mem.Allocator,
    path_parser: svg.PathParser,
    svg_parser: svg.SvgParser,
    text_buf: std.ArrayList(u8),

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator, dpr: f32) void {
        self.initCommon(alloc);
        switch (Backend) {
            .OpenGL => gpu.Graphics.initGL(&self.impl, alloc, dpr),
            .WasmCanvas => canvas.Graphics.init(&self.impl, alloc),
            .Test => testg.Graphics.init(&self.impl, alloc),
            else => stdx.unsupported(),
        }
    }

    pub fn initVK(self: *Self, alloc: std.mem.Allocator, dpr: f32, vk_ctx: vk.VkContext) void {
        self.initCommon(alloc);
        gpu.Graphics.initVK(&self.impl, alloc, dpr, vk_ctx);
    }

    fn initCommon(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .alloc = alloc,
            .path_parser = svg.PathParser.init(alloc),
            .svg_parser = svg.SvgParser.init(alloc),
            .text_buf = std.ArrayList(u8).init(alloc),
            .impl = undefined,
        };

        if (FontRendererBackend == .Freetype) {
            const err = ft.FT_Init_FreeType(&ft_library);
            if (err != 0) {
                stdx.panicFmt("freetype error: {}", .{err});
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.path_parser.deinit();
        self.svg_parser.deinit();
        self.text_buf.deinit();
        switch (Backend) {
            .OpenGL, .Vulkan => self.impl.deinit(),
            .WasmCanvas => self.impl.deinit(),
            .Test => {},
            else => stdx.unsupported(),
        }
    }

    pub fn setCamera(self: *Self, cam: Camera) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setCamera(&self.impl, cam),
            else => stdx.unsupported(),
        }
    }

    /// Shifts origin to x units to the right and y units down.
    pub fn translate(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.translate(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.translate(&self.impl, x, y),
            else => stdx.unsupported(),
        }
    }

    pub fn translate3D(self: *Self, x: f32, y: f32, z: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.translate3D(&self.impl, x, y, z),
            else => stdx.unsupported(),
        }
    }

    // Scales from origin x units horizontally and y units vertically.
    // Negative value flips the axis. Value of 1 does nothing.
    pub fn scale(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.scale(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.scale(&self.impl, x, y),
            else => stdx.unsupported(),
        }
    }

    /// Rotates 2D origin by radians clockwise.
    pub fn rotate(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.rotateZ(&self.impl, rad),
            .WasmCanvas => canvas.Graphics.rotate(&self.impl, rad),
            else => stdx.unsupported(),
        }
    }

    pub fn rotateDeg(self: *Self, deg: f32) void {
        self.rotate(math.degToRad(deg));
    }

    pub fn rotateZ(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.rotateZ(&self.impl, rad),
            else => stdx.unsupported(),
        }
    }

    pub fn rotateX(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.rotateX(&self.impl, rad),
            else => stdx.unsupported(),
        }
    }

    pub fn rotateY(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.rotateY(&self.impl, rad),
            else => stdx.unsupported(),
        }
    }

    // Resets the current transform to identity.
    pub fn resetTransform(self: *Self) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.resetTransform(&self.impl),
            .WasmCanvas => canvas.Graphics.resetTransform(&self.impl),
            else => stdx.unsupported(),
        }
    }

    pub inline fn setClearColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setClearColor(&self.impl, color),
            else => stdx.unsupported(),
        }
    }

    pub inline fn clear(self: Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.clear(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn getFillColor(self: Self) Color {
        return switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.getFillColor(self.impl),
            .WasmCanvas => canvas.Graphics.getFillColor(self.impl),
            else => stdx.unsupported(),
        };
    }

    pub fn setFillColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setFillColor(&self.impl, color),
            .WasmCanvas => canvas.Graphics.setFillColor(&self.impl, color),
            else => stdx.unsupported(),
        }
    }

    /// Set a linear gradient fill style.
    pub fn setFillGradient(self: *Self, start_x: f32, start_y: f32, start_color: Color, end_x: f32, end_y: f32, end_color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setFillGradient(&self.impl, start_x, start_y, start_color, end_x, end_y, end_color),
            else => stdx.unsupported(),
        }
    }

    pub fn getStrokeColor(self: Self) Color {
        return switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.getStrokeColor(self.impl),
            .WasmCanvas => canvas.Graphics.getStrokeColor(self.impl),
            else => stdx.unsupported(),
        };
    }

    pub fn setStrokeColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setStrokeColor(&self.impl, color),
            .WasmCanvas => canvas.Graphics.setStrokeColor(&self.impl, color),
            else => stdx.unsupported(),
        }
    }

    pub fn getLineWidth(self: Self) f32 {
        return switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.getLineWidth(self.impl),
            .WasmCanvas => canvas.Graphics.getLineWidth(self.impl),
            else => stdx.unsupported(),
        };
    }

    pub fn setLineWidth(self: *Self, width: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setLineWidth(&self.impl, width),
            .WasmCanvas => canvas.Graphics.setLineWidth(&self.impl, width),
            else => stdx.unsupported(),
        }
    }

    pub fn fillRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.fillRect(&self.impl, x, y, width, height),
            else => stdx.unsupported(),
        }
    }

    pub fn drawRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.drawRect(&self.impl, x, y, width, height),
            else => stdx.unsupported(),
        }
    }

    pub fn fillRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillRoundRect(&self.impl, x, y, width, height, radius),
            .WasmCanvas => canvas.Graphics.fillRoundRect(&self.impl, x, y, width, height, radius),
            else => stdx.unsupported(),
        }
    }

    pub fn drawRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawRoundRect(&self.impl, x, y, width, height, radius),
            .WasmCanvas => canvas.Graphics.drawRoundRect(&self.impl, x, y, width, height, radius),
            else => stdx.unsupported(),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn fillCircleSector(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillCircleSector(&self.impl, x, y, radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.fillCircleSector(&self.impl, x, y, radius, start_rad, sweep_rad),
            else => stdx.unsupported(),
        }
    }

    pub fn fillCircleSectorDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.fillCircleSector(x, y, radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn drawCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawCircleArc(&self.impl, x, y, radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.drawCircleArc(&self.impl, x, y, radius, start_rad, sweep_rad),
            else => stdx.unsupported(),
        }
    }

    pub fn drawCircleArcDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.drawCircleArc(x, y, radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn fillCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillCircle(&self.impl, x, y, radius),
            .WasmCanvas => canvas.Graphics.fillCircle(&self.impl, x, y, radius),
            else => stdx.unsupported(),
        }
    }

    pub fn drawCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawCircle(&self.impl, x, y, radius),
            .WasmCanvas => canvas.Graphics.drawCircle(&self.impl, x, y, radius),
            else => stdx.unsupported(),
        }
    }

    pub fn fillEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillEllipse(&self.impl, x, y, h_radius, v_radius),
            .WasmCanvas => canvas.Graphics.fillEllipse(&self.impl, x, y, h_radius, v_radius),
            else => stdx.unsupported(),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn fillEllipseSector(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillEllipseSector(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.fillEllipseSector(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            else => stdx.unsupported(),
        }
    }

    pub fn fillEllipseSectorDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.fillEllipseSector(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn drawEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawEllipse(&self.impl, x, y, h_radius, v_radius),
            .WasmCanvas => canvas.Graphics.drawEllipse(&self.impl, x, y, h_radius, v_radius),
            else => stdx.unsupported(),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn drawEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawEllipseArc(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.drawEllipseArc(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            else => stdx.unsupported(),
        }
    }

    pub fn drawEllipseArcDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.drawEllipseArc(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn drawPoint(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawPoint(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.drawPoint(&self.impl, x, y),
            else => stdx.unsupported(),
        }
    }

    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawLine(&self.impl, x1, y1, x2, y2),
            .WasmCanvas => canvas.Graphics.drawLine(&self.impl, x1, y1, x2, y2),
            else => stdx.unsupported(),
        }
    }

    pub fn drawCubicBezierCurve(self: *Self, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawCubicBezierCurve(&self.impl, x1, y1, c1x, c1y, c2x, c2y, x2, y2),
            .WasmCanvas => canvas.Graphics.drawCubicBezierCurve(&self.impl, x1, y1, c1x, c1y, c2x, c2y, x2, y2),
            else => stdx.unsupported(),
        }
    }

    pub fn drawQuadraticBezierCurve(self: *Self, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawQuadraticBezierCurve(&self.impl, x1, y1, cx, cy, x2, y2),
            .WasmCanvas => canvas.Graphics.drawQuadraticBezierCurve(&self.impl, x1, y1, cx, cy, x2, y2),
            else => stdx.unsupported(),
        }
    }

    /// Assumes pts are in ccw order.
    pub fn fillTriangle(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillTriangle(&self.impl, x1, y1, x2, y2, x3, y3),
            .WasmCanvas => canvas.Graphics.fillTriangle(&self.impl, x1, y1, x2, y2, x3, y3),
            else => stdx.unsupported(),
        }
    }

    pub fn fillTriangle3D(self: *Self, x1: f32, y1: f32, z1: f32, x2: f32, y2: f32, z2: f32, x3: f32, y3: f32, z3: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillTriangle3D(&self.impl, x1, y1, z1, x2, y2, z2, x3, y3, z3),
            else => stdx.unsupported(),
        }
    }

    pub fn fillConvexPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillConvexPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.fillPolygon(&self.impl, pts),
            else => stdx.unsupported(),
        }
    }

    pub fn fillPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.fillPolygon(&self.impl, pts),
            else => stdx.unsupported(),
        }
    }

    pub fn drawPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.drawPolygon(&self.impl, pts),
            else => stdx.unsupported(),
        }
    }

    pub fn compileSvgContent(self: *Self, alloc: std.mem.Allocator, str: []const u8) !DrawCommandList {
        return try self.svg_parser.parseAlloc(alloc, str);
    }

    // This is not the recommended way to draw svg content but is available for convenience.
    // For small/medium svg content, first parse the svg into a DrawCommandList and reuse that.
    // For large svg content, render into an image and then draw the image.
    // TODO: allow x, y offset
    pub fn drawSvgContent(self: *Self, str: []const u8) !void {
        const draw_list = try self.svg_parser.parse(str);
        self.executeDrawList(draw_list);
    }

    // This will be slower since it will parse the text every time.
    pub fn fillSvgPathContent(self: *Self, x: f32, y: f32, str: []const u8) !void {
        const path = try self.path_parser.parse(str);
        self.fillSvgPath(x, y, &path);
    }

    pub fn drawSvgPathContent(self: *Self, x: f32, y: f32, str: []const u8) !void {
        const path = try self.path_parser.parse(str);
        self.drawSvgPath(x, y, &path);
    }

    pub fn fillSvgPath(self: *Self, x: f32, y: f32, path: *const SvgPath) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillSvgPath(&self.impl, x, y, path),
            .WasmCanvas => canvas.Graphics.fillSvgPath(&self.impl, x, y, path),
            else => stdx.unsupported(),
        }
    }

    pub fn drawSvgPath(self: *Self, x: f32, y: f32, path: *const SvgPath) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.strokeSvgPath(&self.impl, x, y, path),
            .WasmCanvas => canvas.Graphics.strokeSvgPath(&self.impl, x, y, path),
            else => stdx.unsupported(),
        }
    }

    pub fn executeDrawList(self: *Self, _list: DrawCommandList) void {
        var list = _list;
        for (list.cmds) |ptr| {
            switch (ptr.tag) {
                .FillColor => {
                    const cmd = list.getCommand(.FillColor, ptr);
                    self.setFillColor(Color.fromU32(cmd.rgba));
                },
                .FillPolygon => {
                    const cmd = list.getCommand(.FillPolygon, ptr);
                    const slice = list.getExtraData(cmd.start_vertex_id, cmd.num_vertices * 2);
                    self.fillPolygon(@ptrCast([*]const Vec2, slice.ptr)[0..cmd.num_vertices]);
                },
                .FillPath => {
                    const cmd = list.getCommand(.FillPath, ptr);
                    var end = cmd.start_path_cmd_id + cmd.num_cmds;
                    self.fillSvgPath(0, 0, &SvgPath{
                        .alloc = null,
                        .data = list.extra_data[cmd.start_data_id..],
                        .cmds = std.mem.bytesAsSlice(svg.PathCommand, list.sub_cmds)[cmd.start_path_cmd_id..end],
                    });
                },
                .FillRect => {
                    const cmd = list.getCommand(.FillRect, ptr);
                    self.fillRect(cmd.x, cmd.y, cmd.width, cmd.height);
                },
            }
        }
    }

    pub fn executeDrawListLyon(self: *Self, _list: DrawCommandList) void {
        var list = _list;
        for (list.cmds) |ptr| {
            switch (ptr.tag) {
                .FillColor => {
                    const cmd = list.getCommand(.FillColor, ptr);
                    self.setFillColor(Color.fromU32(cmd.rgba));
                },
                .FillPolygon => {
                    if (Backend == .OpenGL) {
                        const cmd = list.getCommand(.FillPolygon, ptr);
                        const slice = list.getExtraData(cmd.start_vertex_id, cmd.num_vertices * 2);
                        self.impl.fillPolygonLyon(@ptrCast([*]const Vec2, slice.ptr)[0..cmd.num_vertices]);
                    }
                },
                .FillPath => {
                    if (Backend == .OpenGL) {
                        const cmd = list.getCommand(.FillPath, ptr);
                        var end = cmd.start_path_cmd_id + cmd.num_cmds;
                        self.impl.fillSvgPathLyon(0, 0, &SvgPath{
                            .alloc = null,
                            .data = list.extra_data[cmd.start_data_id..],
                            .cmds = std.mem.bytesAsSlice(svg.PathCommand, list.sub_cmds)[cmd.start_path_cmd_id..end],
                        });
                    }
                },
                .FillRect => {
                    const cmd = list.getCommand(.FillRect, ptr);
                    self.fillRect(cmd.x, cmd.y, cmd.width, cmd.height);
                },
            }
        }
    }

    pub fn executeDrawListTess2(self: *Self, _list: DrawCommandList) void {
        var list = _list;
        for (list.cmds) |ptr| {
            switch (ptr.tag) {
                .FillColor => {
                    const cmd = list.getCommand(.FillColor, ptr);
                    self.setFillColor(Color.fromU32(cmd.rgba));
                },
                .FillPolygon => {
                    if (Backend == .OpenGL) {
                        const cmd = list.getCommand(.FillPolygon, ptr);
                        const slice = list.getExtraData(cmd.start_vertex_id, cmd.num_vertices * 2);
                        self.impl.fillPolygonTess2(@ptrCast([*]const Vec2, slice.ptr)[0..cmd.num_vertices]);
                    }
                },
                .FillPath => {
                    if (Backend == .OpenGL) {
                        const cmd = list.getCommand(.FillPath, ptr);
                        var end = cmd.start_path_cmd_id + cmd.num_cmds;
                        self.impl.fillSvgPathTess2(0, 0, &SvgPath{
                            .alloc = null,
                            .data = list.extra_data[cmd.start_data_id..],
                            .cmds = std.mem.bytesAsSlice(svg.PathCommand, list.sub_cmds)[cmd.start_path_cmd_id..end],
                        });
                    }
                },
                .FillRect => {
                    const cmd = list.getCommand(.FillRect, ptr);
                    self.fillRect(cmd.x, cmd.y, cmd.width, cmd.height);
                },
            }
        }
    }

    pub fn setBlendMode(self: *Self, mode: BlendMode) void {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.setBlendMode(&self.impl, mode),
            .WasmCanvas => return canvas.Graphics.setBlendMode(&self.impl, mode),
            else => stdx.unsupported(),
        }
    }

    pub fn createImageFromPathPromise(self: *Self, path: []const u8) stdx.wasm.Promise(Image) {
        switch (Backend) {
            // Only web wasm is supported.
            .WasmCanvas => return canvas.Graphics.createImageFromPathPromise(&self.impl, path),
            else => @compileError("unsupported"),
        }
    }

    /// Path can be absolute or relative to cwd.
    pub fn createImageFromPath(self: *Self, path: []const u8) !Image {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                const data = try std.fs.cwd().readFileAlloc(self.alloc, path, 30e6);
                defer self.alloc.free(data);
                return self.createImage(data);
            },
            .WasmCanvas => stdx.panic("unsupported, use createImageFromPathPromise"),
            else => stdx.unsupported(),
        }
    }

    // Loads an image from various data formats.
    pub fn createImage(self: *Self, data: []const u8) !Image {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.ImageStore.createImageFromData(&self.impl.image_store, data),
            .WasmCanvas => stdx.panic("unsupported, use createImageFromPathPromise"),
            else => stdx.unsupported(),
        }
    }

    /// Assumes data is rgba in row major starting from top left of image.
    /// If data is null, an empty image will be created. In OpenGL, the empty image will have undefined pixel data.
    pub fn createImageFromBitmap(self: *Self, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) ImageId {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                const image = gpu.ImageStore.createImageFromBitmap(&self.impl.image_store, width, height, data, linear_filter);
                return image.image_id;
            },
            else => stdx.unsupported(),
        }
    }

    pub fn dumpImageAsBMP(_: Self, data: []const u8, path: [:0]const u8) void {
        var src_width: c_int = undefined;
        var src_height: c_int = undefined;
        var channels: c_int = undefined;
        const bitmap = stbi.stbi_load_from_memory(data.ptr, @intCast(c_int, data.len), &src_width, &src_height, &channels, 0);
        defer stbi.stbi_image_free(bitmap);
        _ = stbi.stbi_write_bmp(path, src_width, src_height, channels, &bitmap[0]);
    }

    pub inline fn bindImageBuffer(self: *Self, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.bindImageBuffer(&self.impl, image_id),
            else => stdx.unsupported(),
        }
    }

    pub inline fn removeImage(self: *Self, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.ImageStore.markForRemoval(&self.impl.image_store, image_id),
            else => stdx.unsupported(),
        }
    }

    pub fn drawImage(self: *Self, x: f32, y: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.drawImage(&self.impl, x, y, image_id),
            .WasmCanvas => return canvas.Graphics.drawImage(&self.impl, x, y, image_id),
            else => stdx.unsupported(),
        }
    }

    pub fn drawImageSized(self: *Self, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.drawImageSized(&self.impl, x, y, width, height, image_id),
            .WasmCanvas => return canvas.Graphics.drawImageSized(&self.impl, x, y, width, height, image_id),
            else => stdx.unsupported(),
        }
    }

    pub fn drawSubImage(self: *Self, src_x: f32, src_y: f32, src_width: f32, src_height: f32, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.drawSubImage(&self.impl, src_x, src_y, src_width, src_height, x, y, width, height, image_id),
            else => stdx.unsupported(),
        }
    }

    pub fn addFallbackFont(self: *Self, font_id: FontId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.addFallbackFont(&self.impl, font_id),
            else => stdx.unsupported(),
        }
    }

    /// Adds .otb bitmap font with data at different font sizes.
    pub fn addFontOTB(self: *Self, data: []const BitmapFontData) FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.addFontOTB(&self.impl, data),
            else => stdx.unsupported(),
        }
    }

    /// Adds outline or color bitmap font from ttf/otf.
    pub fn addFontTTF(self: *Self, data: []const u8) FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.addFontTTF(&self.impl, data),
            .WasmCanvas => stdx.panic("Unsupported for WasmCanvas. Use addTTF_FontPathForName instead."),
            else => stdx.unsupported(),
        }
    }

    /// Path can be absolute or relative to cwd.
    pub fn addFontFromPathTTF(self: *Self, path: []const u8) !FontId {
        const MaxFileSize = 20e6;
        const data = try std.fs.cwd().readFileAlloc(self.alloc, path, MaxFileSize);
        defer self.alloc.free(data);
        return self.addFontTTF(data);
    }

    /// Wasm/Canvas relies on css to load fonts so it doesn't have access to the font family name.
    /// Other backends will just ignore the name arg. 
    pub fn addFontFromPathCompatTTF(self: *Self, path: []const u8, name: []const u8) !FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                return self.addFontFromPathTTF(path);
            },
            .WasmCanvas => return canvas.Graphics.addFontFromPathTTF(&self.impl, path, name),
            else => stdx.unsupported(),
        }
    }

    pub fn getFontSize(self: *Self) f32 {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.getFontSize(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn setFontSize(self: *Self, font_size: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setFontSize(&self.impl, font_size),
            .WasmCanvas => canvas.Graphics.setFontSize(&self.impl, font_size),
            else => stdx.unsupported(),
        }
    }

    pub fn setFont(self: *Self, font_id: FontId, font_size: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                gpu.Graphics.setFont(&self.impl, font_id);
                gpu.Graphics.setFontSize(&self.impl, font_size);
            },
            .WasmCanvas => canvas.Graphics.setFont(&self.impl, font_id, font_size),
            else => stdx.unsupported(),
        }
    }

    pub fn setFontGroup(self: *Self, font_gid: FontGroupId, font_size: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                gpu.Graphics.setFontGroup(&self.impl, font_gid);
                gpu.Graphics.setFontSize(&self.impl, font_size);
            },
            .WasmCanvas => canvas.Graphics.setFontGroup(&self.impl, font_gid, font_size),
            else => stdx.unsupported(),
        }
    }

    pub fn setTextAlign(self: *Self, align_: TextAlign) void {
        switch (Backend) {
            .OpenGL, .Vulkan =>  {
                gpu.Graphics.setTextAlign(&self.impl, align_);
            },
            else => stdx.unsupported(),
        }
    }

    pub fn setTextBaseline(self: *Self, baseline: TextBaseline) void {
        switch (Backend) {
            .OpenGL, .Vulkan =>  {
                gpu.Graphics.setTextBaseline(&self.impl, baseline);
            },
            else => stdx.unsupported(),
        }
    }

    pub fn fillText(self: *Self, x: f32, y: f32, text: []const u8) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillText(&self.impl, x, y, text),
            .WasmCanvas => canvas.Graphics.fillText(&self.impl, x, y, text),
            else => stdx.unsupported(),
        }
    }

    pub fn fillTextFmt(self: *Self, x: f32, y: f32, comptime format: []const u8, args: anytype) void {
        self.text_buf.clearRetainingCapacity();
        std.fmt.format(self.text_buf.writer(), format, args) catch unreachable;
        self.fillText(x, y, self.text_buf.items);
    }

    pub fn fillTextExt(self: *Self, x: f32, y: f32, comptime format: []const u8, args: anytype, opts: TextOptions) void {
        self.text_buf.clearRetainingCapacity();
        std.fmt.format(self.text_buf.writer(), format, args) catch unreachable;
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillTextExt(&self.impl, x, y, self.text_buf.items, opts),
            else => stdx.unsupported(),
        }
    }

    /// Measure many text at once.
    pub fn measureTextBatch(self: *Self, arr: []*TextMeasure) void {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                for (arr) |measure| {
                    gpu.Graphics.measureFontText(&self.impl, measure.font_gid, measure.font_size, measure.text, &measure.res);
                }
            },
            .WasmCanvas => canvas.Graphics.measureTexts(&self.impl, arr),
            .Test => {},
            else => stdx.unsupported(),
        }
    }

    /// Measure the char advance between two codepoints.
    pub fn measureCharAdvance(self: *Self, font_gid: FontGroupId, font_size: f32, prev_cp: u21, cp: u21) f32 {
        switch (Backend) {
            .OpenGL, .Vulkan => return text_renderer.measureCharAdvance(&self.impl.font_cache, &self.impl, font_gid, font_size, prev_cp, cp),
            .Test => {
                const factor = font_size / self.impl.default_font_size;
                return factor * self.impl.default_font_glyph_advance_width;
            },
            else => stdx.unsupported(),
        }
    }

    /// Measure some text with a given font.
    pub fn measureFontText(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8, out: *TextMetrics) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return self.impl.measureFontText(font_gid, font_size, str, out),
            else => stdx.unsupported(),
        }
    }

    /// Perform text layout and save the results.
    pub fn textLayout(self: *Self, font_gid: FontGroupId, size: f32, str: []const u8, preferred_width: f32, buf: *TextLayout) void {
        buf.lines.clearRetainingCapacity();
        var iter = self.textGlyphIter(font_gid, size, str);
        var y: f32 = 0;
        var last_fit_start_idx: u32 = 0;
        var last_fit_end_idx: u32 = 0;
        var last_fit_x: f32 = 0;
        var x: f32 = 0;
        var max_width: f32 = 0;
        while (iter.nextCodepoint()) {
            x += iter.state.kern;
            // Assume snapping.
            x = @round(x);
            x += iter.state.advance_width;

            if (iter.state.cp == 10) {
                // Line feed. Force new line.
                buf.lines.append(.{
                    .start_idx = last_fit_start_idx,
                    .end_idx = @intCast(u32, iter.state.end_idx - 1), // Exclude new line.
                    .height = iter.primary_height,
                }) catch @panic("error");
                last_fit_start_idx = @intCast(u32, iter.state.end_idx);
                last_fit_end_idx = @intCast(u32, iter.state.end_idx);
                if (x > max_width) {
                    max_width = x;
                }
                x = 0;
                y += iter.primary_height;
                continue;
            }

            if (x <= preferred_width) {
                if (stdx.unicode.isSpace(iter.state.cp)) {
                    // Space character indicates the end of a word.
                    last_fit_end_idx = @intCast(u32, iter.state.end_idx);
                }
            } else {
                if (last_fit_start_idx == last_fit_end_idx) {
                    // Haven't fit a word yet. Just keep going.
                } else {
                    // Wrap to next line.
                    buf.lines.append(.{
                        .start_idx = last_fit_start_idx,
                        .end_idx = last_fit_end_idx,
                        .height = iter.primary_height,
                    }) catch @panic("error");
                    y += iter.primary_height;
                    last_fit_start_idx = last_fit_end_idx;
                    last_fit_x = 0;
                    if (x > max_width) {
                        max_width = x;
                    }
                    x = 0;
                    iter.setIndex(last_fit_start_idx);
                }
            }
        }
        if (last_fit_end_idx < iter.state.end_idx) {
            // Add last line.
            buf.lines.append(.{
                .start_idx = last_fit_start_idx,
                .end_idx = @intCast(u32, iter.state.end_idx),
                .height = iter.primary_height,
            }) catch @panic("error");
            if (x > max_width) {
                max_width = x;
            }
            y += iter.primary_height;
        }
        buf.width = max_width;
        buf.height = y;
    }

    /// Return a text glyph iterator over UTF-8 string.
    pub inline fn textGlyphIter(self: *Self, font_gid: FontGroupId, size: f32, str: []const u8) TextGlyphIterator {
        switch (Backend) {
            .OpenGL, .Vulkan => {
                return gpu.Graphics.textGlyphIter(&self.impl, font_gid, size, str);
            },
            .Test => {
                var iter: TextGlyphIterator = undefined;
                iter.inner = testg.TextGlyphIterator.init(str, size, &self.impl);
                return iter;
            },
            else => stdx.unsupported(),
        }
    }

    pub inline fn getPrimaryFontVMetrics(self: *Self, font_gid: FontGroupId, font_size: f32) VMetrics {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getPrimaryFontVMetrics(&self.impl.font_cache, font_gid, font_size),
            .WasmCanvas => return canvas.Graphics.getPrimaryFontVMetrics(&self.impl, font_gid, font_size),
            .Test => {
                const factor = font_size / self.impl.default_font_size;
                return .{
                    .ascender = factor * self.impl.default_font_metrics.ascender,
                    .descender = 0,
                    .height = factor * self.impl.default_font_metrics.height,
                    .line_gap = factor * self.impl.default_font_metrics.line_gap,
                };
            },
            else => stdx.unsupported(),
        }
    }

    pub inline fn getFontVMetrics(self: *Self, font_id: FontId, font_size: f32) VMetrics {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getFontVMetrics(&self.impl.font_cache, font_id, font_size),
            else => stdx.unsupported(),
        }
    }

    pub inline fn getDefaultFontId(self: *Self) FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return self.impl.default_font_id,
            .Test => return self.impl.default_font_id,
            else => stdx.unsupported(),
        }
    }

    pub inline fn getDefaultFontGroupId(self: *Self) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return self.impl.default_font_gid,
            .Test => return self.impl.default_font_gid,
            else => stdx.unsupported(),
        }
    }

    pub fn getFontByName(self: *Self, name: []const u8) ?FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getFontId(&self.impl.font_cache, name),
            .WasmCanvas => return canvas.Graphics.getFontByName(&self.impl, name),
            else => stdx.unsupported(),
        }
    }

    pub inline fn getFontGroupForSingleFont(self: *Self, font_id: FontId) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getOrLoadFontGroup(&self.impl.font_cache, &.{font_id}),
            else => stdx.unsupported(),
        }
    }

    pub fn getFontGroupByFamily(self: *Self, family: FontFamily) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.getOrLoadFontGroupByFamily(&self.impl, family),
            else => stdx.unsupported(),
        }
    }

    pub fn getFontGroupBySingleFontName(self: *Self, name: []const u8) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getOrLoadFontGroupByNameSeq(&self.impl.font_cache, &.{name}).?,
            .WasmCanvas => stdx.panic("TODO"),
            .Test => return testg.Graphics.getFontGroupBySingleFontName(&self.impl, name),
        }
    }

    pub fn getOrLoadFontGroupByNameSeq(self: *Self, names: []const []const u8) ?FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return FontCache.getOrLoadFontGroupByNameSeq(&self.impl.font_cache, names),
            .Test => return self.impl.default_font_gid,
            else => stdx.unsupported(),
        }
    }

    pub fn pushState(self: *Self) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.pushState(&self.impl),
            .WasmCanvas => canvas.Graphics.save(&self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn clipRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.clipRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.clipRect(&self.impl, x, y, width, height),
            else => stdx.unsupported(),
        }
    }

    pub fn popState(self: *Self) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.popState(&self.impl),
            .WasmCanvas => canvas.Graphics.restore(&self.impl),
            else => stdx.unsupported(),
        }
    }

    pub fn getViewTransform(self: Self) Transform {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.getViewTransform(self.impl),
            else => stdx.unsupported(),
        }
    }

    pub inline fn drawPlane(self: *Self) void {
        switch (Backend) {
            .Vulkan => gpu.Graphics.drawPlane(&self.impl),
            else => stdx.unsupported(),
        }
    }

    /// End the current batched draw command.
    /// OpenGL will flush, while Vulkan will record the command.
    pub inline fn endCmd(self: *Self) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.endCmd(&self.impl),
            .WasmCanvas => {},
            else => stdx.unsupported(),
        }
    }

    pub fn loadGLTF(_: Self, alloc: std.mem.Allocator, buf: []const u8, opts: GLTFloadOptions) !GLTFhandle {
        return GLTFhandle.init(alloc, buf, opts);
    }

    pub fn loadGLTFandBuffers(_: Self, alloc: std.mem.Allocator, buf: []const u8, opts: GLTFloadOptions) !GLTFhandle {
        var ret = try GLTFhandle.init(alloc, buf, opts);
        try ret.loadBuffers(alloc);
        return ret;
    }

    /// Pushes the mesh without modifying the vertex data.
    pub fn drawMesh3D(self: *Self, xform: Transform, verts: []const gpu.TexShaderVertex, indexes: []const u16) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawMesh3D(&self.impl, xform, verts, indexes),
            else => unsupported(),
        }
    }

    pub fn drawScene3D(self: *Self, xform: Transform, scene: GLTFscene) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawScene3D(&self.impl, xform, scene),
            else => unsupported(),
        }
    }

    pub fn drawScenePbr3D(self: *Self, xform: Transform, scene: GLTFscene) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawScenePbr3D(&self.impl, xform, scene),
            else => unsupported(),
        }
    }

    pub fn drawScenePbrCustom3D(self: *Self, xform: Transform, scene: GLTFscene, mat: Material) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawScenePbrCustom3D(&self.impl, xform, scene, mat),
            else => unsupported(),
        }
    }

    pub fn drawTintedScene3D(self: *Self, xform: Transform, scene: GLTFscene, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawTintedScene3D(&self.impl, xform, scene, color),
            else => unsupported(),
        }
    }

    pub fn drawSceneNormals3D(self: *Self, xform: Transform, scene: GLTFscene) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawSceneNormals3D(&self.impl, xform, scene),
            else => unsupported(),
        }
    }

    /// Draws the mesh with the current fill color.
    pub fn fillMesh3D(self: *Self, xform: Transform, verts: []const gpu.TexShaderVertex, indexes: []const u16) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillMesh3D(&self.impl, xform, verts, indexes),
            else => unsupported(),
        }
    }

    pub fn fillScene3D(self: *Self, xform: Transform, scene: GLTFscene) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.fillScene3D(&self.impl, xform, scene),
            else => unsupported(),
        }
    }

    pub fn fillAnimatedMesh3D(self: *Self, model_xform: Transform, mesh: AnimatedMesh) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawAnimatedMesh3D(&self.impl, model_xform, mesh, true),
            else => unsupported(),
        }
    }

    pub fn drawAnimatedMesh3D(self: *Self, model_xform: Transform, mesh: AnimatedMesh) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.drawAnimatedMesh3D(&self.impl, model_xform, mesh, false),
            else => unsupported(),
        }
    }

    /// Draws a wireframe around the mesh with the current stroke color.
    pub fn strokeMesh3D(self: *Self, xform: Transform, verts: []const gpu.TexShaderVertex, indexes: []const u16) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.strokeMesh3D(&self.impl, xform, verts, indexes),
            else => unsupported(),
        }
    }

    pub fn strokeScene3D(self: *Self, xform: Transform, scene: GLTFscene) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.strokeScene3D(&self.impl, xform, scene),
            else => unsupported(),
        }
    }
};

const GLTFstaticBufferEntry = struct {
    name: []const u8,
    buf: []const u8,
    realign: bool = false,
};

pub const GLTFloadOptions = struct {
    static_buffers: ?[]const GLTFstaticBufferEntry = null,
    root_path: [:0]const u8 = "",
};

pub const GLTFhandle = struct {
    data: *cgltf.cgltf_data,
    loaded_buffers: bool,
    static_buffer_map: std.StringHashMap(GLTFstaticBufferEntry),
    image_buffers: std.AutoHashMap(*cgltf.cgltf_image, []const u8),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, buf: []const u8, opts: GLTFloadOptions) !Self {
        var gltf_opts = std.mem.zeroInit(cgltf.cgltf_options, .{});
        var data: *cgltf.cgltf_data = undefined;
        const res = cgltf.parse(&gltf_opts, buf.ptr, buf.len, &data);
        if (res == cgltf.cgltf_result_success) {
            var static_buffer_map = std.StringHashMap(GLTFstaticBufferEntry).init(alloc);
            if (opts.static_buffers) |buffers| {
                for (buffers) |entry| {
                    const name = alloc.dupe(u8, entry.name) catch fatal();
                    var dupe = GLTFstaticBufferEntry{
                        .name = name,
                        .buf = entry.buf,
                        .realign = entry.realign,
                    };
                    if (entry.realign) {
                        dupe.buf = stdx.mem.dupeAlign(alloc, u8, 2, entry.buf) catch fatal();
                    }
                    static_buffer_map.put(name, dupe) catch fatal();
                }
            }
            return Self{
                .data = data,
                .loaded_buffers = false,
                .static_buffer_map = static_buffer_map,
                .image_buffers = std.AutoHashMap(*cgltf.cgltf_image, []const u8).init(alloc),
            };
        } else {
            return error.FailedToLoad;
        }
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        cgltf.cgltf_free(self.data);

        var iter = self.static_buffer_map.valueIterator();
        while (iter.next()) |entry| {
            alloc.free(entry.name);
            if (entry.realign) {
                alloc.free(entry.buf);
            }
        }
        self.static_buffer_map.deinit();

        var image_iter = self.image_buffers.valueIterator();
        while (image_iter.next()) |data| {
            // Owned by cgltf malloc.
            std.c.free(@intToPtr(?*anyopaque, @ptrToInt(data.ptr)));
        }
        self.image_buffers.deinit();
    }

    /// Custom loadBuffers since cgltf.cgltf_load_buffers makes it inconvenient to embed static buffers at runtime.
    /// Also loads image buffers which aren't loaded by default.
    pub fn loadBuffers(self: *Self, alloc: std.mem.Allocator) !void {
        _ = alloc;
        var copts = std.mem.zeroInit(cgltf.cgltf_options, .{});
        if (!self.loaded_buffers) {

            // For a single glb buffer bin.
            if (self.data.buffers_count > 0 and self.data.buffers[0].data == null and self.data.buffers[0].uri == null and self.data.bin != null) {
                if (self.data.bin_size < self.data.buffers[0].size) {
                    return error.BinTooSmall;
                }
                self.data.buffers[0].data = @intToPtr([*c]u8, @ptrToInt(self.data.bin));
                self.data.buffers[0].data_free_method = cgltf.cgltf_data_free_method_none;
            }

            var i: u32 = 0;
            while (i < self.data.buffers_count) : (i += 1) {
                if (self.data.buffers[i].data == null) {
                    const uri = self.data.buffers[i].uri;
                    if (uri == null) {
                        continue;
                    }
                    const uri_slice = std.mem.span(uri);
                    if (std.mem.startsWith(u8, uri_slice, "data:")) {
                        const comma_idx = std.mem.indexOfScalar(u8, uri_slice, ',') orelse return error.UnknownFormat;
                        if (comma_idx >= 7 and std.mem.eql(u8, uri_slice[comma_idx-7..comma_idx], ";base64")) {
                            const res = cgltf.cgltf_load_buffer_base64(&copts, self.data.buffers[i].size, &uri_slice[comma_idx + 1], &self.data.buffers[i].data);
                            self.data.buffers[i].data_free_method = cgltf.cgltf_data_free_method_memory_free;
                            if (res != cgltf.cgltf_result_success) {
                                return error.InvalidData;
                            }
                        } else {
                            return error.UnknownFormat;
                        }
                    } else if (self.static_buffer_map.get(uri_slice)) |entry| {
                        self.data.buffers[i].data = @intToPtr([*c]u8, @ptrToInt(entry.buf.ptr));
                        // Don't auto free for static buffers.
                        self.data.buffers[i].data_free_method = cgltf.cgltf_data_free_method_none;
                        continue;
                    }
                    // Use default loader.
                    // const res = cgltf.cgltf_load_buffer_file(copts, self.data.buffers[i].size, uri, opts.root_path, &self.data.buffers[i].data);
                    // self.data.buffers[i].data_free_method = cgltf.cgltf_data_free_method_file_release;
                    // if (res != cgltf.cgltf_result_success) {
                    //     return error.FailedToLoadFile;
                    // }
                }
            }

            if (self.data.images_count > 0) {
                const images = self.data.images[0..self.data.images_count];
                for (images) |*image| {
                    if (!self.image_buffers.contains(image)) {
                        if (image.uri == null) {
                            continue;
                        }
                        const uri_slice = std.mem.span(image.uri);
                        if (std.mem.startsWith(u8, uri_slice, "data:")) {
                            const comma_idx = std.mem.indexOfScalar(u8, uri_slice, ',') orelse return error.UnknownFormat;
                            if (comma_idx >= 7 and std.mem.eql(u8, uri_slice[comma_idx-7..comma_idx], ";base64")) {
                                const uri_data = uri_slice[comma_idx + 1..];
                                // Determine bytes with padding.
                                const byte_len = (uri_data.len-1)*3/4 + 1;
                                var data: [*c]u8 = undefined;
                                const res = cgltf.cgltf_load_buffer_base64(&copts, byte_len, uri_data.ptr, @ptrCast([*c]?*anyopaque, &data));
                                if (res != cgltf.cgltf_result_success) {
                                    return error.InvalidData;
                                }
                                self.image_buffers.put(image, data[0..byte_len]) catch fatal();
                            }
                        } else {
                            return error.UnknownFormat;
                        }
                    }
                }
            }

            self.loaded_buffers = true;
        }
    }

    pub fn loadDefaultScene(self: *Self, alloc: std.mem.Allocator, gctx: *Graphics) !GLTFscene {
        if (!self.loaded_buffers) {
            return error.BuffersNotLoaded;
        }
        const scene = @ptrCast(*cgltf.cgltf_scene, self.data.scene);
        return GLTFscene.init(alloc, self.*, gctx, scene);
    }
};

fn fromGLTFinterpolation(from: cgltf.cgltf_interpolation_type) Interpolation {
    switch (from) {
        cgltf.cgltf_interpolation_type_linear => return .Linear,
        else => fatal(),
    }
}

const Interpolation = enum(u1) {
    Linear = 0,
};

const TransitionData = union(enum) {
    rotations: []const Vec4,
    scales: []const Vec3,
    translations: []const Vec3,
};

const GLTFtransitionProperty = struct {
    data: TransitionData,
    node_id: u32,
    interpolation: Interpolation,

    fn deinit(self: GLTFtransitionProperty, alloc: std.mem.Allocator) void {
        switch (self.data) {
            .rotations => |rotation| {
                alloc.free(rotation);
            },
            .scales => |scales| {
                alloc.free(scales);
            },
            .translations => |translations| {
                alloc.free(translations);
            },
        }
    }
};

const GLTFanimation = struct {
    name: []const u8,
    transitions: []const GLTFtransition,

    fn deinit(self: GLTFanimation, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        for (self.transitions) |transition| {
            transition.deinit(alloc);
        }
        alloc.free(self.transitions);
    }
};

const GLTFtransition = struct {
    times: []const f32,
    properties: std.ArrayList(GLTFtransitionProperty),
    max_ms: f32,

    fn deinit(self: GLTFtransition, alloc: std.mem.Allocator) void {
        alloc.free(self.times);
        for (self.properties.items) |property| {
            property.deinit(alloc);
        }
        self.properties.deinit();
    }
};

/// Checks whether a node is in an array or is a recursive child.
fn isInOrRecursiveChild(arr: [][*c]cgltf.cgltf_node, node: *cgltf.cgltf_node) bool {
    var cur_node: ?*cgltf.cgltf_node = node;
    while (cur_node != null) {
        if (std.mem.indexOfScalar([*c]cgltf.cgltf_node, arr, cur_node)) |_| return true;
        cur_node = cur_node.?.parent;
    }
    return false;
}

pub const GLTFscene = struct {
    /// Since animations target specific nodes, nodes is writable to allow storing the current temporary transform value.
    nodes: []GLTFnode,
    root_nodes: []const u32,
    mesh_nodes: []const u32,

    animations: []const GLTFanimation,

    pub fn init(alloc: std.mem.Allocator, handle: GLTFhandle, gctx: *Graphics, scene: *cgltf.cgltf_scene) !GLTFscene {
        const data = handle.data;
        var nodes = std.ArrayList(GLTFnode).init(alloc);
        var mesh_nodes = std.ArrayList(u32).init(alloc);
        errdefer {
            for (nodes.items) |it| {
                it.deinit(alloc);
            }
            nodes.deinit();
            mesh_nodes.deinit();
        }

        const S = struct {
            fn dupeNode(nodes_: *std.ArrayList(GLTFnode), map_: *std.AutoHashMap(*cgltf.cgltf_node, u32), node: *cgltf.cgltf_node) void {
                const next_id = @intCast(u32, nodes_.items.len);
                nodes_.append(undefined) catch fatal();
                map_.put(node, next_id) catch fatal();
                if (node.children_count > 0) {
                    const children = node.children[0..node.children_count];
                    for (children) |child| {
                        dupeNode(nodes_, map_, child);
                    }
                }
            }
            fn initNode(alloc_: std.mem.Allocator, handle_: GLTFhandle, gctx_: *Graphics, mesh_nodes_: *std.ArrayList(u32), nodes_: []GLTFnode, map_: std.AutoHashMap(*cgltf.cgltf_node, u32), parent: u32, node: *cgltf.cgltf_node) anyerror!void {
                const id = map_.get(node).?;
                nodes_[id] = try GLTFnode.init(alloc_, handle_, gctx_, map_, parent, node);
                if (nodes_[id].has_mesh) {
                    mesh_nodes_.append(id) catch fatal();
                }
                if (node.children_count > 0) {
                    const children = node.children[0..node.children_count];
                    for (children) |child| {
                        try initNode(alloc_, handle_, gctx_, mesh_nodes_, nodes_, map_, id, child);
                    }
                }
            }
        };

        // First dupe nodes and create map from cgltf pointers to the node ids.
        var map = std.AutoHashMap(*cgltf.cgltf_node, u32).init(alloc);
        defer map.deinit();
        const cnodes = scene.nodes[0..scene.nodes_count];
        // Spec says scene.nodes should be root nodes.
        const root_nodes = alloc.alloc(u32, scene.nodes_count) catch fatal();
        errdefer alloc.free(root_nodes);
        for (cnodes) |node, i| {
            S.dupeNode(&nodes, &map, node);
            const id = map.get(node).?;
            root_nodes[i] = id;
        }

        // Load each node.
        for (cnodes) |node| {
            try S.initNode(alloc, handle, gctx, &mesh_nodes, nodes.items, map, NullId, node);
        }

        if (mesh_nodes.items.len == 0) {
            return error.NoMesh;
        }

        // Track the same time sampler to group multiple channels together.
        var time_accessor_map = std.AutoHashMap(*cgltf.cgltf_accessor, u32).init(alloc);
        defer time_accessor_map.deinit();

        // Look for animations for this scene.
        var animations = std.ArrayList(GLTFanimation).init(alloc);
        errdefer {
            for (animations.items) |anim| {
                anim.deinit(alloc);
            }
            animations.deinit();
        }

        if (data.animations_count > 0) {
            const anims = data.animations[0..data.animations_count];
            for (anims) |anim| {
                if (anim.channels_count > 0) {
                    time_accessor_map.clearRetainingCapacity();

                    var transitions = std.ArrayList(GLTFtransition).init(alloc);
                    errdefer {
                        for (transitions.items) |it| {
                            it.deinit(alloc);
                        }
                        transitions.deinit();
                    }

                    const channels = anim.channels[0..anim.channels_count];
                    for (channels) |chan| {
                        if (!isInOrRecursiveChild(cnodes, chan.target_node)) {
                            continue;
                        }
                        const path = chan.target_path;
                        const sampler = @ptrCast(*cgltf.cgltf_animation_sampler, chan.sampler);
                        const interpolation = sampler.interpolation;

                        var transition: *GLTFtransition = undefined;
                        const time_accessor = @ptrCast(*cgltf.cgltf_accessor, sampler.input);
                        if (time_accessor_map.get(time_accessor)) |transition_idx| {
                            // Matches existing transition.
                            transition = &transitions.items[transition_idx];
                        } else {
                            // Load time data.
                            if (time_accessor.@"type" != cgltf.cgltf_type_scalar) {
                                return error.UnexpectedDataType;
                            }
                            const times = alloc.alloc(f32, time_accessor.count) catch fatal();
                            var i: u32 = 0;
                            while (i < time_accessor.count) : (i += 1) {
                                _ = cgltf.cgltf_accessor_read_float(time_accessor, i, &times[i], 1);
                            }
                            for (times) |_, j| {
                                // From secs to ms.
                                times[j] *= 1000;
                            }
                            const new_idx = @intCast(u32, transitions.items.len);
                            transitions.append(.{
                                .times = times,
                                .max_ms = time_accessor.max[0] * 1000,
                                .properties = std.ArrayList(GLTFtransitionProperty).init(alloc),
                            }) catch fatal();
                            transition = &transitions.items[new_idx];
                            time_accessor_map.put(time_accessor, new_idx) catch fatal();
                        }

                        // Load output data.
                        const out_accessor = @ptrCast(*cgltf.cgltf_accessor, sampler.output);
                        switch (path) {
                            cgltf.cgltf_animation_path_type_rotation => {
                                if (out_accessor.@"type" != cgltf.cgltf_type_vec4 or out_accessor.component_type != cgltf.cgltf_component_type_r_32f) {
                                    return error.UnexpectedDataType;
                                }
                                const num_floats = 4 * out_accessor.count;
                                const val_buf = alloc.alloc(stdx.math.Vec4, num_floats) catch fatal();
                                _ = cgltf.cgltf_accessor_unpack_floats(out_accessor, @ptrCast([*c]f32, val_buf.ptr), num_floats);

                                // for (times) |time, idx| {
                                //     log.debug("{}: {},{}", .{idx, time, val_buf[idx]});
                                // }

                                transition.properties.append(.{
                                    .data = TransitionData{
                                        .rotations = val_buf,
                                    },
                                    .interpolation = fromGLTFinterpolation(interpolation),
                                    .node_id = map.get(chan.target_node).?,
                                }) catch fatal();
                            },
                            cgltf.cgltf_animation_path_type_scale => {
                                if (out_accessor.@"type" != cgltf.cgltf_type_vec3 or out_accessor.component_type != cgltf.cgltf_component_type_r_32f) {
                                    return error.UnexpectedDataType;
                                }
                                const num_floats = 3 * out_accessor.count;
                                const val_buf = alloc.alloc(stdx.math.Vec3, num_floats) catch fatal();
                                _ = cgltf.cgltf_accessor_unpack_floats(out_accessor, @ptrCast([*c]f32, val_buf.ptr), num_floats);

                                transition.properties.append(.{
                                    .data = TransitionData{
                                        .scales = val_buf,
                                    },
                                    .interpolation = fromGLTFinterpolation(interpolation),
                                    .node_id = map.get(chan.target_node).?,
                                }) catch fatal();
                            },
                            cgltf.cgltf_animation_path_type_translation => {
                                if (out_accessor.@"type" != cgltf.cgltf_type_vec3 or out_accessor.component_type != cgltf.cgltf_component_type_r_32f) {
                                    return error.UnexpectedDataType;
                                }
                                const num_floats = 3 * out_accessor.count;
                                const val_buf = alloc.alloc(stdx.math.Vec3, num_floats) catch fatal();
                                _ = cgltf.cgltf_accessor_unpack_floats(out_accessor, @ptrCast([*c]f32, val_buf.ptr), num_floats);

                                transition.properties.append(.{
                                    .data = TransitionData{
                                        .translations = val_buf,
                                    },
                                    .interpolation = fromGLTFinterpolation(interpolation),
                                    .node_id = map.get(chan.target_node).?,
                                }) catch fatal();
                            },
                            else => {
                                log.debug("unsupported {}", .{path});
                                return error.Unsupported;
                            },
                        }
                    }

                    var name: []const u8 = "";
                    if (anim.name != null) {
                        const cname = std.mem.span(anim.name);
                        name = alloc.dupe(u8, cname) catch fatal();
                    }

                    animations.append(.{
                        .name = name,
                        .transitions = transitions.toOwnedSlice(),
                    }) catch fatal();
                }
            }
        }

        return GLTFscene{
            .nodes = nodes.toOwnedSlice(),
            .root_nodes = root_nodes,
            .mesh_nodes = mesh_nodes.toOwnedSlice(),
            .animations = animations.toOwnedSlice(),
        };
    }

    pub fn deinit(self: GLTFscene, alloc: std.mem.Allocator) void {
        for (self.nodes) |node| {
            node.deinit(alloc);
        }
        alloc.free(self.nodes);
        alloc.free(self.root_nodes);
        alloc.free(self.mesh_nodes);
        for (self.animations) |anim| {
            anim.deinit(alloc);
        }
        alloc.free(self.animations);
    }
};

pub const GLTFnode = struct {
    mesh: Mesh3D,
    skin: []const MeshJoint,

    scale: Vec3,
    rotate: Quaternion,
    translate: Vec3,

    parent: u32,
    children: []const u32,

    has_mesh: bool,
    has_scale: bool,
    has_rotate: bool,
    has_translate: bool,

    pub fn init(alloc: std.mem.Allocator, handle: GLTFhandle, gctx: *Graphics, map: std.AutoHashMap(*cgltf.cgltf_node, u32), parent: u32, node: *cgltf.cgltf_node) !GLTFnode {
        var ret: GLTFnode = .{
            .mesh = .{
                .material = .{
                    .roughness = 0,
                    .emissivity = 0,
                    .metallic = 0,
                },
            },
            .skin = &.{},

            .scale = undefined,
            .rotate = undefined,
            .translate = undefined,

            .parent = parent,
            .children = &.{},
            .has_mesh = false,
            .has_scale = false,
            .has_rotate = false,
            .has_translate = false,
        };
        if (node.mesh != null) {
            // This node has mesh data.
            try ret.loadMeshData(alloc, handle, gctx, map, node);
            ret.has_mesh = true;
        }

        if (node.children_count > 0) {
            const children = alloc.alloc(u32, node.children_count) catch fatal();
            const cchildren = node.children[0..node.children_count];
            for (cchildren) |child, i| {
                children[i] = map.get(child).?;
            }
            ret.children = children;
        }

        if (node.has_translation == 1) {
            ret.has_translate = true;
            ret.translate = Vec3.init(node.translation[0], node.translation[1], node.translation[2]);
        }
        if (node.has_scale == 1) {
            ret.has_scale = true;
            ret.scale = Vec3.init(node.scale[0], node.scale[1], node.scale[2]);
        }
        if (node.has_rotation == 1) {
            ret.has_rotate = true;
            ret.rotate = Quaternion.init(Vec4.init(node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3]));
        }
        return ret;
    }

    fn loadMeshData(self: *GLTFnode, alloc: std.mem.Allocator, handle: GLTFhandle, gctx: *Graphics, map: std.AutoHashMap(*cgltf.cgltf_node, u32), node: *cgltf.cgltf_node) !void {
        const mesh = @ptrCast(*cgltf.cgltf_mesh, node.mesh);
        if (mesh.primitives_count > 0) {
            const primitive = mesh.primitives[0];

            if (primitive.material != null) {
                const material = @ptrCast(*cgltf.cgltf_material, primitive.material);
                // Load texture.
                if (material.has_pbr_metallic_roughness == 1) {
                    if (material.pbr_metallic_roughness.base_color_texture.texture != null) {
                        const texture = @ptrCast(*cgltf.cgltf_texture, material.pbr_metallic_roughness.base_color_texture.texture);
                        const cimage = @ptrCast(*cgltf.cgltf_image, texture.image);
                        if (handle.image_buffers.get(cimage)) |data| {
                            const image = try gctx.createImage(data);
                            self.mesh.image_id = image.id;
                            self.mesh.gctx = gctx;
                        } else {
                            // Image data is already loaded from glb.
                            const buffer_view = @ptrCast(*cgltf.cgltf_buffer_view, cimage.buffer_view);
                            const buf = @ptrCast(*cgltf.cgltf_buffer, buffer_view.buffer);
                            const offset = buffer_view.offset;
                            const size = buffer_view.size;
                            const data = @ptrCast([*c]u8, buf.data);
                            const image = try gctx.createImage(data[offset..offset+size]);
                            self.mesh.image_id = image.id;
                            self.mesh.gctx = gctx;
                        }
                    }
                }
            }

            // Determine number of verts by looking at the first attribute.
            var verts: []gpu.TexShaderVertex = undefined;
            if (primitive.attributes_count > 0) {
                const count = primitive.attributes[0].data[0].count;
                verts = alloc.alloc(gpu.TexShaderVertex, count) catch fatal();
            } else return error.NoNumVerts;

            var ai: u32 = 0;
            while (ai < primitive.attributes_count) : (ai += 1) {
                const attr = primitive.attributes[ai];
                const accessor = @ptrCast(*cgltf.cgltf_accessor, attr.data);
                const component_type = accessor.component_type;
                if (accessor.count != verts.len) {
                    return error.NumVertsMismatch;
                }
                switch (attr.@"type") {
                    cgltf.cgltf_attribute_type_normal => {
                        if (accessor.@"type" == cgltf.cgltf_type_vec3 and component_type == cgltf.cgltf_component_type_r_32f) {
                            const val_buf = alloc.alloc(cgltf.cgltf_float, 3 * accessor.count) catch fatal();
                            defer alloc.free(val_buf);
                            _ = cgltf.cgltf_accessor_unpack_floats(accessor, val_buf.ptr, val_buf.len);
                            var vi: u32 = 0;
                            while (vi < verts.len) : (vi += 1) {
                                verts[vi].norm_x = val_buf[vi * 3];
                                verts[vi].norm_y = val_buf[vi * 3 + 1];
                                verts[vi].norm_z = val_buf[vi * 3 + 2];
                            }
                        } else {
                            return error.UnsupportedFormat;
                        }
                    },
                    cgltf.cgltf_attribute_type_position => {
                        if (component_type == cgltf.cgltf_component_type_r_32f) {
                            const num_component_vals = cgltf.cgltf_num_components(accessor.@"type");
                            const num_floats = num_component_vals * accessor.count;
                            const val_buf = alloc.alloc(cgltf.cgltf_float, num_floats) catch fatal();
                            defer alloc.free(val_buf);
                            _ = cgltf.cgltf_accessor_unpack_floats(accessor, val_buf.ptr, num_floats);

                            var vi: u32 = 0;
                            while (vi < verts.len) : (vi += 1) {
                                verts[vi].setXYZ(
                                    val_buf[vi * num_component_vals],
                                    val_buf[vi * num_component_vals + 1],
                                    val_buf[vi * num_component_vals + 2],
                                );
                                verts[vi].setColor(Color.White);
                            }
                        } else {
                            return error.UnsupportedComponentType;
                        }
                    },
                    cgltf.cgltf_attribute_type_texcoord => {
                        if (accessor.@"type" == cgltf.cgltf_type_vec2 and component_type == cgltf.cgltf_component_type_r_32f) {
                            const num_component_vals = cgltf.cgltf_num_components(accessor.@"type");
                            const num_floats = num_component_vals * accessor.count;
                            const val_buf = alloc.alloc(cgltf.cgltf_float, num_floats) catch fatal();
                            defer alloc.free(val_buf);
                            _ = cgltf.cgltf_accessor_unpack_floats(accessor, val_buf.ptr, num_floats);

                            var vi: u32 = 0;
                            while (vi < verts.len) : (vi += 1) {
                                verts[vi].setUV(
                                    val_buf[vi * num_component_vals],
                                    val_buf[vi * num_component_vals + 1],
                                );
                            }
                        } else {
                            return error.UnsupportedComponentType;
                        }
                    },
                    cgltf.cgltf_attribute_type_joints => {
                        const num_component_vals = cgltf.cgltf_num_components(accessor.@"type");
                        if (component_type == cgltf.cgltf_component_type_r_16u and num_component_vals == 4) {
                            var i: u32 = 0;
                            while (i < accessor.count) : (i += 1) {
                                var joints: [4]u32 = undefined;
                                _ = cgltf.cgltf_accessor_read_uint(accessor, i, &joints, 4);
                                verts[i].joints.components.joint_0 = @intCast(u16, joints[0]);
                                verts[i].joints.components.joint_1 = @intCast(u16, joints[1]);
                                verts[i].joints.components.joint_2 = @intCast(u16, joints[2]);
                                verts[i].joints.components.joint_3 = @intCast(u16, joints[3]);
                            }
                        } else {
                            return error.UnsupportedComponentType;
                        }
                    },
                    cgltf.cgltf_attribute_type_weights => {
                        const num_component_vals = cgltf.cgltf_num_components(accessor.@"type");
                        if (component_type == cgltf.cgltf_component_type_r_32f and num_component_vals == 4) {
                            var i: u32 = 0;
                            while (i < accessor.count) : (i += 1) {
                                var weights: [4]f32 = undefined;
                                _ = cgltf.cgltf_accessor_read_float(accessor, i, &weights, 4);
                                const weight0 = @floatToInt(u8, std.math.floor(weights[0] * 255));
                                const weight1 = @floatToInt(u8, std.math.floor(weights[1] * 255));
                                const weight2 = @floatToInt(u8, std.math.floor(weights[2] * 255));
                                const weight3 = @floatToInt(u8, std.math.floor(weights[3] * 255));
                                const weights_u32 = weight0 | (@as(u32, weight1) << 8) | (@as(u32, weight2) << 16) | (@as(u32, weight3) << 24);
                                verts[i].weights = weights_u32;
                            }
                        } else {
                            return error.UnsupportedComponentType;
                        }
                    },
                    else => {},
                }
            }

            var indexes: []u16 = undefined;
            if (primitive.indices != null) {
                const indices = @ptrCast(*cgltf.cgltf_accessor, primitive.indices);
                var i: u32 = 0;
                indexes = alloc.alloc(u16, indices.count) catch fatal();
                while (i < indices.count) : (i += 1) {
                    indexes[i] = @intCast(u16, cgltf.cgltf_accessor_read_index(indices, i));
                }
            }  else {
                // No index data. Generate them from verts.
                indexes = alloc.alloc(u16, verts.len) catch fatal();
                var i: u32 = 0;
                while (i < indexes.len) : (i += 1) {
                    indexes[i] = @intCast(u16, i);
                }
            }

            if (node.skin != null) {
                const skin = @ptrCast(*cgltf.cgltf_skin, node.skin);
                if (skin.joints_count > 0) {
                    const inv_mat_accessor = @ptrCast(*cgltf.cgltf_accessor, skin.inverse_bind_matrices);
                    if (inv_mat_accessor.@"type" == cgltf.cgltf_type_mat4 and inv_mat_accessor.component_type == cgltf.cgltf_component_type_r_32f) {
                        const mesh_joints = alloc.alloc(MeshJoint, skin.joints_count) catch fatal();
                        const joints = skin.joints[0..skin.joints_count];
                        for (joints) |joint_node, i| {
                            var mat: [16]f32 = undefined;
                            _ = cgltf.cgltf_accessor_read_float(skin.inverse_bind_matrices, i, &mat, 16);
                            mesh_joints[i] = .{
                                // Convert from col major to row major.
                                .inv_bind_mat = stdx.math.transpose4x4(mat),
                                .node_id = map.get(joint_node).?,
                            };
                        }
                        self.skin = mesh_joints;
                    } else return error.UnsupportedType;
                }
            }

            self.mesh.verts = verts;
            self.mesh.indexes = indexes;
            return;
        }
        return error.NoPrimitives;
    }

    pub fn toTransform(self: GLTFnode) Transform {
        var xform = Transform.initIdentity();
        if (self.has_scale) {
            xform.scale3D(self.scale.x, self.scale.y, self.scale.z);
        }
        if (self.has_rotate) {
            xform.applyTransform(Transform.initQuaternion(self.rotate));
        }
        if (self.has_translate) {
            xform.translate3D(self.translate.x, self.translate.y, self.translate.z);
        }
        return xform;
    }

    pub fn deinit(self: GLTFnode, alloc: std.mem.Allocator) void {
        self.mesh.deinit(alloc);
        alloc.free(self.skin);
        alloc.free(self.children);
    }
};

pub const MeshJoint = struct {
    inv_bind_mat: Mat4,
    node_id: u32,
};

// TOOL: https://www.andersriggelsen.dk/glblendfunc.php
pub const BlendMode = enum {
    // TODO: Correct alpha blending without premultiplied colors would need to do:
    // gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

    // Common
    StraightAlpha,
    PremultipliedAlpha,
    Glow,
    Additive,
    Multiplied,
    Add,
    Subtract,
    Opaque,

    // TODO: Porter-Duff
    Src,
    SrcATop,
    SrcOver,
    SrcIn,
    SrcOut,
    Dst,
    DstATop,
    DstOver,
    DstIn,
    DstOut,
    Clear,
    Xor,

    // For internal use.
    _undefined,
};

// Vertical metrics that have been scaled to client font size scale.
pub const VMetrics = struct {
    // max distance above baseline (positive units)
    ascender: f32,
    // max distance below baseline (negative units)
    descender: f32,
    // gap between the previous row's descent and current row's ascent.
    line_gap: f32,
    // Should be ascender + descender.
    height: f32,
};

pub const ImageId = u32;

pub const Image = struct {
    id: ImageId,
    width: usize,
    height: usize,
};

pub const TextAlign = enum {
    Left,
    Center,
    Right,
};

pub const TextBaseline = enum {
    Top,
    Middle,
    Alphabetic,
    Bottom,
};

pub const TextOptions = struct {
    @"align": TextAlign = .Left,
    baseline: TextBaseline = .Top,
};

pub const BitmapFontData = struct {
    data: []const u8,
    size: u8,
};

pub const FontFamily = union(enum) {
    Name: []const u8,
    FontGroup: FontGroupId,
    Font: FontId,
    Default: void,
};

const TransitionMarker = struct {
    cur_time_ms: f32,
    time_idx: u32,
    time_t: f32,
};

pub const AnimatedMesh = struct {
    scene: GLTFscene,
    anim: GLTFanimation,

    /// One per transition.
    transition_markers: []TransitionMarker,
    loop: bool,

    pub fn init(alloc: std.mem.Allocator, scene: GLTFscene, anim_idx: u32) AnimatedMesh {
        const ret = AnimatedMesh{
            .scene = scene,
            .anim = scene.animations[anim_idx],
            .transition_markers = alloc.alloc(TransitionMarker, scene.animations[anim_idx].transitions.len) catch fatal(),
            .loop = true,
        };
        for (ret.transition_markers) |*marker| {
            marker.* = .{
                .cur_time_ms = 0,
                .time_idx = 0,
                .time_t = 0,
            };
        }
        return ret;
    }

    pub fn deinit(self: AnimatedMesh, alloc: std.mem.Allocator) void {
        alloc.free(self.transition_markers);
    }

    pub fn update(self: *AnimatedMesh, delta_ms: f32) void {
        for (self.transition_markers) |*marker, i| outer: {
            const transition = self.anim.transitions[i];

            marker.cur_time_ms += delta_ms;
            if (marker.cur_time_ms > transition.max_ms) {
                if (self.loop) {
                    marker.cur_time_ms = @mod(marker.cur_time_ms, transition.max_ms);
                } else {
                    marker.cur_time_ms = transition.max_ms;
                }
            }

            for (transition.times) |time, idx| {
                if (marker.cur_time_ms <= time) {
                    marker.time_idx = @intCast(u32, idx-1);
                    const prev = transition.times[marker.time_idx];
                    marker.time_t = (marker.cur_time_ms - prev) / (time - prev);
                    break :outer;
                }
            }
            marker.time_idx = @intCast(u32, transition.times.len-2);
            const time = transition.times[marker.time_idx];
            marker.time_t = (marker.cur_time_ms - time) / (transition.times[marker.time_idx+1] - time);
        }
    }
};

pub const Mesh3D = struct {
    verts: []const gpu.TexShaderVertex = &.{},
    indexes: []const u16 = &.{},
    image_id: ?ImageId = null,
    material: Material,
    gctx: *Graphics = undefined,

    fn deinit(self: Mesh3D, alloc: std.mem.Allocator) void {
        alloc.free(self.verts);
        alloc.free(self.indexes);
        if (self.image_id) |image_id| {
            self.gctx.removeImage(image_id);
        }
    }
};

pub const Material = struct {
    emissivity: f32,
    roughness: f32,
    metallic: f32,
};