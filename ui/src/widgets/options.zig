const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const Row = ui.widgets.Row;
const Flex = ui.widgets.Flex;
const Text = ui.widgets.Text;
const Slider = ui.widgets.Slider;
const SliderFloat = ui.widgets.SliderFloat;
const Switch = ui.widgets.Switch;
const MouseArea = ui.widgets.MouseArea;
const Padding = ui.widgets.Padding;

// Wrappers over existing widgets to present like a option setting widget.

pub const SliderOption = SliderOptionBase(false);
pub const SliderFloatOption = SliderOptionBase(true);

fn SliderOptionBase(comptime is_float: bool) type {
    const Inner = if (is_float) SliderFloat else Slider;
    const InnerProps = ui.WidgetProps(Inner);
    return struct {
        props: struct {
            label: []const u8 = "Slider",
            slider: InnerProps,
        },

        inner: ui.WidgetRef(Inner),

        const Self = @This();

        pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
            const d = c.decl;
            return d(Row, .{
                .valign = .Center,
                .children = c.list(.{
                    d(Flex, .{
                        .flex = 1,
                        .child = d(Text, .{
                            .text = self.props.label,
                            .color = Color.White,
                            .font_size = 14,
                        }),
                    }),
                    d(Flex, .{
                        .flex = 3,
                        .child = d(Padding, .{
                            .pad_left = 20,
                            .child = d(Inner, .{
                                .bind = &self.inner,
                                .spread = self.props.slider,
                            }),
                        })
                    })
                }),
            });
        }
    };
}

// TODO: Use .spread like SliderOption
pub const SwitchOption = struct {
    props: struct {
        label: []const u8 = "Switch",
        init_val: bool = false,
        onChange: ?stdx.Function(fn (bool) void) = null,
    },

    inner: ui.WidgetRef(Switch),

    const Self = @This();

    pub fn isSet(self: *Self) bool {
        return self.inner.getWidget().isSet();
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClick(self_: *Self, _: platform.MouseUpEvent) void {
                self_.inner.getWidget().toggle();
            }
        };
        const d = c.decl;
        return d(MouseArea, .{
            .onClick = c.funcExt(self, S.onClick),
            .child = d(Row, .{
                .valign = .Center,
                .children = c.list(.{
                    d(Flex, .{
                        .child = d(Text, .{
                            .text = self.props.label,
                            .color = Color.White,
                        }),
                    }),
                    d(Switch, .{
                        .bind = &self.inner,
                        .init_val = self.props.init_val,
                        .onChange = self.props.onChange,
                    }),
                }),
            }),
        });
    }
};