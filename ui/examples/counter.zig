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
const WidgetRef = ui.WidgetRef;

const Row = ui.widgets.Row;
const Text = ui.widgets.Text;
const TextButton = ui.widgets.TextButton;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;

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

    counter: u32,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        _ = c;
        self.counter = 0;
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        const S = struct {
            fn onClick(self_: *Self, _: MouseUpEvent) void {
                self_.counter += 1;
            }
        };

        return c.decl(Center, .{
            .child = c.decl(Row, .{
                .expand = false,
                .children = c.list(.{
                    c.decl(Padding, .{
                        .padding = 10,
                        .pad_left = 30,
                        .pad_right = 30,
                        .child = c.decl(Text, .{
                            .text = c.fmt("{}", .{self.counter}),
                            .color = Color.White,
                        }),
                    }),
                    c.decl(TextButton, .{
                        .text = "Count",
                        .onClick = c.funcExt(self, S.onClick),
                        .corner_radius = 10,
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
    app.init("Counter");
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