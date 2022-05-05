const std = @import("std");
const stdx = @import("stdx");
const Duration = stdx.time.Duration;
const platform = @import("platform");
const KeyDownEvent = platform.KeyDownEvent;
const graphics = @import("graphics");
const FontGroupId = graphics.font.FontGroupId;
const Color = graphics.Color;

const ui = @import("../ui.zig");
const Node = ui.Node;
const ScrollView = ui.widgets.ScrollView;

/// Note: This widget is very incomplete. It could borrow some techniques used in TextField.
/// Also this will be renamed to TextArea and expose a maxLines property as well as things that might be useful for an advanced TextEditor.
pub const TextEditor = struct {
    const Self = @This();

    props: struct {
        content: []const u8,
        font_family: ?[]const u8 = null,
        width: f32 = 400,
        height: f32 = 300,
        text_color: Color = Color.Black,
    },

    lines: std.ArrayList(Line),
    caret_line: usize,
    caret_col: usize,
    inner: ?ui.WidgetRef(TextEditorInner),
    scroll_view: ui.WidgetRef(ScrollView),

    // Current font group used.
    font_gid: FontGroupId,
    font_size: f32,
    font_vmetrics: graphics.font.VMetrics,
    font_line_height: u32,
    font_line_offset_y: f32, // y offset to first text line is drawn

    ctx: *ui.CommonContext,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        const props = self.props;

        var font_gid = c.getDefaultFontGroup();
        if (props.font_family) |font_family| {
            font_gid = c.getFontGroupBySingleFontName(font_family);
        }

        self.lines = std.ArrayList(Line).init(c.alloc);
        self.caret_line = 0;
        self.caret_col = 0;
        self.inner = null;
        self.scroll_view = undefined;
        self.ctx = c.common;
        self.font_gid = font_gid;
        self.setFontSize(24);

        var iter = std.mem.split(u8, props.content, "\n");
        self.lines = std.ArrayList(Line).init(c.alloc);
        while (iter.next()) |it| {
            const measure = c.createTextMeasure(font_gid, self.font_size);
            var line = Line.init(c.alloc, measure);
            line.text.appendSlice(it) catch unreachable;
            self.lines.append(line) catch unreachable;
        }

        // Ensure at least one line.
        if (self.lines.items.len == 0) {
            const measure = c.createTextMeasure(font_gid, self.font_size);
            const line = Line.init(c.alloc, measure);
            self.lines.append(line) catch unreachable;
        }

        c.addKeyDownHandler(self, Self.handleKeyDownEvent);
    }

    pub fn deinit(node: *Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        for (self.lines.items) |line| {
            line.text.deinit();
        }
        self.lines.deinit();
    }

    pub fn setFontSize(self: *Self, font_size: f32) void {
        const font_vmetrics = self.ctx.getPrimaryFontVMetrics(self.font_gid, font_size);
        // log.warn("METRICS {}", .{font_vmetrics});
        self.font_size = font_size;

        const font_line_height_factor: f32 = 1.2;
        const font_line_height = @round(font_line_height_factor * font_size);
        const font_line_offset_y = (font_line_height - font_vmetrics.ascender) / 2;
        // log.warn("{} {} {}", .{font_vmetrics.height, font_line_height, font_line_offset_y});

        self.font_vmetrics = font_vmetrics;
        self.font_line_height = @floatToInt(u32, font_line_height);
        self.font_line_offset_y = font_line_offset_y;

        for (self.lines.items) |line| {
            self.ctx.getTextMeasure(line.measure).setFont(self.font_gid, font_size);
        }

        if (self.inner) |inner| {
            self.ctx.getTextMeasure(inner.widget.to_caret_measure).setFont(self.font_gid, font_size);
        }
    }

    // fn destroyLine(self: *Self, c: *ModuleContext, line: Line) void {
    //     _ = self;
    //     c.destroyTextMeasure(line.measure);
    //     line.deinit();
    // }

    pub fn postInit(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.inner = c.findChildWidgetByType(TextEditorInner).?;
        self.scroll_view = c.findChildWidgetByType(ScrollView).?;
    }

    fn getCaretBottomY(self: *Self) f32 {
        return @intToFloat(f32, self.caret_line + 1) * @intToFloat(f32, self.font_line_height);
    }

    fn getCaretTopY(self: *Self) f32 {
        return @intToFloat(f32, self.caret_line) * @intToFloat(f32, self.font_line_height);
    }

    fn getCaretX(self: *Self) f32 {
        return self.ctx.getTextMeasure(self.inner.?.widget.to_caret_measure).metrics().width;
    }

    fn postLineUpdate(self: *Self, idx: usize) void {
        const line = &self.lines.items[idx];
        self.ctx.getTextMeasure(line.measure).setText(line.text.items);
        self.inner.?.widget.resetCaretAnimation();
    }

    fn postCaretUpdate(self: *Self) void {
        self.inner.?.widget.postCaretUpdate();

        // Scroll to caret.
        const S = struct {
            fn cb(self_: *Self) void {
                const sv = self_.scroll_view;

                const caret_x = self_.getCaretX();
                const caret_bottom_y = self_.getCaretBottomY();
                const caret_top_y = self_.getCaretTopY();
                const view_width = sv.getWidth();
                const view_height = sv.getHeight();

                if (caret_bottom_y > sv.widget.scroll_y + view_height) {
                    // Below current view
                    sv.widget.setScrollPosAfterLayout(sv.node, sv.widget.scroll_x, caret_bottom_y - view_height);
                } else if (caret_top_y < sv.widget.scroll_y) {
                    // Above current view
                    sv.widget.setScrollPosAfterLayout(sv.node, sv.widget.scroll_x, caret_top_y);
                }
                if (caret_x > sv.widget.scroll_x + view_width) {
                    // Right of current view
                    sv.widget.setScrollPosAfterLayout(sv.node, caret_x - view_width, sv.widget.scroll_y);
                } else if (caret_x < sv.widget.scroll_x) {
                    // Left of current view
                    sv.widget.setScrollPosAfterLayout(sv.node, caret_x, sv.widget.scroll_y);
                }
            }
        };
        self.ctx.nextPostLayout(self, S.cb);
    }

    fn handleKeyDownEvent(self: *Self, e: ui.Event(KeyDownEvent)) void {
        _ = self;
        const c = e.ctx.common;
        const val = e.val;
        const line = &self.lines.items[self.caret_line];
        if (val.code == .Backspace) {
            if (self.caret_col > 0) {
                if (line.text.items.len == self.caret_col) {
                    line.text.resize(line.text.items.len-1) catch unreachable;
                } else {
                    _ = line.text.orderedRemove(self.caret_col);
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col -= 1;
                self.postCaretUpdate();
            } else if (self.caret_line > 0) {
                // Join current line with previous.
                var prev_line = self.lines.items[self.caret_line-1];
                self.caret_col = prev_line.text.items.len;
                prev_line.text.appendSlice(line.text.items) catch unreachable;
                line.deinit();
                _ = self.lines.orderedRemove(self.caret_line);
                self.postLineUpdate(self.caret_line-1);

                self.caret_line -= 1;
                self.postCaretUpdate();
            }
        } else if (val.code == .Enter) {
            const measure = c.createTextMeasure(self.font_gid, self.font_size);
            const new_line = Line.init(c.alloc, measure);
            self.lines.insert(self.caret_line + 1, new_line) catch unreachable;
            self.postLineUpdate(self.caret_line + 1);

            self.caret_line += 1;
            self.caret_col = 0;
            self.postCaretUpdate();
        } else {
            if (val.getPrintChar()) |ch| {
                if (self.caret_col == line.text.items.len) {
                    line.text.append(ch) catch unreachable;
                } else {
                    line.text.insert(self.caret_col, ch) catch unreachable;
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col += 1;
                self.postCaretUpdate();
            }
        }
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        _ = self;
        return c.decl(ScrollView, .{
            .child = c.decl(TextEditorInner, .{
                .editor = self,
            }),
        });
    }
};

const Line = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    text: std.ArrayList(u8),

    measure: ui.TextMeasureId,

    fn init(alloc: std.mem.Allocator, measure: ui.TextMeasureId) Self {
        return .{
            .alloc = alloc,
            .text = std.ArrayList(u8).init(alloc),
            .measure = measure,
        };
    }

    fn deinit(self: Self) void {
        self.text.deinit();
    }
};

