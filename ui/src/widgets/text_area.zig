const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const fatal = stdx.fatal;
const Duration = stdx.time.Duration;
const platform = @import("platform");
const KeyDownEvent = platform.KeyDownEvent;
const graphics = @import("graphics");
const FontGroupId = graphics.FontGroupId;
const Color = graphics.Color;

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.text_area);

// TODO: Mimic features from TextField.
// TODO: Expose maxLines property.
// TODO: Expose properties that could be useful for a TextEditor.
pub const TextArea = struct {
    props: struct {
        initValue: []const u8,
        width: f32 = 400,
        height: f32 = 300,
        onBlur: stdx.Function(fn () void) = .{},
        onKeyDown: stdx.Function(fn (ui.WidgetRef(TextArea), platform.KeyDownEvent) ui.EventResult) = .{},
    },

    lines: std.ArrayList(Line),

    caret_line: u32,
    caret_col: u32,
    inner: ui.WidgetRef(TextAreaInner),
    scroll_view: ui.WidgetRef(u.ScrollViewT),

    // Current font group used.
    font_gid: FontGroupId,
    font_size: f32,
    font_vmetrics: graphics.VMetrics,
    font_line_height: u32,
    font_line_offset_y: f32, // y offset to first text line is drawn
    needs_remeasure_font: bool,

    ctx: *ui.CommonContext,
    alloc: std.mem.Allocator,
    node: *ui.Node,

    // Faster access to current padding.
    padding: f32,

    hasSelection: bool,
    selectionStart: DocLocation,
    selectionEnd: DocLocation,
    selectionOrigin: DocLocation,

    pub const Style = struct {
        padding: ?f32 = null,
        bgColor: ?Color = null,
        color: ?Color = null,
        fontSize: ?f32 = null,
        fontFamily: ?graphics.FontFamily = null,
    };

    pub const ComputedStyle = struct {
        padding: f32 = 10,
        bgColor: Color = Color.White,
        color: Color = Color.Black,
        fontSize: f32 = 18,
        fontFamily: graphics.FontFamily = graphics.FontFamily.Default,
    };

    pub fn init(self: *TextArea, c: *ui.InitContext) void {
        const style = c.getStyle(TextArea);
        const props = self.props;

        self.font_gid = c.getFontGroupByFamily(style.fontFamily);
        self.font_size = style.fontSize;
        self.needs_remeasure_font = true;

        self.lines = std.ArrayList(Line).init(c.alloc);
        self.caret_line = 0;
        self.caret_col = 0;
        self.inner = .{};
        self.scroll_view = .{};
        self.ctx = c.common;
        self.node = c.node;
        self.alloc = c.alloc;
        self.padding = style.padding;

        self.hasSelection = false;
        self.selectionStart = undefined;
        self.selectionEnd = undefined;

        self.setText(props.initValue);
        c.setKeyDownHandler(self, onKeyDown);
    }

    pub fn deinit(self: *TextArea, _: *ui.DeinitContext) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    pub fn build(self: *TextArea, c: *ui.BuildContext) ui.FramePtr {
        const style = c.getStyle(TextArea);

        const sv_style = u.ScrollViewStyle{
            .bgColor = style.bgColor,
        };
        return u.ScrollView(.{
            .bind = &self.scroll_view,
            .style = sv_style,
            .onContentMouseDown = c.funcExt(self, onMouseDown) },
            u.Padding(.{ .padding = style.padding },
                c.build(TextAreaInner, .{
                    .bind = &self.inner,
                    .editor = self,
                }),
            ),
        );
    }

    pub fn postPropsUpdate(self: *TextArea, ctx: *ui.UpdateContext) void {
        const style = ctx.getStyle(TextArea);
        const new_font_gid = self.ctx.getFontGroupByFamily(style.fontFamily);
        if (new_font_gid != self.font_gid) {
            self.font_gid = new_font_gid;
            if (!self.needs_remeasure_font) {
                self.queueRemeasureFont();
            }
        }
        if (style.fontSize != self.font_size) {
            self.font_size = style.fontSize;
            if (!self.needs_remeasure_font) {
                self.queueRemeasureFont();
            }
        }
        self.padding = style.padding;
    }

    fn onMouseDown(self: *TextArea, e: platform.MouseDownEvent) ui.EventResult {
        self.requestFocus();

        // Map mouse pos to caret pos.
        const scroll_view = self.scroll_view.getWidget();
        const xf = @intToFloat(f32, e.x) - self.node.abs_bounds.min_x + scroll_view.scroll_x;
        const yf = @intToFloat(f32, e.y) - self.node.abs_bounds.min_y + scroll_view.scroll_y;
        const loc = self.toCaretLoc(self.ctx, xf, yf);

        self.caret_line = loc.lineIdx;
        self.caret_col = loc.colIdx;
        self.postCaretUpdate();

        return .stop;
    }

    /// Should be called before layout.
    pub fn setText(self: *TextArea, text: []const u8) void {
        self.clear();

        var iter = std.mem.split(u8, text, "\n");
        while (iter.next()) |it| {
            var line = Line.init(self.alloc);
            _ = line.buf.appendSubStr(it) catch fatal();
            line.needs_measure = true;
            self.lines.append(line) catch fatal();
        }

        // Ensure at least one line.
        if (self.lines.items.len == 0) {
            const line = Line.init(self.alloc);
            self.lines.append(line) catch unreachable;
        }
    }

    pub fn allocText(self: TextArea, alloc: std.mem.Allocator) ![]const u8 {
        var res: std.ArrayListUnmanaged(u8) = .{};
        for (self.lines.items) |line| {
            try res.appendSlice(alloc, line.buf.buf.items);
            try res.append(alloc, '\n');
        }
        return res.toOwnedSlice(alloc);
    }

    /// Should be called before layout.
    pub fn clear(self: *TextArea) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.clearRetainingCapacity();
    }

    /// Request focus on the TextArea.
    pub fn requestFocus(self: *TextArea) void {
        self.ctx.requestFocus(self.node, .{ .onBlur = onBlur, .onPaste = onPaste });
        const inner = self.inner.getWidget();
        inner.setFocused();
        // std.crypto.hash.Md5.hash(self.buf.items, &self.last_buf_hash, .{});
    }

    fn onPaste(node: *ui.Node, _: *ui.CommonContext, str: []const u8) void {
        const self = node.getWidget(TextArea);
        self.paste(str);
    }

    fn paste(self: *TextArea, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        var iter = std.mem.split(u8, str, "\n");
        // First line inserts to the caret pos.
        const first = iter.next().?;
        var num_new_chars = self.lines.items[self.caret_line].buf.insertSubStr(self.caret_col, first) catch fatal();
        self.postLineUpdate(self.caret_line);
        self.caret_col += num_new_chars;

        while (iter.next()) |line| {
            self.caret_line += 1;

            // Insert a new line.
            var new_line = Line.init(self.alloc);
            num_new_chars = new_line.buf.appendSubStr(line) catch fatal();
            self.lines.insert(self.caret_line, new_line) catch fatal();
            self.postLineUpdate(self.caret_line);

            self.caret_col = num_new_chars;
        }

        self.postCaretUpdate();
        self.postCaretActivity();
    }

    fn onBlur(node: *ui.Node, ctx: *ui.CommonContext) void {
        _ = ctx;
        const self = node.getWidget(TextArea);
        self.inner.getWidget().focused = false;
        // var hash: [16]u8 = undefined;
        // std.crypto.hash.Md5.hash(self.buf.items, &hash, .{});
        // if (!std.mem.eql(u8, &hash, &self.last_buf_hash)) {
        //     self.fireOnChangeEnd();
        // }

        if (self.props.onBlur.isPresent()) {
            self.props.onBlur.call(.{});
        }
    }

    fn toCaretLoc(self: *TextArea, ctx: *ui.CommonContext, x_: f32, y_: f32) DocLocation {
        // Account for padding.
        const x = x_ - self.padding;
        const y = y_ - self.padding;
        if (y < 0) {
            return .{
                .lineIdx = 0,
                .colIdx = 0,
            };
        }
        const line_idx = @floatToInt(u32, y / @intToFloat(f32, self.font_line_height));
        if (line_idx >= self.lines.items.len) {
            return .{
                .lineIdx = @intCast(u32, self.lines.items.len - 1),
                .colIdx = @intCast(u32, self.lines.items[self.lines.items.len-1].buf.num_chars),
            };
        }

        var iter = ctx.textGlyphIter(self.font_gid, self.font_size, self.lines.items[line_idx].buf.buf.items);
        if (iter.nextCodepoint()) {
            if (x < iter.state.advance_width/2) {
                return .{
                    .lineIdx = line_idx,
                    .colIdx = 0,
                };
            }
        } else {
            return .{
                .lineIdx = line_idx,
                .colIdx = 0,
            };
        }
        var cur_x: f32 = iter.state.advance_width;
        var col: u32 = 1;
        while (iter.nextCodepoint()) {
            if (x < cur_x + iter.state.advance_width/2) {
                return .{
                    .lineIdx = line_idx,
                    .colIdx = col,
                };
            }
            cur_x = @round(cur_x + iter.state.kern);
            cur_x += iter.state.advance_width;
            col += 1;
        }
        return .{
            .lineIdx = line_idx,
            .colIdx = col,
        };
    }

    fn queueRemeasureFont(self: *TextArea) void {
        self.needs_remeasure_font = true;

        for (self.lines.items) |*line| {
            line.needs_measure = true;
        }

        if (self.inner.binded) {
            const widget = self.inner.getWidget();
            widget.to_caret_needs_measure = true;
        }
    }

    fn getCaretBottomY(self: *TextArea) f32 {
        return @intToFloat(f32, self.caret_line + 1) * @intToFloat(f32, self.font_line_height) + self.padding;
    }

    fn getCaretTopY(self: *TextArea) f32 {
        return @intToFloat(f32, self.caret_line) * @intToFloat(f32, self.font_line_height) + self.padding;
    }

    fn getCaretX(self: *TextArea) f32 {
        return self.inner.getWidget().to_caret_width + self.padding;
    }

    fn postLineUpdate(self: *TextArea, idx: usize) void {
        const line = &self.lines.items[idx];
        line.needs_measure = true;
    }

    /// After something was done at the caret position.
    /// This would provide a hint to the user that they performed some action.
    fn postCaretActivity(self: *TextArea) void {
        self.inner.getWidget().resetCaretAnimation();
    }

    /// After caret position was changed or the text to the caret pos has changed.
    fn postCaretUpdate(self: *TextArea) void {
        self.inner.getWidget().postCaretUpdate();

        // Scroll to caret.
        const S = struct {
            fn cb(self_: *TextArea) void {
                const sv = self_.scroll_view.getWidget();
                const svn = self_.scroll_view.node;

                const caret_x = self_.getCaretX();
                const caret_bottom_y = self_.getCaretBottomY();
                const caret_top_y = self_.getCaretTopY();
                const view_width = self_.scroll_view.getWidth();
                const view_height = self_.scroll_view.getHeight();

                if (caret_bottom_y > sv.scroll_y + view_height) {
                    // Below current view
                    sv.setScrollPosAfterLayout(svn, sv.scroll_x, caret_bottom_y - view_height);
                } else if (caret_top_y < sv.scroll_y) {
                    // Above current view
                    sv.setScrollPosAfterLayout(svn, sv.scroll_x, caret_top_y);
                }
                const CaretRightPadding = 5;
                if (caret_x > sv.scroll_x + view_width - CaretRightPadding) {
                    // Right of current view
                    sv.setScrollPosAfterLayout(svn, caret_x - view_width + CaretRightPadding, sv.scroll_y);
                } else if (caret_x < sv.scroll_x) {
                    // Left of current view
                    sv.setScrollPosAfterLayout(svn, caret_x, sv.scroll_y);
                }
            }
        };
        self.ctx.nextPostLayout(self, S.cb);
    }

    pub fn getCaretLineBuffer(self: *TextArea) *const stdx.textbuf.TextBuffer {
        return &self.lines.items[self.caret_line].buf;
    }

    pub fn getCodepointBeforeCaret(self: *TextArea) ?u21 {
        if (self.caret_col > 0) {
            return self.lines.items[self.caret_line].buf.getCodepointAt(self.caret_col - 1);
        } else return null;
    }

    /// Assume no new lines.
    pub fn caretInsert(self: *TextArea, str: []const u8) !void {
        const line = &self.lines.items[self.caret_line];
        if (self.caret_col == line.buf.num_chars) {
            self.caret_col += try line.buf.appendSubStr(str);
        } else {
            self.caret_col += try line.buf.insertSubStr(self.caret_col, str);
        }
        self.postLineUpdate(self.caret_line);

        self.postCaretUpdate();
        self.postCaretActivity();
    }

    pub fn caretInsertNewLine(self: *TextArea) !void {
        const new_line = Line.init(self.ctx.alloc);
        try self.lines.insert(self.caret_line + 1, new_line);
        // Requery current line since insert could have resized array.
        const cur_line = &self.lines.items[self.caret_line];
        if (self.caret_col < cur_line.buf.num_chars) {
            // Move text after caret to the new line.
            const after_text = cur_line.buf.getSubStr(self.caret_col, cur_line.buf.num_chars);
            _ = try self.lines.items[self.caret_line+1].buf.appendSubStr(after_text);
            cur_line.buf.removeSubStr(self.caret_col, cur_line.buf.num_chars);
            self.postLineUpdate(self.caret_line);
        }
        self.postLineUpdate(self.caret_line + 1);

        self.caret_line += 1;
        self.caret_col = 0;
        self.postCaretUpdate();
        self.postCaretActivity();
    }

    fn onKeyDown(self: *TextArea, e: ui.KeyDownEvent) void {
        const val = e.val;

        if (self.props.onKeyDown.isPresent()) {
            if (self.props.onKeyDown.call(.{ ui.WidgetRef(TextArea).init(self.node), e.val }) == .stop) {
                return;
            }
        }

        var line = &self.lines.items[self.caret_line];
        const prevCaretLine = self.caret_line;
        const prevCaretCol = self.caret_col;
        var cancelSelect = true;
        if (val.code == .Backspace) {
            if (self.caret_col > 0) {
                if (line.buf.num_chars == self.caret_col) {
                    line.buf.removeChar(line.buf.num_chars-1);
                } else {
                    line.buf.removeChar(self.caret_col-1);
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col -= 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            } else if (self.caret_line > 0) {
                // Join current line with previous.
                var prev_line = &self.lines.items[self.caret_line-1];
                self.caret_col = prev_line.buf.num_chars;
                _ = prev_line.buf.appendSubStr(line.buf.buf.items) catch @panic("error");
                line.deinit();
                _ = self.lines.orderedRemove(self.caret_line);
                self.postLineUpdate(self.caret_line-1);

                self.caret_line -= 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            }
        } else if (val.code == .Delete) {
            if (self.caret_col < line.buf.num_chars) {
                line.buf.removeChar(self.caret_col);
                self.postLineUpdate(self.caret_line);
                self.postCaretActivity();
            } else {
                // Append next line.
                if (self.caret_line < self.lines.items.len-1) {
                    _ = line.buf.appendSubStr(self.lines.items[self.caret_line+1].buf.buf.items) catch @panic("error");
                    self.lines.items[self.caret_line+1].deinit();
                    _ = self.lines.orderedRemove(self.caret_line+1);
                    self.postLineUpdate(self.caret_line);
                    self.postCaretActivity();
                }
            }
        } else if (val.code == .Enter) {
            self.caretInsertNewLine() catch fatal();
        } else if (val.code == .ArrowLeft) {
            if (self.caret_col > 0) {
                self.caret_col -= 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            } else {
                if (self.caret_line > 0) {
                    self.caret_line -= 1;
                    self.caret_col = self.lines.items[self.caret_line].buf.num_chars;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                }
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLine, prevCaretCol);
            }
        } else if (val.code == .ArrowRight) {
            if (self.caret_col < line.buf.num_chars) {
                self.caret_col += 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            } else {
                if (self.caret_line < self.lines.items.len-1) {
                    self.caret_line += 1;
                    self.caret_col = 0;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                }
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLine, prevCaretCol);
            }
        } else if (val.code == .ArrowUp) {
            if (self.caret_line > 0) {
                self.caret_line -= 1;
                if (self.caret_col > self.lines.items[self.caret_line].buf.num_chars) {
                    self.caret_col = self.lines.items[self.caret_line].buf.num_chars;
                }
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLine, prevCaretCol);
            }
        } else if (val.code == .ArrowDown) {
            if (self.caret_line < self.lines.items.len-1) {
                self.caret_line += 1;
                if (self.caret_col > self.lines.items[self.caret_line].buf.num_chars) {
                    self.caret_col = self.lines.items[self.caret_line].buf.num_chars;
                }
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLine, prevCaretCol);
            }
        } else if (val.code == .V and val.isControlPressed()) {
            if (!IsWasm) {
                const clipboard = platform.allocClipboardText(self.alloc) catch fatal();
                defer self.alloc.free(clipboard);
                self.paste(clipboard);
            }
        } else {
            if (val.getPrintChar()) |ch| {
                if (self.hasSelection) {
                    // Remove selection first.
                    self.deleteSelection();
                    line = &self.lines.items[self.caret_line];
                }
                if (self.caret_col == line.buf.num_chars) {
                    line.buf.appendCodepoint(ch) catch @panic("error");
                } else {
                    line.buf.insertCodepoint(self.caret_col, ch) catch @panic("error");
                }
                self.postLineUpdate(self.caret_line);

                self.caret_col += 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            }
        }

        if (cancelSelect and self.hasSelection) {
            self.hasSelection = false;
        }
    }

    fn deleteSelection(self: *TextArea) void {
        if (self.hasSelection) {
            const line = &self.lines.items[self.selectionStart.lineIdx];
            if (self.selectionEnd.lineIdx == self.selectionStart.lineIdx) {
                line.buf.removeSubStr(self.selectionStart.colIdx, self.selectionEnd.colIdx);
            } else {
                line.buf.removeSubStr(self.selectionStart.colIdx, line.buf.numCodepoints());
                const lastLine = self.lines.items[self.selectionEnd.lineIdx];
                const lastSegment = lastLine.buf.getSubStr(self.selectionEnd.colIdx, lastLine.buf.numCodepoints());
                _ = line.buf.appendSubStr(lastSegment) catch fatal();
                self.lines.replaceRange(self.selectionStart.lineIdx+1, self.selectionEnd.lineIdx - self.selectionStart.lineIdx, &.{}) catch fatal();
            }
            self.caret_line = self.selectionStart.lineIdx;
            self.caret_col = self.selectionStart.colIdx;
            self.hasSelection = false;
        }
    }

    fn selectFrom(self: *TextArea, prevCaretLine: u32, prevCaretCol: u32) void {
        if (self.hasSelection) {
            if (self.caret_line == self.selectionOrigin.lineIdx and self.caret_col == self.selectionOrigin.lineIdx) {
                self.hasSelection = false;
            } else {
                if (self.caret_line < self.selectionOrigin.lineIdx or (self.caret_line == self.selectionOrigin.lineIdx and self.caret_col < self.selectionOrigin.colIdx)) {
                    self.selectionStart.lineIdx = self.caret_line;
                    self.selectionStart.colIdx = self.caret_col;
                    self.selectionEnd.lineIdx = self.selectionOrigin.lineIdx;
                    self.selectionEnd.colIdx = self.selectionOrigin.colIdx;
                } else {
                    self.selectionStart.lineIdx = self.selectionOrigin.lineIdx;
                    self.selectionStart.colIdx = self.selectionOrigin.colIdx;
                    self.selectionEnd.lineIdx = self.caret_line;
                    self.selectionEnd.colIdx = self.caret_col;
                }
            }
        } else {
            self.hasSelection = true;
            self.selectionOrigin.lineIdx = prevCaretLine;
            self.selectionOrigin.colIdx = prevCaretCol;
            if (self.caret_line < prevCaretLine or (self.caret_line == prevCaretLine and self.caret_col < prevCaretCol)) {
                self.selectionStart.lineIdx = self.caret_line;
                self.selectionStart.colIdx = self.caret_col;
                self.selectionEnd.lineIdx = prevCaretLine;
                self.selectionEnd.colIdx = prevCaretCol;
            } else {
                self.selectionStart.lineIdx = prevCaretLine;
                self.selectionStart.colIdx = prevCaretCol;
                self.selectionEnd.lineIdx = self.caret_line;
                self.selectionEnd.colIdx = self.caret_col;
            }
        }
    }
};

