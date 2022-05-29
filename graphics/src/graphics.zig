const std = @import("std");
const build_options = @import("build_options");
const stdx = @import("stdx");
const math = stdx.math;
const Vec2 = math.Vec2;
const builtin = @import("builtin");
const t = stdx.testing;
const sdl = @import("sdl");
const ft = @import("freetype");
const platform = @import("platform");

pub const transform = @import("transform.zig");
const Transform = transform.Transform;
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
pub const initTextureProjection = camera.initTextureProjection;

pub const tessellator = @import("tessellator.zig");
pub const RectBinPacker = @import("rect_bin_packer.zig").RectBinPacker;
pub const SwapChain = @import("swapchain.zig").SwapChain;

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

const This = @This();
pub const font = struct {
    pub const FontId = u32;
    // Maybe this should be renamed to FontFamilyId. FontGroup renamed to FontFamily.
    pub const FontGroupId = u32;
    pub const VMetrics = This.VMetrics;
    pub const OpenTypeFont = _ttf.OpenTypeFont;
    pub const Font = @import("font.zig").Font;
    pub const FontType = @import("font.zig").FontType;
    pub const FontGroup = @import("font_group.zig").FontGroup;
    pub const FontDesc = @import("font.zig").FontDesc;
    pub const BitmapFontStrike = @import("font.zig").BitmapFontStrike;

};
const FontGroupId = font.FontGroupId;
const FontId = font.FontId;

pub const canvas = @import("backend/canvas/graphics.zig");
pub const gpu = @import("backend/gpu/graphics.zig");
pub const vk = @import("backend/vk/vk.zig");
pub const gl = @import("backend/gl/gl.zig");
pub const testg = @import("backend/test/graphics.zig");

/// Global freetype library handle.
pub var ft_library: ft.FT_Library = undefined;

