const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");
const ui = @import("../ui.zig");
const w = ui.widgets;

const log = stdx.log.scoped(.file_dialog);

pub const FileDialog = struct {
    props: struct {
        init_cwd: []const u8,
        onResult: ?stdx.Function(fn (path: []const u8) void) = null,
    },

    alloc: std.mem.Allocator,
    cwd: std.ArrayList(u8),
    files: std.ArrayList(FileItem),
    window: *ui.widgets.ModalOverlay,
    scroll_list: ui.WidgetRef(w.ScrollListUI),

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
        self.alloc = c.alloc;
        self.cwd = std.ArrayList(u8).init(c.alloc);
        self.files = std.ArrayList(FileItem).init(c.alloc);
        self.window = c.node.parent.?.getWidget(ui.widgets.ModalOverlay);
        self.gotoDir(self.props.init_cwd);
    }

    pub fn deinit(node: *ui.Node, _: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        self.cwd.deinit();
        for (self.files.items) |it| {
            it.deinit(self.alloc);
        }
        self.files.deinit();
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn buildItem(self_: *Self, _: *ui.BuildContext, i: u32) ui.FrameId {
                return w.Text(.{
                    .text = self_.files.items[i].name,
                    .color = Color.White,
                });
            }
            fn onClickCancel(self_: *Self, e: platform.MouseUpEvent) void {
                _ = e;
                self_.window.requestClose();
            }
            fn onClickSave(self_: *Self, e: platform.MouseUpEvent) void {
                _ = e;
                const list = self_.scroll_list.getWidget();
                const idx = list.getSelectedIdx();
                if (idx != ui.NullId) {
                    if (self_.props.onResult) |cb| {
                        const name = self_.files.items[idx].name;
                        const path = std.fs.path.join(self_.alloc, &.{ self_.cwd.items, name }) catch @panic("error");
                        defer self_.alloc.free(path);
                        cb.call(.{ path });
                    }
                    self_.window.requestClose();
                }
            }
        };
        return w.Sized(.{ .width = 500, .height = 400 },
            w.Column(.{}, &.{
                w.Flex(.{ .stretch_width = true },
                    w.ScrollList(.{ .bind = &self.scroll_list, .bg_color = Color.init(50, 50, 50, 255) },
                        c.tempRange(self.files.items.len, self, S.buildItem),
                    ),
                ),
                w.Row(.{ .halign = .Right }, &.{
                    w.TextButton(.{
                        .text = "Cancel",
                        .onClick = c.funcExt(self, S.onClickCancel),
                    }),
                    w.TextButton(.{
                        .text = "Open",
                        .onClick = c.funcExt(self, S.onClickSave),
                    }),
                }),
            }),
        );
    }

    fn gotoDir(self: *Self, cwd: []const u8) void {
        self.cwd.clearRetainingCapacity();
        self.cwd.appendSlice(cwd) catch @panic("error");

        var dir = std.fs.openIterableDirAbsolute(self.cwd.items, .{}) catch @panic("error");
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch @panic("error")) |entry| {
            self.files.append(.{
                .name = self.alloc.dupe(u8, entry.name) catch @panic("error"),
                .kind = entry.kind,
            }) catch @panic("error");
        }
    }
};

const FileItem = struct {
    kind: std.fs.File.Kind,
    name: []const u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.name);
    }
};