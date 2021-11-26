const std = @import("std");
const stdx = @import("stdx");
const math = stdx.math;
const Vec2 = math.Vec2;
const builtin = @import("builtin");
const t = stdx.testing;

const window = @import("window.zig");
pub const Window = window.Window;
pub const quit = window.quit;
pub const transform = @import("transform.zig");
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
const _font_group = @import("font_group.zig");
const FontGroup = _font_group.FontGroup;
const log = std.log.scoped(.graphics);

const _text = @import("text.zig");
pub const TextMeasure = _text.TextMeasure;
pub const TextMetrics = _text.TextMetrics;

const This = @This();
pub const font = struct {
    pub const FontId = u32;
    pub const FontGroupId = u32;
    pub const VMetrics = This.VMetrics;
    pub const TTF_Font = _ttf.TTF_Font;

    pub usingnamespace switch (Backend) {
        .OpenGL => struct {
            const _font = @import("backend/gl/font.zig");
            const glyph = @import("backend/gl/glyph.zig");
            pub const Font = _font.Font;
            pub const BitmapFont = _font.BitmapFont;
            pub const Glyph = glyph.Glyph;
            pub const FontCache = gl.FontCache;
            pub const FontGroup = _font_group.FontGroup;
        },
        .Test => struct {
            pub const Font = _font.Font;
            pub const Glyph = glyph.Glyph;
            pub const FontCache = gl.FontCache;
            pub const FontGroup = _font_group.FontGroup;
        },
        else => struct {},
    };
};
const FontGroupId = font.FontGroupId;
const FontId = font.FontId;

pub const canvas = @import("backend/wasm/graphics.zig");
pub const gl = @import("backend/gl/graphics.zig");
pub const testg = @import("backend/test/graphics.zig");

// LINKS:
// https://github.com/michal-z/zig-gamedev (windows directx/2d graphics)
// https://github.com/mapbox/earcut (polygon triangulation)
// https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-25-rendering-vector-art-gpu
// https://github.com/intel/fastuidraw
// https://github.com/microsoft/Win2D, https://github.com/microsoft/microsoft-ui-xaml

const BackendType = enum {
    Test,
    WasmCanvas,
    OpenGL,
};

pub const Backend: BackendType = b: {
    if (builtin.is_test) {
        break :b .Test;
    } else if (builtin.target.cpu.arch == .wasm32) {
        break :b .WasmCanvas;
    } else {
        break :b .OpenGL;
    }
};

