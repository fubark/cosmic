const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const importWidget = ui.Import.init;
const Config = ui.Config;
const WidgetRef = ui.WidgetRef;

const Row = ui.widgets.Row;
const Text = ui.widgets.Text;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;
const TextField = ui.widgets.TextField;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    const Self = @This();

    tc_field: WidgetRef(TextField),
    tf_field: WidgetRef(TextField),

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onChangeTc(self_: *Self, text: []const u8) void {
                const tc = std.fmt.parseFloat(f32, text) catch return;
                self_.tf_field.getWidget().setValueFmt("{d:.2}", .{ tc * 9/5 + 32 });
            }
            fn onChangeTf(self_: *Self, text: []const u8) void {
                const tf = std.fmt.parseFloat(f32, text) catch return;
                self_.tc_field.getWidget().setValueFmt("{d:.2}", .{ (tf - 32) * 5 / 9 });
            }
        };

        return c.decl(Center, .{
            .child = c.decl(Row, .{
                .expand = false,
                .children = c.list(.{
                    c.decl(TextField, .{
                        .bind = &self.tc_field,
                        .width = 200,
                        .onChangeEnd = c.funcExt(self, S.onChangeTc),
                    }),
                    c.decl(Padding, .{
                        .child = c.decl(Text, .{
                            .text = "Celsius =",
                            .color = Color.White,
                        }),
                    }),
                    c.decl(TextField, .{
                        .bind = &self.tf_field,
                        .width = 200,
                        .onChangeEnd = c.funcExt(self, S.onChangeTf),
                    }),
                    c.decl(Padding, .{
                        .child = c.decl(Text, .{
                            .text = "Fahrenheit",
                            .color = Color.White,
                        }),
                    }),
                }),
            }),
        });
    }
};

var app: helper.App = undefined;
var ui_mod: ui.Module = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    init();
    defer deinit();
    app.runEventLoop(update);
}

fn init() void {
    app.init("Converter");
    ui_mod.init(app.alloc, app.g);
    ui_mod.addInputHandlers(&app.dispatcher);
}

fn deinit() void {
    ui_mod.deinit();
    app.deinit();
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
            return c.decl(App, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height) catch unreachable;
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() *const u8 {
        return helper.wasmInit(init);
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) *const u8 {
        return helper.wasmUpdate(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        helper.wasmDeinit(deinit);
    }
} else struct {};