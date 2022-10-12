const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const Duration = stdx.time.Duration;
const platform = @import("platform");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const u = ui.widgets;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    progress_bar: ui.WidgetRef(u.ProgressBarT),

    duration_secs: f32,
    progress_ms: f32,
    step_interval: ?u32,

    ctx: *ui.CommonContext,
    node: *ui.Node,

    pub fn init(self: *App, c: *ui.InitContext) void {
        self.step_interval = c.addInterval(Duration.initSecsF(0.01), self, onStep);
        self.progress_ms = 0;
        self.duration_secs = 15;
        self.ctx = c.common;
        self.node = c.node;
    }

    fn onStep(self: *App, e: ui.IntervalEvent) void {
        self.progress_ms += e.progress_ms;
        if (self.progress_ms >= self.duration_secs * 1000) {
            self.progress_ms = self.duration_secs * 1000;
            e.ctx.removeInterval(self.step_interval.?);
            self.step_interval = null;
        }
        self.progress_bar.getWidget().setValue(self.progress_ms/1000);
    }

    fn reset(self: *App) void {
        if (self.step_interval == null) {
            self.step_interval = self.ctx.addInterval(self.node, Duration.initSecsF(0.01), self, onStep);
        } else {
            self.ctx.resetInterval(self.step_interval.?);
        }
        self.progress_ms = 0;
        self.progress_bar.getWidget().setValue(self.progress_ms/1000);
    }

    pub fn build(self: *App, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn onChangeDuration(self_: *App, val: i32) void {
                const duration_secs = @intToFloat(f32, val);
                self_.duration_secs = duration_secs;
                self_.reset();
            }
            fn onClickReset(self_: *App, e: ui.MouseUpEvent) void {
                _ = e;
                self_.reset();
            }
        };

        const t_style = u.TextStyle{
            .color = Color.White,
        };
        const t_style2 = u.TextStyle{
            .color = Color.Blue,
        };
        const tb_style = u.TextButtonStyle{
            .border = .{
                .cornerRadius = 10,
            },
        };

        return u.Center(.{}, 
            u.Sized(.{ .width = 400 },
                u.Column(.{ .expandChildWidth = true, .spacing = 20 }, &.{
                    u.Row(.{}, &.{
                        u.Text(.{
                            .text = "Elapsed Time: ",
                            .style = t_style,
                        }),
                        u.Flex(.{}, 
                            u.ProgressBar(.{
                                .bind = &self.progress_bar,
                                .max_val = self.duration_secs,
                            }),
                        ),
                    }),
                    u.Row(.{}, &.{
                        u.Text(.{
                            .text = c.fmt("{d:.0}ms", .{self.progress_ms}),
                            .style = t_style2,
                        }),
                    }),
                    u.Row(.{}, &.{
                        u.Text(.{
                            .text = "Duration: ",
                            .style = t_style,
                        }),
                        u.Flex(.{},
                            u.Slider(.{
                                .init_val = @floatToInt(i32, self.duration_secs),
                                .min_val = 1,
                                .max_val = 30,
                                .onChange = c.funcExt(self, S.onChangeDuration),
                            }),
                        ),
                    }),
                    u.Row(.{}, &.{
                        u.Flex(.{}, 
                            u.TextButton(.{
                                .text = "Reset",
                                .style = tb_style,
                                .onClick = c.funcExt(self, S.onClickReset),
                            }),
                        ),
                    }),
                }),
            ),
        );
    }
};

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    try app.init("Timer");
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
        return helper.wasmInit(&app, "Timer");
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