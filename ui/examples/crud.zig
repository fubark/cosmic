const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const platform = @import("platform");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const w = ui.widgets;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

pub const App = struct {
    buf: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    filter: []const u8,

    list: ui.WidgetRef(w.ScrollListT),
    first_tf: ui.WidgetRef(w.TextFieldT),
    last_tf: ui.WidgetRef(w.TextFieldT),

    pub fn init(self: *App, c: *ui.InitContext) void {
        self.buf = std.ArrayList([]const u8).init(c.alloc);
        self.alloc = c.alloc;
        self.filter = "";
    }

    pub fn deinit(self: *App, _: std.mem.Allocator) void {
        for (self.buf.items) |str| {
            self.alloc.free(str);
        }
        self.alloc.free(self.filter);
        self.buf.deinit();
    }

    pub fn build(self: *App, c: *ui.BuildContext) ui.FrameId {
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

            fn buildItem(self_: *App, _: *ui.BuildContext, i: u32) ui.FrameId {
                if (std.mem.startsWith(u8, self_.buf.items[i], self_.filter)) {
                    return w.Text(.{ .text = self_.buf.items[i] });
                } else {
                    return ui.NullFrameId;
                }
            }
        };

        const left_side = w.Column(.{}, &.{
            w.Flex(.{}, 
                w.Sized(.{ .width = 300 },
                    w.ScrollList(.{ .bind = &self.list },
                        c.tempRange(self.buf.items.len, self, S.buildItem),
                    ),
                ),
            ),
        });

        const right_side = w.Column(.{ .spacing = 20 }, &.{
            w.Row(.{}, &.{
                w.Padding(.{}, 
                    w.Text(.{ .text = "First: ", .color = Color.White }),
                ),
                w.Flex(.{}, 
                    w.TextField(.{ .bind = &self.first_tf }),
                ),
            }),
            w.Row(.{}, &.{
                w.Padding(.{}, 
                    w.Text(.{ .text = "Last: ", .color = Color.White }),
                ),
                w.Flex(.{},
                    w.TextField(.{ .bind = &self.last_tf }),
                ),
            }),
            w.Row(.{ .spacing = 10 }, &.{
                w.Flex(.{},
                    w.TextButton(.{
                        .text = "Create",
                        .corner_radius = 10,
                        .onClick = c.funcExt(self, S.onClickCreate),
                    }),
                ),
                w.Flex(.{},
                    w.TextButton(.{
                        .text = "Update",
                        .corner_radius = 10,
                        .onClick = c.funcExt(self, S.onClickUpdate),
                    }),
                ),
                w.Flex(.{}, 
                    w.TextButton(.{
                        .text = "Delete",
                        .corner_radius = 10,
                        .onClick = c.funcExt(self, S.onClickDelete),
                    }),
                ),
            })
        });

        return w.Center(.{},
            w.Sized(.{ .width = 600, .height = 500 }, 
                w.Column(.{}, &.{
                    w.Padding(.{ .padding = 0, .pad_bottom = 20 },
                        w.Row(.{}, &.{
                            w.Padding(.{ .padding = 10 },
                                w.Text(.{
                                    .text = c.fmt("Search: ({} Entries)", .{self.buf.items.len}),
                                    .color = Color.White,
                                }),
                            ),
                            w.Flex(.{}, 
                                w.TextField(.{ .onChangeEnd = c.funcExt(self, S.onChangeSearch) }),
                            )
                        }),
                    ),
                    w.Row(.{ .spacing = 10 }, &.{
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
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
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