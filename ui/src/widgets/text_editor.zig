const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const graphics = @import("graphics");
const platform = @import("platform");

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.text_editor);

pub const TextEditor = struct {
    props: *const struct {
        initValue: []const u8,
        onFocus: stdx.Function(fn () void) = .{},
        onBlur: stdx.Function(fn () void) = .{},
        onKeyDown: stdx.Function(fn (ui.WidgetRef(TextEditor), platform.KeyDownEvent) ui.EventResult) = .{},
        onTokenize: stdx.Function(fn ([]const u.TextAreaT.Line, []LineExt, lineStartIdx: u32, lineEndIdx: u32) void) = .{},
        tokenStyles: std.AutoHashMapUnmanaged(u32, graphics.Color) = .{},

        /// Fires before internal handler.
        onEvent: stdx.Function(fn (u.TextAreaT.Event) void) = .{},
    },

    ta: ui.WidgetRef(u.TextAreaT),
    node: *ui.Node,
    alloc: std.mem.Allocator,
    lines: std.ArrayListUnmanaged(LineExt),
    segmentsBuf: *std.ArrayListUnmanaged(graphics.TextRunSegment),

    pub const Style = struct {
        textArea: ?u.TextAreaStyle = null,
    };

    pub const ComputedStyle = struct {
        textArea: ?u.TextAreaStyle = null,
    };

    pub fn init(self: *TextEditor, ctx: *ui.InitContext) void {
        self.* = .{
            .props = self.props,
            .ta = .{},
            .node = ctx.node,
            .alloc = ctx.alloc,
            .lines = .{},
            .segmentsBuf = &ctx.common.common.textRunSegmentsBuf,
        };
        // Ensure at least one line.
        self.lines.append(self.alloc, .{}) catch fatal();
    }

    pub fn build(self: *TextEditor, ctx: *ui.BuildContext) ui.FramePtr {
        const style = ctx.getStyle(TextEditor);
        const taStyle = ctx.getStylePropPtr(style, "textArea");
        return u.TextArea(.{
            .initValue = self.props.initValue,
            .bind = &self.ta,
            .style = taStyle,
            .onFocus = self.props.onFocus,
            .onBlur = self.props.onBlur,
            .onKeyDown = ctx.funcExt(self, onKeyDown),
            .onEvent = ctx.funcExt(self, onEvent),
            .onRenderLines = ctx.funcExt(self, onRenderLines),
        });
    }

    fn onKeyDown(self: *TextEditor, _: ui.WidgetRef(u.TextAreaT), e: platform.KeyDownEvent) ui.EventResult {
        if (self.props.onKeyDown.isPresent()) {
            const ref = ui.WidgetRef(TextEditor).init(self.node);
            return self.props.onKeyDown.call(.{ ref, e });
        }
        return .default;
    }

    pub fn setText(self: *TextEditor, text: []const u8) void {
        self.ta.getWidget().setText(text);
    }

    pub fn getTextArea(self: *TextEditor) *u.TextAreaT {
        return self.ta.getWidget();
    }

    pub fn allocText(self: TextEditor, alloc: std.mem.Allocator) ![]const u8 {
        return self.ta.getWidget().allocText(alloc);
    }

    fn getChangeLineRange(self: *TextEditor, start: u.TextAreaT.DocLocation, end: u.TextAreaT.DocLocation) stdx.Pair(u32, u32) {
        _ = self;
        var changeStartLineIdx = start.lineIdx;
        var changeEndLineIdx = end.lineIdx + 1;
        return stdx.Pair(u32, u32).init(changeStartLineIdx, changeEndLineIdx);
    }

    fn onEvent(self: *TextEditor, event_: u.TextAreaT.Event) void {
        if (self.props.onEvent.isPresent()) {
            self.props.onEvent.call(.{ event_ });
        }
        switch (event_.eventT) {
            .insert => {
                const event = event_.inner.insert;
                var i = event.start.lineIdx + 1;
                while (i <= event.end.lineIdx) : (i += 1) {
                    self.lines.insert(self.alloc, i, .{}) catch fatal();
                }

                const changeRange = self.getChangeLineRange(event.start, event.end);
                if (self.props.onTokenize.isPresent()) {
                    self.props.onTokenize.call(.{ self.ta.getWidget().lines.items, self.lines.items, changeRange.first, changeRange.second });
                }
            },
            .remove => {
                const event = event_.inner.remove;

                var removeStartLineIdx = event.start.lineIdx + 1;
                if (event.end.lineIdx >= removeStartLineIdx) {
                    self.lines.replaceRange(self.alloc, removeStartLineIdx, event.end.lineIdx - event.start.lineIdx, &.{}) catch fatal();
                }

                if (self.props.onTokenize.isPresent()) {
                    // startIdx == endIdx, indicates there are no lines that have changed but it still needs to reconcile
                    // with the first token before startIdx and the first token after endIdx.
                    self.props.onTokenize.call(.{ self.ta.getWidget().lines.items, self.lines.items, event.start.lineIdx, event.start.lineIdx + 1 });
                }
            },
            .replace => {
                const event = event_.inner.replace;

                var removeStartLineIdx = event.start.lineIdx + 1;
                if (event.end.lineIdx >= removeStartLineIdx) {
                    self.lines.replaceRange(self.alloc, removeStartLineIdx, event.end.lineIdx - event.start.lineIdx, &.{}) catch fatal();
                }

                var i = event.start.lineIdx + 1;
                while (i <= event.newEnd.lineIdx) : (i += 1) {
                    self.lines.insert(self.alloc, i, .{}) catch fatal();
                }

                const changeRange = self.getChangeLineRange(event.start, event.newEnd);
                if (self.props.onTokenize.isPresent()) {
                    self.props.onTokenize.call(.{ self.ta.getWidget().lines.items, self.lines.items, changeRange.first, changeRange.second });
                }
            },
        }
    }

    fn onRenderLines(
        self: *TextEditor,
        gctx: *graphics.Graphics,
        bounds: stdx.math.BBox,
        style: *const u.TextAreaT.ComputedStyle,
        lines: []const u.TextAreaT.Line,
        visibleStartIdx: u32, visibleEndIdx: u32,
        lineOffsetY: f32, lineHeight: f32,
    ) void {
        var i: usize = @intCast(usize, visibleStartIdx);
        gctx.setFillColor(style.color);

        const ta = self.getTextArea();
        var multiLineToken: ?LineToken = null;
        var multiLineTokenEndLine: u32 = undefined;

        if (i < visibleEndIdx and self.lines.items[i].tokens.items.len == 0) {
            // First line doesn't have a token. Look for previous multi line token.
            if (self.getFirstTokenLocBeforeLine(i)) |loc| {
                const tokens = self.lines.items[loc.lineIdx].tokens.items;
                const token = tokens[tokens.len-1];
                multiLineToken = token;
                multiLineTokenEndLine = loc.lineIdx + token.endLineOffset;
            }
        }

        while (i < visibleEndIdx) : (i += 1) {
            var line = lines[i];

            const lineExt = self.lines.items[i];
            self.segmentsBuf.clearRetainingCapacity();

            var col: u32 = 0;
            if (multiLineToken) |token| {
                if (i < multiLineTokenEndLine) {
                    self.segmentsBuf.append(self.alloc, .{
                        .fontGroupId = ta.font_gid,
                        .fontSize = ta.font_size,
                        .color = self.props.tokenStyles.get(token.tokenT) orelse style.color,
                        .start = 0,
                        .end = line.buf.string().len,
                    }) catch fatal();
                    col = line.buf.string().len;
                } else if (i == multiLineTokenEndLine) {
                    if (token.end != 0) {
                        self.segmentsBuf.append(self.alloc, .{
                            .fontGroupId = ta.font_gid,
                            .fontSize = ta.font_size,
                            .color = self.props.tokenStyles.get(token.tokenT) orelse style.color,
                            .start = 0,
                            .end = token.end,
                        }) catch fatal();
                    }
                    multiLineToken = null;
                    col = token.end;
                }
            }

            if (col < line.buf.string().len) {
                if (lineExt.tokens.items.len > 0) {
                    for (lineExt.tokens.items) |token| {
                        if (token.start == line.buf.string().len) {
                            // Skip new line token.
                            continue;
                        }
                        if (col < token.start) {
                            self.segmentsBuf.append(self.alloc, .{
                                .fontGroupId = ta.font_gid,
                                .fontSize = ta.font_size,
                                .color = style.color,
                                .start = col,
                                .end = token.start,
                            }) catch fatal();
                        }
                        if (token.endLineOffset > 0) {
                            // Multiline token.
                            col = line.buf.string().len;
                            multiLineToken = token;
                            multiLineTokenEndLine = i + token.endLineOffset;
                        } else {
                            col = if (token.end == 0) line.buf.string().len else token.end;
                        }
                        self.segmentsBuf.append(self.alloc, .{
                            .fontGroupId = ta.font_gid,
                            .fontSize = ta.font_size,
                            .color = self.props.tokenStyles.get(token.tokenT) orelse style.color,
                            .start = token.start,
                            .end = col,
                        }) catch fatal();
                    }
                    if (col < line.buf.string().len) {
                        self.segmentsBuf.append(self.alloc, .{
                            .fontGroupId = ta.font_gid,
                            .fontSize = ta.font_size,
                            .color = style.color,
                            .start = col,
                            .end = line.buf.string().len,
                        }) catch fatal();
                    }
                } else {
                    self.segmentsBuf.append(self.alloc, .{
                        .fontGroupId = ta.font_gid,
                        .fontSize = ta.font_size,
                        .color = style.color,
                        .start = col,
                        .end = line.buf.string().len,
                    }) catch fatal();
                }
            }

            if (self.segmentsBuf.items.len > 0) {
                gctx.fillTextRun(bounds.min_x, bounds.min_y + lineOffsetY + @intToFloat(f32, i) * lineHeight, .{
                    .str = line.buf.buf.items,
                    .segments = self.segmentsBuf.items,
                });
            }
        }

        // gctx.fillText(bounds.min_x, bounds.min_y + lineOffsetY + @intToFloat(f32, i) * lineHeight, line.buf.buf.items);
    }

    pub fn getFirstTokenLocBeforeLine(self: *TextEditor, lineIdx: u32) ?u.TextAreaT.DocLocation {
        var i = lineIdx;
        while (i > 0) {
            i -= 1;
            const line = self.lines.items[i];
            if (line.tokens.items.len > 0) {
                const last = line.tokens.items[line.tokens.items.len-1];
                return u.TextAreaT.DocLocation.init(i, last.start);
            }
        }
        return null;
    }

    pub const LineExt = struct {
        tokens: std.ArrayListUnmanaged(LineToken) = .{},

        fn deinit(self: *LineExt, alloc: std.mem.Allocator) void {
            self.tokens.deinit(alloc);
        }
    };

    pub const LineToken = struct {
        tokenT: u32,
        /// start col of the current line.
        start: u32,
        /// Token may end on a different line. Using offset so line inserts/removals don't invalidate the token.
        endLineOffset: u32,
        /// end col of the endLine.
        end: u32,
    };
};