pub const TextEditorInner = struct {
    const Self = @This();

    props: struct {
        editor: *TextEditor,
    },

    caret_anim_show_toggle: bool,
    caret_anim_id: ui.IntervalId,
    to_caret_measure: ui.TextMeasureId,
    editor: *TextEditor,
    ctx: *ui.CommonContext,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        const props = self.props;
        self.to_caret_measure = c.createTextMeasure(props.editor.font_gid, props.editor.font_size);
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, Self.handleCaretInterval);
        self.caret_anim_show_toggle = true;
        self.editor = props.editor;
        self.ctx = c.common;
    }

    fn resetCaretAnimation(self: *Self) void {
        self.caret_anim_show_toggle = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn postCaretUpdate(self: *Self) void {
        const line = self.editor.lines.items[self.editor.caret_line].text.items;
        self.ctx.getTextMeasure(self.to_caret_measure).setText(line[0..self.editor.caret_col]);
    }

    fn handleCaretInterval(self: *Self, e: ui.IntervalEvent) void {
        _ = e;
        self.caret_anim_show_toggle = !self.caret_anim_show_toggle;
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        _ = self;
        _ = c;
        return ui.NullFrameId;
    }

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        var height: f32 = 0;
        var max_width: f32 = 0;
        for (self.editor.lines.items) |it| {
            const metrics = c.common.getTextMeasure(it.measure).metrics();
            if (metrics.width > max_width) {
                max_width = metrics.width;
            }
            height += @intToFloat(f32, self.editor.font_line_height);
        }
        return ui.LayoutSize.init(max_width, height);
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        _ = self;
        const editor = self.editor;

        const lo = c.getAbsLayout();

        const g = c.getGraphics();
        const line_height = @intToFloat(f32, editor.font_line_height);

        g.setFont(editor.font_gid, editor.font_size);
        g.setFillColor(self.editor.props.text_color);
        // TODO: Use binary search when word wrap is enabled and we can't determine the first visible line with O(1)
        const visible_start_idx = std.math.max(0, @floatToInt(i32, @floor(editor.scroll_view.widget.scroll_y / line_height)));
        const visible_end_idx = std.math.min(editor.lines.items.len, @floatToInt(i32, @ceil((editor.scroll_view.widget.scroll_y + editor.scroll_view.getHeight()) / line_height)));
        // log.warn("{} {}", .{visible_start_idx, visible_end_idx});
        const line_offset_y = editor.font_line_offset_y;
        var i: usize = @intCast(usize, visible_start_idx);
        while (i < visible_end_idx) : (i += 1) {
            const line = editor.lines.items[i];
            g.fillText(lo.x, lo.y + line_offset_y + @intToFloat(f32, i) * line_height, line.text.items);
        }

        // Draw caret.
        if (self.caret_anim_show_toggle) {
            g.setFillColor(self.editor.props.text_color);
            const width = c.common.getTextMeasure(self.to_caret_measure).metrics().width;
            // log.warn("width {d:2}", .{width});
            const height = self.editor.font_vmetrics.height;
            g.fillRect(@round(lo.x + width), lo.y + @intToFloat(f32, self.editor.caret_line) * line_height, 1, height);
        }
    }
};