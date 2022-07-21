const std = @import("std");
const stdx = @import("stdx");
const Duration = stdx.time.Duration;
const Function = stdx.Function;
const platform = @import("platform");
const MouseDownEvent = platform.MouseDownEvent;
const KeyDownEvent = platform.KeyDownEvent;
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const w = ui.widgets;
const log = stdx.log.scoped(.text_field);

const NullId = std.math.maxInt(u32);

/// Handles a single line of text input.
pub const TextField = struct {
    props: struct {
        bg_color: Color = Color.White,
        text_color: Color = Color.Black,
        focused_border_color: Color = Color.Blue,
        font_id: graphics.FontId = NullId,
        font_size: f32 = 20,
        onChangeEnd: ?Function(fn ([]const u8) void) = null,
        onKeyDown: ?Function(fn (ui.WidgetRef(w.TextFieldUI), KeyDownEvent) void) = null,
        padding: f32 = 10,
        placeholder: ?[]const u8 = null,
        width: ?f32 = null,
        focused_show_border: bool = true,
    },

    buf: stdx.textbuf.TextBuffer,

    inner: ui.WidgetRef(TextFieldInner),

    /// Used to determine if the text changed since it received focus.
    last_buf_hash: [16]u8,

    ctx: *ui.CommonContext,
    node: *ui.Node,

    pub fn init(self: *TextField, c: *ui.InitContext) void {
        self.buf = stdx.textbuf.TextBuffer.init(c.alloc, "") catch @panic("error");
        self.last_buf_hash = undefined;
        c.addKeyDownHandler(self, onKeyDown);
        c.addMouseDownHandler(self, onMouseDown);
        self.ctx = c.common;
        self.node = c.node;
    }

    pub fn deinit(node: *ui.Node, _: std.mem.Allocator) void {
        const self = node.getWidget(TextField);
        self.buf.deinit();
    }

    pub fn build(self: *TextField, c: *ui.BuildContext) ui.FrameId {
        return w.Padding(.{ .padding = self.props.padding },
            c.build(TextFieldInner, .{
                .bind = &self.inner,
                .text = self.buf.buf.items,
                .font_size = self.props.font_size,
                .font_id = self.props.font_id,
                .text_color = self.props.text_color,
                .placeholder = self.props.placeholder,
            }),
        );
    }

    pub fn setValueFmt(self: *TextField, comptime format: []const u8, args: anytype) void {
        self.buf.clear();
        self.buf.appendFmt(format, args);
        self.ensureCaretPos();
    }

    pub fn clear(self: *TextField) void {
        self.buf.clear();
        self.ensureCaretPos();
    }

    fn ensureCaretPos(self: *TextField) void {
        const inner = self.inner.getWidget();
        if (inner.caret_idx > self.buf.num_chars) {
            inner.caret_idx = self.buf.num_chars;
        }
    }

    /// Request focus on the TextField.
    pub fn requestFocus(self: *TextField) void {
        self.ctx.requestFocus(self.node, onBlur);
        const inner = self.inner.getWidget();
        inner.setFocused();
        std.crypto.hash.Md5.hash(self.buf.buf.items, &self.last_buf_hash, .{});
    }

    pub fn getValue(self: TextField) []const u8 {
        return self.buf.buf.items;
    }

    fn onMouseDown(self: *TextField, e: ui.MouseDownEvent) ui.EventResult {
        const me = e.val;
        self.requestFocus();

        // Map mouse pos to caret pos.
        const inner = self.inner.getWidget();
        const xf = @intToFloat(f32, me.x);
        inner.caret_idx = self.getCaretIdx(e.ctx.common, xf - inner.node.abs_pos.x + inner.scroll_x);
        return .Continue;
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        const self = node.getWidget(TextField);
        self.inner.getWidget().focused = false;
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(self.buf.buf.items, &hash, .{});
        if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
            self.fireOnChangeEnd();
        }
    }

    fn fireOnChangeEnd(self: *TextField) void {
        if (self.props.onChangeEnd) |cb| {
            cb.call(.{ self.buf.buf.items });
        }
    }

    fn getCaretIdx(self: *TextField, ctx: *ui.CommonContext, x: f32) u32 {
        const font_gid = ctx.getFontGroupForSingleFontOrDefault(self.props.font_id);
        var iter = ctx.textGlyphIter(font_gid, self.props.font_size, self.buf.buf.items);
        if (iter.nextCodepoint()) {
            if (x < iter.state.advance_width/2) {
                return 0;
            }
        } else {
            return 0;
        }
        var char_idx: u32 = 1;
        var cur_x: f32 = iter.state.advance_width;
        while (iter.nextCodepoint()) {
            if (x < cur_x + iter.state.advance_width/2) {
                return char_idx;
            }
            cur_x = @round(cur_x + iter.state.kern);
            cur_x += iter.state.advance_width;
            char_idx += 1;
        }
        return char_idx;
    }

    fn onKeyDown(self: *TextField, e: ui.KeyDownEvent) void {
        const ke = e.val;
        // User onKeyDown is fired first. In the future this could let the user cancel the default behavior.
        if (self.props.onKeyDown) |cb| {
            cb.call(.{ ui.WidgetRef(TextField).init(e.ctx.node), ke });
        }

        const inner = self.inner.getWidget();
        if (ke.code == .Backspace) {
            if (inner.caret_idx > 0) {
                if (self.buf.num_chars == inner.caret_idx) {
                    self.buf.removeChar(self.buf.num_chars-1);
                } else {
                    self.buf.removeChar(inner.caret_idx-1);
                }
                // self.postLineUpdate(self.caret_line);
                inner.caret_idx -= 1;
                inner.keepCaretFixedInView();
                inner.resetCaretAnim();
            }
        } else if (ke.code == .Delete) {
            if (inner.caret_idx < self.buf.num_chars) {
                self.buf.removeChar(inner.caret_idx);
                inner.keepCaretFixedInView();
                inner.resetCaretAnim();
            }
        } else if (ke.code == .Enter) {
            var hash: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(self.buf.buf.items, &hash, .{});
            if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
                self.fireOnChangeEnd();
                self.last_buf_hash = hash;
                inner.resetCaretAnim();
            }
        } else if (ke.code == .ArrowLeft) {
            if (inner.caret_idx > 0) {
                inner.caret_idx -= 1;
                inner.keepCaretInView();
                inner.resetCaretAnim();
            }
        } else if (ke.code == .ArrowRight) {
            if (inner.caret_idx < self.buf.num_chars) {
                inner.caret_idx += 1;
                inner.keepCaretInView();
                inner.resetCaretAnim();
            }
        } else {
            if (ke.getPrintChar()) |ch| {
                if (inner.caret_idx == self.buf.num_chars) {
                    self.buf.appendCodepoint(ch) catch @panic("error");
                } else {
                    self.buf.insertCodepoint(inner.caret_idx, ch) catch @panic("error");
                }
                // self.postLineUpdate(self.caret_line);
                inner.caret_idx += 1;
                inner.keepCaretInView();
                inner.resetCaretAnim();
            }
        }
    }

    pub fn layout(self: *TextField, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraint();
        const child = c.getNode().children.items[0];
        if (self.props.width) |width| {
            const child_size = c.computeLayoutStretch(child, ui.LayoutSize.init(width, cstr.height), true, c.prefer_exact_height);
            c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));
            return child_size;
        } else {
            const child_size = c.computeLayoutStretch(child, cstr, c.prefer_exact_width, c.prefer_exact_height);
            c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));
            return child_size;
        }
    }

    pub fn render(self: *TextField, c: *ui.RenderContext) void {
        _ = self;
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        // Background.
        g.setFillColor(self.props.bg_color);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        if (c.isFocused() and self.props.focused_show_border) {
            g.setStrokeColor(self.props.focused_border_color);
            g.setLineWidth(2);
            g.drawRect(alo.x, alo.y, alo.width, alo.height);
        }
    }
};

