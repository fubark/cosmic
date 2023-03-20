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

const EventType = enum {
    insert,
    remove,
    replace,
};

// TODO: Expose maxLines property.
// TODO: Expose properties that could be useful for a TextEditor.
pub const TextArea = struct {
    props: *const struct {
        initValue: []const u8,
        width: f32 = 400,
        height: f32 = 300,
        onFocus: stdx.Function(fn () void) = .{},
        onBlur: stdx.Function(fn () void) = .{},
        onKeyDown: stdx.Function(fn (ui.WidgetRef(TextArea), platform.KeyDownEvent) ui.EventResult) = .{},
        onEvent: stdx.Function(fn (Event) void) = .{},
        onRenderLines: stdx.Function(fn (*graphics.Graphics, stdx.math.BBox, *const ComputedStyle, []const Line, visibleStartIdx: u32, visibleEndIdx: u32, lineOffsetY: f32, lineHeight: f32) void) = .{},
    },

    lines: std.ArrayList(Line),

    caretLoc: DocLocation,
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

        self.font_gid = c.getFontGroupByFamily(style.fontFamily);
        self.font_size = style.fontSize;
        self.needs_remeasure_font = true;

        self.lines = std.ArrayList(Line).init(c.alloc);
        self.caretLoc.lineIdx = 0;
        self.caretLoc.colIdx = 0;
        self.inner = .{};
        self.scroll_view = .{};
        self.ctx = c.common;
        self.node = c.node;
        self.alloc = c.alloc;
        self.padding = style.padding;

        self.hasSelection = false;
        self.selectionStart = undefined;
        self.selectionEnd = undefined;

        c.setKeyDownHandler(self, onKeyDown);
    }

    pub fn postInit(self: *TextArea, _: *ui.InitContext) void {
        // setText in post to allow parent to bind this instance.
        self.setText(self.props.initValue);
    }

    pub fn deinit(self: *TextArea, _: *ui.DeinitContext) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    pub fn build(self: *TextArea, ctx: *ui.BuildContext) ui.FramePtr {
        const style = ctx.getStyle(TextArea);

        const sv_style = u.ScrollViewStyle{
            .bgColor = style.bgColor,
        };
        return u.ScrollView(.{
            .bind = &self.scroll_view,
            .style = sv_style,
            .childOverlay = u.MouseDragArea(.{
                .onDragStart = ctx.funcExt(self, onDragStart),
                .onDragMove = ctx.funcExt(self, onDragMove),
                .onDragEnd = ctx.funcExt(self, onDragEnd),
            }, .{}), },
            u.Padding(.{ .padding = style.padding },
                ctx.build(TextAreaInner, .{
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

    /// Map mouse pos to caret pos.
    fn absMouseToCaretLoc(self: *TextArea, x: i16, y: i16) DocLocation {
        const scroll_view = self.scroll_view.getWidget();
        const xf = @intToFloat(f32, x) - self.node.abs_bounds.min_x + scroll_view.scroll_x;
        const yf = @intToFloat(f32, y) - self.node.abs_bounds.min_y + scroll_view.scroll_y;
        return self.localToCaretLoc(self.ctx, xf, yf);
    }

    fn onDragStart(self: *TextArea, e: ui.DragStartEvent) void {
        self.requestFocus();

        const loc = self.absMouseToCaretLoc(e.x, e.y);
        self.caretLoc.lineIdx = loc.lineIdx;
        self.caretLoc.colIdx = loc.colIdx;
        self.selectionOrigin.lineIdx = self.caretLoc.lineIdx;
        self.selectionOrigin.colIdx = self.caretLoc.colIdx;
        self.postCaretUpdate();
    }

    fn onDragMove(self: *TextArea, e: ui.DragMoveEvent) void {
        const prevCaretLoc = self.caretLoc;

        self.caretLoc = self.absMouseToCaretLoc(e.x, e.y);
        self.postCaretUpdate();

        self.selectFrom(prevCaretLoc);
    }

    fn onDragEnd(self: *TextArea, x: i16, y: i16) void {
        const prevCaretLoc = self.caretLoc;

        self.caretLoc = self.absMouseToCaretLoc(x, y);
        self.postCaretUpdate();

        self.selectFrom(prevCaretLoc);
    }

    /// Should be called before layout.
    pub fn setText(self: *TextArea, text: []const u8) void {
        const endLine = self.lines.items.len;
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

        const lastLineLen = self.lines.items[self.lines.items.len-1].buf.numCodepoints();
        self.fireReplaceEvent(DocLocation.init(0, 0),
            DocLocation.init(@intCast(u32, endLine), 0),
            DocLocation.init(@intCast(u32, self.lines.items.len-1), lastLineLen));
    }

    pub fn allocSelectedText(self: TextArea, alloc: std.mem.Allocator) ![]const u8 {
        if (self.hasSelection) {
            var res: std.ArrayListUnmanaged(u8) = .{};
            var i = self.selectionStart.lineIdx;
            var line = self.lines.items[i];
            if (self.selectionEnd.lineIdx == self.selectionStart.lineIdx) {
                try res.appendSlice(alloc, line.buf.getSubStr(self.selectionStart.colIdx, self.selectionEnd.colIdx));
                return res.toOwnedSlice(alloc);
            }
            try res.appendSlice(alloc, line.buf.getSubStr(self.selectionStart.colIdx, line.buf.numCodepoints()));
            try res.append(alloc, '\n');
            i += 1;
            while (i < self.selectionEnd.lineIdx) {
                line = self.lines.items[i];
                try res.appendSlice(alloc, line.buf.buf.items);
                try res.append(alloc, '\n');
                i += 1;
            }
            line = self.lines.items[i];
            try res.appendSlice(alloc, line.buf.getSubStr(0, self.selectionEnd.colIdx));
            return res.toOwnedSlice(alloc);
        } else return "";
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
        if (self.props.onFocus.isPresent()) {
            self.props.onFocus.call(.{});
        }
        // std.crypto.hash.Md5.hash(self.buf.items, &self.last_buf_hash, .{});
    }

    fn onPaste(node: *ui.Node, _: *ui.CommonContext, str: []const u8) void {
        const self = node.getWidget(TextArea);
        if (self.hasSelection) {
            const start = self.selectionStart;
            const end = self.selectionEnd;
            self.deleteSelection();
            self.fireReplaceEvent(start, end, self.caretLoc);
        } else {
            const prev = self.caretLoc;
            self.paste(str);
            self.fireInsertEvent(prev, self.caretLoc);
        }
    }

    fn paste(self: *TextArea, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        var iter = std.mem.split(u8, str, "\n");
        // First line inserts to the caret pos.
        const first = iter.next().?;

        // Text after caret is appended to the last inserted line.
        const line = &self.lines.items[self.caretLoc.lineIdx];
        const afterCaretText = self.alloc.dupe(u8, line.buf.getSubStr(self.caretLoc.colIdx, line.buf.numCodepoints())) catch fatal();
        defer self.alloc.free(afterCaretText);
        line.buf.removeSubStr(self.caretLoc.colIdx, line.buf.numCodepoints());
        var num_new_chars = line.buf.appendSubStr(first) catch fatal();
        self.postLineUpdate(self.caretLoc.lineIdx);
        self.caretLoc.colIdx += num_new_chars;

        while (iter.next()) |pline| {
            self.caretLoc.lineIdx += 1;

            // Insert a new line.
            var new_line = Line.init(self.alloc);
            num_new_chars = new_line.buf.appendSubStr(pline) catch fatal();
            self.lines.insert(self.caretLoc.lineIdx, new_line) catch fatal();
            self.postLineUpdate(self.caretLoc.lineIdx);

            self.caretLoc.colIdx = num_new_chars;
        }

        // Reattach text that was after the caret before the paste.
        _ = self.lines.items[self.caretLoc.lineIdx].buf.appendSubStr(afterCaretText) catch fatal();

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

    fn localToCaretLoc(self: *TextArea, ctx: *ui.CommonContext, x_: f32, y_: f32) DocLocation {
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
        return @intToFloat(f32, self.caretLoc.lineIdx + 1) * @intToFloat(f32, self.font_line_height) + self.padding;
    }

    fn getCaretTopY(self: *TextArea) f32 {
        return @intToFloat(f32, self.caretLoc.lineIdx) * @intToFloat(f32, self.font_line_height) + self.padding;
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
        return &self.lines.items[self.caretLoc.lineIdx].buf;
    }

    pub fn getCodepointBeforeCaret(self: *TextArea) ?u21 {
        if (self.caretLoc.colIdx > 0) {
            return self.lines.items[self.caretLoc.lineIdx].buf.getCodepointAt(self.caretLoc.colIdx - 1);
        } else return null;
    }

    /// Assume no new lines.
    pub fn modelInsertFromCaret(self: *TextArea, str: []const u8) !void {
        const line = &self.lines.items[self.caretLoc.lineIdx];
        if (self.caretLoc.colIdx == line.buf.num_chars) {
            self.caretLoc.colIdx += try line.buf.appendSubStr(str);
        } else {
            self.caretLoc.colIdx += try line.buf.insertSubStr(self.caretLoc.colIdx, str);
        }
        self.postLineUpdate(self.caretLoc.lineIdx);

        self.postCaretUpdate();
        self.postCaretActivity();
    }

    pub fn insertFromCaret(self: *TextArea, str: []const u8) !void {
        if (str.len == 0) {
            return;
        }
        const prev = self.caretLoc;
        try self.modelInsertFromCaret(str);
        self.fireInsertEvent(prev, self.caretLoc);
    }

    fn modelInsertNewLineFromCaret(self: *TextArea) !void {
        const new_line = Line.init(self.ctx.alloc);
        try self.lines.insert(self.caretLoc.lineIdx + 1, new_line);
        // Requery current line since insert could have resized array.
        const cur_line = &self.lines.items[self.caretLoc.lineIdx];
        if (self.caretLoc.colIdx < cur_line.buf.num_chars) {
            // Move text after caret to the new line.
            const after_text = cur_line.buf.getSubStr(self.caretLoc.colIdx, cur_line.buf.num_chars);
            _ = try self.lines.items[self.caretLoc.lineIdx+1].buf.appendSubStr(after_text);
            cur_line.buf.removeSubStr(self.caretLoc.colIdx, cur_line.buf.num_chars);
            self.postLineUpdate(self.caretLoc.lineIdx);
        }
        self.postLineUpdate(self.caretLoc.lineIdx + 1);

        self.caretLoc.lineIdx += 1;
        self.caretLoc.colIdx = 0;
        self.postCaretUpdate();
        self.postCaretActivity();
    }

    pub fn insertNewLineFromCaret(self: *TextArea) !void {
        const prev = self.caretLoc;
        try self.modelInsertNewLineFromCaret();
        self.fireInsertEvent(prev, self.caretLoc);
    }

    fn onKeyDown(self: *TextArea, e: ui.KeyDownEvent) void {
        const val = e.val;

        if (self.props.onKeyDown.isPresent()) {
            if (self.props.onKeyDown.call(.{ ui.WidgetRef(TextArea).init(self.node), e.val }) == .stop) {
                return;
            }
        }

        var line = &self.lines.items[self.caretLoc.lineIdx];
        const prevCaretLoc = self.caretLoc;
        var cancelSelect = true;
        if (val.code == .Backspace) {
            if (self.hasSelection) {
                const start = self.selectionStart;
                const end = self.selectionEnd;
                self.deleteSelection();
                self.postCaretUpdate();
                self.postCaretActivity();
                self.fireRemoveEvent(start, end);
            } else {
                if (self.caretLoc.colIdx > 0) {
                    const prev = self.caretLoc;
                    if (line.buf.num_chars == self.caretLoc.colIdx) {
                        line.buf.removeChar(line.buf.num_chars-1);
                    } else {
                        line.buf.removeChar(self.caretLoc.colIdx-1);
                    }
                    self.postLineUpdate(self.caretLoc.lineIdx);

                    self.caretLoc.colIdx -= 1;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                    self.fireRemoveEvent(self.caretLoc, prev);
                } else if (self.caretLoc.lineIdx > 0) {
                    // Join current line with previous.
                    const prev = self.caretLoc;
                    var prev_line = &self.lines.items[self.caretLoc.lineIdx-1];
                    self.caretLoc.colIdx = prev_line.buf.num_chars;
                    _ = prev_line.buf.appendSubStr(line.buf.buf.items) catch @panic("error");
                    line.deinit();
                    _ = self.lines.orderedRemove(self.caretLoc.lineIdx);
                    self.postLineUpdate(self.caretLoc.lineIdx-1);

                    self.caretLoc.lineIdx -= 1;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                    self.fireRemoveEvent(self.caretLoc, prev);
                }
            }
        } else if (val.code == .Delete) {
            if (self.hasSelection) {
                const start = self.selectionStart;
                const end = self.selectionEnd;
                self.deleteSelection();
                self.postCaretUpdate();
                self.postCaretActivity();
                self.fireRemoveEvent(start, end);
            } else {
                if (self.caretLoc.colIdx < line.buf.num_chars) {
                    line.buf.removeChar(self.caretLoc.colIdx);
                    self.postLineUpdate(self.caretLoc.lineIdx);
                    self.postCaretActivity();
                    var end = self.caretLoc;
                    end.colIdx += 1;
                    self.fireRemoveEvent(self.caretLoc, end);
                } else {
                    // Append next line.
                    if (self.caretLoc.lineIdx < self.lines.items.len-1) {
                        _ = line.buf.appendSubStr(self.lines.items[self.caretLoc.lineIdx+1].buf.buf.items) catch @panic("error");
                        self.lines.items[self.caretLoc.lineIdx+1].deinit();
                        _ = self.lines.orderedRemove(self.caretLoc.lineIdx+1);
                        self.postLineUpdate(self.caretLoc.lineIdx);
                        self.postCaretActivity();
                        var end = self.caretLoc;
                        end.lineIdx += 1;
                        self.fireRemoveEvent(self.caretLoc, end);
                    }
                }
            }
        } else if (val.code == .Enter) {
            if (self.hasSelection) {
                const start = self.selectionStart;
                const end = self.selectionEnd;
                self.deleteSelection();
                self.modelInsertNewLineFromCaret() catch fatal();
                self.fireReplaceEvent(start, end, self.caretLoc);
            } else {
                const prev = self.caretLoc;
                self.modelInsertNewLineFromCaret() catch fatal();
                self.fireInsertEvent(prev, self.caretLoc);
            }
        } else if (val.code == .ArrowLeft) {
            if (self.caretLoc.colIdx > 0) {
                self.caretLoc.colIdx -= 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            } else {
                if (self.caretLoc.lineIdx > 0) {
                    self.caretLoc.lineIdx -= 1;
                    self.caretLoc.colIdx = self.lines.items[self.caretLoc.lineIdx].buf.num_chars;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                }
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .ArrowRight) {
            if (self.caretLoc.colIdx < line.buf.numCodepoints()) {
                self.caretLoc.colIdx += 1;
                self.postCaretUpdate();
                self.postCaretActivity();
            } else {
                if (self.caretLoc.lineIdx < self.lines.items.len-1) {
                    self.caretLoc.lineIdx += 1;
                    self.caretLoc.colIdx = 0;
                    self.postCaretUpdate();
                    self.postCaretActivity();
                }
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .ArrowUp) {
            if (self.caretLoc.lineIdx > 0) {
                self.caretLoc.lineIdx -= 1;
                if (self.caretLoc.colIdx > self.lines.items[self.caretLoc.lineIdx].buf.num_chars) {
                    self.caretLoc.colIdx = self.lines.items[self.caretLoc.lineIdx].buf.num_chars;
                }
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .ArrowDown) {
            if (self.caretLoc.lineIdx < self.lines.items.len-1) {
                self.caretLoc.lineIdx += 1;
                if (self.caretLoc.colIdx > self.lines.items[self.caretLoc.lineIdx].buf.num_chars) {
                    self.caretLoc.colIdx = self.lines.items[self.caretLoc.lineIdx].buf.num_chars;
                }
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .Home) {
            if (self.caretLoc.colIdx > 0) {
                self.caretLoc.colIdx = 0;
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .End) {
            if (self.caretLoc.colIdx < line.buf.numCodepoints()) {
                self.caretLoc.colIdx = line.buf.numCodepoints();
                self.postCaretUpdate();
                self.postCaretActivity();
            }
            if (val.isShiftPressed()) {
                cancelSelect = false;
                self.selectFrom(prevCaretLoc);
            }
        } else if (val.code == .V and val.isControlPressed()) {
            if (!IsWasm) {
                if (self.hasSelection) {
                    const start = self.selectionStart;
                    const end = self.selectionEnd;
                    self.deleteSelection();
                    self.fireReplaceEvent(start, end, self.caretLoc);
                } else {
                    const clipboard = platform.allocClipboardText(self.alloc) catch fatal();
                    defer self.alloc.free(clipboard);
                    self.paste(clipboard);
                    self.fireInsertEvent(prevCaretLoc, self.caretLoc);
                }
            }
        } else if (val.code == .X and val.isControlPressed()) {
            // Cut to clipboard.
            if (self.hasSelection) {
                const selected = self.allocSelectedText(self.alloc) catch fatal();
                defer self.alloc.free(selected);
                platform.setClipboardText(self.alloc, selected) catch fatal();
                const start = self.selectionStart;
                const end = self.selectionEnd;
                self.deleteSelection();
                self.postCaretUpdate();
                self.postCaretActivity();
                self.fireRemoveEvent(start, end);
            }
        } else if (val.code == .C and val.isControlPressed()) {
            // Copy to clipboard.
            if (self.hasSelection) {
                const selected = self.allocSelectedText(self.alloc) catch fatal();
                defer self.alloc.free(selected);
                platform.setClipboardText(self.alloc, selected) catch fatal();
                cancelSelect = false;
            }
        } else {
            if (val.getPrintChar()) |ch| {
                var start: DocLocation = undefined;
                var end: DocLocation = undefined;
                var hadSelection = self.hasSelection;
                if (self.hasSelection) {
                    // Remove selection first.
                    start = self.selectionStart;
                    end = self.selectionEnd;
                    self.deleteSelection();
                    line = &self.lines.items[self.caretLoc.lineIdx];
                }
                if (self.caretLoc.colIdx == line.buf.num_chars) {
                    line.buf.appendCodepoint(ch) catch @panic("error");
                } else {
                    line.buf.insertCodepoint(self.caretLoc.colIdx, ch) catch @panic("error");
                }
                self.postLineUpdate(self.caretLoc.lineIdx);

                const prev = self.caretLoc;
                self.caretLoc.colIdx += 1;
                self.postCaretUpdate();
                self.postCaretActivity();
                
                if (hadSelection) {
                    self.fireReplaceEvent(start, end, self.caretLoc);
                } else {
                    self.fireInsertEvent(prev, self.caretLoc);
                }
            } else {
                cancelSelect = false;
            }
        }

        if (cancelSelect and self.hasSelection) {
            self.hasSelection = false;
        }
    }

    fn fireInsertEvent(self: *TextArea, start: DocLocation, end: DocLocation) void {
        if (self.props.onEvent.isPresent()) {
            const event = Event{
                .eventT = .insert,
                .inner = .{
                    .insert = .{
                        .start = start,
                        .end = end,
                    },
                },
            };
            self.props.onEvent.call(.{ event });
        }
    }

    fn fireRemoveEvent(self: *TextArea, start: DocLocation, end: DocLocation) void {
        if (self.props.onEvent.isPresent()) {
            const event = Event{
                .eventT = .remove,
                .inner = .{
                    .remove = .{
                        .start = start,
                        .end = end,
                    },
                },
            };
            self.props.onEvent.call(.{ event });
        }
    }

    fn fireReplaceEvent(self: *TextArea, start: DocLocation, end: DocLocation, newEnd: DocLocation) void {
        if (self.props.onEvent.isPresent()) {
            const event = Event{
                .eventT = .replace,
                .inner = .{
                    .replace = .{
                        .start = start,
                        .end = end,
                        .newEnd = newEnd,
                    },
                },
            };
            self.props.onEvent.call(.{ event });
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
                for (self.lines.items[self.selectionStart.lineIdx+1..self.selectionEnd.lineIdx+1]) |line_| {
                    line_.deinit();
                }
                self.lines.replaceRange(self.selectionStart.lineIdx+1, self.selectionEnd.lineIdx - self.selectionStart.lineIdx, &.{}) catch fatal();
            }
            self.caretLoc = self.selectionStart;
            self.hasSelection = false;
        }
    }

    fn selectFrom(self: *TextArea, prevCaretLoc: DocLocation) void {
        if (self.hasSelection) {
            if (self.caretLoc.lineIdx == self.selectionOrigin.lineIdx and self.caretLoc.colIdx == self.selectionOrigin.colIdx) {
                self.hasSelection = false;
            } else {
                if (self.caretLoc.lineIdx < self.selectionOrigin.lineIdx or (self.caretLoc.lineIdx == self.selectionOrigin.lineIdx and self.caretLoc.colIdx < self.selectionOrigin.colIdx)) {
                    self.selectionStart = self.caretLoc;
                    self.selectionEnd = self.selectionOrigin;
                } else {
                    self.selectionStart = self.selectionOrigin;
                    self.selectionEnd = self.caretLoc;
                }
            }
        } else {
            if (self.caretLoc.lineIdx < prevCaretLoc.lineIdx or (self.caretLoc.lineIdx == prevCaretLoc.lineIdx and self.caretLoc.colIdx < prevCaretLoc.colIdx)) {
                self.selectionStart = self.caretLoc;
                self.selectionEnd = prevCaretLoc;
            } else {
                self.selectionStart = prevCaretLoc;
                self.selectionEnd = self.caretLoc;
            }
            if (self.selectionEnd.lineIdx > self.selectionStart.lineIdx or self.selectionEnd.colIdx > self.selectionStart.colIdx) {
                // Must be selecting at least one codepoint
                self.hasSelection = true;
                self.selectionOrigin = prevCaretLoc;
            }
        }
    }

    pub const Line = struct {
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

    pub const Event = struct {
        eventT: EventType,
        inner: union {
            insert: struct {
                start: DocLocation,
                end: DocLocation,
            },
            remove: struct {
                start: DocLocation,
                end: DocLocation,
            },
            replace: struct {
                start: DocLocation,
                end: DocLocation,
                newEnd: DocLocation,
            },
        },
    };

    pub const DocLocation = struct {
        lineIdx: u32,
        colIdx: u32,

        pub fn init(lineIdx: u32, colIdx: u32) DocLocation {
            return .{ .lineIdx = lineIdx, .colIdx = colIdx };
        }
    };
};

pub const TextAreaInner = struct {
    props: *const struct {
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
        const line = self.editor.lines.items[self.editor.caretLoc.lineIdx];
        self.to_caret_str = line.buf.getSubStr(0, self.editor.caretLoc.colIdx);
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
        const visible_start_idx = @intCast(u32, std.math.max(0, @floatToInt(i32, @floor(scroll_view.scroll_y / line_height))));
        const visible_end_idx = std.math.min(@intCast(u32, editor.lines.items.len), @floatToInt(i32, @ceil((scroll_view.scroll_y + editor.scroll_view.getHeight()) / line_height)));
        // log.debug("{} {}", .{visible_start_idx, visible_end_idx});
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

        if (editor.props.onRenderLines.isPresent()) {
            editor.props.onRenderLines.call(.{ g, bounds, style, editor.lines.items, visible_start_idx, visible_end_idx, line_offset_y, line_height });
        } else {
            var i: usize = @intCast(usize, visible_start_idx);
            g.setFillColor(style.color);
            while (i < visible_end_idx) : (i += 1) {
                const line = editor.lines.items[i];
                g.fillText(bounds.min_x, bounds.min_y + line_offset_y + @intToFloat(f32, i) * line_height, line.buf.buf.items);
            }
        }

        if (self.focused) {
            // Draw caret.
            if (self.caret_anim_show_toggle) {
                g.setFillColor(style.color);
                const height = self.editor.font_vmetrics.height;
                g.fillRect(@round(bounds.min_x + self.to_caret_width), bounds.min_y + line_offset_y + @intToFloat(f32, self.editor.caretLoc.lineIdx) * line_height, 2, height);
            }
        }
    }
};
