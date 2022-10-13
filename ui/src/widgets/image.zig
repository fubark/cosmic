const std = @import("std");
const stdx = @import("stdx");
const graphics = @import("graphics");
const platform = @import("platform");

const ui = @import("../ui.zig");
const w = ui.widgets;

const NullId = std.math.maxInt(u32);

pub const Image = struct {
    props: *const struct {
        imageId: graphics.ImageId = NullId,
        tint: graphics.Color = graphics.Color.White,
        width: ?f32 = null,
        height: ?f32 = null,
    },

    pub fn build(_: *Image, _: *ui.BuildContext) ui.FramePtr {
        return .{};
    }

    pub fn init(self: *Image, c: *ui.InitContext) void {
        _ = self;
        _ = c;
    }

    pub fn layout(self: *Image, ctx: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.imageId != NullId) {
            const size = ctx.gctx.getImageSize(self.props.imageId);
            const width = self.props.width orelse @intToFloat(f32, size.x);
            const height = self.props.height orelse @intToFloat(f32, size.y);
            return ui.LayoutSize.init(width, height);
        } else {
            return ui.LayoutSize.init(0, 0);
        }
    }

    pub fn render(self: *Image, ctx: *ui.RenderContext) void {
        if (self.props.imageId != NullId) {
            const bounds = ctx.getAbsBounds();
            const gctx = ctx.getGraphics();
            gctx.drawImageScaledTinted(bounds.min_x, bounds.min_y, bounds.computeWidth(), bounds.computeHeight(), self.props.imageId, self.props.tint);
        }
    }
};