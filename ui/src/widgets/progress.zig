const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const ui = @import("../ui.zig");
const log = stdx.log.scoped(.render);

pub const ProgressBar = struct {
    props: *const struct {
        max_val: f32 = 100,
        init_val: f32 = 0,
        bar_color: Color = Color.Blue,
    },

    value: f32,

    pub fn init(self: *ProgressBar, c: *ui.InitContext) void {
        _ = c;
        self.value = self.props.init_val;
    }

    pub fn setValue(self: *ProgressBar, value: f32) void {
        self.value = value;
    }

    pub fn layout(self: *ProgressBar, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;
        const min_width = 200;
        const min_height = 25;

        const cstr = c.getSizeConstraints();
        var res = ui.LayoutSize.init(min_width, min_height);
        res.growToMin(cstr);
        return res;
    }

    pub fn render(self: *ProgressBar, c: *ui.RenderContext) void {
        const g = c.gctx;
        const bounds = c.getAbsBounds();

        g.setFillColor(Color.DarkGray);
        c.fillBBox(bounds);
        g.setFillColor(self.props.bar_color);
        const progress_width = (self.value / self.props.max_val) * bounds.computeWidth();
        g.fillRectBounds(bounds.min_x, bounds.min_y, bounds.min_x + progress_width, bounds.max_y);
    }
};