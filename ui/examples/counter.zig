const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const platform = @import("platform");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const u = ui.widgets;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    counter: u32,

    pub fn init(self: *App, _: *ui.InitContext) void {
        self.counter = 0;
    }

    pub fn build(self: *App, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn onClick(self_: *App, _: ui.MouseUpEvent) void {
                self_.counter += 1;
            }
        };
        const t_style = u.TextStyle{
            .color = Color.White,
        };
        const tb_style = u.TextButtonStyle{
            .border = .{
                .cornerRadius = 10,
            },
        };
        return u.Center(.{}, 
            u.Row(.{}, &.{
                u.Padding(.{
                    .padding = 10,
                    .pad_left = 30,
                    .pad_right = 30, }, 
                    u.Text(.{
                        .text = c.fmt("{}", .{self.counter}),
                        .style = t_style,
                    }),
                ),
                u.TextButton(.{
                    .text = "Count",
                    .onClick = c.funcExt(self, S.onClick),
                    .style = tb_style,
                }),
            }),
        );
    }
};

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    try app.init("Counter");
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
        return helper.wasmInit(&app, "Counter");
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