pub const Graphics = struct {
    const Self = @This();

    g: switch (Backend) {
        .Test => testg.Graphics,
        .WasmCanvas => canvas.Graphics,
        .OpenGL => gl.Graphics,
    },
    path_parser: svg.PathParser,
    svg_parser: svg.SvgParser,

    pub fn init(self: *Self, alloc: *std.mem.Allocator, buf_width: u32, buf_height: u32) void {
        switch (Backend) {
            .Test => testg.Graphics.init(&self.g, alloc),
            .WasmCanvas => canvas.Graphics.init(&self.g, alloc, buf_width, buf_height),
            .OpenGL => gl.Graphics.init(&self.g, alloc, buf_width, buf_height),
        }
        self.path_parser = svg.PathParser.init(alloc);
        self.svg_parser = svg.SvgParser.init(alloc);
    }

    pub fn deinit(self: *Self) void {
        self.path_parser.deinit();
        self.svg_parser.deinit();
        switch (Backend) {
            .WasmCanvas => self.g.deinit(),
            .OpenGL => self.g.deinit(),
            .Test => {},
        }
    }

    // Setup for the frame before user draw calls.
    pub fn beginFrame(self: *Self) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.beginFrame(&self.g),
            .OpenGL => gl.Graphics.beginFrame(&self.g),
            else => @compileError("unsupported"),
        }
    }

    // Post frame ops.
    pub fn endFrame(self: *Self) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.endFrame(&self.g),
            .OpenGL => gl.Graphics.endFrame(&self.g),
            else => @compileError("unsupported"),
        }
    }

    // Shifts origin to x units to the right and y units down.
    pub fn translate(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.translate(&self.g, x, y),
            else => @panic("unsupported"),
        }
    }

    // Scales from origin x units horizontally and y units vertically.
    // Negative value flips the axis. Value of 1 does nothing.
    pub fn scale(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.scale(&self.g, x, y),
            else => @panic("unsupported"),
        }
    }

    // Rotates origin by radians clockwise.
    pub fn rotate(self: *Self, rad: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.rotate(&self.g, rad),
            else => @panic("unsupported"),
        }
    }

    pub fn rotateDeg(self: *Self, deg: f32) void {
        self.rotate(math.degToRad(deg));
    }

    // Resets the current transform to identity.
    pub fn resetTransform(self: *Self) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.resetTransform(&self.g),
            else => @compileError("unsupported"),
        }
    }

    pub fn setFillColor(self: *Self, color: Color) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.setFillColor(&self.g, color),
            .OpenGL => gl.Graphics.setFillColor(&self.g, color),
            else => @compileError("unsupported"),
        }
    }

    pub fn setStrokeColor(self: *Self, color: Color) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.setStrokeColor(&self.g, color),
            .OpenGL => gl.Graphics.setStrokeColor(&self.g, color),
            else => @compileError("unsupported"),
        }
    }

    pub fn setLineWidth(self: *Self, width: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.setLineWidth(&self.g, width),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.fillRect(&self.g, x, y, width, height),
            .OpenGL => gl.Graphics.fillRect(&self.g, x, y, width, height),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.drawRect(&self.g, x, y, width, height),
            .OpenGL => gl.Graphics.drawRect(&self.g, x, y, width, height),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillRoundRect(&self.g, x, y, width, height, radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawRoundRect(&self.g, x, y, width, height, radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, end_rad: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillCircleArc(&self.g, x, y, radius, start_rad, end_rad),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillCircleArcDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, end_deg: f32) void {
        self.fillCircleArc(x, y, radius, math.degToRad(start_deg), math.degToRad(end_deg));
    }

    pub fn drawCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, end_rad: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawCircleArc(&self.g, x, y, radius, start_rad, end_rad),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawCircleArcDeg(self: *Self, x: f32, y: f32, radius: f32, start_deg: f32, end_deg: f32) void {
        self.drawCircleArc(x, y, radius, math.degToRad(start_deg), math.degToRad(end_deg));
    }

    pub fn fillCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillCircle(&self.g, x, y, radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawCircle(&self.g, x, y, radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillEllipse(&self.g, x, y, h_radius, v_radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, end_rad: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillEllipseArc(&self.g, x, y, h_radius, v_radius, start_rad, end_rad),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillEllipseArcDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, end_deg: f32) void {
        self.fillEllipseArc(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(end_deg));
    }

    pub fn drawEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawEllipse(&self.g, x, y, h_radius, v_radius),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, end_rad: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawEllipseArc(&self.g, x, y, h_radius, v_radius, start_rad, end_rad),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawEllipseArcDeg(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, end_deg: f32) void {
        self.drawEllipseArc(x, y, h_radius, v_radius, math.degToRad(start_deg), math.degToRad(end_deg));
    }

    pub fn drawPoint(self: *Self, x: f32, y: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawPoint(&self.g, x, y),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawLine(&self.g, x1, y1, x2, y2),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawCubicBezierCurve(self: *Self, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawCubicBezierCurve(&self.g, x1, y1, c1x, c1y, c2x, c2y, x2, y2),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawQuadraticBezierCurve(self: *Self, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawQuadraticBezierCurve(&self.g, x1, y1, cx, cy, x2, y2),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillTriangle(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillTriangle(&self.g, x1, y1, x2, y2, x3, y3),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillConvexPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillConvexPolygon(&self.g, pts),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillPolygon(&self.g, pts),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawPolygon(self: *Self, pts: []const Vec2) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.drawPolygon(&self.g, pts),
            else => @compileError("unsupported"),
        }
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
            .OpenGL => gl.Graphics.fillSvgPath(&self.g, x, y, path),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawSvgPath(self: *Self, x: f32, y: f32, path: *const SvgPath) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.strokeSvgPath(&self.g, x, y, path),
            else => @compileError("unsupported"),
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

    pub fn createImageFromFile(self: *Self, path: []const u8) !Image {
        switch (Backend) {
            .OpenGL => return gl.Graphics.createImageFromFile(&self.g, path),
            else => @compileError("unsupported"),
        }
    }

    // Assumes data is rgba in row major starting from top left of image.
    pub fn createImageFromBitmap(self: *Self, width: usize, height: usize, data: []const u8, linear_filter: bool) ImageId {
        switch (Backend) {
            .OpenGL => {
                const image = gl.Graphics.createImageFromBitmap(&self.g, width, height, data, linear_filter, .{});
                return image.image_id;
            },
            else => @compileError("unsupported"),
        }
    }

    pub fn drawImage(self: *Self, x: f32, y: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gl.Graphics.drawImage(&self.g, x, y, image_id),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawImageSized(self: *Self, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gl.Graphics.drawImageSized(&self.g, x, y, width, height, image_id),
            else => @compileError("unsupported"),
        }
    }

    pub fn drawSubImage(self: *Self, src_x: f32, src_y: f32, src_width: f32, src_height: f32, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        switch (Backend) {
            .OpenGL => return gl.Graphics.drawSubImage(&self.g, src_x, src_y, src_width, src_height, x, y, width, height, image_id),
            else => @compileError("unsupported"),
        }
    }

    pub fn addFallbackFont(self: *Self, font_id: FontId) void {
        switch (Backend) {
            .OpenGL => return gl.Graphics.addFallbackFont(&self.g, font_id),
            else => @compileError("unsupported"),
        }
    }

    pub fn addTTF_Font(self: *Self, data: []const u8) FontId {
        switch (Backend) {
            .OpenGL => return gl.Graphics.addTTF_Font(&self.g, data),
            else => @compileError("unsupported"),
        }
    }

    pub fn setFont(self: *Self, font_gid: FontId, font_size: f32) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.setFont(&self.g, font_gid, font_size),
            .OpenGL => {
                gl.Graphics.setFont(&self.g, font_gid);
                gl.Graphics.setFontSize(&self.g, font_size);
            },
            else => @compileError("unsupported"),
        }
    }

    pub fn setFontGroup(self: *Self, font_gid: FontGroupId, font_size: f32) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.setFontGroup(&self.g, font_gid, font_size),
            .OpenGL => {
                gl.Graphics.setFontGroup(&self.g, font_gid);
                gl.Graphics.setFontSize(&self.g, font_size);
            },
            else => @compileError("unsupported"),
        }
    }

    pub fn fillText(self: *Self, x: f32, y: f32, text: []const u8) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.fillText(&self.g, x, y, text),
            .OpenGL => gl.Graphics.fillText(&self.g, x, y, text),
            else => @compileError("unsupported"),
        }
    }

    pub fn fillTextFmt(self: *Self, x: f32, y: f32, comptime format: []const u8, args: anytype) void {
        switch (Backend) {
            .OpenGL => gl.Graphics.fillTextFmt(&self.g, x, y, format, args),
            else => @compileError("unsupported"),
        }
    }

    // Measure many text at once.
    pub fn measureTextBatch(self: *Self, arr: []*TextMeasure) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.measureTexts(&self.g, arr),
            .OpenGL => {
                for (arr) |measure| {
                    gl.Graphics.measureFontText(&self.g, measure.font_gid, measure.font_size, measure.text, &measure.res);
                }
            },
            .Test => {},
        }
    }

    pub fn measureCharAdvance(self: *Self, font_gid: FontGroupId, font_size: f32, prev_cp: u21, cp: u21) f32 {
        switch (Backend) {
            .OpenGL => return text_renderer.measureCharAdvance(&self.g.font_cache, &self.g, font_gid, font_size, prev_cp, cp),
            .Test => {
                const factor = font_size / self.g.default_font_size;
                return factor * self.g.default_font_glyph_advance_width;
            },
            else => stdx.debug.panic("unsupported"),
        }
    }

    pub fn measureFontTextIter(self: *Self, font_gid: FontGroupId, size: f32, str: []const u8) MeasureTextIterator {
        switch (Backend) {
            .OpenGL => {
                var iter: MeasureTextIterator = undefined;
                gl.Graphics.measureFontTextIter(&self.g, font_gid, size, str, &iter.inner);
                return iter;
            },
            .Test => {
                var iter: MeasureTextIterator = undefined;
                iter.inner = testg.MeasureTextIterator.init(str, size, &self.g);
                return iter;
            },
            else => stdx.debug.panic("unsupported"),
        }
    }

    pub fn getPrimaryFontVMetrics(self: *Self, font_gid: FontGroupId, font_size: f32) VMetrics {
        switch (Backend) {
            .WasmCanvas => return canvas.Graphics.getPrimaryFontVMetrics(&self.g, font_gid, font_size),
            .OpenGL => return FontCache.getPrimaryFontVMetrics(&self.g.font_cache, font_gid, font_size),
            .Test => {
                const factor = font_size / self.g.default_font_size;
                return .{
                    .ascender = factor * self.g.default_font_metrics.ascender,
                    .descender = 0,
                    .height = factor * self.g.default_font_metrics.height,
                    .line_gap = factor * self.g.default_font_metrics.line_gap,
                };
            },
        }
    }

