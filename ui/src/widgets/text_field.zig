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
const Node = ui.Node;
const Padding = ui.widgets.Padding;
const log = stdx.log.scoped(.text_field);

/// Handles a single line of text input.
pub const TextField = struct {
    const Self = @This();

    props: struct {
        text_color: Color = Color.Black,
        font_size: f32 = 20,
        onChangeEnd: ?Function([]const u8) = null,
        padding: f32 = 10,
        width: ?f32 = null,
    },

    buf: std.ArrayList(u8),
    font_gid: graphics.font.FontGroupId,

    inner: ui.WidgetRef(TextFieldInner),

    /// Used to determine if the text changed since it received focus.
    last_buf_hash: [16]u8,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.buf = std.ArrayList(u8).init(c.alloc);
        self.font_gid = c.getDefaultFontGroup();
        self.last_buf_hash = undefined;
        c.addKeyDownHandler(self, Self.onKeyDown);
        c.addMouseDownHandler(self, Self.onMouseDown);
    }

    pub fn deinit(node: *Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        self.buf.deinit();
    }

    pub fn setValueFmt(self: *Self, comptime format: []const u8, args: anytype) void {
        self.buf.resize(@intCast(usize, std.fmt.count(format, args))) catch unreachable;
        _ = std.fmt.bufPrint(self.buf.items, format, args) catch unreachable;
    }

    pub fn getValue(self: Self) []const u8 {
        return self.buf.items;
    }

    fn onMouseDown(self: *Self, e: ui.Event(MouseDownEvent)) void {
        e.ctx.requestFocus(onBlur);
        self.inner.widget.setFocused();
        std.crypto.hash.Md5.hash(self.buf.items, &self.last_buf_hash, .{});

        // Map mouse pos to caret pos.
        const xf = @intToFloat(f32, e.val.x);
        self.inner.widget.caret_idx = self.getCaretIdx(e.ctx.common, xf - self.inner.node.abs_pos.x + self.inner.widget.scroll_x);
    }

    fn onBlur(node: *Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        const self = node.getWidget(Self);
        self.inner.widget.focused = false;
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(self.buf.items, &hash, .{});
        if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
            self.fireOnChangeEnd();
        }
    }

    fn fireOnChangeEnd(self: *Self) void {
        if (self.props.onChangeEnd) |cb| {
            cb.call(self.buf.items);
        }
    }

    fn getCaretIdx(self: *Self, ctx: *ui.CommonContext, x: f32) u32 {
        var iter = ctx.measureTextIter(self.font_gid, self.props.font_size, self.buf.items);
        if (iter.nextCodepoint()) {
            if (x < iter.state.advance_width/2) {
                return 0;
            }
        } else {
            return 0;
        }
        var idx: u32 = 1;
        var cur_x: f32 = iter.state.advance_width;
        while (iter.nextCodepoint()) {
            if (x < cur_x + iter.state.advance_width/2) {
                return idx;
            }
            cur_x = @round(cur_x + iter.state.kern);
            cur_x += iter.state.advance_width;
            idx += 1;
        }
        return idx;
    }

    fn onKeyDown(self: *Self, e: ui.Event(KeyDownEvent)) void {
        _ = self;
        const ke = e.val;
        if (ke.code == .Backspace) {
            if (self.inner.widget.caret_idx > 0) {
                if (self.buf.items.len == self.inner.widget.caret_idx) {
                    self.buf.resize(self.buf.items.len-1) catch unreachable;
                } else {
                    _ = self.buf.orderedRemove(self.inner.widget.caret_idx-1);
                }
                // self.postLineUpdate(self.caret_line);
                self.inner.widget.caret_idx -= 1;
                self.inner.widget.keepCaretFixedInView();
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .Delete) {
            if (self.inner.widget.caret_idx < self.buf.items.len) {
                _ = self.buf.orderedRemove(self.inner.widget.caret_idx);
                self.inner.widget.keepCaretFixedInView();
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .Enter) {
            var hash: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(self.buf.items, &hash, .{});
            if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
                self.fireOnChangeEnd();
                self.last_buf_hash = hash;
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .ArrowLeft) {
            if (self.inner.widget.caret_idx > 0) {
                self.inner.widget.caret_idx -= 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        } else if (ke.code == .ArrowRight) {
            if (self.inner.widget.caret_idx < self.buf.items.len) {
                self.inner.widget.caret_idx += 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        } else {
            if (ke.getPrintChar()) |ch| {
                if (self.inner.widget.caret_idx == self.buf.items.len) {
                    self.buf.append(ch) catch unreachable;
                } else {
                    self.buf.insert(self.inner.widget.caret_idx, ch) catch unreachable;
                }
                // self.postLineUpdate(self.caret_line);
                self.inner.widget.caret_idx += 1;
                self.inner.widget.keepCaretInView();
                self.inner.widget.resetCaretAnim();
            }
        }
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        return c.decl(Padding, .{
            .padding = self.props.padding,
            .child = c.decl(TextFieldInner, .{
                .bind = &self.inner,
                .text = self.buf.items,
                .font_size = self.props.font_size,
                .font_gid = self.font_gid,
            }),
        });
    }

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
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

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        _ = self;
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        // Background.
        g.setFillColor(Color.White);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);

        if (c.isFocused()) {
            g.setStrokeColor(Color.Blue);
            g.setLineWidth(2);
            g.drawRect(alo.x, alo.y, alo.width, alo.height);
        }
    }
};

pub const TextFieldInner = struct {
    const Self = @This();

    props: struct {
        text_color: Color = Color.Black,
        font_size: f32 = 20,
        font_gid: graphics.font.FontGroupId,
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
    node: *Node,

    /// [0,1]
    fixed_in_view: f32,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.scroll_x = 0;
        self.caret_idx = 0;
        self.caret_pos_x = 0;
        self.caret_anim_show = true;
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, onCaretInterval);
        self.focused = false;
        self.ctx = c.common;
        self.node = c.node;
    }

    pub fn postUpdate(self: *Self) void {
        // Make sure caret_idx is in bounds.
        if (self.caret_idx > self.props.text.len) {
            self.caret_idx = @intCast(u32, self.props.text.len);
        }
    }

    fn setFocused(self: *Self) void {
        self.focused = true;
        self.resetCaretAnim();
    }

    fn resetCaretAnim(self: *Self) void {
        self.caret_anim_show = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn onCaretInterval(self: *Self, e: ui.IntervalEvent) void {
        _ = e;
        self.caret_anim_show = !self.caret_anim_show;
    }

    fn keepCaretFixedInView(self: *Self) void {
        const S = struct {
            fn cb(self_: *Self) void {
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

    fn keepCaretInView(self: *Self) void {
        const S = struct {
            fn cb(self_: *Self) void {
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

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        const cstr = c.getSizeConstraint();

        const vmetrics = c.getPrimaryFontVMetrics(self.props.font_gid, self.props.font_size);
        const metrics = c.measureText(self.props.font_gid, self.props.font_size, self.props.text);
        self.text_width = metrics.width;
        self.caret_pos_x = c.measureText(self.props.font_gid, self.props.font_size, self.props.text[0..self.caret_idx]).width;

        var res = ui.LayoutSize.init(metrics.width, vmetrics.height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        } else if (res.width > cstr.width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        const alo = c.getAbsLayout();
        const g = c.getGraphics();

        const needs_clipping = self.scroll_x > 0 or alo.width < self.text_width;
        if (needs_clipping) {
            g.pushState();
            g.clipRect(alo.x, alo.y, alo.width, alo.height);
        }
        g.setFillColor(self.props.text_color);
        g.setFontGroup(self.props.font_gid, self.props.font_size);
        g.fillText(alo.x - self.scroll_x, alo.y, self.props.text);

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