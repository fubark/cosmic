const std = @import("std");
const stdx = @import("stdx");
const Point2 = stdx.math.Point2(u32);
const t = stdx.testing;
const log = stdx.log.scoped(.rect_bin_packer);

const SpanId = u32;
const NullId = std.math.maxInt(SpanId);
const ResizeCallback = std.meta.FnPtr(fn (ctx: ?*anyopaque, width: u32, height: u32) void);
const ResizeCallbackItem = struct {
    ctx: ?*anyopaque,
    cb: ResizeCallback,
};

/// Rectangle bin packer implemented with the skyline bottom-left algorithm.
/// Trades some performance to pack rects more efficiently.
/// Perform best fit placement. The placement with the lowest y is chosen, ties are broken with lowest waste.
/// Does not own the underlying buffer and only cares about providing the next available rectangle and triggering resize events.
/// When the buffer needs to resize, the width and height are doubled and resize callbacks are invoked.
pub const RectBinPacker = struct {
    spans: stdx.ds.PooledHandleSLLBuffer(SpanId, Span),

    /// Current spans from left to right. 
    head: SpanId,

    /// In-order callbacks.
    resize_cbs: std.ArrayList(ResizeCallbackItem),

    width: u32,
    height: u32,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, width: u32, height: u32) Self {
        var new = Self{
            .spans = stdx.ds.PooledHandleSLLBuffer(SpanId, Span).init(alloc),
            .resize_cbs = std.ArrayList(ResizeCallbackItem).init(alloc),
            .width = width,
            .height = height,
            .head = undefined,
        };
        new.head = new.spans.add(.{ .x = 0, .y = 0, .width = width }) catch @panic("error");
        return new;
    }

    pub fn deinit(self: *Self) void {
        self.spans.deinit();
        self.resize_cbs.deinit();
    }

    pub fn addResizeCallback(self: *Self, ctx: ?*anyopaque, cb: ResizeCallback) void {
        self.resize_cbs.append(.{
            .ctx = ctx,
            .cb = cb,
        }) catch @panic("error");
    }

    pub fn removeResizeCallback(self: *Self, needle: ResizeCallback) void {
        for (self.resize_cbs.items) |it, i| {
            if (it.cb == needle) {
                self.resize_cbs.orderedRemove(i);
                break;
            }
        }
    }

    pub fn allocRect(self: *Self, width: u32, height: u32) Point2 {
        if (self.findRectSpace(width, height)) |res| {
            self.allocRectResult(res);
            return Point2.init(res.x, res.y);
        } else {
            // Perform resize.
            while (true) {
                self.width *= 2;
                self.height *= 2;

                // Add or extend a span.
                const last_id = self.spans.getLast(self.head).?;
                const last = self.spans.getPtrNoCheck(last_id);
                if (last.y == 0) {
                    // Extend.
                    last.width = self.width - last.x;
                } else {
                    const start_x = last.x + last.width;
                    _ = self.spans.insertAfter(last_id, .{
                        .x = start_x,
                        .y = 0,
                        .width = self.width - start_x,
                    }) catch @panic("error");
                }

                if (self.findRectSpace(width, height)) |res| {
                    self.allocRectResult(res);
                    // Invoke resize callbacks only after we allocated the rect.
                    for (self.resize_cbs.items) |it| {
                        it.cb(it.ctx, self.width, self.height);
                    }
                    return Point2.init(res.x, res.y);
                }
            }
        }
    }

    fn allocRectResult(self: *Self, res: FindSpaceResult) void {
        // Remove all spans that are covered by the requested width.
        var visited_width: u32 = 0;
        var cur = if (res.prev_span_id == NullId) self.head else self.spans.getNextNoCheck(res.prev_span_id);
        while (cur != NullId) {
            const node = self.spans.nodes.getPtrNoCheck(cur);
            const span = node.data;
            const next = node.next;

            visited_width += span.width;
            if (visited_width <= res.width) {
                // Completely covered.
                self.spans.nodes.remove(cur);
            } else {
                // Modify existing span.
                node.data.x = res.x + res.width;
                node.data.width = visited_width - res.width;
                break;
            }
            cur = next;
        }

        // Reattach the list.
        if (res.prev_span_id == NullId) {
            self.head = cur;
            const head = self.spans.getPtrNoCheck(self.head);
            if (head.y == res.y + res.height) {
                // Extend.
                head.width += head.x;
                head.x = 0;
            } else {
                // Create span.
                self.head = self.spans.insertBeforeHeadNoCheck(self.head, .{
                    .x = 0,
                    .y = res.y + res.height,
                    .width = res.width,
                }) catch @panic("error");
            }
        } else {
            const prev = self.spans.getPtrNoCheck(res.prev_span_id);
            if (prev.y == res.y + res.height) {
                // Extend prev.
                prev.width += res.width;
                if (cur != NullId) {
                    const next = self.spans.nodes.getNoCheck(cur);
                    if (next.data.y == res.y + res.height) {
                        // Extend prev again by removing next.
                        const next_next = next.next;
                        prev.width += next.data.width;
                        self.spans.nodes.remove(cur);
                        cur = next_next;
                    }
                }
                self.spans.nodes.getPtrNoCheck(res.prev_span_id).next = cur;
            } else {
                self.spans.nodes.getPtrNoCheck(res.prev_span_id).next = cur;
                if (cur != NullId) {
                    const next = self.spans.getPtrNoCheck(cur);
                    if (next.y == res.y + res.height) {
                        // Extend next.
                        next.x = res.x;
                        next.width += res.width;
                    } else {
                        // Create span.
                        _ = self.spans.insertAfter(res.prev_span_id, .{
                            .x = res.x,
                            .y = res.y + res.height,
                            .width = res.width,
                        }) catch @panic("error");
                    }
                } else {
                    // Create span.
                    _ = self.spans.insertAfter(res.prev_span_id, .{
                        .x = res.x,
                        .y = res.y + res.height,
                        .width = res.width,
                    }) catch @panic("error");
                }
            }
        }
    }

    /// Returns the result of the next available position that can fit the requested rect.
    /// Does not allocate the space. Returns null if no position was found.
    fn findRectSpace(self: Self, width: u32, height: u32) ?FindSpaceResult {
        var best_prev_id: SpanId = NullId;
        var best_waste: u32 = NullId;
        var best_x: u32 = NullId;
        var best_y: u32 = NullId;
        var prev: SpanId = NullId;
        var cur = self.head;
        while (cur != NullId) {
            const node = self.spans.nodes.getNoCheck(cur);
            const span = node.data;
            if (span.x + width > self.width) {
                // Can not fit.
                break;
            }

            var waste: u32 = undefined;
            const y_fit = self.findLowestY(cur, span.x, width, &waste);
            if (y_fit + height <= self.height) {
                // Best fit picks the lowest y. If there is a tie, pick the one with the lowest waste.
                if (y_fit < best_y or (y_fit == best_y and waste < best_waste)) {
                    best_y = y_fit;
                    best_x = span.x;
                    best_waste = waste;
                    best_prev_id = prev;
                }
            }
            prev = cur;
            cur = node.next;
        }

        if (best_y == NullId) {
            // No placement was found. Need to resize the atlas.
            return null;
        } else {
            return FindSpaceResult{
                .prev_span_id = best_prev_id,
                .x = best_x,
                .y = best_y,
                .width = width,
                .height = height,
            };
        }
    }

    /// Returns the lowest y value that can fit the requested width starting at a node.
    fn findLowestY(self: Self, cur_: SpanId, start_x: u32, req_width: u32, out_waste: *u32) u32 {
        const end_x = start_x + req_width;
        var min_y: u32 = 0;
        var waste: u32 = 0;
        var visited_width: u32 = 0;
        var cur = cur_;
        while (cur != NullId) {
            const node = self.spans.nodes.getNoCheck(cur);
            const span = node.data;
            if (span.x >= end_x) {
                break;
            }
            if (span.y > min_y) {
                // Elevate min_y and add waste for visited width.
                waste += visited_width * (span.y - min_y);
                min_y = span.y;
                visited_width += span.width;
            } else {
                // Add waste below min_y.
                var under_width = span.width;
                if (under_width + visited_width > req_width) {
                    under_width = req_width - visited_width;
                }
                waste += under_width * (min_y - span.y);
                visited_width += span.width;
            }
            cur = node.next;
        }
        out_waste.* = waste;
        return min_y;
    }
};