// TODO: Should we have a default font?
//     pub fn getDefaultFontGroupId(self: *Self) FontGroupId {
//         switch (Backend) {
//             .OpenGL => return self.g.default_font_gid,
//             .Test => return self.g.default_font_gid,
//             else => stdx.debug.panic("unsupported"),
//         }
//     }

    pub fn getFontGroupBySingleFontName(self: *Self, name: []const u8) FontGroupId {
        switch (Backend) {
            .WasmCanvas => return canvas.Graphics.getFontGroupBySingleFontName(&self.g, name),
            .OpenGL => return FontCache.getOrLoadFontGroupByNameSeq(&self.g.font_cache, &.{name}).?,
            .Test => return testg.Graphics.getFontGroupBySingleFontName(&self.g, name),
        }
    }

    pub fn getOrLoadFontGroupByNameSeq(self: *Self, names: []const []const u8) ?FontGroupId {
        switch (Backend) {
            .OpenGL => return FontCache.getOrLoadFontGroupByNameSeq(&self.g.font_cache, names),
            .Test => return self.g.default_font_gid,
            else => @compileError("unsupported"),
        }
    }

    pub fn pushState(self: *Self) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.save(&self.g),
            .OpenGL => gl.Graphics.pushState(&self.g),
            else => stdx.debug.panic("unsupported"),
        }
    }

    pub fn clipRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.clipRect(&self.g, x, y, width, height),
            .OpenGL => gl.Graphics.clipRect(&self.g, x, y, width, height),
            else => stdx.debug.panic("unsupported"),
        }
    }

    pub fn popState(self: *Self) void {
        switch (Backend) {
            .WasmCanvas => canvas.Graphics.restore(&self.g),
            .OpenGL => gl.Graphics.popState(&self.g),
            else => stdx.debug.panic("unsupported"),
        }
    }

