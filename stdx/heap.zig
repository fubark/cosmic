const std = @import("std");
const stdx = @import("stdx.zig");
const builtin = @import("builtin");
const t = stdx.testing;

const log = stdx.log.scoped(.heap);

const IsWasm = builtin.target.cpu.arch == .wasm32;

const MeasureMemory = false;
var gpa: ?std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = MeasureMemory }) = null;
var wasm_gpa: WasmDefaultAllocator = undefined;
var wasm_gpa_inited = false;

pub fn getDefaultAllocator() std.mem.Allocator {
    if (IsWasm) {
        if (!wasm_gpa_inited) {
            wasm_gpa.init(.{}) catch stdx.fatal();
            wasm_gpa_inited = true;
        }
        return wasm_gpa.allocator();
        // return std.heap.page_allocator;
    } else {
        if (gpa == null) {
            gpa = .{};
        }
        return gpa.?.allocator();
    }
}

pub fn deinitDefaultAllocator() void {
    if (IsWasm) {
        wasm_gpa_inited = false;
    } else {
        // This will report memory leaks in debug mode.
        _ = gpa.?.deinit();
        gpa = null;
    }
}

pub fn getTotalRequestedMemory() usize {
    if (IsWasm or !MeasureMemory) {
        stdx.panic("unsupported");
    } else {
        return gpa.?.total_requested_bytes;
    }
}

