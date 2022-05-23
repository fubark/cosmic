const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const platform = @import("platform");
const MouseUpEvent = platform.MouseUpEvent;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const Row = ui.widgets.Row;
const Column = ui.widgets.Column;
const Text = ui.widgets.Text;
const TextButton = ui.widgets.TextButton;
const TextField = ui.widgets.TextField;
const Flex = ui.widgets.Flex;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;
const Sized = ui.widgets.Sized;
const ScrollList = ui.widgets.ScrollList;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    buf: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    filter: []const u8,

    list: ui.WidgetRef(ScrollList),
    first_tf: ui.WidgetRef(TextField),
    last_tf: ui.WidgetRef(TextField),

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
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

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClickCreate(self_: *Self, _: MouseUpEvent) void {
                const first_w = self_.first_tf.getWidget();
                const last_w = self_.last_tf.getWidget();
                const first = if (first_w.getValue().len == 0) "Foo" else first_w.getValue();
                const last = if (last_w.getValue().len == 0) "Bar" else last_w.getValue();
                const new_name = std.fmt.allocPrint(self_.alloc, "{s}, {s}", .{ first, last }) catch unreachable;
                self_.buf.append(new_name) catch unreachable;
            }

            fn onClickDelete(self_: *Self, _: MouseUpEvent) void {
                const selected_idx = self_.list.getWidget().getSelectedIdx();
                if (selected_idx != ui.NullId) {
                    self_.alloc.free(self_.buf.items[selected_idx]);
                    _ = self_.buf.orderedRemove(selected_idx);
                }
            }

            fn onClickUpdate(self_: *Self, _: MouseUpEvent) void {
                const first_w = self_.first_tf.getWidget();
                const last_w = self_.last_tf.getWidget();
                const selected_idx = self_.list.getWidget().getSelectedIdx();
                if (selected_idx != ui.NullId) {
                    const first = if (first_w.getValue().len == 0) "Foo" else first_w.getValue();
                    const last = if (last_w.getValue().len == 0) "Bar" else last_w.getValue();
                    const new_name = std.fmt.allocPrint(self_.alloc, "{s}, {s}", .{ first, last }) catch unreachable;
                    self_.alloc.free(self_.buf.items[selected_idx]);
                    self_.buf.items[selected_idx] = new_name;
                }
            }

            fn onChangeSearch(self_: *Self, val: []const u8) void {
                self_.alloc.free(self_.filter);
                self_.filter = self_.alloc.dupe(u8, val) catch unreachable;
            }

            fn buildItem(self_: *Self, c_: *ui.BuildContext, i: u32) ui.FrameId {
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
                d(Flex, .{
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
                        d(Flex, .{
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
                        d(Flex, .{
                            .child = d(TextField, .{
                                .bind = &self.last_tf,
                            }),
                        }),
                    }),
                }),
                d(Row, .{
                    .spacing = 10,
                    .children = c.list(.{
                        d(Flex, .{
                            .child = d(TextButton, .{
                                .text = "Create",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, S.onClickCreate),
                            }),
                        }),
                        d(Flex, .{
                            .child = d(TextButton, .{
                                .text = "Update",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, S.onClickUpdate),
                            }),
                        }),
                        d(Flex, .{
                            .child = d(TextButton, .{
                                .text = "Delete",
                                .corner_radius = 10,
                                .onClick = c.funcExt(self, S.onClickDelete),
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
                                            .text = c.fmt("Search: ({} Entries)", .{self.buf.items.len}),
                                            .color = Color.White,
                                        }),
                                    }),
                                    d(Flex, .{
                                        .child = d(TextField, .{
                                            .onChangeEnd = c.funcExt(self, S.onChangeSearch),
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

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    app.init("CRUD");
    defer app.deinit();
    app.runEventLoop(update);
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
            return c.decl(App, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    app.ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height) catch unreachable;
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() *const u8 {
        return helper.wasmInit(&app, "CRUD");
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) *const u8 {
        return helper.wasmUpdate(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        app.deinit();
        stdx.wasm.deinit();
    }
} else struct {};