const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");

pub const ProgressBar = struct {
    props: struct {
        max_val: f32 = 100,
        init_val: f32 = 0,
        bar_color: Color = Color.Blue,
    },

    value: f32,

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
        _ = c;
        self.value = self.props.init_val;
    }

    pub fn setValue(self: *Self, value: f32) void {
        self.value = value;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const min_width = 200;
        const min_height = 25;

        const cstr = c.getSizeConstraint();
        var res = ui.LayoutSize.init(min_width, min_height);
        if (c.prefer_exact_width) {
            res.width = cstr.width;
        }
        return res;
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        const g = c.gctx;
        const alo = c.getAbsLayout();

        g.setFillColor(Color.DarkGray);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);
        g.setFillColor(self.props.bar_color);
        const progress_width = (self.value / self.props.max_val) * alo.width;
        g.fillRect(alo.x, alo.y, progress_width, alo.height);
    }
};