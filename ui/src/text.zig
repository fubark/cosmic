const graphics = @import("graphics");
const FontGroupId = graphics.font.FontGroupId;
const TextMetrics = graphics.TextMetrics;

pub const TextMeasure = struct {
    const Self = @This();

    measure: graphics.TextMeasure,

    needs_measure: bool,
    // measure: TextSize,
    // words: []const u8,

    pub fn init(text: []const u8, font_gid: FontGroupId, font_size: f32) Self {
        return .{
            .measure = .{
                .text = text,
                .font_gid = font_gid,
                .font_size = font_size,
            },
            .needs_measure = true,
        };
    }

    pub fn setText(self: *Self, _text: []const u8) void {
        self.measure.text = _text;
        self.needs_measure = true;
    }

    pub fn setFont(self: *Self, font_gid: FontGroupId, font_size: f32) void {
        self.measure.font_gid = font_gid;
        self.measure.font_size = font_size;
        self.needs_measure = true;
    }

    pub fn metrics(self: *Self) TextMetrics {
        return self.measure.res;
    }
};