const Line = struct {
    buf: stdx.textbuf.TextBuffer,

    /// Computed width.
    width: f32,

    /// Whether this line should be measured during layout.
    needs_measure: bool,

    fn init(alloc: std.mem.Allocator) Line {
        return .{
            .buf = stdx.textbuf.TextBuffer.init(alloc, "") catch @panic("error"),
            .needs_measure = false,
            .width = 0,
        };
    }

    fn deinit(self: Line) void {
        self.buf.deinit();
    }
};

pub const TextAreaInner = struct {
    props: struct {
        editor: *TextArea,
    },

    caret_anim_show_toggle: bool,
    caret_anim_id: ui.IntervalId,

    to_caret_str: []const u8,
    to_caret_width: f32,
    to_caret_needs_measure: bool,

    editor: *TextArea,
    ctx: *ui.CommonContext,
    focused: bool,

    pub fn init(self: *TextAreaInner, c: *ui.InitContext) void {
        const props = self.props;
        self.caret_anim_id = c.addInterval(Duration.initSecsF(0.6), self, handleCaretInterval);
        self.caret_anim_show_toggle = true;
        self.editor = props.editor;
        self.ctx = c.common;
        self.focused = false;
        self.to_caret_str = "";
        self.to_caret_width = 0;
        self.to_caret_needs_measure = false;
    }

    fn setFocused(self: *TextAreaInner) void {
        self.focused = true;
        self.resetCaretAnimation();
    }

    fn resetCaretAnimation(self: *TextAreaInner) void {
        self.caret_anim_show_toggle = true;
        self.ctx.resetInterval(self.caret_anim_id);
    }

    fn postCaretUpdate(self: *TextAreaInner) void {
        const line = self.editor.lines.items[self.editor.caret_line];
        self.to_caret_str = line.buf.getSubStr(0, self.editor.caret_col);
        self.to_caret_needs_measure = true;
    }

    fn handleCaretInterval(self: *TextAreaInner, e: ui.IntervalEvent) void {
        _ = e;
        self.caret_anim_show_toggle = !self.caret_anim_show_toggle;
    }

    pub fn build(self: *TextAreaInner, c: *ui.BuildContext) ui.FramePtr {
        _ = self;
        _ = c;
        return .{};
    }

    pub fn layout(self: *TextAreaInner, ctx: *ui.LayoutContext) ui.LayoutSize {
        const editor = self.props.editor;
        if (editor.needs_remeasure_font) {
            const font_vmetrics = self.ctx.getPrimaryFontVMetrics(editor.font_gid, editor.font_size);
            // log.warn("METRICS {}", .{font_vmetrics});
            const font_line_height_factor: f32 = 1.2;
            const font_line_height = @round(font_line_height_factor * editor.font_size);
            const font_line_offset_y = (font_line_height - font_vmetrics.height) / 2;
            // log.warn("{} {} {}", .{font_vmetrics.height, font_line_height, font_line_offset_y});

            editor.font_vmetrics = font_vmetrics;
            editor.font_line_height = @floatToInt(u32, font_line_height);
            editor.font_line_offset_y = font_line_offset_y;
            editor.needs_remeasure_font = false;
        }

        var height: f32 = 0;
        var max_width: f32 = 0;
        for (self.editor.lines.items) |*it| {
            if (it.needs_measure) {
                it.width = ctx.measureText(self.editor.font_gid, self.editor.font_size, it.buf.buf.items).width;
                it.needs_measure = false;
            }
            const width = it.width;
            if (width > max_width) {
                max_width = width;
            }
            height += @intToFloat(f32, self.editor.font_line_height);
        }
        if (self.to_caret_needs_measure) {
            self.to_caret_width = ctx.measureText(self.editor.font_gid, self.editor.font_size, self.to_caret_str).width;
            self.to_caret_needs_measure = false;
        }
        return ui.LayoutSize.init(max_width, height);
    }

    pub fn render(self: *TextAreaInner, ctx: *ui.RenderContext) void {
        const editor = self.editor;

        const bounds = ctx.getAbsBounds();

        const g = ctx.getGraphics();
        const line_height = @intToFloat(f32, editor.font_line_height);

        g.setFontGroup(editor.font_gid, editor.font_size);
        const style = ctx.common.getNodeStyle(TextArea, self.props.editor.node);
        // TODO: Use binary search when word wrap is enabled and we can't determine the first visible line with O(1)
        const scroll_view = editor.scroll_view.getWidget();
        const visible_start_idx = std.math.max(0, @floatToInt(i32, @floor(scroll_view.scroll_y / line_height)));
        const visible_end_idx = std.math.min(editor.lines.items.len, @floatToInt(i32, @ceil((scroll_view.scroll_y + editor.scroll_view.getHeight()) / line_height)));
        const line_offset_y = editor.font_line_offset_y;

        // Fill selection background before drawing text.
        if (editor.hasSelection) {
            const visibleSelectLineStart = std.math.max(editor.selectionStart.lineIdx, @intCast(u32, visible_start_idx));
            const visibleSelectLineEnd = std.math.min(editor.selectionEnd.lineIdx + 1, visible_end_idx);

            if (visibleSelectLineStart < visibleSelectLineEnd) {
                g.setFillColor(Color.Blue);
                var i = visibleSelectLineStart;
                // Highlight first select line.
                if (i == editor.selectionStart.lineIdx) {
                    const line = editor.lines.items[i];
                    const beforeSelectText = line.buf.getSubStr(0, editor.selectionStart.colIdx);
                    const beforeSelectWidth = ctx.measureText(editor.font_gid, editor.font_size, beforeSelectText).width;
                    const y = bounds.min_y + line_offset_y + @intToFloat(f32, i) * line_height;
                    if (i == editor.selectionEnd.lineIdx) {
                        const selectText = line.buf.getSubStr(editor.selectionStart.colIdx, editor.selectionEnd.colIdx);
                        const selectWidth = ctx.measureText(editor.font_gid, editor.font_size, selectText).width;
                        g.fillRect(bounds.min_x + beforeSelectWidth, y, selectWidth, line_height);
                    } else {
                        g.fillRect(bounds.min_x + beforeSelectWidth, y, line.width - beforeSelectWidth, line_height);
                    }
                    i += 1;
                }

                while (i + 1 < visibleSelectLineEnd) {
                    const line = editor.lines.items[i];
                    const y = bounds.min_y + line_offset_y + @intToFloat(f32, i) * line_height;
                    g.fillRect(bounds.min_x, y, line.width, line_height);
                    i += 1;
                }

                if (i < visibleSelectLineEnd) {
                    const line = editor.lines.items[i];
                    const y = bounds.min_y + line_offset_y + @intToFloat(f32, i) * line_height;
                    if (i == editor.selectionEnd.lineIdx) {
                        const selectText = line.buf.getSubStr(0, editor.selectionEnd.colIdx);
                        const selectWidth = ctx.measureText(editor.font_gid, editor.font_size, selectText).width;
                        g.fillRect(bounds.min_x, y, selectWidth, line_height);
                    } else {
                        g.fillRect(bounds.min_x, y, line.width, line_height);
                    }
                }
            }
        }

        // log.warn("{} {}", .{visible_start_idx, visible_end_idx});
        var i: usize = @intCast(usize, visible_start_idx);
        g.setFillColor(style.color);
        while (i < visible_end_idx) : (i += 1) {
            const line = editor.lines.items[i];
            g.fillText(bounds.min_x, bounds.min_y + line_offset_y + @intToFloat(f32, i) * line_height, line.buf.buf.items);
        }

        if (self.focused) {
            // Draw caret.
            if (self.caret_anim_show_toggle) {
                g.setFillColor(style.color);
                // log.warn("width {d:2}", .{width});
                const height = self.editor.font_vmetrics.height;
                g.fillRect(@round(bounds.min_x + self.to_caret_width), bounds.min_y + line_offset_y + @intToFloat(f32, self.editor.caret_line) * line_height, 1, height);
            }
        }
    }
};

const DocLocation = struct {
    lineIdx: u32,
    colIdx: u32,
};