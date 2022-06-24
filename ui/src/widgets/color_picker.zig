const stdx = @import("stdx");
const Function = stdx.Function;
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const widgets = ui.widgets;
const Row = widgets.Row;
const Column = widgets.Column;
const Flex = widgets.Flex;
const Slider = widgets.Slider;
const Sized = widgets.Sized;
const MouseArea = widgets.MouseArea;
const Text = widgets.Text;
const TextButton = widgets.TextButton;
const Root = widgets.Root;
const Stretch = widgets.Stretch;

const log = stdx.log.scoped(.color_picker);

// TODO: Split this into ColorPicker and ColorPickerOption.
pub const ColorPicker = struct {
    props: struct {
        label: []const u8 = "Color",
        font_size: f32 = 16,
        init_val: Color = Color.White,
        onPreviewChange: ?Function(fn (Color) void) = null,
        onResult: ?Function(fn (color: Color, save: bool) void) = null,
    },

    color: Color,
    slider: ui.WidgetRef(Slider),
    preview: ui.WidgetRef(Sized),
    root: *Root,
    node: *ui.Node,

    popover_inner: ui.WidgetRef(ColorPickerPopover),
    popover: u32,

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
        self.root = c.getRoot();
        self.node = c.node;
        self.color = self.props.init_val;
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn buildPopover(ptr: ?*anyopaque, c_: *ui.BuildContext) ui.FrameId {
                const self_ = stdx.mem.ptrCastAlign(*Self, ptr);
                return c_.decl(ColorPickerPopover, .{
                    .bind = &self_.popover_inner,
                    .init_val = self_.color,
                    .onPreviewChange = self_.props.onPreviewChange,
                });
            }
            fn onPopoverClose(ptr: ?*anyopaque) void {
                const self_ = stdx.mem.ptrCastAlign(*Self, ptr);
                const inner = self_.popover_inner.getWidget();
                if (inner.save_result) {
                    self_.color = inner.color;
                }
                if (self_.props.onResult) |cb| {
                    cb.call(.{ self_.color, inner.save_result });
                }
            }
            fn onClick(self_: *Self, _: platform.MouseUpEvent) void {
                self_.popover = self_.root.showPopover(self_.node, self_, buildPopover, .{
                    .close_ctx = self_, 
                    .close_cb = onPopoverClose,
                });
            }
        };
        const d = c.decl;
        return d(MouseArea, .{
            .onClick = c.funcExt(self, S.onClick),
            .child = d(Row, .{
                .valign = .Center,
                .children = c.list(.{
                    d(Flex, .{
                        .child = d(Text, .{
                            .text = self.props.label,
                            .font_size = self.props.font_size,
                            .color = Color.White,
                        }),
                    }),
                    d(Sized, .{
                        .bind = &self.preview,
                        .width = 30,
                        .height = 30,
                    }),
                }),
            }),
        });
    }

    pub fn render(self: *Self, ctx: *ui.RenderContext) void {
        const preview_alo = self.preview.getAbsLayout();
        ctx.g.setFillColor(self.color);
        ctx.g.fillRect(preview_alo.x, preview_alo.y, preview_alo.width, preview_alo.height);
    }
};