pub const Graphics = struct {
    impl: switch (Backend) {
        .OpenGL, .Vulkan => gpu.Graphics,
        .WasmCanvas => canvas.Graphics,
        .Test => testg.Graphics,
        else => stdx.panic("unsupported"),
    },
    alloc: std.mem.Allocator,
    path_parser: svg.PathParser,
    svg_parser: svg.SvgParser,
    text_buf: std.ArrayList(u8),

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator, w: platform.Window) void {
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

        switch (Backend) {
            .OpenGL => gpu.Graphics.init(&self.impl, alloc, w.inner.dpr),
            .Vulkan => gpu.Graphics.init(&self.impl, alloc, w.inner.dpr),
            .WasmCanvas => canvas.Graphics.init(&self.impl, alloc),
            .Test => testg.Graphics.init(&self.impl, alloc),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn deinit(self: *Self) void {
        self.path_parser.deinit();
        self.svg_parser.deinit();
        self.text_buf.deinit();
        switch (Backend) {
            .OpenGL => self.impl.deinit(),
            .WasmCanvas => self.impl.deinit(),
            .Test => {},
            else => stdx.panicUnsupported(),
        }
    }

    // Shifts origin to x units to the right and y units down.
    pub fn translate(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.translate(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.translate(&self.impl, x, y),
            else => stdx.panic("unsupported"),
        }
    }

    // Scales from origin x units horizontally and y units vertically.
    // Negative value flips the axis. Value of 1 does nothing.
    pub fn scale(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.scale(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.scale(&self.impl, x, y),
            else => stdx.panic("unsupported"),
        }
    }

    // Rotates origin by radians clockwise.
    pub fn rotate(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.rotate(&self.impl, rad),
            .WasmCanvas => canvas.Graphics.rotate(&self.impl, rad),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn rotateDeg(self: *Self, deg: f32) void {
        self.rotate(math.degToRad(deg));
    }

    // Resets the current transform to identity.
    pub fn resetTransform(self: *Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.resetTransform(&self.impl),
            .WasmCanvas => canvas.Graphics.resetTransform(&self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn setClearColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setClearColor(&self.impl, color),
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn clear(self: Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.clear(self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getFillColor(self: Self) Color {
        return switch (Backend) {
            .OpenGL => gpu.Graphics.getFillColor(self.impl),
            .WasmCanvas => canvas.Graphics.getFillColor(self.impl),
            else => stdx.panic("unsupported"),
        };
    }

    pub fn setFillColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.setFillColor(&self.impl, color),
            .WasmCanvas => canvas.Graphics.setFillColor(&self.impl, color),
            else => stdx.panic("unsupported"),
        }
    }

    /// Set a linear gradient fill style.
    pub fn setFillGradient(self: *Self, start_x: f32, start_y: f32, start_color: Color, end_x: f32, end_y: f32, end_color: Color) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.setFillGradient(&self.impl, start_x, start_y, start_color, end_x, end_y, end_color),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getStrokeColor(self: Self) Color {
        return switch (Backend) {
            .OpenGL => gpu.Graphics.getStrokeColor(self.impl),
            .WasmCanvas => canvas.Graphics.getStrokeColor(self.impl),
            else => stdx.panic("unsupported"),
        };
    }

    pub fn setStrokeColor(self: *Self, color: Color) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.setStrokeColor(&self.impl, color),
            .WasmCanvas => canvas.Graphics.setStrokeColor(&self.impl, color),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getLineWidth(self: Self) f32 {
        return switch (Backend) {
            .OpenGL => gpu.Graphics.getLineWidth(self.impl),
            .WasmCanvas => canvas.Graphics.getLineWidth(self.impl),
            else => stdx.panic("unsupported"),
        };
    }

    pub fn setLineWidth(self: *Self, width: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.setLineWidth(&self.impl, width),
            .WasmCanvas => canvas.Graphics.setLineWidth(&self.impl, width),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.fillRect(&self.impl, x, y, width, height),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.drawRect(&self.impl, x, y, width, height),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillRoundRect(&self.impl, x, y, width, height, radius),
            .WasmCanvas => canvas.Graphics.fillRoundRect(&self.impl, x, y, width, height, radius),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawRoundRect(&self.impl, x, y, width, height, radius),
            .WasmCanvas => canvas.Graphics.drawRoundRect(&self.impl, x, y, width, height, radius),
            else => stdx.panic("unsupported"),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn fillCircleSector(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillCircleSector(&self.impl, x, y, radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.fillCircleSector(&self.impl, x, y, radius, start_rad, sweep_rad),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillCircleSectorDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.fillCircleSector(x, y, radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn drawCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawCircleArc(&self.impl, x, y, radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.drawCircleArc(&self.impl, x, y, radius, start_rad, sweep_rad),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawCircleArcDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.drawCircleArc(x, y, radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn fillCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillCircle(&self.impl, x, y, radius),
            .WasmCanvas => canvas.Graphics.fillCircle(&self.impl, x, y, radius),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawCircle(&self.impl, x, y, radius),
            .WasmCanvas => canvas.Graphics.drawCircle(&self.impl, x, y, radius),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillEllipse(&self.impl, x, y, h_radius, v_radius),
            .WasmCanvas => canvas.Graphics.fillEllipse(&self.impl, x, y, h_radius, v_radius),
            else => stdx.panic("unsupported"),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn fillEllipseSector(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillEllipseSector(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.fillEllipseSector(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillEllipseSectorDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.fillEllipseSector(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn drawEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawEllipse(&self.impl, x, y, h_radius, v_radius),
            .WasmCanvas => canvas.Graphics.drawEllipse(&self.impl, x, y, h_radius, v_radius),
            else => stdx.panic("unsupported"),
        }
    }

    // Radians start at 0 and end at 2pi going clockwise. Negative radians goes counter clockwise.
    pub fn drawEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawEllipseArc(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            .WasmCanvas => canvas.Graphics.drawEllipseArc(&self.impl, x, y, h_radius, v_radius, start_rad, sweep_rad),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawEllipseArcDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
        self.drawEllipseArc(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(sweep_deg));
    }

    pub fn drawPoint(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawPoint(&self.impl, x, y),
            .WasmCanvas => canvas.Graphics.drawPoint(&self.impl, x, y),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawLine(&self.impl, x1, y1, x2, y2),
            .WasmCanvas => canvas.Graphics.drawLine(&self.impl, x1, y1, x2, y2),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawCubicBezierCurve(self: *Self, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawCubicBezierCurve(&self.impl, x1, y1, c1x, c1y, c2x, c2y, x2, y2),
            .WasmCanvas => canvas.Graphics.drawCubicBezierCurve(&self.impl, x1, y1, c1x, c1y, c2x, c2y, x2, y2),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawQuadraticBezierCurve(self: *Self, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawQuadraticBezierCurve(&self.impl, x1, y1, cx, cy, x2, y2),
            .WasmCanvas => canvas.Graphics.drawQuadraticBezierCurve(&self.impl, x1, y1, cx, cy, x2, y2),
            else => stdx.panic("unsupported"),
        }
    }

    /// Assumes pts are in ccw order.
    pub fn fillTriangle(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillTriangle(&self.impl, x1, y1, x2, y2, x3, y3),
            .WasmCanvas => canvas.Graphics.fillTriangle(&self.impl, x1, y1, x2, y2, x3, y3),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillConvexPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillConvexPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.fillPolygon(&self.impl, pts),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.fillPolygon(&self.impl, pts),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.drawPolygon(&self.impl, pts),
            .WasmCanvas => canvas.Graphics.drawPolygon(&self.impl, pts),
            else => stdx.panic("unsupported"),
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
            .OpenGL => gpu.Graphics.fillSvgPath(&self.impl, x, y, path),
            .WasmCanvas => canvas.Graphics.fillSvgPath(&self.impl, x, y, path),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawSvgPath(self: *Self, x: f32, y: f32, path: *const SvgPath) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.strokeSvgPath(&self.impl, x, y, path),
            .WasmCanvas => canvas.Graphics.strokeSvgPath(&self.impl, x, y, path),
            else => stdx.panic("unsupported"),
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
            else => stdx.panic("unsupported"),
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
            .OpenGL => {
                const data = try std.fs.cwd().readFileAlloc(self.alloc, path, 30e6);
                defer self.alloc.free(data);
                return self.createImage(data);
            },
            .WasmCanvas => stdx.panic("unsupported, use createImageFromPathPromise"),
            else => stdx.panic("unsupported"),
        }
    }

    // Loads an image from various data formats.
    pub fn createImage(self: *Self, data: []const u8) !Image {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.createImageFromData(&self.impl, data),
            .WasmCanvas => stdx.panic("unsupported, use createImageFromPathPromise"),
            else => stdx.panic("unsupported"),
        }
    }

    /// Assumes data is rgba in row major starting from top left of image.
    /// If data is null, an empty image will be created. In OpenGL, the empty image will have undefined pixel data.
    pub fn createImageFromBitmap(self: *Self, width: usize, height: usize, data: ?[]const u8, linear_filter: bool) ImageId {
        switch (Backend) {
            .OpenGL => {
                const image = gpu.Graphics.createImageFromBitmap(&self.impl, width, height, data, linear_filter);
                return image.image_id;
            },
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn bindImageBuffer(self: *Self, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.bindImageBuffer(&self.impl, image_id),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawImage(self: *Self, x: f32, y: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.drawImage(&self.impl, x, y, image_id),
            .WasmCanvas => return canvas.Graphics.drawImage(&self.impl, x, y, image_id),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawImageSized(self: *Self, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.drawImageSized(&self.impl, x, y, width, height, image_id),
            .WasmCanvas => return canvas.Graphics.drawImageSized(&self.impl, x, y, width, height, image_id),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn drawSubImage(self: *Self, src_x: f32, src_y: f32, src_width: f32, src_height: f32, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.drawSubImage(&self.impl, src_x, src_y, src_width, src_height, x, y, width, height, image_id),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn addFallbackFont(self: *Self, font_id: FontId) void {
        switch (Backend) {
            .OpenGL, .Vulkan => gpu.Graphics.addFallbackFont(&self.impl, font_id),
            else => stdx.panic("unsupported"),
        }
    }

    /// Adds .otb bitmap font with data at different font sizes.
    pub fn addFontOTB(self: *Self, data: []const BitmapFontData) FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.addFontOTB(&self.impl, data),
            else => stdx.panic("unsupported"),
        }
    }

    /// Adds outline or color bitmap font from ttf/otf.
    pub fn addFontTTF(self: *Self, data: []const u8) FontId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.addFontTTF(&self.impl, data),
            .WasmCanvas => stdx.panic("Unsupported for WasmCanvas. Use addTTF_FontPathForName instead."),
            else => stdx.panic("unsupported"),
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
            .OpenGL => {
                return self.addFontFromPathTTF(path);
            },
            .WasmCanvas => return canvas.Graphics.addFontFromPathTTF(&self.impl, path, name),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getFontSize(self: *Self) f32 {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.getFontSize(self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setFontSize(self: *Self, font_size: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.setFontSize(&self.impl, font_size),
            .WasmCanvas => canvas.Graphics.setFontSize(&self.impl, font_size),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setFont(self: *Self, font_id: FontId, font_size: f32) void {
        switch (Backend) {
            .OpenGL => {
                gpu.Graphics.setFont(&self.impl, font_id);
                gpu.Graphics.setFontSize(&self.impl, font_size);
            },
            .WasmCanvas => canvas.Graphics.setFont(&self.impl, font_id, font_size),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setFontGroup(self: *Self, font_gid: FontGroupId, font_size: f32) void {
        switch (Backend) {
            .OpenGL => {
                gpu.Graphics.setFontGroup(&self.impl, font_gid);
                gpu.Graphics.setFontSize(&self.impl, font_size);
            },
            .WasmCanvas => canvas.Graphics.setFontGroup(&self.impl, font_gid, font_size),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setTextAlign(self: *Self, align_: TextAlign) void {
        switch (Backend) {
            .OpenGL =>  {
                gpu.Graphics.setTextAlign(&self.impl, align_);
            },
            else => stdx.panic("unsupported"),
        }
    }

    pub fn setTextBaseline(self: *Self, baseline: TextBaseline) void {
        switch (Backend) {
            .OpenGL =>  {
                gpu.Graphics.setTextBaseline(&self.impl, baseline);
            },
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillText(self: *Self, x: f32, y: f32, text: []const u8) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.fillText(&self.impl, x, y, text),
            .WasmCanvas => canvas.Graphics.fillText(&self.impl, x, y, text),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn fillTextFmt(self: *Self, x: f32, y: f32, comptime format: []const u8, args: anytype) void {
        self.text_buf.clearRetainingCapacity();
        std.fmt.format(self.text_buf.writer(), format, args) catch unreachable;
        self.fillText(x, y, self.text_buf.items);
    }

    /// Measure many text at once.
    pub fn measureTextBatch(self: *Self, arr: []*TextMeasure) void {
        switch (Backend) {
            .OpenGL => {
                for (arr) |measure| {
                    gpu.Graphics.measureFontText(&self.impl, measure.font_gid, measure.font_size, measure.text, &measure.res);
                }
            },
            .WasmCanvas => canvas.Graphics.measureTexts(&self.impl, arr),
            .Test => {},
            else => stdx.panic("unsupported"),
        }
    }

    /// Measure the char advance between two codepoints.
    pub fn measureCharAdvance(self: *Self, font_gid: FontGroupId, font_size: f32, prev_cp: u21, cp: u21) f32 {
        switch (Backend) {
            .OpenGL => return text_renderer.measureCharAdvance(&self.impl.font_cache, &self.impl, font_gid, font_size, prev_cp, cp),
            .Test => {
                const factor = font_size / self.impl.default_font_size;
                return factor * self.impl.default_font_glyph_advance_width;
            },
            else => stdx.panic("unsupported"),
        }
    }

    /// Measure some text with a given font.
    pub fn measureFontText(self: *Self, font_gid: FontGroupId, font_size: f32, str: []const u8, out: *TextMetrics) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return self.impl.measureFontText(font_gid, font_size, str, out),
            else => stdx.panic("unsupported"),
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
            .OpenGL => {
                return gpu.Graphics.textGlyphIter(&self.impl, font_gid, size, str);
            },
            .Test => {
                var iter: TextGlyphIterator = undefined;
                iter.inner = testg.TextGlyphIterator.init(str, size, &self.impl);
                return iter;
            },
            else => stdx.panic("unsupported"),
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
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn getFontVMetrics(self: *Self, font_id: FontId, font_size: f32) VMetrics {
        switch (Backend) {
            .OpenGL => return FontCache.getFontVMetrics(&self.impl.font_cache, font_id, font_size),
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn getDefaultFontId(self: *Self) FontId {
        switch (Backend) {
            .OpenGL => return self.impl.default_font_id,
            .Test => return self.impl.default_font_id,
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn getDefaultFontGroupId(self: *Self) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return self.impl.default_font_gid,
            .Test => return self.impl.default_font_gid,
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getFontByName(self: *Self, name: []const u8) ?FontId {
        switch (Backend) {
            .OpenGL => return FontCache.getFontId(&self.impl.font_cache, name),
            .WasmCanvas => return canvas.Graphics.getFontByName(&self.impl, name),
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn getFontGroupForSingleFont(self: *Self, font_id: FontId) FontGroupId {
        switch (Backend) {
            .OpenGL => return FontCache.getOrLoadFontGroup(&self.impl.font_cache, &.{font_id}),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getFontGroupByFamily(self: *Self, family: FontFamily) FontGroupId {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.Graphics.getOrLoadFontGroupByFamily(&self.impl, family),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getFontGroupBySingleFontName(self: *Self, name: []const u8) FontGroupId {
        switch (Backend) {
            .OpenGL => return FontCache.getOrLoadFontGroupByNameSeq(&self.impl.font_cache, &.{name}).?,
            .WasmCanvas => stdx.panic("TODO"),
            .Test => return testg.Graphics.getFontGroupBySingleFontName(&self.impl, name),
        }
    }

    pub fn getOrLoadFontGroupByNameSeq(self: *Self, names: []const []const u8) ?FontGroupId {
        switch (Backend) {
            .OpenGL => return FontCache.getOrLoadFontGroupByNameSeq(&self.impl.font_cache, names),
            .Test => return self.impl.default_font_gid,
            else => stdx.panic("unsupported"),
        }
    }

    pub fn pushState(self: *Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.pushState(&self.impl),
            .WasmCanvas => canvas.Graphics.save(&self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn clipRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.clipRect(&self.impl, x, y, width, height),
            .WasmCanvas => canvas.Graphics.clipRect(&self.impl, x, y, width, height),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn popState(self: *Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.popState(&self.impl),
            .WasmCanvas => canvas.Graphics.restore(&self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    pub fn getViewTransform(self: Self) Transform {
        switch (Backend) {
            .OpenGL => return gpu.Graphics.getViewTransform(self.impl),
            else => stdx.panic("unsupported"),
        }
    }

    /// Flush any draw commands queued up.
    pub inline fn flushDraw(self: *Self) void {
        switch (Backend) {
            .OpenGL => gpu.Graphics.flushDraw(&self.impl),
            .WasmCanvas => {},
            else => stdx.panic("unsupported"),
        }
    }
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