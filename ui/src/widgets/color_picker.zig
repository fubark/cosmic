const stdx = @import("stdx");
const fatal = stdx.fatal;
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const w = ui.widgets;

const log = stdx.log.scoped(.color_picker);

// TODO: Split this into ColorPicker and ColorPickerOption.
pub const ColorPicker = struct {
    props: struct {
        label: []const u8 = "Color",
        fontSize: f32 = 16,
        init_val: Color = Color.White,
        onPreviewChange: ?Function(fn (Color) void) = null,
        onResult: ?Function(fn (color: Color, save: bool) void) = null,
    },

    color: Color,
    slider: ui.WidgetRef(w.SliderT),
    preview: ui.WidgetRef(w.SizedT),
    root: *w.Root,
    node: *ui.Node,

    popover_inner: ui.WidgetRef(ColorPickerPopover),
    popover: u32,

    pub fn init(self: *ColorPicker, c: *ui.InitContext) void {
        self.root = c.getRoot();
        self.node = c.node;
        self.color = self.props.init_val;
    }

    pub fn build(self: *ColorPicker, c: *ui.BuildContext) ui.FrameId {
        return w.MouseArea(.{ .onClick = c.funcExt(self, onClick) },
            w.Row(.{ .valign = .Center }, &.{
                w.Flex(.{}, 
                    w.Text(.{
                        .text = self.props.label,
                        .fontSize = self.props.fontSize,
                        .color = Color.White,
                    }),
                ),
                w.Sized(.{
                    .bind = &self.preview,
                    .width = 30,
                    .height = 30,
                }, ui.NullFrameId),
            }),
        );
    }

    pub fn render(self: *ColorPicker, ctx: *ui.RenderContext) void {
        const preview_bounds = self.preview.getAbsBounds();
        ctx.gctx.setFillColor(self.color);
        ctx.fillBBox(preview_bounds);
    }

    fn onClick(self: *ColorPicker, _: ui.MouseUpEvent) void {
        const S = struct {
            fn buildPopover(ptr: ?*anyopaque, c_: *ui.BuildContext) ui.FrameId {
                const self_ = stdx.mem.ptrCastAlign(*ColorPicker, ptr);
                return c_.build(ColorPickerPopover, .{
                    .bind = &self_.popover_inner,
                    .init_val = self_.color,
                    .onPreviewChange = self_.props.onPreviewChange,
                });
            }
            fn onPopoverClose(ptr: ?*anyopaque) void {
                const self_ = stdx.mem.ptrCastAlign(*ColorPicker, ptr);
                const inner = self_.popover_inner.getWidget();
                if (inner.save_result) {
                    self_.color = inner.color;
                }
                if (self_.props.onResult) |cb| {
                    cb.call(.{ self_.color, inner.save_result });
                }
            }
        };
        self.popover = self.root.showPopover(self.node, self, S.buildPopover, .{
            .close_ctx = self, 
            .close_cb = S.onPopoverClose,
        }) catch fatal();
    }
};

