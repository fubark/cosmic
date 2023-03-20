const std = @import("std");
const stdx = @import("stdx");
const Backend = @import("graphics_options").GraphicsBackend;

const graphics = @import("graphics.zig");
const FontGroupId = graphics.FontGroupId;
const gpu = @import("backend/gpu/graphics.zig");
const testg = @import("backend/test/graphics.zig");

pub const TextMetrics = struct {
    width: f32,
    height: f32,

    pub fn init(width: f32, height: f32) @This() {
        return .{
            .width = width,
            .height = height,
        };
    }
};

// Result is stored with text description.
pub const TextMeasure = struct {
    text: []const u8,
    font_size: f32,
    font_gid: FontGroupId,
    res: TextMetrics = TextMetrics.init(0, 0),
};

pub const TextLayout = struct {
    lines: std.ArrayList(TextLine),

    /// Max width in logical pixels of all the lines.
    width: f32,

    /// Height in logical pixels of all the lines.
    height: f32,

    firstLineStartX: f32,
    lastLineEndX: f32,

    pub fn init(alloc: std.mem.Allocator) TextLayout {
        return .{
            .lines = std.ArrayList(TextLine).init(alloc),
            .width = 0,
            .height = 0,
            .firstLineStartX = 0,
            .lastLineEndX = 0,
        };
    }

    pub fn deinit(self: TextLayout) void {
        self.lines.deinit();
    }
};

pub fn textLayout(gctx: *graphics.Graphics, font_gid: FontGroupId, size: f32, str: []const u8, preferred_width: f32, spanStartX: f32, buf: *TextLayout) void {
    buf.lines.clearRetainingCapacity();
    var iter = gctx.textGlyphIter(font_gid, size, str);
    var y: f32 = 0;
    var last_fit_start_idx: u32 = 0;
    var last_fit_end_idx: u32 = 0;
    var last_fit_x: f32 = 0;
    var x: f32 = spanStartX;
    var max_width: f32 = 0;
    while (iter.nextCodepoint()) {
        x += iter.state.kern;
        // Assume snapping.
        x = @round(x);
        x += iter.state.advance_width;

        if (iter.state.cp == 10) {
            // Line feed. Force new line.
            buf.lines.append(.{
                .start_idx = last_fit_start_idx,
                .end_idx = @intCast(u32, iter.state.end_idx - 1), // Exclude new line.
                .height = iter.primary_height,
            }) catch @panic("error");
            last_fit_start_idx = @intCast(u32, iter.state.end_idx);
            last_fit_end_idx = @intCast(u32, iter.state.end_idx);
            if (x > max_width) {
                max_width = x;
            }
            x = 0;
            y += iter.primary_height;
            continue;
        }

        if (x <= preferred_width) {
            if (stdx.unicode.isSpace(iter.state.cp)) {
                // Space character indicates the end of a word.
                last_fit_end_idx = @intCast(u32, iter.state.end_idx);
            }
        } else {
            if (last_fit_start_idx == last_fit_end_idx) {
                // Haven't fit a word yet. Just keep going.
            } else {
                // Wrap to next line.
                buf.lines.append(.{
                    .start_idx = last_fit_start_idx,
                    .end_idx = last_fit_end_idx,
                    .height = iter.primary_height,
                }) catch @panic("error");
                y += iter.primary_height;
                last_fit_start_idx = last_fit_end_idx;
                last_fit_x = 0;
                if (x > max_width) {
                    max_width = x;
                }
                x = 0;
                iter.setIndex(last_fit_start_idx);
            }
        }
    }
    if (last_fit_end_idx <= iter.state.end_idx) {
        // Add last line.
        buf.lines.append(.{
            .start_idx = last_fit_start_idx,
            .end_idx = @intCast(u32, iter.state.end_idx),
            .height = iter.primary_height,
        }) catch @panic("error");
        if (x > max_width) {
            max_width = x;
        }
        y += iter.primary_height;
    }
    buf.width = max_width;
    buf.height = y;
    buf.firstLineStartX = spanStartX;
    buf.lastLineEndX = x;
}

pub const TextLine = struct {
    start_idx: u32,
    end_idx: u32,
    height: f32,
};

/// Used to traverse text one UTF-8 codepoint at a time.
pub const TextGlyphIterator = struct {
    inner: switch (Backend) {
        .OpenGL, .Vulkan => gpu.TextGlyphIterator,
        .Test => testg.TextGlyphIterator,
        else => stdx.unsupported(),
    },

    /// The primary vertical metrics are available and won't change.
    primary_ascent: f32,
    primary_descent: f32,
    primary_height: f32,
    state: State,

    const Self = @This();

    /// Units are scaled to the effective user font size.
    pub const State = struct {
        /// The current codepoint.
        cp: u21,

        /// The current codepoint's start idx in the given UTF-8 buffer.
        start_idx: usize,

        /// THe current codepoint's end idx in the given UTF-8 buffer. Not inclusive.
        end_idx: usize,

        /// The kern with the previous codepoint.
        kern: f32,

        /// How much this codepoint should advance the current x position.
        /// Note that this does not include the kern value with a previous codepoint.
        advance_width: f32,

        /// How much the glyph is above the baseline.
        ascent: f32,

        /// How much the glyph is below the baseline.
        descent: f32,

        /// Height would be ascent + descent.
        height: f32,

        /// y-offset needed in final glyph position in order to be aligned with the primary font.
        /// If the glyph is from the primary font, this should be zero.
        primary_offset_y: f32,
    };

    pub inline fn nextCodepoint(self: *Self) bool {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.TextGlyphIterator.nextCodepoint(&self.inner, &self.state, {}, null),
            .Test => return testg.TextGlyphIterator.nextCodepoint(&self.inner, &self.state),
            else => stdx.unsupported(),
        }
    }

    pub inline fn setIndex(self: *Self, i: usize) void {
        switch (Backend) {
            .OpenGL, .Vulkan => return gpu.TextGlyphIterator.setIndex(&self.inner, i),
            .Test => return testg.TextGlyphIterator.setIndex(&self.inner, i),
            else => stdx.unsupported(),
        }
    }
};

pub const TextRun = struct {
    str: []const u8,
    segments: []const TextRunSegment,
};

pub const TextRunSegment = struct {
    color: graphics.Color,
    fontGroupId: graphics.FontGroupId,
    fontSize: f32,
    /// start/end pos of the TextRun string.
    start: u32,
    end: u32,
};