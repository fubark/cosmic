const std = @import("std");
const stdx = @import("stdx");
const Backend = @import("build_options").GraphicsBackend;

const graphics = @import("graphics.zig");
const FontGroupId = graphics.font.FontGroupId;
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

    pub fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .lines = std.ArrayList(TextLine).init(alloc),
            .width = 0,
            .height = 0,
        };
    }

    pub fn deinit(self: @This()) void {
        self.lines.deinit();
    }
};

pub const TextLine = struct {
    start_idx: u32,
    end_idx: u32,
    height: f32,
};

/// Used to traverse text one UTF-8 codepoint at a time.
pub const TextGlyphIterator = struct {
    inner: switch (Backend) {
        .OpenGL => gpu.TextGlyphIterator,
        .Vulkan => struct {},
        .Test => testg.TextGlyphIterator,
        else => stdx.panic("unsupported"),
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
            .OpenGL => return gpu.TextGlyphIterator.nextCodepoint(&self.inner, &self.state, {}, null),
            .Test => return testg.TextGlyphIterator.nextCodepoint(&self.inner, &self.state),
            else => stdx.panic("unsupported"),
        }
    }

    pub inline fn setIndex(self: *Self, i: usize) void {
        switch (Backend) {
            .OpenGL => return gpu.TextGlyphIterator.setIndex(&self.inner, i),
            .Test => return testg.TextGlyphIterator.setIndex(&self.inner, i),
            else => stdx.panic("unsupported"),
        }
    }
};