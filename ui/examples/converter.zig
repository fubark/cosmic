const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const u = ui.widgets;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    tc_field: ui.WidgetRef(u.TextFieldT),
    tf_field: ui.WidgetRef(u.TextFieldT),

    pub fn build(self: *App, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn onChangeTc(self_: *App, text: []const u8) void {
                const tc = std.fmt.parseFloat(f32, text) catch return;
                self_.tf_field.getWidget().setValueFmt("{d:.2}", .{ tc * 9/5 + 32 });
            }
            fn onChangeTf(self_: *App, text: []const u8) void {
                const tf = std.fmt.parseFloat(f32, text) catch return;
                self_.tc_field.getWidget().setValueFmt("{d:.2}", .{ (tf - 32) * 5 / 9 });
            }
        };
        const t_style = u.TextStyle{
            .color = Color.White,
        };
        return u.Center(.{}, 
            u.Row(.{}, &.{
                u.TextField(.{
                    .bind = &self.tc_field,
                    .width = 200,
                    .onChangeEnd = c.funcExt(self, S.onChangeTc),
                }),
                u.Padding(.{}, 
                    u.Text(.{
                        .text = "Celsius =",
                        .style = t_style,
                    }),
                ),
                u.TextField(.{
                    .bind = &self.tf_field,
                    .width = 200,
                    .onChangeEnd = c.funcExt(self, S.onChangeTf),
                }),
                u.Padding(.{}, 
                    u.Text(.{
                        .text = "Fahrenheit",
                        .style = t_style,
                    }),
                ),
            }),
        );
    }
};

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    try app.init("Converter");
    defer app.deinit();
    app.runEventLoop(update);
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FramePtr {
            return c.build(App, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    app.ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height) catch unreachable;
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() [*]const u8 {
        return helper.wasmInit(&app, "Converter");
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) [*]const u8 {
        return helper.wasmUpdate(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        app.deinit();
        stdx.wasm.deinit();
    }
} else struct {};