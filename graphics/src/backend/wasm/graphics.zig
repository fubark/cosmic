const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;
const WasmJsBuffer = stdx.wasm.WasmJsBuffer;

const graphics = @import("../../graphics.zig");
const Image = graphics.Image;
const ImageId = graphics.ImageId;
const svg = graphics.svg;
const BlendMode = graphics.BlendMode;
const Color = graphics.Color;
const FontId = graphics.font.FontId;
const FontGroupId = graphics.font.FontGroupId;
const UserVMetrics = graphics.font.UserVMetrics;
const TextMeasure = graphics.TextMeasure;
const log = stdx.log.scoped(.graphics_canvas);

extern "graphics" fn jsSave() void;
extern "graphics" fn jsRestore() void;
extern "graphics" fn jsClipRect(x: f32, y: f32, width: f32, height: f32) void;
extern "graphics" fn jsDrawRect(x: f32, y: f32, width: f32, height: f32) void;
extern "graphics" fn jsFillRect(x: f32, y: f32, width: f32, height: f32) void;
extern "graphics" fn jsFillCircle(x: f32, y: f32, radius: f32) void;
extern "graphics" fn jsDrawCircle(x: f32, y: f32, radius: f32) void;
extern "graphics" fn jsFillCircleSector(x: f32, y: f32, radius: f32, start_rad: f32, end_rad: f32) void;
extern "graphics" fn jsDrawCircleArc(x: f32, y: f32, radius: f32, start_rad: f32, end_rad: f32) void;
extern "graphics" fn jsFillEllipse(x: f32, y: f32, h_radius: f32, v_radius: f32) void;
extern "graphics" fn jsDrawEllipse(x: f32, y: f32, h_radius: f32, v_radius: f32) void;
extern "graphics" fn jsFillEllipseSector(x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, end_rad: f32) void;
extern "graphics" fn jsDrawEllipseArc(x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, end_rad: f32) void;
extern "graphics" fn jsFillTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void;
extern "graphics" fn jsFillPolygon(buf_ptr: [*]const u8, num_verts: u32) void;
extern "graphics" fn jsDrawPolygon(buf_ptr: [*]const u8, num_verts: u32) void;
extern "graphics" fn jsFillRoundRect(x: f32, y: f32, width: f32, height: f32, radius: f32) void;
extern "graphics" fn jsDrawRoundRect(x: f32, y: f32, width: f32, height: f32, radius: f32) void;
extern "graphics" fn jsDrawPoint(x: f32, y: f32) void;
extern "graphics" fn jsDrawLine(x1: f32, y1: f32, x2: f32, y2: f32) void;
extern "graphics" fn jsDrawCubicBezierCurve(x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void;
extern "graphics" fn jsDrawQuadraticBezierCurve(x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void;
extern "graphics" fn jsFillStyle(r: f32, g: f32, b: f32, a: f32) void;
extern "graphics" fn jsStrokeStyle(r: f32, g: f32, b: f32, a: f32) void;
extern "graphics" fn jsFillText(x: f32, y: f32, ptr: [*]const u8, len: usize) void;
extern "graphics" fn jsSetLineWidth(width: f32) void;
extern "graphics" fn jsMeasureTexts(args_buffer: [*]const u8) usize;
extern "graphics" fn jsGetPrimaryFontVMetrics(font_gid: usize, font_size: f32, res_ptr: [*]const u8) void;
extern "graphics" fn jsAddFont(path_ptr: [*]const u8, path_len: usize, name_ptr: [*]const u8, name_len: usize) FontId;
extern "graphics" fn jsGetFont(name_ptr: [*]const u8, name_len: usize) FontId;
extern "graphics" fn jsSetFontStyle(font_gid: FontGroupId, font_size: f32) void;
extern "graphics" fn jsTranslate(x: f32, y: f32) void;
extern "graphics" fn jsRotate(rad: f32) void;
extern "graphics" fn jsScale(x: f32, y: f32) void;
extern "graphics" fn jsResetTransform() void;
extern "graphics" fn jsCreateImage(promise_id: u32, ptr: [*]const u8, len: usize) void;
extern "graphics" fn jsDrawImageSized(image_id: u32, x: f32, y: f32, width: f32, height: f32) void;
extern "graphics" fn jsDrawImage(image_id: u32, x: f32, y: f32) void;

// Incremental path ops.
extern "graphics" fn jsFill() void;
extern "graphics" fn jsStroke() void;
extern "graphics" fn jsClosePath() void;
extern "graphics" fn jsMoveTo(x: f32, y: f32) void;
extern "graphics" fn jsLineTo(x: f32, y: f32) void;
extern "graphics" fn jsQuadraticCurveTo(cx: f32, cy: f32, x2: f32, y2: f32) void;
extern "graphics" fn jsCubicCurveTo(c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void;

pub const Graphics = struct {
    const Self = @This();

    js_buf: *WasmJsBuffer,

    buffer_width: usize,
    buffer_height: usize,
    clear_color: Color,
    cur_stroke_color: Color,
    cur_fill_color: Color,
    cur_font_gid: FontGroupId,
    cur_font_size: f32,

    // Used to keep link results back to TextMeasures
    text_measures_buffer: std.ArrayList(*TextMeasure),

    pub fn init(self: *Self, alloc: *std.mem.Allocator, width: usize, height: usize) void {
        _ = alloc;
        self.* = .{
            .buffer_width = width,
            .buffer_height = height,
            .clear_color = Color.initFloat(0, 0, 0, 1.0),
            .text_measures_buffer = std.ArrayList(*TextMeasure).init(alloc),
            .cur_stroke_color = undefined,
            .cur_fill_color = undefined,
            .cur_font_gid = 0,
            .cur_font_size = 0,
            .js_buf = stdx.wasm.getJsBuffer(),
        };
        self.forceSetFillColor(Color.Black);
        self.forceSetStrokeColor(Color.Black);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        self.text_measures_buffer.deinit();
        self.text_buf.deinit();
    }

    pub fn beginFrame(self: *Self) void {
        self.setFillColor(self.clear_color);
        self.fillRect(0, 0, @intToFloat(f32, self.buffer_width), @intToFloat(f32, self.buffer_height));
    }

    pub fn endFrame(self: *Self) void {
        _ = self;
    }

    pub fn flushDraw(self: *Self) void {
        _ = self;
    }

    pub fn save(self: *Self) void {
        _ = self;
        jsSave();
    }

    pub fn clipRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        _ = self;
        jsClipRect(x, y, width, height);
    }

    pub fn restore(self: *Self) void {
        _ = self;
        jsRestore();
    }

    pub fn setBlendMode(self: *Self, mode: BlendMode) void {
        _ = mode;
        _ = self;
        stdx.panic("unsupported");
    }

    pub fn resetTransform(self: *Self) void {
        _ = self;
        jsResetTransform();
    }

    pub fn scale(self: *Self, x: f32, y: f32) void {
        _ = self;
        jsScale(x, y);
    }

    pub fn rotate(self: *Self, rad: f32) void {
        _ = self;
        jsRotate(rad);
    }

    pub fn translate(self: *Self, x: f32, y: f32) void {
        _ = self;
        jsTranslate(x, y);
    }

    pub fn setLineWidth(self: *Self, width: f32) void {
        _ = self;
        jsSetLineWidth(width);
    }

    // This might be useful:
    // https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/textBaseline
    pub fn fillText(self: *Self, x: f32, y: f32, text: []const u8) void {
        _ = self;
        jsFillText(x, y, text.ptr, text.len);
    }

    pub fn drawRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        _ = self;
        jsDrawRect(x, y, width, height);
    }

    pub fn fillRect(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        _ = self;
        jsFillRect(x, y, width, height);
    }

    pub fn fillCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        _ = self;
        jsFillCircle(x, y, radius);
    }

    pub fn drawCircle(self: *Self, x: f32, y: f32, radius: f32) void {
        _ = self;
        jsDrawCircle(x, y, radius);
    }

    pub fn fillCircleSector(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        _ = self;
        if (sweep_rad < 0) {
            jsFillCircleSector(x, y, radius, start_rad + sweep_rad, start_rad);
        } else {
            jsFillCircleSector(x, y, radius, start_rad, start_rad + sweep_rad);
        }
    }

    pub fn drawCircleArc(self: *Self, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
        _ = self;
        if (sweep_rad < 0) {
            jsDrawCircleArc(x, y, radius, start_rad + sweep_rad, start_rad);
        } else {
            jsDrawCircleArc(x, y, radius, start_rad, start_rad + sweep_rad);
        }
    }

    pub fn fillEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        _ = self;
        jsFillEllipse(x, y, h_radius, v_radius);
    }

    pub fn drawEllipse(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
        _ = self;
        jsDrawEllipse(x, y, h_radius, v_radius);
    }

    pub fn fillEllipseSector(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        _ = self;
        if (sweep_rad < 0) {
            jsFillEllipseSector(x, y, h_radius, v_radius, start_rad + sweep_rad, start_rad);
        } else {
            jsFillEllipseSector(x, y, h_radius, v_radius, start_rad, start_rad + sweep_rad);
        }
    }

    pub fn drawEllipseArc(self: *Self, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
        _ = self;
        if (sweep_rad < 0) {
            jsDrawEllipseArc(x, y, h_radius, v_radius, start_rad + sweep_rad, start_rad);
        } else {
            jsDrawEllipseArc(x, y, h_radius, v_radius, start_rad, start_rad + sweep_rad);
        }
    }

    pub fn fillTriangle(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        _ = self;
        jsFillTriangle(x1, y1, x2, y2, x3, y3);
    }

    pub fn fillPolygon(self: *Self, pts: []const Vec2) void {
        _ = self;
        self.js_buf.clearOutput();
        for (pts) |pt| {
            self.js_buf.appendF32(pt.x);
            self.js_buf.appendF32(pt.y);
        }
        jsFillPolygon(self.js_buf.getOutputPtr(), pts.len);
    }

    pub fn drawPolygon(self: *Self, pts: []const Vec2) void {
        _ = self;
        self.js_buf.clearOutput();
        for (pts) |pt| {
            self.js_buf.appendF32(pt.x);
            self.js_buf.appendF32(pt.y);
        }
        jsDrawPolygon(self.js_buf.getOutputPtr(), pts.len);
    }

    pub fn fillRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        _ = self;
        jsFillRoundRect(x, y, width, height, radius);
    }

    pub fn drawRoundRect(self: *Self, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
        _ = self;
        jsDrawRoundRect(x, y, width, height, radius);
    }

    pub fn drawPoint(self: *Self, x: f32, y: f32) void {
        _ = self;
        jsDrawPoint(x, y);
    }

    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32) void {
        _ = self;
        jsDrawLine(x1, y1, x2, y2);
    }

    pub fn drawQuadraticBezierCurve(self: *Self, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
        _ = self;
        jsDrawQuadraticBezierCurve(x1, y1, cx, cy, x2, y2);
    }

    pub fn drawCubicBezierCurve(self: *Self, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
        _ = self;
        jsDrawCubicBezierCurve(x1, y1, c1x, c1y, c2x, c2y, x2, y2);
    }

    // Iterator of TextMeasure data
    pub fn measureTexts(self: *Self, iter: anytype) void {
        _ = self;
        var _iter = iter;

        // Write text ptrs to wasm output buffer.

        // Skip headers and numTexts until we finish the iterator.
        self.js_buf.clearOutputWithSize(10);

        self.text_measures_buffer.shrinkRetainingCapacity(0);
        while (_iter.nextPtr()) |it| {
            if (it.needs_measure) {
                it.needs_measure = false;

                // Empty text has size 0.
                if (it.text.len == 0) {
                    it.size.width = 0;
                    continue;
                }

                // Record TextMeasure to link with result.
                self.text_measures_buffer.append(it) catch unreachable;

                self.js_buf.appendInt(u32, @ptrToInt(it.text.ptr));
                self.js_buf.appendInt(u16, it.text.len);
                // log.debug("len from zig {}", .{@intCast(u16, it.text.len)});
                self.js_buf.appendInt(u16, it.font_gid);
                self.js_buf.appendF32(it.font_size);
            }
        }

        if (self.text_measures_buffer.items.len == 0) {
            return;
        }

        // Write headers.
        self.js_buf.writeIntAt(u32, 0, @ptrToInt(self.js_buf.input_buf.items.ptr));
        self.js_buf.writeIntAt(u32, 4, self.js_buf.input_buf.capacity);
        self.js_buf.writeIntAt(u16, 8, @intCast(u16, self.text_measures_buffer.items.len));

        const input_len = jsMeasureTexts(self.js_buf.output_buf.items.ptr);
        self.js_buf.input_buf.resize(input_len) catch unreachable;
        var offset: usize = 0;
        for (self.text_measures_buffer.items) |it| {
            const width = self.js_buf.readF32At(offset);
            it.size.width = width;
            it.needs_measure = false;
            offset += 4;
        }

        const last = self.text_measures_buffer.items[self.text_measures_buffer.items.len-1];
        self.cur_font_gid = last.font_gid;
        self.cur_font_size = last.font_size;
    }

    fn forceSetStrokeColor(self: *Self, color: Color) void {
        jsStrokeStyle(
            @intToFloat(f32, color.channels.r),
            @intToFloat(f32, color.channels.g),
            @intToFloat(f32, color.channels.b),
            @intToFloat(f32, color.channels.a) / 255);
        self.cur_stroke_color = color;
    }

    fn forceSetFillColor(self: *Self, color: Color) void {
        jsFillStyle(
            @intToFloat(f32, color.channels.r),
            @intToFloat(f32, color.channels.g),
            @intToFloat(f32, color.channels.b),
            @intToFloat(f32, color.channels.a) / 255);
        self.cur_fill_color = color;
    }

    pub fn setFont(self: *Self, font_gid: FontGroupId, font_size: f32) void {
        if (font_gid != self.cur_font_gid or font_size != self.cur_font_size) {
            jsSetFontStyle(font_gid, font_size);
            self.cur_font_gid = font_gid;
            self.cur_font_size = font_size;
        }
    }

    pub fn setStrokeColor(self: *Self, color: Color) void {
        if (!std.meta.eql(color, self.cur_stroke_color)) {
            self.forceSetStrokeColor(color);
        }
    }

    pub fn setFillColor(self: *Self, color: Color) void {
        if (!std.meta.eql(color, self.cur_fill_color)) {
            self.forceSetFillColor(color);
        }
    }

    // NOTE: Does not support UserVMetrics.line_gap.
    // ascent/height are estimated since they do not come from the underlying font file but from dom measurement.
    pub fn getPrimaryFontVMetrics(self: *const Self, font_gid: FontGroupId, font_size: f32) UserVMetrics {
        _ = self;
        self.js_buf.input_buf.resize(8) catch unreachable;
        jsGetPrimaryFontVMetrics(font_gid, font_size, self.js_buf.input_buf.items.ptr);
        const ascent = self.js_buf.readF32At(0);
        const height = self.js_buf.readF32At(4);
        const descent = -(height - ascent);
        return .{
            .ascender = ascent,
            .descender = descent,
            .height = height,
            .line_gap = 0,
        };
    }

    pub fn addTTF_FontFromExeDir(self: *Self, path: []const u8, name: []const u8) FontId {
        _ = self;
        return jsAddFont(path.ptr, path.len, name.ptr, name.len);
    }

    pub fn getFontByName(self: *Self, name: []const u8) FontId {
        _ = self;
        return jsGetFont(name.ptr, name.len);
    }

    // pub fn getFontGroupBySingleFontName(self: *Self, name: []const u8) FontGroupId {
    //     _ = self;
    //     return jsGetFontGroup(name.ptr, name.len);
    // }

    pub fn fillSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
        self.drawSvgPath(x, y, path, true);
    }

    pub fn strokeSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath) void {
        self.drawSvgPath(x, y, path, false);
    }

    fn drawSvgPath(self: *Self, x: f32, y: f32, path: *const svg.SvgPath, fill: bool) void {
        _ = self;
        // log.debug("drawSvgPath {}", .{path.cmds.len});
        _ = x;
        _ = y;
        var cur_pos = vec2(0, 0);
        var cur_data_idx: u32 = 0;
        var last_control_pos = vec2(0, 0);
        var last_cmd_was_curveto = false;

        for (path.cmds) |it| {
            var cmd_is_curveto = false;
            switch (it) {
                .MoveTo => {
                    // log.debug("lyon begin", .{});
                    const data = path.getData(.MoveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    jsMoveTo(cur_pos.x, cur_pos.y);
                },
                .MoveToRel => {
                    const data = path.getData(.MoveToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.MoveToRel)) / 4;
                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    jsMoveTo(cur_pos.x, cur_pos.y);
                },
                .VertLineTo => {
                    const data = path.getData(.VertLineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineTo)) / 4;
                    cur_pos.y = data.y;
                    jsLineTo(cur_pos.x, cur_pos.y);
                },
                .VertLineToRel => {
                    const data = path.getData(.VertLineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.VertLineToRel)) / 4;
                    cur_pos.y += data.y;
                    jsLineTo(cur_pos.x, cur_pos.y);
                },
                .LineTo => {
                    const data = path.getData(.LineTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    jsLineTo(cur_pos.x, cur_pos.y);
                },
                .LineToRel => {
                    const data = path.getData(.LineToRel, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.LineToRel)) / 4;
                    cur_pos.x += data.x;
                    cur_pos.y += data.y;
                    jsLineTo(cur_pos.x, cur_pos.y);
                },
                .CurveTo => {
                    const data = path.getData(.CurveTo, cur_data_idx);
                    cur_data_idx += @sizeOf(svg.PathCommandData(.CurveTo)) / 4;
                    cur_pos.x = data.x;
                    cur_pos.y = data.y;
                    last_control_pos.x = data.cb_x;
                    last_control_pos.y = data.cb_y;
                    cmd_is_curveto = true;
                    jsCubicCurveTo(data.ca_x, data.ca_y, last_control_pos.x, last_control_pos.y, cur_pos.x, cur_pos.y);
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
                    jsCubicCurveTo(prev_x + data.ca_x, prev_y + data.ca_y, last_control_pos.x, last_control_pos.y, cur_pos.x, cur_pos.y);
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
                    jsCubicCurveTo(c1_x, c1_y, last_control_pos.x, last_control_pos.y, cur_pos.x, cur_pos.y);
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
                    jsCubicCurveTo(c1_x, c1_y, last_control_pos.x, last_control_pos.y, cur_pos.x, cur_pos.y);
                },
                .ClosePath => {
                    jsClosePath();
                },
            }
            last_cmd_was_curveto = cmd_is_curveto;
        }
        if (fill) {
            jsFill();
        } else {
            jsStroke();
        }
    }

    pub fn createImageFromExeDirPromise(self: *Self, path: []const u8) stdx.wasm.Promise(Image) {
        _ = self;
        const p = stdx.wasm.createPromise(Image);
        jsCreateImage(p.id, path.ptr, path.len);
        return p;
    }

    pub fn drawImageSized(self: *Self, x: f32, y: f32, width: f32, height: f32, image_id: ImageId) void {
        _ = self;
        jsDrawImageSized(image_id, x, y, width, height);
    }

    pub fn drawImage(self: *Self, x: f32, y: f32, image_id: ImageId) void {
        _ = self;
        jsDrawImage(image_id, x, y);
    }
};

export fn wasmResolveImagePromise(promise_id: stdx.wasm.PromiseId, image_id: ImageId, width: usize, height: usize) void {
    stdx.wasm.resolvePromise(promise_id, Image{
        .id = image_id,
        .width = width,
        .height = height,
    });
}