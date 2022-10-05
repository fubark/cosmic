const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const w = ui.widgets;
const log = stdx.log.scoped(.switch_);

pub const Switch = struct {
    props: struct {
        label: ?[]const u8 = null,
        init_val: bool = false,
        onChange: ?stdx.Function(fn (bool) void) = null,
    },

    is_set: bool,
    anim: ui.SimpleTween,

    const Width = 60;
    const Height = 30;
    const InnerPadding = 5;
    const InnerRadius = (Height - InnerPadding * 2) / 2;

    pub fn init(self: *Switch, _: *ui.InitContext) void {
        self.is_set = self.props.init_val;
        self.anim = ui.SimpleTween.init(100);
        self.anim.finish();
    }
    
    pub fn build(self: *Switch, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn onClick(self_: *Switch, _: ui.MouseUpEvent) void {
                self_.toggle();
            }
        };

        return w.MouseArea(.{ .onClick = c.funcExt(self, S.onClick) },
            w.Sized(.{
                .width = Width,
                .height = Height,
            }, .{}),
        );
    }

    pub fn isSet(self: Switch) bool {
        return self.is_set;
    }

    pub fn toggle(self: *Switch) void {
        self.is_set = !self.is_set;
        self.anim.reset();
        if (self.props.onChange) |cb| {
            cb.call(.{ self.is_set });
        }
    }

    pub fn render(self: *Switch, c: *ui.RenderContext) void {
        const g = c.gctx;
        const bounds = c.getAbsBounds();

        if (self.is_set) {
            g.setFillColor(Color.Blue);
        } else {
            g.setFillColor(Color.DarkGray);
        }
        c.fillRoundBBox(bounds, bounds.computeHeight() * 0.5);

        g.setFillColor(Color.White);
        self.anim.step(c.delta_ms);
        var offset_x: f32 = undefined;
        if (self.is_set) {
            offset_x = self.anim.t * (Width - InnerPadding * 2 - InnerRadius * 2);
        } else {
            offset_x = (1 - self.anim.t) * (Width - InnerPadding * 2 - InnerRadius * 2);
        }
        g.fillCircle(bounds.min_x + InnerPadding + InnerRadius + offset_x, bounds.min_y + InnerPadding + InnerRadius, InnerRadius);
    }
};