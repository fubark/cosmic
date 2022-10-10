const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.text);

const NullId = std.math.maxInt(u32);

pub const Text = struct {
    props: struct {
        text: ui.SlicePtr(u8) = .{},
    },

    font_gid: graphics.FontGroupId,
    font_size: f32,
    word_wrap: bool,
    tlo: graphics.TextLayout,
    use_layout: bool,
    needs_relayout: bool,
    ctx: *ui.CommonContext,
    cached_layout: ui.LayoutSize,
    cached_line_height: f32,
    str_hash: stdx.string.StringHash,

    pub const Style = struct {
        color: ?Color = null,
        fontSize: ?f32 = null,
        fontFamily: ?graphics.FontFamily = null,
    };

    pub const ComputedStyle = struct {
        color: Color = Color.Black,
        fontSize: f32 = 18,
        fontFamily: graphics.FontFamily = graphics.FontFamily.Default,
    };

    pub fn init(self: *Text, c: *ui.InitContext) void {
        const style = c.getStyle(Text);
        self.font_gid = c.getFontGroupByFamily(style.fontFamily);
        self.font_size = style.fontSize;
        self.word_wrap = false;
        self.use_layout = false;
        self.needs_relayout = true;

        self.tlo = graphics.TextLayout.init(c.alloc);
        self.ctx = c.common;
        self.str_hash = stdx.string.StringHash.init(self.props.text.slice());
    }

    pub fn deinit(self: *Text, _: *ui.DeinitContext) void {
        self.tlo.deinit();
    }

    pub fn postPropsUpdate(self: *Text, ctx: *ui.UpdateContext) void {
        const style = ctx.getStyle(Text);
        const new_font_gid = self.ctx.getFontGroupByFamily(style.fontFamily);
        if (new_font_gid != self.font_gid) {
            self.font_gid = new_font_gid;
            self.needs_relayout = true;
        }
        if (style.fontSize != self.font_size) {
            self.font_size = style.fontSize;
            self.needs_relayout = true;
        }
        if (!self.str_hash.eqStringHash(self.props.text.slice())) {
            self.str_hash = stdx.string.StringHash.init(self.props.text.slice());
            self.needs_relayout = true;
        }
    }

    fn remeasureText(self: *Text, c: *ui.LayoutContext, max_width: f32) ui.LayoutSize {
        if (!self.word_wrap) {
            const m = c.measureText(self.font_gid, self.font_size, self.props.text.slice());
            return ui.LayoutSize.init(m.width, m.height);
        } else {
            // Compute text layout. Perform word wrap.
            c.textLayout(self.font_gid, self.font_size, self.props.text.slice(), max_width, &self.tlo);
            return ui.LayoutSize.init(self.tlo.width, self.tlo.height);
        }
    }

    pub fn build(_: *Text, _: *ui.BuildContext) ui.FramePtr {
        return .{};
    }

    pub fn layout(self: *Text, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.text.slice().len > 0) {
            const cstr = c.getSizeConstraints();
            const new_word_wrap = cstr.max_width != ui.ExpandedWidth;
            if (self.word_wrap != new_word_wrap) {
                self.word_wrap = new_word_wrap;
                self.needs_relayout = true;
            }

            if (self.needs_relayout) {
                self.cached_layout = self.remeasureText(c, cstr.max_width);
                self.cached_line_height = c.getPrimaryFontVMetrics(self.font_gid, self.font_size).height;
                self.needs_relayout = false;
            }
            return self.cached_layout;
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Text, c: *ui.RenderContext) void {
        const g = c.gctx;
        const bounds = c.getAbsBounds();

        const text = self.props.text.slice();
        if (text.len > 0) {
            const style = c.getStyle(Text);
            g.setFont(self.font_gid, self.font_size);
            g.setFillColor(style.color);

            if (self.word_wrap) {
                const clipped = g.getClipRect();
                const min_y = clipped.y - self.cached_line_height;
                const max_y = clipped.y + clipped.height - self.cached_line_height;
                var y = bounds.min_y;
                if (self.tlo.lines.items.len > 0) {
                    const firstLine = self.tlo.lines.items[0];
                    if (y >= min_y and y <= max_y) {
                        const lineS = text[firstLine.start_idx..firstLine.end_idx];
                        g.fillText(bounds.min_x + self.tlo.firstLineStartX, y, lineS);
                    }
                    y += firstLine.height;
                    for (self.tlo.lines.items[1..]) |line| {
                        if (y >= min_y and y <= max_y) {
                            const lineS = text[line.start_idx..line.end_idx];
                            g.fillText(bounds.min_x, y, lineS);
                        }
                        y += line.height;
                    }
                }
            } else {
                g.fillText(bounds.min_x, bounds.min_y, text);
            }
        }
    }
};

/// Since Text can be laid out inline the hit test should only consider the region where there is text.
pub const TextLink = struct {
    props: struct {
        uri: ui.SlicePtr(u8) = .{},
        text: ui.SlicePtr(u8) = .{},
    },

    node: *ui.Node,
    text: ui.WidgetRef(u.TextT),

    pub const Style = struct {
        color: ?Color = null,
    };

    pub const ComputedStyle = struct {
        color: Color = Color.Blue.lighter(),
    };

    pub fn init(self: *TextLink, ctx: *ui.InitContext) void {
        self.node = ctx.node;
    }

    pub fn build(self: *TextLink, ctx: *ui.BuildContext) ui.FramePtr {
        const style = ctx.getStyle(TextLink);
        const t_style = u.TextStyle{
            .color = style.color,
        };
        return u.MouseHoverArea(.{
            .hitTest = ctx.funcExt(self, hitTest),
            .onHoverChange = ctx.funcExt(self, onHover), }, 
            u.MouseArea(.{ .onClick = ctx.funcExt(self, onClick), .hitTest = ctx.funcExt(self, hitTest) },
                u.Text(.{ .text = self.props.text.dupeRef(), .style = t_style, .bind = &self.text }),
            ),
        );
    }

    fn hitTest(self: *TextLink, x: i16, y: i16) bool {
        const b = self.node.abs_bounds;
        const textW = self.text.getWidget();
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);

        if (b.containsPt(xf, yf)) {
            // Isn't before first line start x.
            if (yf < b.min_y + textW.cached_line_height and xf < b.min_x + textW.tlo.firstLineStartX) {
                return false;
            }
            // Isn't after last line end x.
            if (yf > b.max_y - textW.cached_line_height and xf > b.min_x + textW.tlo.lastLineEndX) {
                return false;
            }
            return true;
        }
        return false;
    }

    fn onHover(self: *TextLink, e: ui.HoverChangeEvent) void {
        _ = self;
        if (e.hovered) {
            platform.setSystemCursor(.pointer);
        } else {
            platform.setSystemCursor(.default);
        }
    }

    fn onClick(self: *TextLink, e: ui.MouseUpEvent) void {
        _ = e;
        const uri = self.props.uri.slice();
        if (std.mem.startsWith(u8, uri, "https://") or std.mem.startsWith(u8, uri, "http://")) {
            platform.openUrl(uri);
        }
    }
};