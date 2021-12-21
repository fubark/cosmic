const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const t = stdx.testing;

const log = stdx.log.scoped(.document);

const MaxLineChunkSize = 50;

// When line chunk becomes full, the size is reduced to target threshold.
const LineChunkTargetThreshold = 40;

pub const LineChunkId = u32;

// Line chunk is a relative pointer into the buffer.
pub const LineChunk = struct {
    // Offset from line chunk buffer.
    id: LineChunkId,
    size: u32,
};

const LineChunkArray = [MaxLineChunkSize]LineId;

pub const LineLocation = struct {
    leaf_id: NodeId,

    // Offset from the leaf's line chunk.
    chunk_line_idx: u32,
};

const TreeBranchFactor = 3;

// Document is organized by lines. It has nice properties for most text editing tasks.
// A self balancing btree is used to group adjacent lines into chunks.
// This allows line ops to affect only relevant chunks and not the entire document while preserving line order.
// It's also capable of propagating up aggregate line info like line-height which should come in handy when we implement line wrapping.
//
// Notes:
// - Always has at least one leaf node. (TODO: Revisit this)
// - Once a chunk gets to size 0 it is removed. It won't be able to match any line position and it simplifies line iteration when we can assume each chunk is at least 1 line.
// TODO: Might want to keep newline characters in lines for scanning convenience.
pub const Document = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    line_tree: ds.CompleteTreeArray(TreeBranchFactor, Node),
    line_chunks: ds.CompactUnorderedList(LineChunkId, LineChunkArray),
    lines: ds.CompactUnorderedList(LineId, Line),

    // Temp vars.
    node_buf: std.ArrayList(NodeId),
    str_buf: std.ArrayList(u8),

    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .line_tree = ds.CompleteTreeArray(3, Node).init(alloc),
            .alloc = alloc,
            .line_chunks = ds.CompactUnorderedList(LineChunkId, LineChunkArray).init(alloc),
            .lines = ds.CompactUnorderedList(LineId, Line).init(alloc),
            .node_buf = std.ArrayList(NodeId).init(alloc),
            .str_buf = std.ArrayList(u8).init(alloc),
        };
        self.setUpEmptyDoc();
    }

    fn setUpEmptyDoc(self: *Self) void {
        const chunk_id = self.line_chunks.add(undefined) catch unreachable;
        _ = self.line_tree.append(.{
            .Branch = .{
                .num_lines = 0,
            },
        }) catch unreachable;
        _ = self.line_tree.append(.{
            .Leaf = .{
                .chunk = .{
                    .id = chunk_id,
                    .size = 0,
                },
            },
        }) catch unreachable;
    }

    pub fn deinit(self: *Self) void {
        self.line_tree.deinit();
        self.line_chunks.deinit();
        var iter = self.lines.iterator();
        while (iter.next()) |line| {
            line.buf.deinit();
        }
        self.lines.deinit();
        self.node_buf.deinit();
        self.str_buf.deinit();
    }

    // This is findLineLoc except if line_idx is at the end,
    // it will return a LineLocation that points to existing leaf but chunk_lin_idx doesn't exist yet.
    fn findInsertLineLoc(self: *Self, line_idx: u32) LineLocation {
        const root = self.line_tree.getNodePtr(0);
        if (line_idx < root.Branch.num_lines) {
            return self.findLineLoc(line_idx);
        } else if (line_idx == root.Branch.num_lines) {
            // Shortcut for getting the last leaf.
            const last = self.line_tree.getLastLeaf();
            return .{
                .leaf_id = last,
                .chunk_line_idx = self.line_tree.getNode(last).Leaf.chunk.size,
            };
        } else {
            unreachable;
        }
    }

    // Assumes line idx is in bounds.
    pub fn findLineLoc(self: *Self, line_idx: u32) LineLocation {
        return self.findLineLoc2(0, 0, line_idx).?;
    }

    fn findLineLoc2(self: *Self, node_id: NodeId, start_line: u32, target_line: u32) ?LineLocation {
        const node = self.line_tree.getNodePtr(node_id);
        switch (node.*) {
            .Branch => |br| {
                if (target_line >= start_line and target_line < start_line + br.num_lines) {
                    var cur_line = start_line;
                    const range = self.line_tree.getChildrenRange(node_id);
                    var id = range.start;
                    while (id < range.end) : (id += 1) {
                        const cur_item = self.line_tree.getNode(id);
                        const res = self.findLineLoc2(id, cur_line, target_line);
                        if (res != null) {
                            return res;
                        }
                        switch (cur_item) {
                            .Branch => |child_br| {
                                cur_line += child_br.num_lines;
                            },
                            .Leaf => |child_leaf| {
                                cur_line += child_leaf.chunk.size;
                            },
                        }
                    }
                }
            },
            .Leaf => |leaf| {
                if (target_line >= start_line and target_line < start_line + leaf.chunk.size) {
                    return LineLocation{
                        .leaf_id = node_id,
                        .chunk_line_idx = target_line - start_line,
                    };
                }
            },
        }
        return null;
    }

    // Move lines from existing chunk to new if target threshold is exceeded.
    // Caller must deal with rebalancing the tree and moving the new leaf to the right place.
    fn reallocLeafLineChunk(self: *Self, loc: LineLocation) LineLocation {
        const leaf = self.line_tree.getNodePtr(loc.leaf_id);
        const num_lines = leaf.Leaf.chunk.size;
        if (num_lines <= LineChunkTargetThreshold) {
            unreachable;
        }
        const num_moved = num_lines - LineChunkTargetThreshold;

        const new_chunk_id = self.line_chunks.add(undefined) catch unreachable;
        const new_chunk_ptr = LineChunk{
            .id = new_chunk_id,
            .size = num_moved,
        };
        const new_leaf = self.line_tree.append(.{
            .Leaf = .{
                .chunk = new_chunk_ptr,
            },
        }) catch unreachable;

        // log.warn("leaf: {}, {}", .{leaf, loc});
        const chunk = self.getLineChunkSlice(leaf.Leaf.chunk);
        const new_chunk = self.getLineChunkSlice(new_chunk_ptr);
        var i: u32 = 0;
        while (i < num_moved) : (i += 1) {
            new_chunk[i] = chunk[LineChunkTargetThreshold + i];
        }

        leaf.Leaf.chunk.size -= num_moved;
        self.updateParentNumLines(loc.leaf_id, -@intCast(i32, num_moved));

        return .{
            .leaf_id = new_leaf,
            .chunk_line_idx = 0,
        };
    }

    // Assumes already balanced line tree except new leaf node.
    // Assumes new leaf was created to come after target leaf.
    // If new leaf is after target, then we need to shift every node AFTER target downwards to the new node.
    // Then new node is moved to the node AFTER target.
    // If new leaf is before target, then we need to shift every node at target upwards to the new node.
    // Then new node is moved to the target.
    fn rebalanceWithNewLeaf(self: *Self, new_id: NodeId, after_target: NodeId) void {
        self.node_buf.resize(self.line_tree.getMaxLeaves()) catch unreachable;

        // TODO: Only get leaves from new to target.
        const leaves = self.line_tree.getInOrderLeaves(self.node_buf.items);

        if (self.line_tree.isLeafNodeBefore(new_id, after_target)) {
            // Start from new node.
            var i = std.mem.indexOfScalar(NodeId, leaves, new_id).?;
            const temp = self.line_tree.getNode(new_id);

            // First node that moves to the new node is special since all it's num lines is reported to parent.
            var node = self.line_tree.getNodePtr(leaves[i]);
            node.* = self.line_tree.getNode(leaves[i + 1]);
            self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size));
            i += 1;

            // Shift the rest upwards.
            while (leaves[i] != after_target) : (i += 1) {
                // log.warn("i={} cur_node={} target={}", .{i, leaves[i], after_target});
                node = self.line_tree.getNodePtr(leaves[i]);
                const last_num_lines = node.Leaf.chunk.size;
                node.* = self.line_tree.getNode(leaves[i + 1]);
                self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size) - @intCast(i32, last_num_lines));
            }

            // Replace target with new.
            node = self.line_tree.getNodePtr(leaves[i]);
            const last_num_lines = node.Leaf.chunk.size;
            node.* = temp;
            self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size) - @intCast(i32, last_num_lines));
        } else {
            // Start from new node.
            var i = std.mem.indexOfScalar(NodeId, leaves, new_id).?;

            // First node that moves to the new node is special since all it's num lines is reported to parent.
            if (leaves[i] != after_target + 1) {
                var node = self.line_tree.getNodePtr(leaves[i]);
                node.* = self.line_tree.getNode(leaves[i - 1]);
                self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size));
                i -= 1;

                const temp = self.line_tree.getNode(new_id);
                // Shift the rest downwards.
                while (leaves[i] != after_target + 1) : (i -= 1) {
                    node = self.line_tree.getNodePtr(leaves[i]);
                    const last_num_lines = node.Leaf.chunk.size;
                    node.* = self.line_tree.getNode(leaves[i - 1]);
                    self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size) - @intCast(i32, last_num_lines));
                }

                // Replace node AFTER target with new.
                node = self.line_tree.getNodePtr(leaves[i]);
                const last_num_lines = node.Leaf.chunk.size;
                node.* = temp;
                self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size) - @intCast(i32, last_num_lines));
            } else {
                // New node is exactly where it should be already.
                const node = self.line_tree.getNodePtr(leaves[i]);
                self.updateParentNumLines(leaves[i], @intCast(i32, node.Leaf.chunk.size));
            }
        }
    }

    pub fn removeRangeInLine(self: *Self, line_idx: u32, start: u32, end: u32) void {
        self.replaceRangeInLine(line_idx, start, end, "");
    }

    pub fn replaceRangeInLine(self: *Self, line_idx: u32, start: u32, end: u32, str: []const u8) void {
        const line_id = self.getLineId(line_idx);
        const buf = &self.lines.getPtr(line_id).buf;
        buf.replaceRange(start, end - start, str) catch unreachable;
    }

    // Performs insert in a line. Assumes no new lines.
    pub fn insertIntoLine(self: *Self, line_idx: u32, ch_idx: u32, str: []const u8) void {
        const line_id = self.getLineId(line_idx);
        const buf = &self.lines.getPtr(line_id).buf;
        buf.insertSlice(ch_idx, str) catch unreachable;
    }

    pub fn insertLine(self: *Self, line_idx: u32, str: []const u8) void {
        var line = Line{
            .buf = std.ArrayList(u8).init(self.alloc),
        };
        line.buf.appendSlice(str) catch unreachable;
        const line_id = self.lines.add(line) catch unreachable;
        var loc = self.findInsertLineLoc(line_idx);

        var leaf = self.line_tree.getNodePtr(loc.leaf_id);
        if (leaf.Leaf.chunk.size == MaxLineChunkSize) {
            // Reached chunk limit, allocate another leaf node line chunk.
            const new_loc = self.reallocLeafLineChunk(loc);

            if (self.line_tree.getParent(new_loc.leaf_id)) |parent_id| {
                const parent = self.line_tree.getNode(parent_id);
                if (parent == .Leaf) {
                    // If parent is a leaf node, we have to insert a branch.
                    const new_branch = self.line_tree.append(.{
                        .Branch = .{
                            .num_lines = parent.Leaf.chunk.size,
                        },
                    }) catch unreachable;
                    self.line_tree.swap(parent_id, new_branch);
                    // Update the target loc if we swapped it.
                    if (loc.leaf_id == parent_id) {
                        loc.leaf_id = new_branch;
                    }
                }
            }

            // Rebalance line tree with new leaf node.
            self.rebalanceWithNewLeaf(new_loc.leaf_id, loc.leaf_id);

            // Find the target leaf again.
            loc = self.findInsertLineLoc(line_idx);
            leaf = self.line_tree.getNodePtr(loc.leaf_id);
        }

        // Copy existing lines down.
        const offset = loc.chunk_line_idx;

        leaf.Leaf.chunk.size += 1;
        var chunk = self.getLineChunkSlice(leaf.Leaf.chunk);

        var i = chunk.len - offset - 1;
        while (i >= offset + 1) : (i -= 1) {
            chunk[i] = chunk[i - 1];
        }
        chunk[offset] = line_id;
        // log.warn("new line id: {}", .{line_id});
        // log.warn("buf after: {any}", .{chunk.*});

        // Propagate size change upwards.
        self.updateParentNumLines(loc.leaf_id, 1);
    }

    fn updateParentNumLines(self: *Self, node_id: NodeId, lc_delta: i32) void {
        const parent_id = self.line_tree.getParent(node_id);
        if (parent_id == null) {
            return;
        }
        const parent = self.line_tree.getNodePtr(parent_id.?);
        if (lc_delta > 0) {
            parent.Branch.num_lines += @intCast(u32, lc_delta);
        } else {
            parent.Branch.num_lines -= @intCast(u32, -lc_delta);
        }
        self.updateParentNumLines(parent_id.?, lc_delta);
    }

    // Clears the doc.
    fn clearRetainingCapacity(self: *Self) void {
        self.line_tree.clearRetainingCapacity();
        self.line_chunks.clearRetainingCapacity();
        var iter = self.lines.iterator();
        while (iter.next()) |line| {
            line.buf.deinit();
        }
        self.lines.clearRetainingCapacity();
        self.setUpEmptyDoc();
    }

    pub fn loadSource(self: *Self, src: []const u8) void {
        self.clearRetainingCapacity();
        var iter = stdx.string.splitLines(src);
        while (iter.next()) |line| {
            self.insertLine(self.numLines(), line);
        }
    }

    pub fn loadFromFile(self: *Self, path: []const u8) void {
        _ = self;
        _ = path;
        // Load from stream.
        @compileError("TODO");
    }

    pub fn getFirstLeaf(self: *Self) NodeId {
        return self.line_tree.getFirstLeaf();
    }

    pub fn getLastLeaf(self: *Self) NodeId {
        return self.line_tree.getLastLeaf();
    }

    pub fn numLines(self: *Self) u32 {
        return self.line_tree.getNode(0).Branch.num_lines;
    }

    pub fn getLeafLineChunkSlice(self: *Self, leaf_id: NodeId) []LineId {
        const leaf = self.getNode(leaf_id);
        return self.getLineChunkSlice(leaf.Leaf.chunk);
    }

    pub fn getLineChunkSlice(self: *Self, chunk: LineChunk) []LineId {
        return self.line_chunks.getPtr(chunk.id)[0..chunk.size];
    }

    pub fn getLineId(self: *Self, line_idx: u32) LineId {
        const loc = self.findLineLoc(line_idx);
        return self.getLineIdByLoc(loc);
    }

    pub fn getLineIdByLoc(self: *Self, loc: LineLocation) LineId {
        return self.getLeafLineChunkSlice(loc.leaf_id)[loc.chunk_line_idx];
    }

    pub fn getLine(self: *Self, line_idx: u32) []const u8 {
        const line_id = self.getLineId(line_idx);
        return self.lines.get(line_id).buf.items;
    }

    pub fn getLineById(self: *Self, id: LineId) []const u8 {
        return self.lines.get(id).buf.items;
    }

    pub fn getNode(self: *Self, id: NodeId) Node {
        return self.line_tree.getNode(id);
    }

    pub fn getNextLeafNode(self: *Self, id: NodeId) ?NodeId {
        return self.line_tree.getNextLeaf(id);
    }

    pub fn getPrevLeafNode(self: *Self, id: NodeId) ?NodeId {
        return self.line_tree.getPrevLeaf(id);
    }

    // Given a location to the line and char offsets from the line, get the string between the offsets.
    pub fn getSubstringFromLineLoc(self: *Self, loc: LineLocation, start_ch: u32, end_ch: u32) []const u8 {
        var cur_leaf_id = loc.leaf_id;
        var chunk = self.getLeafLineChunkSlice(cur_leaf_id);
        var chunk_line_idx = loc.chunk_line_idx;
        var line = self.getLineById(chunk[chunk_line_idx]);
        if (end_ch <= line.len) {
            // It's a substring from the start line.
            return line[start_ch..end_ch];
        } else {
            // Build multiline string.
            self.str_buf.clearRetainingCapacity();

            // Add first line substring.
            self.str_buf.appendSlice(line[start_ch..]) catch unreachable;
            self.str_buf.append('\n') catch unreachable;
            var offset: u32 = @intCast(u32, self.str_buf.items.len);

            // Add middle lines.
            while (true) {
                chunk_line_idx += 1;
                if (chunk_line_idx == chunk.len) {
                    // Advance line chunk.
                    cur_leaf_id = self.getNextLeafNode(cur_leaf_id).?;
                    chunk = self.getLeafLineChunkSlice(cur_leaf_id);
                    chunk_line_idx = 0;
                }
                line = self.getLineById(chunk[chunk_line_idx]);
                offset += @intCast(u32, line.len) + 1;
                if (offset >= end_ch) {
                    break;
                }
                self.str_buf.appendSlice(line) catch unreachable;
                self.str_buf.append('\n') catch unreachable;
            }

            // Add last line substring.
            line = self.getLineById(chunk[chunk_line_idx]);
            self.str_buf.appendSlice(line[0..end_ch]) catch unreachable;

            return self.str_buf.items;
        }
    }

    // end_chunk_line_idx is inclusive
    // end_ch_idx is exclusive
    pub fn getString(self: *Self, start: NodeId, start_chunk_line_idx: u32, start_ch_idx: u32, end: NodeId, end_chunk_line_idx: u32, end_ch_idx: u32) []const u8 {
        if (start == end and start_chunk_line_idx == end_chunk_line_idx) {
            const chunk = self.getLeafLineChunkSlice(start);
            return self.getLineById(chunk[start_chunk_line_idx])[start_ch_idx..end_ch_idx];
        } else {
            // Build temp string.
            self.str_buf.clearRetainingCapacity();

            var cur_node = start;
            var cur_chunk_line_idx = start_chunk_line_idx;

            var cur_chunk = self.getLeafLineChunkSlice(cur_node);
            var line = self.getLineById(cur_chunk[cur_chunk_line_idx]);

            // Add first line substring.
            self.str_buf.appendSlice(line[start_ch_idx..]) catch unreachable;
            self.str_buf.append('\n') catch unreachable;

            // Add middle lines.
            while (true) {
                if (cur_chunk_line_idx == cur_chunk.len) {
                    // Advance line chunk.
                    cur_node = self.getNextLeafNode(cur_node).?;
                    cur_chunk = self.getLeafLineChunkSlice(cur_node);
                    cur_chunk_line_idx = 0;
                }
                if (cur_node == end and cur_chunk_line_idx == end_chunk_line_idx) {
                    break;
                }
                line = self.getLineById(cur_chunk[cur_chunk_line_idx]);
                self.str_buf.appendSlice(line) catch unreachable;
                self.str_buf.append('\n') catch unreachable;
                cur_chunk_line_idx += 1;
            }

            // Add last line substring.
            line = self.getLineById(cur_chunk[cur_chunk_line_idx]);
            self.str_buf.appendSlice(line[0..end_ch_idx]) catch unreachable;

            return self.str_buf.items;
        }
    }
};

test "Document" {
    const src =
        \\This is a document.
        \\This is the second line.
    ;

    var doc: Document = undefined;
    doc.init(t.alloc);
    defer doc.deinit();

    doc.loadSource(src);

    try t.eq(doc.numLines(), 2);
    try t.eqStr(doc.getLine(0), "This is a document.");

    // Test insert op on line.
    doc.insertIntoLine(0, 10, "cool ");
    try t.eqStr(doc.getLine(0), "This is a cool document.");
}

test "Big document" {
    const line = "This is a line.\n";

    var src_buf = std.ArrayList(u8).init(t.alloc);
    defer src_buf.deinit();
    src_buf.resize(line.len * 1000) catch unreachable;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        src_buf.appendSlice(line) catch unreachable;
    }

    var doc: Document = undefined;
    doc.init(t.alloc);
    defer doc.deinit();

    doc.loadSource(src_buf.items);
    try t.eq(doc.numLines(), 1001);
}

pub const NodeId = u32;
const Node = union(enum) {
    Branch: struct {
        num_lines: u32,
    },
    Leaf: struct {
        chunk: LineChunk,
    },
};

pub const LineId = u32;
const Line = struct {
    buf: std.ArrayList(u8),
};