const ColorPickerPopover = struct {
    props: struct {
        init_val: Color,
        onPreviewChange: ?Function(fn (Color) void) = null,
    },

    palette: ui.WidgetRef(Stretch),
    hue_slider: ui.WidgetRef(Slider),

    save_result: bool,
    color: Color,
    palette_xratio: f32,
    palette_yratio: f32,
    hue: f32,
    is_pressed: bool,
    window: *ui.widgets.PopoverOverlay,

    const Self = @This();
    const ThumbRadius = 10;

    pub fn init(self: *Self, c: *ui.InitContext) void {
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
        
        c.addMouseDownHandler(self, onMouseDown);
        c.addMouseUpHandler(self, onMouseUp);
    }

    fn onMouseUp(self: *Self, _: ui.MouseUpEvent) void {
        self.is_pressed = false;
    }

    fn onMouseDown(self: *Self, e: ui.MouseDownEvent) ui.EventResult {
        const xf = @intToFloat(f32, e.val.x);
        const yf = @intToFloat(f32, e.val.y);

        const palette_alo = self.palette.node.getAbsLayout();
        if (palette_alo.contains(xf, yf)) {
            e.ctx.requestFocus(onBlur);
            self.is_pressed = true;
            self.setMouseValue(e.val.x, e.val.y);

            e.ctx.removeMouseMoveHandler(*Self, onMouseMove);
            e.ctx.addMouseMoveHandler(self, onMouseMove);
        }
        return .Continue;
    }

    fn setMouseValue(self: *Self, x: i32, y: i32) void {
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        const palette_alo = self.palette.node.getAbsLayout();
        self.palette_xratio = (xf - palette_alo.x) / palette_alo.width;
        if (self.palette_xratio < 0) {
            self.palette_xratio = 0;
        } else if (self.palette_xratio > 1) {
            self.palette_xratio = 1;
        }
        self.palette_yratio = (yf - palette_alo.y) / palette_alo.height;
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

    fn onMouseMove(self: *Self, e: ui.MouseMoveEvent) void {
        if (self.is_pressed) {
            self.setMouseValue(e.val.x, e.val.y);
        }
    }

    fn onBlur(_: *ui.Node, c: *ui.CommonContext) void {
        // const self = node.getWidget(Self);
        c.removeMouseMoveHandler(*Self, onMouseMove);
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClickSave(self_: *Self, _: platform.MouseUpEvent) void {
                self_.save_result = true;
                self_.window.requestClose();
            }
            fn onChangeHue(self_: *Self, hue: i32) void {
                // Update color.
                self_.hue = @intToFloat(f32, hue);
                self_.color = Color.fromHsv(self_.hue, self_.palette_xratio, 1 - self_.palette_yratio);
                if (self_.props.onPreviewChange) |cb| {
                    cb.call(.{ self_.color });
                }
            }
        };
        return c.decl(Sized, .{
            .width = 200,
            .child = c.decl(Column, .{
                .expand = false,
                .stretch_width = true,
                .children = c.list(.{
                    c.decl(Stretch, .{
                        .method = .WidthAndKeepRatio,
                        .aspect_ratio = 1,
                        .bind = &self.palette,
                    }),
                    c.decl(Slider, .{
                        .min_val = 0,
                        .max_val = 360,
                        .init_val = @floatToInt(i32, self.hue),
                        .bind = &self.hue_slider,
                        .thumb_color = Color.Transparent,
                        .onChange = c.funcExt(self, S.onChangeHue),
                    }),
                    c.decl(TextButton, .{
                        .text = "Save",
                        .onClick = c.funcExt(self, S.onClickSave),
                    }),
                }),
            }),
        });
    }

    fn getValue(self: Self) Color {
        _ = self;
        return Color.Red;
    }

    pub fn renderCustom(self: *Self, ctx: *ui.RenderContext) void {
        // const alo = ctx.getAbsLayout();
        const g = ctx.g;

        // Render children so palette box resolves it's abs pos.
        ctx.renderChildren();

        // Draw custom slider bar.
        const slider = self.hue_slider.getWidget();
        const hue = @intToFloat(f32, slider.value);
        const bar_layout = slider.getBarLayout();

        const bar_x = slider.node.abs_pos.x + bar_layout.x;
        const bar_y = slider.node.abs_pos.y + bar_layout.y;

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
        const thumb_x = slider.node.abs_pos.x + slider.getThumbLayoutX();
        const thumb_y = slider.node.abs_pos.y + bar_layout.y + bar_layout.height/2;
        const slider_color = Color.fromHsv(hue, 1, 1);
        g.setFillColor(slider_color);
        g.fillCircle(thumb_x, thumb_y, ThumbRadius);
        g.setStrokeColor(Color.White);
        g.setLineWidth(2);
        g.drawCircle(thumb_x, thumb_y, ThumbRadius);

        // Draw the palette.
        const palette_alo = self.palette.getAbsLayout();
        g.setFillGradient(palette_alo.x, palette_alo.y, Color.White, palette_alo.x + palette_alo.width, palette_alo.y, slider_color);
        g.fillRect(palette_alo.x, palette_alo.y, palette_alo.width, palette_alo.height);
        g.setFillGradient(palette_alo.x, palette_alo.y, Color.Transparent, palette_alo.x, palette_alo.y + palette_alo.height, Color.Black);
        g.fillRect(palette_alo.x, palette_alo.y, palette_alo.width, palette_alo.height);
    }

    fn postPopoverRender(ptr: ?*anyopaque, c: *ui.RenderContext) void {
        const self = stdx.mem.ptrCastAlign(*Self, ptr);
        const palette_alo = self.palette.getAbsLayout();
        const g = c.g;

        // Draw the palette cursor.
        const cursor_x = palette_alo.x + palette_alo.width * self.palette_xratio;
        const cursor_y = palette_alo.y + palette_alo.height * self.palette_yratio;
        g.setFillColor(self.color);
        g.fillCircle(cursor_x, cursor_y, ThumbRadius);
        g.setStrokeColor(Color.White);
        g.setLineWidth(2);
        g.drawCircle(cursor_x, cursor_y, ThumbRadius);
    }
};