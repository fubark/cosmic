const stdx = @import("stdx");
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const FontId = graphics.font.FontId;
const StdColor = graphics.Color;
const Vec2 = stdx.math.Vec2;
const v8 = @import("v8");

const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const This = runtime.This;
const RuntimeValue = runtime.RuntimeValue;
const v8x = @import("v8x.zig");

/// @title Graphics
/// @name graphics
/// @ns cs.graphics
/// Provides a cross platform API to draw lines, shapes, text, images, and other graphics onto a window or buffer.
/// By default, the coordinate system assumes the origin is at the top-left corner (0, 0). Positive x values go right and positive y values go down.
/// Angle units like radians and degrees start at 0 and positive values go clockwise.
/// In a future release, there will be a direct API to the OpenGL 3 context, and support for WebGPU to target modern graphics hardware.
/// Currently, the API is focused on 2D graphics, but there are plans to add 3D graphics utilities.
pub const cs_graphics = struct {

    /// This provides an interface to the underlying graphics handle. It has a similar API to Web Canvas.
    pub const Context = struct {

        /// Returns the FontId of "Bitstream Vera Sans" the default font embedded into the runtime.
        pub inline fn defaultFont(self: *Graphics) FontId {
            return self.getDefaultFontId();
        }

        /// Sets the current fill color for painting shapes.
        /// @param color
        pub inline fn fillColor(self: *Graphics, color: Color) void {
            return self.setFillColor(toStdColor(color));
        }

        /// Returns the current fill color.
        pub inline fn getFillColor(self: *Graphics) Color {
            return fromStdColor(self.getFillColor());
        }

        /// Sets the current stroke color for painting shape outlines.
        /// @param color
        pub inline fn strokeColor(self: *Graphics, color: Color) void {
            return self.setStrokeColor(toStdColor(color));
        }

        /// Returns the current stroke color.
        pub inline fn getStrokeColor(self: *Graphics) Color {
            return fromStdColor(self.getStrokeColor());
        }

        /// Sets the current line width for painting shape outlines.
        /// @param width
        pub inline fn lineWidth(self: *Graphics, width: f32) void {
            return self.setLineWidth(width);
        }

        /// Returns the current line width.
        pub inline fn getLineWidth(self: *Graphics) f32 {
            return self.getLineWidth();
        }

        /// Path can be absolute or relative to the cwd.
        /// @param path
        pub fn addTtfFont(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.font.FontId {
            return g.addTTF_FontFromPath(path) catch |err| {
                if (err == error.FileNotFound) {
                    v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
                    return 0;
                } else {
                    unreachable;
                }
            };
        }

        /// @param fontId
        pub inline fn addFallbackFont(self: *Graphics, font_id: FontId) void {
            self.addFallbackFont(font_id);
        }

        /// Path can be absolute or relative to the cwd.
        /// @param path
        pub fn newImage(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.Image {
            return g.createImageFromPath(path) catch |err| {
                if (err == error.FileNotFound) {
                    v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
                    return undefined;
                } else {
                    unreachable;
                }
            };
        }

        /// Paints a rectangle with the current fill color.
        /// @param x
        /// @param y
        /// @param width
        /// @param height
        pub inline fn rect(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
            Graphics.fillRect(self, x, y, width, height);
        }

        /// Paints a rectangle outline with the current stroke color.
        /// @param x
        /// @param y
        /// @param width
        /// @param height
        pub inline fn rectOutline(self: *Graphics, x: f32, y: f32, width: f32, height: f32) void {
            Graphics.drawRect(self, x, y, width, height);
        }

        /// Paints a round rectangle with the current fill color.
        /// @param x
        /// @param y
        /// @param width
        /// @param height
        /// @param radius
        pub inline fn roundRect(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
            self.fillRoundRect(x, y, width, height, radius);
        }

        /// Paints a round rectangle outline with the current stroke color.
        /// @param x
        /// @param y
        /// @param width
        /// @param height
        /// @param radius
        pub inline fn roundRectOutline(self: *Graphics, x: f32, y: f32, width: f32, height: f32, radius: f32) void {
            self.drawRoundRect(x, y, width, height, radius);
        }

        /// Shifts the origin x units to the right and y units down.
        /// @param x
        /// @param y
        pub inline fn translate(self: *Graphics, x: f32, y: f32) void {
            Graphics.translate(self, x, y);
        }

        /// Scales from the origin x units horizontally and y units vertically.
        /// Negative value flips the axis. Value of 1 does nothing.
        /// @param x
        /// @param y
        pub inline fn scale(self: *Graphics, x: f32, y: f32) void {
            Graphics.scale(self, x, y);
        }

        /// Rotates the origin by radians clockwise.
        /// @param rad
        pub inline fn rotate(self: *Graphics, rad: f32) void {
            Graphics.rotate(self, rad);
        }

        /// Rotates the origin by degrees clockwise.
        /// @param deg
        pub inline fn rotateDeg(self: *Graphics, deg: f32) void {
            self.rotateDeg(deg);
        }

        /// Resets the current transform to identity.
        pub inline fn resetTransform(self: *Graphics) void {
            self.resetTransform();
        }

        /// Sets the current font and font size.
        /// @param fontId
        /// @param size
        pub inline fn font(self: *Graphics, font_id: FontId, font_size: f32) void {
            self.setFont(font_id, font_size);
        }

        /// Sets the current font size.
        /// @param size
        pub inline fn fontSize(self: *Graphics, font_size: f32) void {
            self.setFontSize(font_size);
        }

        /// Paints text with the current fill color.
        /// @param x
        /// @param y
        /// @param text
        pub inline fn text(self: *Graphics, x: f32, y: f32, str: []const u8) void {
            self.fillText(x, y, str);
        }

        /// Paints a circle sector in radians with the current fill color.
        /// @param x
        /// @param y
        /// @param radius
        /// @param startRad
        /// @param sweepRad
        pub inline fn circleSector(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.fillCircleSector(x, y, radius, start_rad, sweep_rad);
        }

        /// Paints a circle sector in degrees with the current fill color.
        /// @param x
        /// @param y
        /// @param radius
        /// @param startDeg
        /// @param sweepDeg
        pub inline fn circleSectorDeg(self: *Graphics, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.fillCircleSectorDeg(x, y, radius, start_deg, sweep_deg);
        }

        /// Paints a circle arc in radians with the current stroke color.
        /// @param x
        /// @param y
        /// @param radius
        /// @param startRad
        /// @param sweepRad
        pub inline fn circleArc(self: *Graphics, x: f32, y: f32, radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.drawCircleArc(x, y, radius, start_rad, sweep_rad);
        }

        /// Paints a circle arc in degrees with the current stroke color.
        /// @param x
        /// @param y
        /// @param radius
        /// @param startDeg
        /// @param sweepDeg
        pub inline fn circleArcDeg(self: *Graphics, x: f32, y: f32, radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.drawCircleArcDeg(x, y, radius, start_deg, sweep_deg);
        }

        /// Paints a circle with the current fill color.
        /// @param x
        /// @param y
        /// @param radius
        pub inline fn circle(self: *Graphics, x: f32, y: f32, radius: f32) void {
            self.fillCircle(x, y, radius);
        }

        /// Paints a circle outline with the current stroke color.
        /// @param x
        /// @param y
        /// @param radius
        pub inline fn circleOutline(self: *Graphics, x: f32, y: f32, radius: f32) void {
            self.drawCircle(x, y, radius);
        }

        /// Paints a ellipse with the current fill color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        pub inline fn ellipse(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
            self.fillEllipse(x, y, h_radius, v_radius);
        }

        /// Paints a ellipse outline with the current stroke color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        pub inline fn ellipseOutline(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32) void {
            self.drawEllipse(x, y, h_radius, v_radius);
        }

        /// Paints a ellipse sector in radians with the current fill color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        /// @param startRad
        /// @param sweepRad
        pub inline fn ellipseSector(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.fillEllipseSector(x, y, h_radius, v_radius, start_rad, sweep_rad);
        }

        /// Paints a ellipse sector in degrees with the current fill color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        /// @param startDeg
        /// @param sweepDeg
        pub inline fn ellipseSectorDeg(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.fillEllipseSectorDeg(x, y, h_radius, v_radius, start_deg, sweep_deg);
        }

        /// Paints a ellipse arc in radians with the current stroke color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        /// @param startRad
        /// @param sweepRad
        pub inline fn ellipseArc(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_rad: f32, sweep_rad: f32) void {
            self.drawEllipseArc(x, y, h_radius, v_radius, start_rad, sweep_rad);
        }

        /// Paints a ellipse arc in degrees with the current stroke color.
        /// @param x
        /// @param y
        /// @param hRadius
        /// @param vRadius
        /// @param startDeg
        /// @param sweepDeg
        pub inline fn ellipseArcDeg(self: *Graphics, x: f32, y: f32, h_radius: f32, v_radius: f32, start_deg: f32, sweep_deg: f32) void {
            self.drawEllipseArcDeg(x, y, h_radius, v_radius, start_deg, sweep_deg);
        }

        /// Paints a point with the current stroke color.
        /// @param x
        /// @param y
        pub inline fn point(self: *Graphics, x: f32, y: f32) void {
            self.drawPoint(x, y);
        }

        /// Paints a line with the current stroke color.
        /// @param x1
        /// @param y1
        /// @param x2
        /// @param y2
        pub inline fn line(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32) void {
            self.drawLine(x1, y1, x2, y2);
        }

        /// Paints a cubic bezier curve with the current stroke color.
        /// @param x1
        /// @param y1
        /// @param c1x
        /// @param c1y
        /// @param c2x
        /// @param c2y
        /// @param x2
        /// @param y2
        pub inline fn cubicBezierCurve(self: *Graphics, x1: f32, y1: f32, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x2: f32, y2: f32) void {
            self.drawCubicBezierCurve(x1, y1, c1x, c1y, c2x, c2y, x2, y2);
        }

        /// Paints a quadratic bezier curve with the current stroke color.
        /// @param x1
        /// @param y1
        /// @param cx
        /// @param cy
        /// @param x2
        /// @param y2
        pub inline fn quadraticBezierCurve(self: *Graphics, x1: f32, y1: f32, cx: f32, cy: f32, x2: f32, y2: f32) void {
            self.drawQuadraticBezierCurve(x1, y1, cx, cy, x2, y2);
        }

        /// Paints a triangle with the current fill color.
        /// @param x1
        /// @param y1
        /// @param x2
        /// @param y2
        /// @param x3
        /// @param y3
        pub inline fn triangle(self: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
            self.fillTriangle(x1, y1, x2, y2, x3, y3);
        }

        /// Paints a convex polygon with the current fill color.
        /// @param pts
        pub fn convexPolygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
            rt.vec2_buf.resize(pts.len / 2) catch unreachable;
            var i: u32 = 0;
            var vec_idx: u32 = 0;
            while (i < pts.len - 1) : ({
                i += 2;
                vec_idx += 1;
            }) {
                rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
            }
            g.fillConvexPolygon(rt.vec2_buf.items);
        }

        /// Paints any polygon with the current fill color.
        /// @param pts
        pub fn polygon(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
            rt.vec2_buf.resize(pts.len / 2) catch unreachable;
            var i: u32 = 0;
            var vec_idx: u32 = 0;
            while (i < pts.len - 1) : ({
                i += 2;
                vec_idx += 1;
            }) {
                rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
            }
            g.fillPolygon(rt.vec2_buf.items);
        }

        /// Paints any polygon outline with the current stroke color.
        /// @param pts
        pub fn polygonOutline(rt: *RuntimeContext, g: *Graphics, pts: []const f32) void {
            rt.vec2_buf.resize(pts.len / 2) catch unreachable;
            var i: u32 = 0;
            var vec_idx: u32 = 0;
            while (i < pts.len - 1) : ({
                i += 2;
                vec_idx += 1;
            }) {
                rt.vec2_buf.items[vec_idx] = Vec2.init(pts[i], pts[i + 1]);
            }
            g.drawPolygon(rt.vec2_buf.items);
        }

        /// Compiles svg content in UTF-8 into a draw list handle.
        /// @param content
        pub fn compileSvgContent(rt: *RuntimeContext, g: *Graphics, content: []const u8) v8.Persistent(v8.Object) {
            const draw_list = g.compileSvgContent(rt.alloc, content) catch unreachable;

            const native_ptr = rt.alloc.create(RuntimeValue(graphics.DrawCommandList)) catch unreachable;
            native_ptr.* = .{
                .rt = rt,
                .inner = draw_list,
            };
            _ = rt.weak_handles.add(.{
                .ptr = native_ptr,
                .tag = .DrawCommandList,
            }) catch unreachable;

            const ctx = rt.context;
            const iso = rt.isolate;
            const new = rt.handle_class.initInstance(ctx);
            const data = iso.initExternal(native_ptr);
            new.setInternalField(0, data);

            var new_p = iso.initPersistent(v8.Object, new);
            new_p.setWeakFinalizer(native_ptr, finalize_DrawCommandList, v8.WeakCallbackType.kParameter);
            return new_p;
        }

        /// Paints svg content in UTF-8.
        /// @param content
        pub fn svgContent(g: *Graphics, content: []const u8) void {
            g.drawSvgContent(content) catch unreachable;
        }

        /// Executes a draw list handle.
        /// @param handle
        pub fn executeDrawList(g: *Graphics, handle: v8.Object) void {
            const ptr = handle.getInternalField(0).castTo(v8.External).get();
            const value = stdx.mem.ptrCastAlign(*RuntimeValue(graphics.DrawCommandList), ptr);
            g.executeDrawList(value.inner);
        }

        /// Paints an image.
        /// @param x
        /// @param y
        /// @param width
        /// @param height
        /// @param image
        pub fn imageSized(g: *Graphics, x: f32, y: f32, width: f32, height: f32, image: graphics.Image) void {
            g.drawImageSized(x, y, width, height, image.id);
        }

        fn finalize_DrawCommandList(c_info: ?*const v8.C_WeakCallbackInfo) callconv(.C) void {
            const info = v8.WeakCallbackInfo.initFromC(c_info);
            const ptr = info.getParameter();
            const rt = stdx.mem.ptrCastAlign(*RuntimeValue(graphics.DrawCommandList), ptr).rt;
            rt.destroyWeakHandleByPtr(ptr);
        }
    };

    pub const Color = struct {

        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub const lightGray = fromStdColor(StdColor.LightGray);
        pub const gray = fromStdColor(StdColor.Gray);
        pub const darkGray = fromStdColor(StdColor.DarkGray);
        pub const yellow = fromStdColor(StdColor.Yellow);
        pub const gold = fromStdColor(StdColor.Gold);
        pub const orange = fromStdColor(StdColor.Orange);
        pub const pink = fromStdColor(StdColor.Pink);
        pub const red = fromStdColor(StdColor.Red);
        pub const maroon = fromStdColor(StdColor.Maroon);
        pub const green = fromStdColor(StdColor.Green);
        pub const lime = fromStdColor(StdColor.Lime);
        pub const darkGreen = fromStdColor(StdColor.DarkGreen);
        pub const skyBlue = fromStdColor(StdColor.SkyBlue);
        pub const blue = fromStdColor(StdColor.Blue);
        pub const darkBlue = fromStdColor(StdColor.DarkBlue);
        pub const purple = fromStdColor(StdColor.Purple);
        pub const violet = fromStdColor(StdColor.Violet);
        pub const darkPurple = fromStdColor(StdColor.DarkPurple);
        pub const beige = fromStdColor(StdColor.Beige);
        pub const brown = fromStdColor(StdColor.Brown);
        pub const darkBrown = fromStdColor(StdColor.DarkBrown);
        pub const white = fromStdColor(StdColor.White);
        pub const black = fromStdColor(StdColor.Black);
        pub const transparent = fromStdColor(StdColor.Transparent);
        pub const magenta = fromStdColor(StdColor.Magenta);

        pub fn lighter(rt: *RuntimeContext, this: This) cs_graphics.Color {
            const color = rt.getNativeValue(cs_graphics.Color, this.obj.toValue()).?;
            return fromStdColor(toStdColor(color).lighter());
        }

        pub fn darker(rt: *RuntimeContext, this: This) cs_graphics.Color {
            const color = rt.getNativeValue(cs_graphics.Color, this.obj.toValue()).?;
            return fromStdColor(toStdColor(color).darker());
        }

        /// @param alpha
        pub fn withAlpha(rt: *RuntimeContext, this: This, a: u8) cs_graphics.Color {
            const color = rt.getNativeValue(cs_graphics.Color, this.obj.toValue()).?;
            return fromStdColor(toStdColor(color).withAlpha(a));
        }
    };

};

fn fromStdColor(color: StdColor) cs_graphics.Color {
    return .{ .r = color.channels.r, .g = color.channels.g, .b = color.channels.b, .a = color.channels.a };
}

fn toStdColor(color: cs_graphics.Color) StdColor {
    return .{ .channels = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a } };
}