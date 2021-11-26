const graphics = @import("graphics.zig");
const FontGroupId = graphics.font.FontGroupId;

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
