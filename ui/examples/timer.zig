const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const Duration = stdx.time.Duration;
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const importWidget = ui.Import.init;
const WidgetRef = ui.WidgetRef;

const Column = ui.widgets.Column;
const Row = ui.widgets.Row;
const Text = ui.widgets.Text;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;
const TextField = ui.widgets.TextField;
const Slider = ui.widgets.Slider;
const Sized = ui.widgets.Sized;
const ProgressBar = ui.widgets.ProgressBar;
const TextButton = ui.widgets.TextButton;
const Grow = ui.widgets.Grow;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const MyConfig = b: {
    var config = ui.Config{
        .Imports = ui.widgets.BaseWidgets,
    };
    config.Imports = config.Imports ++ &[_]ui.Import{
        importWidget(App),
    };
    break :b config;
};

pub const App = struct {
    const Self = @This();

    progress_bar: WidgetRef(ProgressBar),

    duration_secs: f32,
    progress_ms: f32,
    step_interval: ?u32,

    ctx: *ui.CommonContext,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.step_interval = c.addInterval(Duration.initSecsF(0.01), self, onStep);
        self.progress_ms = 0;
        self.duration_secs = 15;
        self.ctx = c.common;
    }

    fn onStep(self: *Self, e: ui.IntervalEvent) void {
        self.progress_ms += e.progress_ms;
        if (self.progress_ms >= self.duration_secs * 1000) {
            self.progress_ms = self.duration_secs * 1000;
            e.ctx.removeInterval(self.step_interval.?);
            self.step_interval = null;
        }
        self.progress_bar.widget.setValue(self.progress_ms/1000);
    }

    fn reset(self: *Self) void {
        if (self.step_interval == null) {
            self.step_interval = self.ctx.addInterval(Duration.initSecsF(0.01), self, onStep);
        } else {
            self.ctx.resetInterval(self.step_interval.?);
        }
        self.progress_ms = 0;
        self.progress_bar.widget.setValue(self.progress_ms/1000);
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        const S = struct {
            fn onChangeDuration(self_: *Self, val: i32) void {
                const duration_secs = @intToFloat(f32, val);
                self_.duration_secs = duration_secs;
                self_.reset();
            }
            fn onClickReset(self_: *Self, e: MouseUpEvent) void {
                _ = e;
                self_.reset();
            }
        };

        return c.decl(Center, .{
            .child = c.decl(Sized, .{
                .width = 400,
                .child = c.decl(Column, .{
                    .expand = false,
                    .spacing = 20,
                    .children = c.list(.{
                        c.decl(Row, .{
                            .children = c.list(.{
                                c.decl(Text, .{
                                    .text = "Elapsed Time: ",
                                    .color = Color.White,
                                }),
                                c.decl(Grow, .{
                                    .child = c.decl(ProgressBar, .{
                                        .bind = &self.progress_bar,
                                        .max_val = self.duration_secs,
                                    }),
                                }),
                            }),
                        }),
                        c.decl(Row, .{
                            .children = c.list(.{
                                c.decl(Text, .{
                                    .text = c.fmt("{d:.0}ms", .{self.progress_ms}),
                                    .color = Color.Blue,
                                }),
                            }),
                        }),
                        c.decl(Row, .{
                            .children = c.list(.{
                                c.decl(Text, .{
                                    .text = "Duration: ",
                                    .color = Color.White,
                                }),
                                c.decl(Grow, .{
                                    .child = c.decl(Slider, .{
                                        .init_val = @floatToInt(i32, self.duration_secs),
                                        .min_val = 1,
                                        .max_val = 30,
                                        .onChange = c.funcExt(self, i32, S.onChangeDuration),
                                    }),
                                }),
                            }),
                        }),
                        c.decl(Row, .{
                            .children = c.list(.{
                                c.decl(Grow, .{
                                    .child = c.decl(TextButton, .{
                                        .text = "Reset",
                                        .corner_radius = 10,
                                        .onClick = c.funcExt(self, MouseUpEvent, S.onClickReset),
                                    }),
                                }),
                            }),
                        }),
                    }),
                }),
            }),
        });
    }
};

var app: helper.App = undefined;
var ui_mod: ui.Module(MyConfig) = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    init();
    defer deinit();
    app.runEventLoop(update);
}

fn init() void {
    app.init("Timer");
    ui_mod.init(app.alloc, app.g);
    ui_mod.addInputHandlers(&app.dispatcher);
}

fn deinit() void {
    ui_mod.deinit();
    app.deinit();
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *MyConfig.Build()) ui.FrameId {
            return c.decl(App, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height);
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