/// Custom wasm allocator using segmented free lists.
/// A goal is to minimize the number of memory.grow calls (since it's slow).
/// Initially, 256 * Pages or 16MB of memory will be reserved.
/// Afterwards, the memory reserved doubles.
const WasmDefaultAllocator = struct {
    base_page_idx: usize,
    next_page_idx: usize,
    reserved_pages: u32,

    /// Contains the heads of each segment size from 1 word size to 256 word size.
    segments: [256]?*Node,

    /// Main free list contains pages.
    main_free_list: ?*Node,

    const PageSize: u32 = 64 * 1024;
    const WordSize: u32 = @sizeOf(usize);
    const PageWordSize: u32 = @divExact(PageSize, WordSize);

    /// User payload memory follows Node.
    const Node = struct {
        /// Size in bytes of the user payload adjusted for len_align. This is used for resize.
        user_size: usize,
        next: packed union {
            /// When the node is in a free list, this points to next free node.
            node: ?*Node,
            /// When the node is allocated, this helps determine which free list it belongs to.
            /// If seg_size > 256, then it belongs to the page free list.
            seg_size: usize,
        },
    };

    const PageHeader = struct {
        prev_page_last_free_node: ?*Node,
        freed_bytes: usize,
    };

    const Options = struct {
        initial_pages: u32 = 256,
    };

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    pub fn init(self: *WasmDefaultAllocator, opts: Options) !void {
        // Reserve intitial 256 pages of memory.
        const base_page_idx = wasmMemorySize();
        self.* = .{
            .base_page_idx = base_page_idx,
            .next_page_idx = base_page_idx,
            .reserved_pages = 0,
            .segments = undefined,
            .main_free_list = null,
        };
        std.mem.set(?*Node, &self.segments, null);
        try self.growMemory(opts.initial_pages);
    }

    pub fn allocator(self: *WasmDefaultAllocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    inline fn wasmMemorySize() u32 {
        if (builtin.is_test) {
            return @intCast(u32, @divTrunc(@ptrToInt(wasmTestMemory.ptr) + wasmTestMemoryLen - 1, PageSize) + 1);
        } else {
            // TODO: Can't pass var into @wasmMemorySize atm.
            return @wasmMemorySize(0);
        }
    }

    inline fn wasmMemoryGrow(delta: usize) i32 {
        if (builtin.is_test) {
            const delta_size = delta * PageSize - @ptrToInt(wasmTestMemory.ptr);
            if (wasmTestMemoryLen + delta_size <= wasmTestMemory.len) {
                wasmTestMemoryLen += delta_size;
                return @intCast(i32, @divExact(wasmTestMemoryLen, PageSize));
            } else return -1;
        } else {
            // TODO: Can't pass idx into @wasmMemoryGrow atm.
            return @wasmMemoryGrow(0, delta);
        }
    }

    fn alloc(
        ptr: *anyopaque,
        len: usize,
        alignment: u29,
        len_align: u29,
        ret_addr: usize,
    ) std.mem.Allocator.Error![]u8 {
        _ = ret_addr;

        const self = @ptrCast(*WasmDefaultAllocator, @alignCast(@sizeOf(usize), ptr));
        if (len == 0) {
            stdx.panic("TODO: len 0");
        }
        const payload_size = if (len_align == 0) len else b: {
            // len_align is not always a power of two so std.mem.alignForward won't work.
            if (len_align == 1) {
                break :b len;
            } else {
                break :b len + len_align - @mod(len, len_align);
            }
        };

        // Need enough space for Node and alignment.
        const req_num_bytes = payload_size + @sizeOf(Node) + alignment - 1;

        const seg_size = @divTrunc(req_num_bytes - 1, WordSize) + 1;
        // log.debug("alloc len={} align={} lalign={} => seg={}", .{len, alignment, len_align, seg_size});
        if (seg_size <= 256) {
            // Small allocation.
            if (self.segments[seg_size-1]) |free_node| {
                self.segments[seg_size-1] = free_node.next.node;
                return self.allocToNode(free_node, seg_size, payload_size, alignment);
            } else {
                // Allocate a page for size.
                try self.allocSegmentPage(seg_size);

                const free_node = self.segments[seg_size-1].?;
                self.segments[seg_size-1] = free_node.next.node;
                return self.allocToNode(free_node, seg_size, payload_size, alignment);
            }
        } else {
            // Big allocation.

            const req_num_pages = @divTrunc(req_num_bytes - 1, PageSize) + 1;
            const first = self.allocContiguousPages(req_num_pages);

            // Assumes node addr has no offset from it's base frame addr.
            const user_addr = std.mem.alignForward(@ptrToInt(first) + @sizeOf(Node), alignment);

            // Node is initialized from an offset depending on alignment.
            const user_node = @intToPtr(*Node, user_addr - @sizeOf(Node));
            user_node.* = .{
                .user_size = payload_size,
                .next = .{
                    .seg_size = seg_size,
                },
            };
            // log.debug("returned memory {}", .{user_addr});
            return @intToPtr([*]u8, user_addr)[0..payload_size];
        }
    }

    /// Returns the first node with num of contiguous pages.
    fn allocContiguousPages(self: *WasmDefaultAllocator, num_pages: usize) *Node {
        var first: *Node = undefined;
        if (self.main_free_list) |node| {
            first = node;
        } else {
            stdx.panic("No more pages");
        }

        if (num_pages == 1) {
            self.main_free_list = first.next.node;
            return first;
        }

        var next_cont_addr = @ptrToInt(first) + PageSize;
        var i: u32 = 1;
        var prev: *Node = undefined;
        var mb_cur: ?*Node = first.next.node;
        while (mb_cur) |cur| {
            if (@ptrToInt(cur) == next_cont_addr) {
                i += 1;
                if (i == num_pages) {
                    if (first == self.main_free_list) {
                        self.main_free_list = cur.next.node;
                    } else {
                        prev.next.node = cur.next.node;
                    }
                    return first;
                }
            } else {
                first = cur;
                i = 1;
            }
            next_cont_addr = @ptrToInt(cur) + PageSize;
            prev = cur;
            mb_cur = cur.next.node;
        }
        stdx.panic("Could not find contiguous pages");
    }

    fn allocToNode(self: *WasmDefaultAllocator, node: *Node, seg_size: usize, payload_size: usize, alignment: u29) []u8 {
        _ = self;
        // Assumes node addr has no offset from it's base frame addr.
        const user_addr = std.mem.alignForward(@ptrToInt(node) + @sizeOf(Node), alignment);
        
        // Node is initialized from an offset depending on alignment.
        const user_node = @intToPtr(*Node, user_addr - @sizeOf(Node));
        user_node.* = .{
            .user_size = payload_size,
            .next = .{
                .seg_size = seg_size,
            },
        };
        // log.debug("returned memory {}", .{user_addr});
        return @intToPtr([*]u8, user_addr)[0..payload_size];
    }

    /// Grows the wasm memory by number of pages.
    fn growMemory(self: *WasmDefaultAllocator, num_pages: u32) !void {
        // log.debug("grow memory", .{});
        const res = wasmMemoryGrow(self.next_page_idx + num_pages);
        if (res == -1) {
            return error.OutOfMemory;
        }
        const first_new_page_idx = self.next_page_idx;
        self.next_page_idx = self.next_page_idx + num_pages;
        self.reserved_pages += num_pages;

        // Add reserved pages into free list.
        const first_addr = first_new_page_idx * PageSize;
        const first = @intToPtr(*Node, first_addr);
        first.* = .{
            .user_size = 0,
            .next = .{
                .node = null,
            },
        };
        // Assumes main free list is empty which implies that no other free node addr is before the new nodes.
        self.main_free_list = first;
        var prev = first;
        var i: u32 = 1;
        while (i < num_pages) : (i += 1) {
            const node_addr = (first_new_page_idx + i) * PageSize;
            const node = @intToPtr(*Node, node_addr);
            node.* = .{
                .user_size = 0,
                .next = .{
                    .node = null,
                },
            };
            prev.next.node = node;
            prev = node;
        }
    }

    fn allocSegmentPage(self: *WasmDefaultAllocator, seg_size: usize) !void {
        if (self.main_free_list == null) {
            try self.growMemory(self.reserved_pages);
        }

        // Allocate next free page.
        const node = self.main_free_list.?;
        self.main_free_list = node.next.node;

        const header = @ptrCast(*PageHeader, node);
        header.* = .{
            // Assumes no previous free node.
            .prev_page_last_free_node = null,
            .freed_bytes = PageSize,
        };

        // Initialize empty nodes.
        const seg_byte_size = seg_size * WordSize;
        const num_free_nodes = @divTrunc(PageSize - @sizeOf(PageHeader), seg_byte_size);
        const first_addr = @ptrToInt(header) + @sizeOf(PageHeader);
        const first = @intToPtr(*Node, first_addr);
        first.* = .{
            .user_size = 0,
            .next = .{
                .node = null,
            },
        };

        // Assumes free list is empty which implies that no free node addr is before the new allocated nodes.
        self.segments[seg_size-1] = first;
        var prev = first;
        var i: u32 = 1;
        while (i < num_free_nodes) : (i += 1) {
            const seg_node = @intToPtr(*Node, first_addr + (i * seg_byte_size));
            seg_node.* = .{
                .user_size = 0,
                .next = .{
                    .node = null,
                },
            };
            prev.next.node = seg_node;
            prev = seg_node;
        }
    }

    fn resize(
        ptr: *anyopaque,
        buf: []u8,
        buf_align: u29,
        new_len: usize,
        len_align: u29,
        ret_addr: usize,
    ) ?usize {
        _ = ret_addr;
        _ = buf_align;
        const self = @ptrCast(*WasmDefaultAllocator, @alignCast(@sizeOf(usize), ptr));
        _ = self;
        if (new_len == 0) {
            stdx.panic("TODO: new_len 0");
        }

        const new_payload_size = if (len_align == 0) new_len else b: {
            // len_align is not always a power of two so std.mem.alignForward won't work.
            if (len_align == 1) {
                break :b new_len;
            } else {
                break :b new_len + len_align - @mod(new_len, len_align);
            }
        };

        const user_node_addr = @ptrToInt(buf.ptr) - @sizeOf(Node);
        const user_node = @intToPtr(*Node, user_node_addr);

        // log.debug("resize {} {} {} {}", .{@ptrToInt(buf.ptr), buf_align, new_len, len_align});

        if (new_payload_size <= user_node.user_size) {
            // TODO: If this is a big allocation, check to free unused pages.
            user_node.user_size = new_payload_size;
            return new_len;
        } else {
            // TODO: Check to grow.
            return null;
        }
    }

    fn free(
        ptr: *anyopaque,
        buf: []u8,
        buf_align: u29,
        ret_addr: usize,
    ) void {
        _ = ret_addr;
        _ = buf_align;
        const self = @ptrCast(*WasmDefaultAllocator, @alignCast(@sizeOf(usize), ptr));

        const user_node_addr = @ptrToInt(buf.ptr) - @sizeOf(Node);
        const user_node = @intToPtr(*Node, user_node_addr);

        // Save the user seg_size before writing to Node overwrites it.
        const seg_size = user_node.next.seg_size;
        if (seg_size <= 256) {
            // Small allocation.
            // TODO: Free empty pages.

            const page_idx = @divTrunc(@ptrToInt(buf.ptr), PageSize);
            const page_addr = page_idx * PageSize;

            const frame_size = seg_size * WordSize;
            const frame_idx = @divTrunc(@ptrToInt(buf.ptr) - page_addr - @sizeOf(PageHeader), frame_size);
            // log.debug("free small {} {} {}", .{@ptrToInt(buf.ptr), page_idx, frame_idx});

            const node_addr = page_addr + @sizeOf(PageHeader) + frame_idx * frame_size;
            const node = @intToPtr(*Node, node_addr);

            // Find the prev node to insert in order.
            var mb_prev: ?*Node = null;
            var mb_cur = self.segments[seg_size-1];
            while (mb_cur) |cur| {
                if (@ptrToInt(cur) > node_addr) {
                    break;
                }
                mb_prev = cur;
                mb_cur = cur.next.node;
            }

            node.* = .{
                .user_size = 0,
                .next = .{
                    .node = null,
                },
            };

            if (mb_prev) |prev| {
                const next = prev.next.node;
                // Insert after node.
                prev.next.node = node;
                node.next.node = next;
            } else {
                // Insert after head.
                node.next.node = self.segments[seg_size-1];
                self.segments[seg_size-1] = node;
            }
        } else {
            // Big allocation.
            const page_idx = @divTrunc(@ptrToInt(buf.ptr), PageSize);
            const base_node_addr = page_idx * PageSize;
            const base_node = @intToPtr(*Node, base_node_addr);
            const num_pages = @divTrunc(seg_size - 1, PageWordSize) + 1;
            // log.debug("large free {} {} {} {}", .{@ptrToInt(buf.ptr), buf.len, page_idx, num_pages});

            // Find the prev node to insert in order.
            var mb_prev: ?*Node = null;
            var mb_cur = self.main_free_list;
            while (mb_cur) |cur| {
                if (@ptrToInt(cur) > base_node_addr) {
                    break;
                }
                mb_prev = cur;
                mb_cur = cur.next.node;
            }

            // Create connected free nodes and determine last node.
            var i: u32 = 1;
            var tmp_prev = base_node;
            while (i < num_pages) : (i += 1) {
                const node = @intToPtr(*Node, base_node_addr + i * PageSize);
                node.* = .{
                    .user_size = 0,
                    .next = .{
                        .node = null,
                    },
                };
                tmp_prev.next.node = node;
                tmp_prev = node;
            }
            const last_freed = tmp_prev;

            if (mb_prev) |prev| {
                const next = prev.next.node;
                // Insert after node.
                prev.next.node = base_node;
                last_freed.next.node = next;
            } else {
                // Insert after head.
                last_freed.next.node = self.main_free_list;
                self.main_free_list = base_node;
            }
        }
    }
};

var wasmTestMemory: []u8 = undefined;
var wasmTestMemoryLen: usize = 0;

test "WasmDefaultAllocator" {
    const PageSize: u32 = 64 * 1024;
    wasmTestMemory = try t.alloc.alignedAlloc(u8, PageSize, PageSize * 16);
    wasmTestMemoryLen = 0;
    defer t.alloc.free(wasmTestMemory);
    const start_addr = @ptrToInt(wasmTestMemory.ptr);

    var wgpa: WasmDefaultAllocator = undefined;
    try wgpa.init(.{ .initial_pages = 16 });
    const alloc = wgpa.allocator();

    // Small allocations using the same segment.
    const small1 = try alloc.alloc(u8, 16);
    try t.expect(@ptrToInt(small1.ptr) >= start_addr and @ptrToInt(small1.ptr) < start_addr + wasmTestMemoryLen);
    const small2 = try alloc.alloc(u8, 16);
    try t.expect(@ptrToInt(small2.ptr) >= start_addr and @ptrToInt(small2.ptr) < start_addr + wasmTestMemoryLen);
    try t.eq(@ptrToInt(small2.ptr), @ptrToInt(small1.ptr) + 32);

    // Small allocation reuses freed slot.
    const small_addr = @ptrToInt(small1.ptr);
    alloc.free(small1);
    const small3 = try alloc.alloc(u8, 16);
    try t.eq(@ptrToInt(small3.ptr), small_addr);
}