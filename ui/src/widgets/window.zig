const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;
const platform = @import("platform");

const ui = @import("../ui.zig");
const u = ui.widgets;
const log = stdx.log.scoped(.window);

pub const Window = struct {
    props: struct {
        bgColor: Color = Color.DarkGray,
        title: ?[]const u8,
        init_x: f32,
        init_y: f32,
        child: ui.FrameId = ui.NullFrameId,
        onClose: ?stdx.Function(fn (ui.WidgetRef(Window)) void) = null,
    },

    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// For dragging window.
    drag_start_offset_x: i16,
    drag_start_offset_y: i16,

    /// For resizing window.
    drag_start_x: i16,
    drag_start_y: i16,
    drag_start_win_left: f32,
    drag_start_win_right: f32,
    drag_start_win_top: f32,
    drag_start_win_bottom: f32,
    resize_type: ResizeType,

    const TitleBarHeight = 30;

    pub fn init(self: *Window, ctx: *ui.InitContext) void {
        _ = ctx;
        self.x = self.props.init_x;
        self.y = self.props.init_y;
        self.width = 300;
        self.height = 200;

        ctx.setMouseDownHandler(self, onMouseDown);
    }

    pub fn build(self: *Window, ctx: *ui.BuildContext) ui.FrameId {
        return u.Positioned(.{ .x = self.x, .y = self.y, .width = self.width, .height = self.height },
            u.MouseHoverArea(.{
                .hitTest = ctx.funcExt(self, hitResizeBorder),
                .onHoverChange = ctx.funcExt(self, onHoverResizeBorder),
                .onHoverMove = ctx.funcExt(self, onHoverMoveResizeBorder) },
                u.MouseDragArea(.{
                    .hitTest = ctx.funcExt(self, hitResizeBorder),
                    .useInitialMouseDown = true,
                    .onDragStart = ctx.funcExt(self, onDragStartBorder),
                    .onDragMove = ctx.funcExt(self, onDragMoveBorder), },
                    u.Column(.{}, &.{
                        u.Container(.{ .bgColor = Color.Gray, .width = ui.ExpandedWidth, .height = TitleBarHeight },
                            u.Row(.{}, &.{
                                u.Flex(.{},
                                    u.MouseDragArea(.{
                                        .onDragStart = ctx.funcExt(self, onDragStartTitle),
                                        .onDragMove = ctx.funcExt(self, onDragMoveTitle), },
                                        u.Text(.{ .text = self.props.title }),
                                    ),
                                ),
                                u.Button(.{ .onClick = ctx.funcExt(ctx.node, onClickClose) }, 
                                    u.Text(.{ .text = "close" }),
                                ),
                            }),
                        ),
                        u.Container(.{ .bgColor = self.props.bgColor, .width = ui.ExpandedWidth, .height = ui.ExpandedHeight }, 
                            self.props.child,
                        ),
                    }),
                ),
            ),
        );
    }

    fn onMouseDown(_: *Window, _: ui.MouseDownEvent) ui.EventResult {
        return .stop;
    }

    /// Assumes (x, y) is in border bounds.
    fn computeResizeType(self: *Window, x: i16, y: i16) ResizeType {
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        if (xf <= self.x + ResizeBorderSize) {
            if (yf <= self.y + ResizeBorderSize) {
                return .top_left;
            } else if (yf < self.y + self.height - ResizeBorderSize) {
                return .left;
            } else {
                return .bottom_left;
            }
        } else if (xf < self.x + self.width - ResizeBorderSize) {
            if (yf <= self.y + ResizeBorderSize) {
                return .top;
            } else {
                return .bottom;
            }
        } else {
            if (yf <= self.y + ResizeBorderSize) {
                return .top_right;
            } else if (yf < self.y + self.height - ResizeBorderSize) {
                return .right;
            } else {
                return .bottom_right;
            }
        }
    }

    /// Set cursor depending on resize type.
    fn updateCursor(resize_type: ResizeType) void {
        switch (resize_type) {
            .top_left,
            .bottom_right => platform.setSystemCursor(.size_nwse),
            .left,
            .right => platform.setSystemCursor(.size_we),
            .top_right,
            .bottom_left => platform.setSystemCursor(.size_nesw),
            .top,
            .bottom => platform.setSystemCursor(.size_ns),
        }
    }

    fn onHoverMoveResizeBorder(self: *Window, x: i16, y: i16) void {
        const t = self.computeResizeType(x, y);
        updateCursor(t);
    }

    fn onHoverResizeBorder(self: *Window, e: ui.HoverChangeEvent) void {
        _ = self;
        if (e.hovered) {
            const t = self.computeResizeType(e.x, e.y);
            updateCursor(t);
        } else {
            platform.setSystemCursor(.default);
        }
    }

    fn onDragStartBorder(self: *Window, e: ui.DragStartEvent) void {
        self.resize_type = self.computeResizeType(e.x, e.y);
        self.drag_start_x = e.x;
        self.drag_start_y = e.y;
        self.drag_start_win_left = self.x;
        self.drag_start_win_right = self.x + self.width;
        self.drag_start_win_top = self.y;
        self.drag_start_win_bottom = self.y + self.height;
    }

    fn resizeLeft(self: *Window, x: i16) void {
        const dx = x - self.drag_start_x;
        var new_left = self.drag_start_win_left + @intToFloat(f32, dx);
        if (new_left > self.drag_start_win_right - MinWidth) {
            new_left = self.drag_start_win_right - MinWidth;
        }
        if (new_left < 0) {
            new_left = 0;
        }
        self.x = new_left;
        self.width = self.drag_start_win_right - new_left;
    }

    fn resizeRight(self: *Window, x: i16, max_right: f32) void {
        const dx = x - self.drag_start_x;
        var new_right = self.drag_start_win_right + @intToFloat(f32, dx);
        if (new_right < self.drag_start_win_left + MinWidth) {
            new_right = self.drag_start_win_left + MinWidth;
        }
        if (new_right > max_right) {
            new_right = max_right;
        }
        self.width = new_right - self.drag_start_win_left;
    }

    fn resizeTop(self: *Window, y: i16) void {
        const dy = y - self.drag_start_y;
        var new_top = self.drag_start_win_top + @intToFloat(f32, dy);
        if (new_top > self.drag_start_win_bottom - MinHeight) {
            new_top = self.drag_start_win_bottom - MinHeight;
        }
        if (new_top < 0) {
            new_top = 0;
        }
        self.y = new_top;
        self.height = self.drag_start_win_bottom - new_top;
    }

    fn resizeBottom(self: *Window, y: i16, max_bottom: f32) void {
        const dy = y - self.drag_start_y;
        var new_bot = self.drag_start_win_bottom + @intToFloat(f32, dy);
        if (new_bot < self.drag_start_win_top + MinHeight) {
            new_bot = self.drag_start_win_top + MinHeight;
        }
        if (new_bot > max_bottom) {
            new_bot = max_bottom;
        }
        self.height = new_bot - self.drag_start_win_top;
    }

    const MinWidth = 100;
    const MinHeight = 100;
    fn onDragMoveBorder(self: *Window, e: ui.DragMoveEvent) void {
        const root_size = e.ctx.getRootLayoutSize();
        switch (self.resize_type) {
            .left => {
                self.resizeLeft(e.x);
            },
            .right => {
                self.resizeRight(e.x, root_size.width);
            },
            .top => {
                self.resizeTop(e.y);
            },
            .bottom => {
                self.resizeBottom(e.y, root_size.height);
            },
            .top_left => {
                self.resizeLeft(e.x);
                self.resizeTop(e.y);
            },
            .top_right => {
                self.resizeRight(e.x, root_size.width);
                self.resizeTop(e.y);
            },
            .bottom_left => {
                self.resizeLeft(e.x);
                self.resizeBottom(e.y, root_size.height);
            },
            .bottom_right => {
                self.resizeRight(e.x, root_size.width);
                self.resizeBottom(e.y, root_size.height);
            },
        }
    }

    const ResizeBorderSize = 5;
    fn hitResizeBorder(self: *Window, x: i16, y: i16) bool {
        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        const outer = stdx.math.BBox.init(self.x, self.y, self.x + self.width, self.y + self.height);
        if (outer.containsPt(xf, yf)) {
            const inner = stdx.math.BBox.init(outer.min_x + ResizeBorderSize, outer.min_y + ResizeBorderSize, outer.max_x - ResizeBorderSize, outer.max_y - ResizeBorderSize);
            if (!inner.containsPt(xf, yf)) {
                return true;
            }
        }
        return false;
    } 

    fn onDragStartTitle(self: *Window, e: ui.DragStartEvent) void {
        self.drag_start_offset_x = e.getSrcOffsetX();
        self.drag_start_offset_y = e.getSrcOffsetY();
    }

    fn onDragMoveTitle(self: *Window, e: ui.DragMoveEvent) void {
        self.x = @intToFloat(f32, e.x - self.drag_start_offset_x);
        self.y = @intToFloat(f32, e.y - self.drag_start_offset_y);
        const root_size = e.ctx.getRootLayoutSize();
        if (self.x < 0) {
            self.x = 0;
        } else if (self.x + self.width > root_size.width) {
            self.x = root_size.width - self.width;
        }
        if (self.y < 0) {
            self.y = 0;
        } else if (self.y + self.height > root_size.height) {
            self.y = root_size.height - self.height;
        }
    }

    fn onClickClose(node: *ui.Node, _: ui.MouseUpEvent) void {
        const self = node.getWidget(Window);
        if (self.props.onClose) |cb| {
            const src = ui.WidgetRef(Window).init(node);
            cb.call(.{ src });
        }
    }
};

const ResizeType = enum(u4) {
    top_left = 0,
    top = 1,
    top_right = 2,
    right = 3,
    bottom_right = 4,
    bottom = 5,
    bottom_left = 6,
    left = 7,
};