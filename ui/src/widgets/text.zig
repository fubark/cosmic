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
        font_id: graphics.FontId = NullId,
        color: Color = Color.Black,
    },

    tlo: graphics.TextLayout,
    use_layout: bool,

    pub fn init(self: *Text, c: *ui.InitContext) void {
        self.tlo = graphics.TextLayout.init(c.alloc);
        self.use_layout = false;
    }

    pub fn deinit(self: *Text, _: std.mem.Allocator) void {
        self.tlo.deinit();
    }

    pub fn build(_: *Text, _: *ui.BuildContext) ui.FrameId {
        return ui.NullFrameId;
    }

    pub fn layout(self: *Text, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.text != null) {
            const font_gid = c.getFontGroupForSingleFontOrDefault(self.props.font_id);

            const cstr = c.getSizeConstraints();
            if (cstr.max_width == ui.ExpandedWidth) {
                const m = c.measureText(font_gid, self.props.font_size, self.props.text.?);
                self.use_layout = false;
                return ui.LayoutSize.init(m.width, m.height);
            } else {
                // Compute text layout. Perform word wrap.
                c.textLayout(font_gid, self.props.font_size, self.props.text.?, cstr.max_width, &self.tlo);
                self.use_layout = true;
                return ui.LayoutSize.init(self.tlo.width, self.tlo.height);
            }
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Text, c: *ui.RenderContext) void {
        const g = c.gctx;
        const bounds = c.getAbsBounds();

        if (self.props.text != null) {
            if (self.props.font_id == NullId) {
                g.setFont(g.getDefaultFontId(), self.props.font_size);
            } else {
                g.setFont(self.props.font_id, self.props.font_size);
            }
            g.setFillColor(self.props.color);

            if (self.use_layout) {
                var y = bounds.min_y;
                for (self.tlo.lines.items) |line| {
                    const text = self.props.text.?[line.start_idx..line.end_idx];
                    g.fillText(bounds.min_x, y, text);
                    y += line.height;
                }
            } else {
                g.fillText(bounds.min_x, bounds.min_y, self.props.text.?);
            }
        }
    }
};