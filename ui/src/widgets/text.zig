const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const log = stdx.log.scoped(.text);

const NullId = std.math.maxInt(u32);

pub const Text = struct {
    props: struct {
        text: ?[]const u8,
        font_size: f32 = 20,
        font_id: graphics.font.FontId = NullId,
        color: Color = Color.Black,
    },

    tlo: graphics.TextLayout,

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
        self.tlo = graphics.TextLayout.init(c.alloc);
    }

    pub fn deinit(node: *ui.Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        self.tlo.deinit();
    }

    pub fn build(_: *Self, _: *ui.BuildContext) ui.FrameId {
        return ui.NullFrameId;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.text != null) {
            const font_gid = c.getFontGroupForSingleFontOrDefault(self.props.font_id);

            const cstr = c.getSizeConstraint();
            if (cstr.width == std.math.inf_f32) {
                const m = c.measureText(font_gid, self.props.font_size, self.props.text.?);
                return ui.LayoutSize.init(m.width, m.height);
            } else {
                // Compute text layout. Perform word wrap.
                c.textLayout(font_gid, self.props.font_size, self.props.text.?, cstr.width, &self.tlo);
                return ui.LayoutSize.init(self.tlo.width, self.tlo.height);
            }
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

            var y = alo.y;
            for (self.tlo.lines.items) |line| {
                const text = self.props.text.?[line.start_idx..line.end_idx];
                g.fillText(alo.x, y, text);
                y += line.height;
            }
        }
    }
};