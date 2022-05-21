const std = @import("std");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");

const NullId = std.math.maxInt(u32);

pub const Text = struct {
    props: struct {
        text: ?[]const u8,
        font_size: f32 = 20,
        font_id: graphics.font.FontId = NullId,
        color: Color = Color.Black,
    },

    const Self = @This();

    pub fn build(_: *Self, _: *ui.BuildContext) ui.FrameId {
        return ui.NullFrameId;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.text != null) {
            const font_gid = c.getFontGroupForSingleFontOrDefault(self.props.font_id);
            const m = c.common.measureText(font_gid, self.props.font_size, self.props.text.?);
            return ui.LayoutSize.init(m.width, m.height);
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        const g = c.g;
        const alo = c.getAbsLayout();

        if (self.props.text != null) {
            if (self.props.font_id == NullId) {
                g.setFont(g.getDefaultFontId(), self.props.font_size);
            } else {
                g.setFont(self.props.font_id, self.props.font_size);
            }
            g.setFillColor(self.props.color);
            g.fillText(alo.x, alo.y, self.props.text.?);
        }
    }
};