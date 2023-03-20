const stdx = @import("stdx");
const graphics = @import("graphics");
const ui = @import("../ui.zig");
const u = ui.widgets;

pub const Menu = struct {
    props: *const struct {
        openLabel: ui.FramePtr = .{},
        children: ui.FrameListPtr = .{},
    },

    popover: ?u32,

    pub fn init(self: *Menu, _: *ui.InitContext) void {
        self.popover = null;
    }

    pub fn build(self: *Menu, ctx: *ui.BuildContext) ui.FramePtr {
        return u.Button(.{ .onClick = ctx.funcExt(self, onClick) },
            self.props.openLabel.dupe(),
        );
    }

    fn onClick(self: *Menu, e: ui.MouseUpEvent) void {
        const S = struct {
            fn buildPopover(ptr: ?*anyopaque, ctx: *ui.BuildContext) ui.FramePtr {
                const self_ = stdx.ptrCastAlign(*Menu, ptr);
                return u.Container(.{ .bgColor = graphics.Color.Green, .width = 150 }, 
                    ctx.build(u.ColumnT, .{
                        .expandChildWidth = true,
                        .children = self_.props.children.dupe(),
                    }),
                );
            }
            fn onPopoverClose(ptr: ?*anyopaque) void {
                const self_ = stdx.ptrCastAlign(*Menu, ptr);
                self_.popover = null;
            }
        };

        if (self.popover == null) {
            self.popover = e.ctx.getRoot().showPopover(e.ctx.node, self, S.buildPopover, .{
                .close_ctx = self, 
                .close_cb = S.onPopoverClose,
                .closeAfterMouseLeave = false,
                .closeAfterMouseClick = true,
                .placement = .bottom,
                .margin_from_src = 0,
                .top_layer = true,
            }) catch stdx.fatal();
        }
    }
};