const Span = struct {
    x: u32,
    y: u32,
    width: u32,
};

const FindSpaceResult = struct {
    prev_span_id: SpanId,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

test "Extend prev span after insert." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(5, 5);
    try t.eq(packer.spans.size(), 2);
    pos = packer.allocRect(5, 5);

    try t.eq(packer.spans.size(), 1);
    const head = packer.spans.getNoCheck(packer.head);
    try t.eq(head, .{
        .x = 0,
        .y = 5,
        .width = 10,
    });
}

test "Insert new tail." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(5, 5);
    try t.eq(packer.spans.size(), 2);
    pos = packer.allocRect(5, 1);
    try t.eq(packer.spans.size(), 2);

    pos = packer.allocRect(5, 1);
    try t.eq(packer.spans.size(), 2);
    var node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 5, .width = 5 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 5, .y = 2, .width = 5 });
}

test "Extend next span after insert." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(4, 5);
    pos = packer.allocRect(2, 2);
    try t.eq(packer.spans.size(), 3);
    var node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 5, .width = 4 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 4, .y = 2, .width = 2 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 6, .y = 0, .width = 4 });
    try t.eq(node.next, NullId);

    pos = packer.allocRect(4, 4);
    try t.eq(packer.spans.size(), 3);
    node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 5, .width = 4 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 4, .y = 2, .width = 2 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 6, .y = 4, .width = 4 });
    try t.eq(node.next, NullId);

    pos = packer.allocRect(2, 2);
    try t.eq(packer.spans.size(), 2);
    const last_id = packer.spans.getLast(packer.head).?;
    const last = packer.spans.getNoCheck(last_id);
    try t.eq(last, .{
        .x = 4,
        .y = 4,
        .width = 6,
    });
}

