const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const platform = @import("platform");

const ui = @import("../ui.zig");
const w = ui.widgets;

const NullId = std.math.maxInt(u32);

pub const Image = struct {
    props: struct {
        imageId: graphics.ImageId = NullId,
    },

    pub fn build(_: *Image, _: *ui.BuildContext) ui.FrameId {
        return ui.NullFrameId;
    }

    pub fn init(self: *Image, c: *ui.InitContext) void {
        _ = self;
        _ = c;
    }

    pub fn layout(self: *Image, ctx: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.imageId != NullId) {
            const size = ctx.gctx.getImageSize(self.props.imageId);
            return ui.LayoutSize.init(@intToFloat(f32, size.x), @intToFloat(f32, size.y));
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Image, ctx: *ui.RenderContext) void {
        const bounds = ctx.getAbsBounds();
        const gctx = ctx.getGraphics();

        gctx.drawImage(bounds.min_x, bounds.min_y, self.props.imageId);
    }
};