//     pub fn flushDraw(self: *Self) void {
//         switch (Backend) {
//             .WasmCanvas => canvas.Graphics.flushDraw(&self.g),
//             .OpenGL => gl.Graphics.flushDraw(&self.g),
//             else => @compileError("unsupported"),
//         }
//     }

//     pub fn fontCache(self: *Self) *FontCache {
//         switch (Backend) {
//             .OpenGL => return &self.g.font_cache,
//             else => stdx.debug.panic("unsupported"),
//         }
//     }

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


const FontMetrics = struct {
    ascender: f32,
    descender: f32,
    line_height: f32,
};

pub fn get_font_metrics() FontMetrics {
    var res = std.mem.zeroes(FontMetrics);
    // fons.fonsVertMetrics(fons_user_ctx.fons_ctx, &res.ascender, &res.descender, &res.line_height);
    return res;
}

pub const MeasureTextIterator = struct {
    const Self = @This();

    // Units are scaled to user font size.
    pub const State = struct {
        cp: u21,

        start_idx: usize,

        // Not inclusive.
        end_idx: usize,

        kern: f32,
        advance_width: f32,

        // Height would be ascent + descent.
        ascent: f32,
        descent: f32,
        height: f32,
    };

    inner: switch (Backend) {
        .OpenGL => gl.MeasureTextIterator,
        .Test => testg.MeasureTextIterator,
        else => stdx.debug.panic("unsupported"),
    },

    state: State,

    pub fn nextCodepoint(self: *Self) bool {
        switch (Backend) {
            .Test => return testg.MeasureTextIterator.nextCodepoint(&self.inner),
            .OpenGL => return gl.font_cache.MeasureTextIterator.nextCodepoint(&self.inner),
            else => stdx.debug.panic("unsupported"),
        }
    }

    pub fn setIndex(self: *Self, i: usize) void {
        switch (Backend) {
            .Test => return testg.MeasureTextIterator.setIndex(&self.inner, i),
            .OpenGL => return gl.font_cache.MeasureTextIterator.setIndex(&self.inner, i),
            else => stdx.debug.panic("unsupported"),
        }
    }
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