test "Merge prev, inserted, and next span into prev." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(4, 4);
    pos = packer.allocRect(2, 2);
    pos = packer.allocRect(4, 4);
    try t.eq(packer.spans.size(), 3);
    pos = packer.allocRect(2, 2);

    try t.eq(packer.spans.size(), 1);
    const head = packer.spans.getNoCheck(packer.head);
    try t.eq(head, .{
        .x = 0,
        .y = 4,
        .width = 10,
    });
}

test "Extend next after insert." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(4, 1);
    pos = packer.allocRect(6, 4);
    try t.eq(packer.spans.size(), 2);

    pos = packer.allocRect(4, 3);
    try t.eq(packer.spans.size(), 1);
    const head = packer.spans.getNoCheck(packer.head);
    try t.eq(head, .{
        .x = 0,
        .y = 4,
        .width = 10,
    });
}

test "Insert new head." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(4, 1);
    pos = packer.allocRect(6, 4);
    try t.eq(packer.spans.size(), 2);

    pos = packer.allocRect(4, 2);
    try t.eq(packer.spans.size(), 2);
    var node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 3, .width = 4 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 4, .y = 4, .width = 6 });
}

test "Stack from not enough remaing space at the right." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(6, 1);
    pos = packer.allocRect(6, 1);
    pos = packer.allocRect(6, 1);
    try t.eq(packer.spans.size(), 2);
    var node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 3, .width = 6 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 6, .y = 0, .width = 4 });
}

test "Resize." {
    var packer = RectBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    const Context = struct {
        width: u32,
        height: u32,
    };
    const S = struct {
        fn onResize(ptr: ?*anyopaque, width: u32, height: u32) void {
            const ctx_ = stdx.mem.ptrCastAlign(*Context, ptr);
            ctx_.width = width;
            ctx_.height = height;
        }
    };
    var ctx = Context{ .width = 0, .height = 0 };
    packer.addResizeCallback(&ctx, S.onResize);

    _ = packer.allocRect(11, 11);
    try t.eq(ctx.width, 20);
    try t.eq(ctx.height, 20);

    try t.eq(packer.spans.size(), 2);
    var node = packer.spans.nodes.getNoCheck(packer.head);
    try t.eq(node.data, .{ .x = 0, .y = 11, .width = 11 });
    node = packer.spans.nodes.getNoCheck(node.next);
    try t.eq(node.data, .{ .x = 11, .y = 0, .width = 9 });
}

/// Allocation is constant time but inefficient with space allocation.
/// Tracks the next available pos and the max height of the current row.
/// Upon resize, only the height is doubled since context info is lost from the other rows.
pub const FastBinPacker = struct {
    width: u32,
    height: u32,

    /// Start pos for the next glyph.
    next_x: u32,
    next_y: u32,

    /// The max height of the current row.
    /// Used to advance next_y once width is reached for the current row.
    row_height: u32,

    /// In-order callbacks.
    resize_cbs: std.ArrayList(ResizeCallbackItem),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, width: u32, height: u32) @This() {
        return .{
            .width = width,
            .height = height,
            .next_x = 0,
            .next_y = 0,
            .row_height = 0,
            .resize_cbs = std.ArrayList(ResizeCallbackItem).init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        self.resize_cbs.deinit();
    }

    pub fn allocRect(self: *Self, width: u32, height: u32) Point2 {
        if (self.next_x + width > self.width) {
            // Wrap to the next row.
            if (self.row_height == 0) {
                // Current width can't fit.
                @panic("Requested width too large.");
            }
            self.next_y += self.row_height;
            self.next_x = 0;
            self.row_height = 0;
            return self.allocRect(width, height);
        }
        if (self.next_y + height > self.height) {
            // Increase buffer height.
            self.height *= 2;

            // Invoke resize callbacks only after we allocated the rect.
            for (self.resize_cbs.items) |it| {
                it.cb(it.ctx, self.width, self.height);
            }
            return self.allocRect(width, height);
        }
        defer self.advancePos(width, height);
        return Point2.init(self.next_x, self.next_y);
    }

    fn advancePos(self: *Self, width: u32, height: u32) void {
        self.next_x += width;
        if (width > self.row_height) {
            self.row_height = height;
        }
    }
};

test "FastBinPacker" {
    var packer = FastBinPacker.init(t.alloc, 10, 10);
    defer packer.deinit();

    var pos = packer.allocRect(5, 5);
    try t.eq(pos, Point2.init(0, 0));
    pos = packer.allocRect(5, 5);
    try t.eq(pos, Point2.init(5, 0));
}