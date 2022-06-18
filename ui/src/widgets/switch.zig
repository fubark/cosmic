const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const widgets = ui.widgets;
const MouseArea = widgets.MouseArea;
const Row = widgets.Row;
const Flex = widgets.Flex;
const Sized = widgets.Sized;
const Text = widgets.Text;
const log = stdx.log.scoped(.switch_);

pub const Switch = struct {
    props: struct {
        label: ?[]const u8 = null,
        init_val: bool = false,
        onChange: ?stdx.Function(fn (bool) void) = null,
    },

    is_set: bool,
    anim: ui.SimpleTween,

    const Self = @This();
    const Width = 60;
    const Height = 30;
    const InnerPadding = 5;
    const InnerRadius = (Height - InnerPadding * 2) / 2;

    pub fn init(self: *Self, _: *ui.InitContext) void {
        self.is_set = self.props.init_val;
        self.anim = ui.SimpleTween.init(100);
        self.anim.finish();
    }
    
    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClick(self_: *Self, _: platform.MouseUpEvent) void {
                self_.toggle();
            }
        };

        const d = c.decl;
        return d(MouseArea, .{
            .onClick = c.funcExt(self, S.onClick),
            .child = d(Sized, .{
                .width = Width,
                .height = Height,
            }),
        });
    }

    pub fn isSet(self: Self) bool {
        return self.is_set;
    }

    pub fn toggle(self: *Self) void {
        self.is_set = !self.is_set;
        self.anim.reset();
        if (self.props.onChange) |cb| {
            cb.call(.{ self.is_set });
        }
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        const g = c.g;
        const alo = c.getAbsLayout();

        if (self.is_set) {
            g.setFillColor(Color.Blue);
        } else {
            g.setFillColor(Color.DarkGray);
        }
        g.fillRoundRect(alo.x, alo.y, alo.width, alo.height, alo.height * 0.5);

        g.setFillColor(Color.White);
        self.anim.step(c.delta_ms);
        var offset_x: f32 = undefined;
        if (self.is_set) {
            offset_x = self.anim.t * (Width - InnerPadding * 2 - InnerRadius * 2);
        } else {
            offset_x = (1 - self.anim.t) * (Width - InnerPadding * 2 - InnerRadius * 2);
        }
        g.fillCircle(alo.x + InnerPadding + InnerRadius + offset_x, alo.y + InnerPadding + InnerRadius, InnerRadius);
    }
};