const ColorPickerPopover = struct {
    props: struct {
        init_val: Color,
        onPreviewChange: ?Function(fn (Color) void) = null,
    },

    palette: ui.WidgetRef(w.StretchT),
    hue_slider: ui.WidgetRef(w.SliderT),

    save_result: bool,
    color: Color,
    palette_xratio: f32,
    palette_yratio: f32,
    hue: f32,
    is_pressed: bool,
    window: *ui.widgets.PopoverOverlay,

    const ThumbRadius = 10;

    pub fn init(self: *ColorPickerPopover, c: *ui.InitContext) void {
        self.color = self.props.init_val;
        const hsv = self.color.toHsv();
        self.hue = hsv[0];
        self.palette_xratio = hsv[1];
        self.palette_yratio = 1 - hsv[2];
        self.save_result = false;

        // Set custom post render over the popover window.
        self.window = c.node.parent.?.getWidget(ui.widgets.PopoverOverlay);
        self.window.custom_post_render = postPopoverRender;
        self.window.custom_post_render_ctx = self;
        
        c.setMouseDownHandler(self, onMouseDown);
    }

    fn onMouseUp(self: *ColorPickerPopover, e: ui.MouseUpEvent) void {
        self.is_pressed = false;
        e.ctx.clearGlobalMouseUpHandler();
        e.ctx.clearGlobalMouseMoveHandler();
    }

    fn onMouseDown(self: *ColorPickerPopover, e: ui.MouseDownEvent) ui.EventResult {
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        const palette_bounds = self.palette.node.getAbsBounds();
        if (palette_bounds.containsPt(xf, yf)) {
            e.ctx.requestFocus(.{ .onBlur = onBlur });
            self.is_pressed = true;
            self.setMouseValue(e.val.x, e.val.y);

            e.ctx.setGlobalMouseUpHandler(self, onMouseUp);
            e.ctx.setGlobalMouseMoveHandler(self, onMouseMove);
            return .stop;
        }
        return .default;
    }

    fn setMouseValue(self: *ColorPickerPopover, x: i32, y: i32) void {
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        const palette_bounds = self.palette.node.getAbsBounds();
        const width = palette_bounds.computeWidth();
        self.palette_xratio = (xf - palette_bounds.min_x) / width;
        if (self.palette_xratio < 0) {
            self.palette_xratio = 0;
        } else if (self.palette_xratio > 1) {
            self.palette_xratio = 1;
        }
        const height = palette_bounds.computeHeight();
        self.palette_yratio = (yf - palette_bounds.min_y) / height;
        if (self.palette_yratio < 0) {
            self.palette_yratio = 0;
        } else if (self.palette_yratio > 1) {
            self.palette_yratio = 1;
        }
        self.color = Color.fromHsv(self.hue, self.palette_xratio, 1 - self.palette_yratio);
        if (self.props.onPreviewChange) |cb| {
            cb.call(.{ self.color });
        }
    }

    fn onMouseMove(self: *ColorPickerPopover, e: ui.MouseMoveEvent) void {
        if (self.is_pressed) {
            self.setMouseValue(e.val.x, e.val.y);
        }
    }

    fn onBlur(n: *ui.Node, c: *ui.CommonContext) void {
        // const self = node.getWidget(ColorPickerPopover);
        c.clearGlobalMouseMoveHandler(n);
        c.clearGlobalMouseUpHandler(n);
    }

    pub fn build(self: *ColorPickerPopover, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClickSave(self_: *ColorPickerPopover, _: ui.MouseUpEvent) void {
                self_.save_result = true;
                self_.window.requestClose();
            }
            fn onChangeHue(self_: *ColorPickerPopover, hue: i32) void {
                // Update color.
                self_.hue = @intToFloat(f32, hue);
                self_.color = Color.fromHsv(self_.hue, self_.palette_xratio, 1 - self_.palette_yratio);
                if (self_.props.onPreviewChange) |cb| {
                    cb.call(.{ self_.color });
                }
            }
        };
        return w.Sized(.{ .width = 200 },
            w.Column(.{ .expand_child_width = true }, &.{
                w.Stretch(.{
                    .method = .WidthAndKeepRatio,
                    .aspect_ratio = 1,
                    .bind = &self.palette,
                }, ui.NullFrameId),
                w.Slider(.{
                    .min_val = 0,
                    .max_val = 360,
                    .init_val = @floatToInt(i32, self.hue),
                    .bind = &self.hue_slider,
                    .thumb_color = Color.Transparent,
                    .onChange = c.funcExt(self, S.onChangeHue),
                }),
                w.TextButton(.{
                    .text = "Save",
                    .onClick = c.funcExt(self, S.onClickSave),
                }),
            }),
        );
    }

    fn getValue(self: ColorPickerPopover) Color {
        _ = self;
        return Color.Red;
    }

    pub fn renderCustom(self: *ColorPickerPopover, ctx: *ui.RenderContext) void {
        // const alo = ctx.getAbsLayout();
        const g = ctx.gctx;

        // Render children so palette box resolves it's abs pos.
        ctx.renderChildren();

        // Draw custom slider bar.
        const slider = self.hue_slider.getWidget();
        const hue = @intToFloat(f32, slider.value);
        const bar_layout = slider.getBarLayout();

        const bar_x = slider.node.abs_bounds.min_x + bar_layout.x;
        const bar_y = slider.node.abs_bounds.min_y + bar_layout.y;

        const step = @as(f32, 1) / @as(f32, 6);
        // 0 Red - 60 Yellow
        g.setFillGradient(bar_x, bar_y, Color.StdRed, bar_x + bar_layout.width * step, bar_y, Color.StdYellow);
        g.fillRect(bar_x, bar_y, bar_layout.width * step, bar_layout.height);
        // 60 Yellow - 120 Green
        g.setFillGradient(bar_x + bar_layout.width * step, bar_y, Color.StdYellow, bar_x + bar_layout.width * step * 2, bar_y, Color.StdGreen);
        g.fillRect(bar_x + bar_layout.width * step, bar_y, bar_layout.width * step, bar_layout.height);
        // 120 Green - 180 Cyan
        g.setFillGradient(bar_x + bar_layout.width * step * 2, bar_y, Color.StdGreen, bar_x + bar_layout.width * step * 3, bar_y, Color.StdCyan);
        g.fillRect(bar_x + bar_layout.width * step * 2, bar_y, bar_layout.width * step, bar_layout.height);
        // 180 Cyan - 240 Blue
        g.setFillGradient(bar_x + bar_layout.width * step * 3, bar_y, Color.StdCyan, bar_x + bar_layout.width * step * 4, bar_y, Color.StdBlue);
        g.fillRect(bar_x + bar_layout.width * step * 3, bar_y, bar_layout.width * step, bar_layout.height);
        // 240 Blue - 300 Magenta
        g.setFillGradient(bar_x + bar_layout.width * step * 4, bar_y, Color.StdBlue, bar_x + bar_layout.width * step * 5, bar_y, Color.StdMagenta);
        g.fillRect(bar_x + bar_layout.width * step * 4, bar_y, bar_layout.width * step, bar_layout.height);
        // 300 Magenta - 360 Red
        g.setFillGradient(bar_x + bar_layout.width * step * 5, bar_y, Color.StdMagenta, bar_x + bar_layout.width, bar_y, Color.StdRed);
        g.fillRect(bar_x + bar_layout.width * step * 5, bar_y, bar_layout.width * step, bar_layout.height);

        // Draw custom slider thumb.
        const thumb_x = slider.node.abs_bounds.min_x + slider.getThumbLayoutX();
        const thumb_y = slider.node.abs_bounds.min_y + bar_layout.y + bar_layout.height/2;
        const slider_color = Color.fromHsv(hue, 1, 1);
        g.setFillColor(slider_color);
        g.fillCircle(thumb_x, thumb_y, ThumbRadius);
        g.setStrokeColor(Color.White);
        g.setLineWidth(2);
        g.drawCircle(thumb_x, thumb_y, ThumbRadius);

        // Draw the palette.
        const palette_bounds = self.palette.getAbsBounds();
        g.setFillGradient(palette_bounds.min_x, palette_bounds.min_y, Color.White, palette_bounds.max_x, palette_bounds.min_y, slider_color);
        ctx.fillBBox(palette_bounds);
        g.setFillGradient(palette_bounds.min_x, palette_bounds.min_y, Color.Transparent, palette_bounds.min_x, palette_bounds.max_y, Color.Black);
        ctx.fillBBox(palette_bounds);
    }

    fn postPopoverRender(ptr: ?*anyopaque, c: *ui.RenderContext) void {
        const self = stdx.mem.ptrCastAlign(*ColorPickerPopover, ptr);
        const palette_bounds = self.palette.getAbsBounds();
        const g = c.gctx;

        // Draw the palette cursor.
        const width = palette_bounds.computeWidth();
        const height = palette_bounds.computeHeight();
        const cursor_x = palette_bounds.min_x + width * self.palette_xratio;
        const cursor_y = palette_bounds.min_y + height * self.palette_yratio;
        g.setFillColor(self.color);
        g.fillCircle(cursor_x, cursor_y, ThumbRadius);
        g.setStrokeColor(Color.White);
        g.setLineWidth(2);
        g.drawCircle(cursor_x, cursor_y, ThumbRadius);
    }
};