pub const TextFieldInner = struct {
    props: struct {
        text_color: Color = Color.Black,
        font_size: f32 = 20,
        font_id: graphics.FontId = NullId,
        placeholder: ?[]const u8 = null,
        text: []const u8 = "",
    },

    scroll_x: f32,
    text_width: f32,

    caret_idx: u32,
    caret_pos_x: f32,

    caret_anim_id: u32,
    caret_anim_show: bool,

    focused: bool,
    ctx: *ui.CommonContext,
    node: *ui.Node,

    /// [0,1]
    fixed_in_view: f32,

    pub fn init(self: *TextFieldInner, c: *ui.InitContext) void {
        self.scroll_x = 0;
        self.caret_idx = 0;
        self.caret_pos_x = 0;
        self.caret_anim_show = true;
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, onCaretInterval);
        self.focused = false;
        self.ctx = c.common;
        self.node = c.node;
    }

    pub fn postPropsUpdate(self: *TextFieldInner) void {
        // Make sure caret_idx is in bounds.
        if (self.caret_idx > self.props.text.len) {
            self.caret_idx = @intCast(u32, self.props.text.len);
        }
    }

    fn setFocused(self: *TextFieldInner) void {
        self.focused = true;
        self.resetCaretAnim();
    }

    fn resetCaretAnim(self: *TextFieldInner) void {
        self.caret_anim_show = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn onCaretInterval(self: *TextFieldInner, e: ui.IntervalEvent) void {
        _ = e;
        self.caret_anim_show = !self.caret_anim_show;
    }

    fn keepCaretFixedInView(self: *TextFieldInner) void {
        const S = struct {
            fn cb(self_: *TextFieldInner) void {
                self_.scroll_x = self_.caret_pos_x - self_.fixed_in_view * self_.node.layout.width;
                if (self_.scroll_x < 0) {
                    self_.scroll_x = 0;
                }
            }
        };
        self.fixed_in_view = (self.caret_pos_x - self.scroll_x) / self.node.layout.width;
        if (self.fixed_in_view < 0) {
            self.fixed_in_view = 0;
        } else if (self.fixed_in_view > 1) {
            self.fixed_in_view = 1;
        }
        self.ctx.nextPostLayout(self, S.cb);
    }

    fn keepCaretInView(self: *TextFieldInner) void {
        const S = struct {
            fn cb(self_: *TextFieldInner) void {
                const layout_width = self_.node.layout.width;

                if (self_.caret_pos_x > self_.scroll_x + layout_width - 2) {
                    // Caret is to the right of the view. Add a tiny padding since it's at the edge.
                    self_.scroll_x = self_.caret_pos_x - layout_width + 2;
                } else if (self_.caret_pos_x < self_.scroll_x) {
                    // Caret is to the left of the view
                    self_.scroll_x = self_.caret_pos_x;
                }
            }
        };
        self.ctx.nextPostLayout(self, S.cb);
    }

    pub fn layout(self: *TextFieldInner, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraint();

        const font_gid = c.getFontGroupForSingleFontOrDefault(self.props.font_id);
        const vmetrics = c.getPrimaryFontVMetrics(font_gid, self.props.font_size);
        const metrics = c.measureText(font_gid, self.props.font_size, self.props.text);
        self.text_width = metrics.width;
        self.caret_pos_x = c.measureText(font_gid, self.props.font_size, self.props.text[0..self.caret_idx]).width;

        var res = ui.LayoutSize.init(metrics.width, vmetrics.height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        } else if (res.width > cstr.width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *TextFieldInner, c: *ui.RenderContext) void {
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        const needs_clipping = self.scroll_x > 0 or alo.width < self.text_width;
        if (needs_clipping) {
            g.pushState();
            g.clipRect(alo.x, alo.y, alo.width, alo.height);
        }
        g.setFillColor(self.props.text_color);

        if (self.props.font_id == NullId) {
            g.setFont(g.getDefaultFontId(), self.props.font_size);
        } else {
            g.setFont(self.props.font_id, self.props.font_size);
        }
        g.fillText(alo.x - self.scroll_x, alo.y, self.props.text);

        if (self.props.text.len == 0) {
            if (self.props.placeholder) |placeholder| {
                g.setFillColor(Color.init(100, 100, 100, 255));
                g.fillText(alo.x, alo.y, placeholder);
            }
        }

        // Draw caret.
        if (self.focused) {
            if (self.caret_anim_show) {
                g.fillRect(@round(alo.x - self.scroll_x + self.caret_pos_x), alo.y, 1, alo.height);
            }
        }

        if (needs_clipping) {
            g.popState();
        }
    }
};