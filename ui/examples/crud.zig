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
    buf: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    filter: []const u8,

    list: ui.WidgetRef(u.ScrollListT),
    first_tf: ui.WidgetRef(u.TextFieldT),
    last_tf: ui.WidgetRef(u.TextFieldT),

    pub fn init(self: *App, c: *ui.InitContext) void {
        self.buf = std.ArrayList([]const u8).init(c.alloc);
        self.alloc = c.alloc;
        self.filter = "";
    }

    pub fn deinit(self: *App, _: *ui.DeinitContext) void {
        for (self.buf.items) |str| {
            self.alloc.free(str);
        }
        self.alloc.free(self.filter);
        self.buf.deinit();
    }

    pub fn build(self: *App, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn onClickCreate(self_: *App, _: ui.MouseUpEvent) void {
                const first_w = self_.first_tf.getWidget();
                const last_w = self_.last_tf.getWidget();
                const first = if (first_w.getValue().len == 0) "Foo" else first_w.getValue();
                const last = if (last_w.getValue().len == 0) "Bar" else last_w.getValue();
                const new_name = std.fmt.allocPrint(self_.alloc, "{s}, {s}", .{ first, last }) catch unreachable;
                self_.buf.append(new_name) catch unreachable;
            }

            fn onClickDelete(self_: *App, _: ui.MouseUpEvent) void {
                const selected_idx = self_.list.getWidget().getSelectedIdx();
                if (selected_idx != ui.NullId) {
                    self_.alloc.free(self_.buf.items[selected_idx]);
                    _ = self_.buf.orderedRemove(selected_idx);
                }
            }

            fn onClickUpdate(self_: *App, _: ui.MouseUpEvent) void {
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

            fn onChangeSearch(self_: *App, val: []const u8) void {
                self_.alloc.free(self_.filter);
                self_.filter = self_.alloc.dupe(u8, val) catch unreachable;
            }

            fn buildItem(self_: *App, _: *ui.BuildContext, i: u32) ui.FramePtr {
                if (std.mem.startsWith(u8, self_.buf.items[i], self_.filter)) {
                    return u.Text(.{ .text = self_.buf.items[i] });
                } else {
                    return .{};
                }
            }
        };

        const left_side = u.Column(.{}, &.{
            u.Flex(.{}, 
                u.Sized(.{ .width = 300 },
                    u.ScrollList(.{ .bind = &self.list },
                        c.tempRange(self.buf.items.len, self, S.buildItem),
                    ),
                ),
            ),
        });

        const t_style = u.TextStyle{
            .color = Color.White,
        };
        const tb_style = u.TextButtonStyle{
            .border = .{
                .cornerRadius = 10,
            },
        };

        const right_side = u.Column(.{ .spacing = 20 }, &.{
            u.Row(.{}, &.{
                u.Padding(.{}, 
                    u.Text(.{ .text = "First: ", .style = t_style }),
                ),
                u.Flex(.{}, 
                    u.TextField(.{ .bind = &self.first_tf }),
                ),
            }),
            u.Row(.{}, &.{
                u.Padding(.{}, 
                    u.Text(.{ .text = "Last: ", .style = t_style }),
                ),
                u.Flex(.{},
                    u.TextField(.{ .bind = &self.last_tf }),
                ),
            }),
            u.Row(.{ .spacing = 10 }, &.{
                u.Flex(.{},
                    u.TextButton(.{
                        .text = "Create",
                        .style = tb_style,
                        .onClick = c.funcExt(self, S.onClickCreate),
                    }),
                ),
                u.Flex(.{},
                    u.TextButton(.{
                        .text = "Update",
                        .style = tb_style,
                        .onClick = c.funcExt(self, S.onClickUpdate),
                    }),
                ),
                u.Flex(.{}, 
                    u.TextButton(.{
                        .text = "Delete",
                        .style = tb_style,
                        .onClick = c.funcExt(self, S.onClickDelete),
                    }),
                ),
            })
        });

        return u.Center(.{},
            u.Sized(.{ .width = 600, .height = 500 }, 
                u.Column(.{}, &.{
                    u.Padding(.{ .padding = 0, .pad_bottom = 20 },
                        u.Row(.{}, &.{
                            u.Padding(.{ .padding = 10 },
                                u.Text(.{
                                    .text = c.fmt("Search: ({} Entries)", .{self.buf.items.len}),
                                    .style = t_style,
                                }),
                            ),
                            u.Flex(.{}, 
                                u.TextField(.{ .onChangeEnd = c.funcExt(self, S.onChangeSearch) }),
                            )
                        }),
                    ),
                    u.Row(.{ .spacing = 10 }, &.{
                        left_side,
                        right_side,
                    }),
                }),
            ),
        );
    }
};

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    try app.init("CRUD");
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
        return helper.wasmInit(&app, "CRUD");
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