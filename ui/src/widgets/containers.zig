const stdx = @import("stdx");
const ui = @import("../ui.zig");
const log = stdx.log.scoped(.containers);

/// Provides padding around a child widget.
pub const Padding = struct {
    props: struct {
        pad_top: ?f32 = null,
        pad_right: ?f32 = null,
        pad_bottom: ?f32 = null,
        pad_left: ?f32 = null,
        padding: f32 = 10,
        child: ui.FrameId = ui.NullFrameId,
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = self;
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        _ = self;

        var pad_top = self.props.pad_top orelse self.props.padding;
        var pad_right = self.props.pad_right orelse self.props.padding;
        var pad_bottom = self.props.pad_bottom orelse self.props.padding;
        var pad_left = self.props.pad_left orelse self.props.padding;

        const h_pad = pad_left + pad_right;
        const v_pad = pad_top + pad_bottom;

        const cstr = c.getSizeConstraint();
        const node = c.getNode();
        if (node.children.items.len == 0) {
            return ui.LayoutSize.init(h_pad, v_pad);
        }

        const child = node.children.items[0];
        if (!c.prefer_exact_width_or_height) {
            const child_cstr = cstr.toIncSize(-h_pad, -v_pad);
            var child_size = c.computeLayout(child, child_cstr);
            c.setLayout(child, ui.Layout.init(pad_left, pad_top, child_size.width, child_size.height));
            return child_size.toIncSize(h_pad, v_pad);
        } else {
            const child_cstr = cstr.toIncSize(-h_pad, -v_pad);
            const child_size = c.computeLayoutStretch(child, child_cstr, c.prefer_exact_width, c.prefer_exact_height);
            c.setLayout(child, ui.Layout.init(pad_left, pad_top, child_size.width, child_size.height));
            return child_size.toIncSize(h_pad, v_pad);
        }
    }
};

pub const Sized = struct {
    props: struct {
        /// If width is not provided, this container will shrink to the child's width.
        width: ?f32 = null,

        /// If height is not provided, this container will shrink to the child's height.
        height: ?f32 = null,

        child: ui.FrameId = ui.NullFrameId,
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        if (self.props.child != ui.NullFrameId) {
            var child_cstr = c.getSizeConstraint();
            var prefer_exact_width = c.prefer_exact_width;
            var prefer_exact_height = c.prefer_exact_height;
            if (self.props.width) |width| {
                child_cstr.width = width;
                prefer_exact_width = true;
            }
            if (self.props.height) |height| {
                child_cstr.height = height;
                prefer_exact_height = true;
            }

            const child = c.getNode().children.items[0];
            const child_size = c.computeLayoutStretch(child, child_cstr, prefer_exact_width, prefer_exact_height);
            c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));

            var res = ui.LayoutSize.init(0, 0);
            res.width = self.props.width orelse child_size.width;
            res.height = self.props.height orelse child_size.height;
            return res;
        } else {
            var res = ui.LayoutSize.init(0, 0);
            res.width = self.props.width orelse 0;
            res.height = self.props.height orelse 0;
            return res;
        }
    }
};

pub const Center = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        vcenter: bool = true,
        hcenter: bool = true,
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        const cstr = c.getSizeConstraint();

        if (self.props.child == ui.NullFrameId) {
            return cstr;
        }

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayout(child, cstr);
        child_size.cropTo(cstr);

        const x = if (self.props.hcenter) (cstr.width - child_size.width)/2 else 0;
        const y = if (self.props.vcenter) (cstr.height - child_size.height)/2 else 0;

        c.setLayout(child, ui.Layout.init(x, y, child_size.width, child_size.height));
        return cstr;
    }
};

const StretchMethod = enum(u3) {
    None = 0,
    Both = 1,
    Width = 2,
    Height = 3,
    WidthAndKeepRatio = 4,
    HeightAndKeepRatio = 5,
};

/// When method = WidthAndKeepRatio, the width is stretched and the height is adjusted to keep the aspect ratio.
/// When method = HeightAndKeepRatio, the height is stretched and the width is adjusted to keep the aspect ratio.
pub const Stretch = struct {
    props: struct {
        child: ui.FrameId = ui.NullFrameId,
        method: StretchMethod = .Both,

        /// Width to height ratio.
        aspect_ratio: f32 = 1,
    },

    const Self = @This();

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        _ = c;
        return self.props.child;
    }

    pub fn layout(self: *Self, c: *ui.LayoutContext) ui.LayoutSize {
        var cstr = c.getSizeConstraint();
        switch (self.props.method) {
            .WidthAndKeepRatio => cstr.height = cstr.width / self.props.aspect_ratio,
            .HeightAndKeepRatio => cstr.width = cstr.height * self.props.aspect_ratio,
            else => {},
        }

        if (self.props.child == ui.NullFrameId) {
            return cstr;
        }

        const h_stretch = self.props.method == .Both or self.props.method == .Width or self.props.method == .WidthAndKeepRatio or self.props.method == .HeightAndKeepRatio;
        const v_stretch = self.props.method == .Both or self.props.method == .Height or self.props.method == .WidthAndKeepRatio or self.props.method == .HeightAndKeepRatio;

        const node = c.getNode();
        const child = node.children.items[0];
        var child_size = c.computeLayoutStretch(child, cstr, h_stretch, v_stretch);
        child_size.cropTo(cstr);

        c.setLayout(child, ui.Layout.init(0, 0, child_size.width, child_size.height));
        var res = child_size;
        if (h_stretch) {
            res.width = cstr.width;
        }
        if (v_stretch) {
            res.height = cstr.height;
        }
        return res;
    }
};

// TODO: Container with more comprehensive properties.
// pub const Container = struct {
//     const Self = @This();
// };