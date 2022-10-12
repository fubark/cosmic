const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("../ui.zig");
const u = ui.widgets;

const log = stdx.log.scoped(.file_dialog);

pub const FileDialog = struct {
    props: struct {
        init_cwd: []const u8,
        onResult: stdx.Function(fn (path: []const u8) void) = .{},
        onRequestClose: stdx.Function(fn () void) = .{},
    },

    alloc: std.mem.Allocator,
    cwd: std.ArrayList(u8),
    files: std.ArrayList(FileItem),
    scroll_list: ui.WidgetRef(u.ScrollListT),

    pub fn init(self: *FileDialog, c: *ui.InitContext) void {
        self.alloc = c.alloc;
        self.cwd = std.ArrayList(u8).init(c.alloc);
        self.files = std.ArrayList(FileItem).init(c.alloc);
        self.gotoDir(self.props.init_cwd);
    }

    pub fn deinit(self: *FileDialog, _: *ui.DeinitContext) void {
        self.cwd.deinit();
        for (self.files.items) |it| {
            it.deinit(self.alloc);
        }
        self.files.deinit();
    }

    pub fn build(self: *FileDialog, c: *ui.BuildContext) ui.FramePtr {
        const S = struct {
            fn buildItem(self_: *FileDialog, _: *ui.BuildContext, i: u32) ui.FramePtr {
                const t_style = u.TextStyle{ .color = Color.White };
                return u.Text(.{
                    .text = self_.files.items[i].name,
                    .style = t_style,
                });
            }
            fn onClickCancel(self_: *FileDialog, e: ui.MouseUpEvent) void {
                _ = e;
                if (self_.props.onRequestClose.isPresent()) {
                    self_.props.onRequestClose.call(.{});
                }
            }
            fn onClickSave(self_: *FileDialog, e: ui.MouseUpEvent) void {
                _ = e;
                const list = self_.scroll_list.getWidget();
                const idx = list.getSelectedIdx();
                if (idx != ui.NullId) {
                    if (self_.props.onResult.isPresent()) {
                        const name = self_.files.items[idx].name;
                        const path = std.fs.path.join(self_.alloc, &.{ self_.cwd.items, name }) catch @panic("error");
                        defer self_.alloc.free(path);
                        self_.props.onResult.call(.{ path });
                    }
                    if (self_.props.onRequestClose.isPresent()) {
                        self_.props.onRequestClose.call(.{});
                    }
                }
            }
        };
        return u.Sized(.{ .width = 500, .height = 400 },
            u.Column(.{ .expandChildWidth = true }, &.{
                u.Flex(.{},
                    u.ScrollList(.{ .bind = &self.scroll_list, .bg_color = Color.init(50, 50, 50, 255) },
                        c.tempRange(self.files.items.len, self, S.buildItem),
                    ),
                ),
                u.Row(.{ .halign = .right }, &.{
                    u.TextButton(.{
                        .text = "Cancel",
                        .onClick = c.funcExt(self, S.onClickCancel),
                    }),
                    u.TextButton(.{
                        .text = "Open",
                        .onClick = c.funcExt(self, S.onClickSave),
                    }),
                }),
            }),
        );
    }

    fn gotoDir(self: *FileDialog, cwd: []const u8) void {
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

    pub fn deinit(self: FileItem, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
    }
};