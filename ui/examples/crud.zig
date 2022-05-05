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
const Column = ui.widgets.Column;
const Text = ui.widgets.Text;
const TextButton = ui.widgets.TextButton;
const TextField = ui.widgets.TextField;
const Grow = ui.widgets.Grow;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;
const Sized = ui.widgets.Sized;
const ScrollList = ui.widgets.ScrollList;

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

    buf: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    filter: []const u8,

    list: WidgetRef(ScrollList),
    first_tf: WidgetRef(TextField),
    last_tf: WidgetRef(TextField),

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        self.buf = std.ArrayList([]const u8).init(c.alloc);
        self.alloc = c.alloc;
        self.filter = "";
    }

    pub fn deinit(node: *ui.Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        for (self.buf.items) |str| {
            self.alloc.free(str);
        }
        self.alloc.free(self.filter);
        self.buf.deinit();
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        const S = struct {
            fn onClickCreate(self_: *Self, _: MouseUpEvent) void {
                const first = if (self_.first_tf.widget.getValue().len == 0) "Foo" else self_.first_tf.widget.getValue();
                const last = if (self_.last_tf.widget.getValue().len == 0) "Bar" else self_.last_tf.widget.getValue();
                const new_name = std.fmt.allocPrint(self_.alloc, "{s}, {s}", .{ first, last }) catch unreachable;
                self_.buf.append(new_name) catch unreachable;
            }

            fn onClickDelete(self_: *Self, _: MouseUpEvent) void {
                const selected_idx = self_.list.widget.getSelectedIdx();
                if (selected_idx != ui.NullId) {
                    self_.alloc.free(self_.buf.items[selected_idx]);
                    _ = self_.buf.orderedRemove(selected_idx);
                }
            }

            fn onClickUpdate(self_: *Self, _: MouseUpEvent) void {
                const selected_idx = self_.list.widget.getSelectedIdx();
                if (selected_idx != ui.NullId) {
                    const first = if (self_.first_tf.widget.getValue().len == 0) "Foo" else self_.first_tf.widget.getValue();
                    const last = if (self_.last_tf.widget.getValue().len == 0) "Bar" else self_.last_tf.widget.getValue();
                    const new_name = std.fmt.allocPrint(self_.alloc, "{s}, {s}", .{ first, last }) catch unreachable;
                    self_.alloc.free(self_.buf.items[selected_idx]);
                    self_.buf.items[selected_idx] = new_name;
                }
            }

            fn onChangeSearch(self_: *Self, val: []const u8) void {
                self_.alloc.free(self_.filter);
                self_.filter = self_.alloc.dupe(u8, val) catch unreachable;
            }

            fn buildItem(self_: *Self, c_: *C.Build(), i: u32) ui.FrameId {
                if (std.mem.startsWith(u8, self_.buf.items[i], self_.filter)) {
                    return c_.decl(Text, .{ .text = self_.buf.items[i] });
                } else {
                    return ui.NullFrameId;
                }
            }
        };

        const d = c.decl;

        const left_side = d(Column, .{
            .children = c.list(.{
                d(Grow, .{
                    .child = d(Sized, .{
                        .width = 300,
                        .child = d(ScrollList, .{
                            .bind = &self.list,
                            .children = c.range(self.buf.items.len, self, S.buildItem),
                        }),
                    }),
                }),
            }),
        });

        const right_side = d(Column, .{
            .spacing = 20,
            .children = c.list(.{
                d(Row, .{
                    .children = c.list(.{
                        d(Padding, .{
                            .child = d(Text, .{ .text = "First: ", .color = Color.White }),
                        }),
                        d(Grow, .{
                            .child = d(TextField, .{
                                .bind = &self.first_tf,
                            }),
                        }),
                    }),
                }),
                d(Row, .{
                    .children = c.list(.{
                        d(Padding, .{
                            .child = d(Text, .{ .text = "Last: ", .color = Color.White }),
                        }),
                        d(Grow, .{
                            .child = d(TextField, .{
                                .bind = &self.last_tf,
                            }),
                        }),
                    }),
                }),
                d(Row, .{
                    .spacing = 10,
                    .children = c.list(.{
                        d(Grow, .{
                            .child = d(TextButton, .{
                                .text = "Create",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, MouseUpEvent, S.onClickCreate),
                            }),
                        }),
                        d(Grow, .{
                            .child = d(TextButton, .{
                                .text = "Update",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, MouseUpEvent, S.onClickUpdate),
                            }),
                        }),
                        d(Grow, .{
                            .child = d(TextButton, .{
                                .text = "Delete",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, MouseUpEvent, S.onClickDelete),
                            }),
                        }),
                    }),
                }),
            })
        });

        return d(Center, .{
            .child = d(Sized, .{
                .width = 600,
                .height = 500,
                .child = d(Column, .{
                    .expand = false,
                    .children = c.list(.{
                        d(Padding, .{
                            .padding = 0,
                            .pad_bottom = 20,
                            .child = d(Row, .{
                                .children = c.list(.{
                                    d(Padding, .{
                                        .padding = 10,
                                        .child = d(Text, .{
                                            .text = "Search: ",
                                            .color = Color.White,
                                        }),
                                    }),
                                    d(Grow, .{
                                        .child = d(TextField, .{
                                            .onChangeEnd = c.funcExt(self, []const u8, S.onChangeSearch),
                                        }),
                                    })
                                }),
                            }),
                        }),
                        d(Row, .{
                            .spacing = 10,
                            .children = c.list(.{
                                left_side,
                                right_side,
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
    app.init("CRUD");
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