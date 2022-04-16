const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const t = stdx.testing;
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;
const RbTree = stdx.ds.RbTree;
const CompactSinglyLinkedListBuffer = stdx.ds.CompactSinglyLinkedListBuffer;

const log_ = stdx.log.scoped(.tessellator);

const DeferredVertexNodeId = u16;
const NullId = stdx.ds.CompactNull(DeferredVertexNodeId);

const EventQueue = std.PriorityQueue(u32, *std.ArrayList(Event), compareEventIdx);

const debug = true and builtin.mode == .Debug;

pub fn log(comptime format: []const u8, args: anytype) void {
    if (debug) {
        log_.debug(format, args);
    }
}

pub const Tessellator = struct {
    /// Buffers.
    verts: std.ArrayList(InternalVertex),
    events: std.ArrayList(Event),
    event_q: EventQueue,
    sweep_edges: RbTree(u16, SweepEdge, Event, compareSweepEdge),
    deferred_verts: CompactSinglyLinkedListBuffer(DeferredVertexNodeId, DeferredVertexNode),

    /// Verts to output.
    /// No duplicate verts will be outputed to reduce size footprint.
    /// Since some verts won't be discovered until during the processing of events (edge intersections),
    /// verts are added as the events are processed. As a result, the verts are also in order y-asc and x-asc.
    out_verts: std.ArrayList(Vec2),

    /// Triangles to output are triplets of indexes that point to verts. They are in ccw direction.
    out_idxes: std.ArrayList(u16),

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator) void {
        self.* = .{
            .verts = std.ArrayList(InternalVertex).init(alloc),
            .events = std.ArrayList(Event).init(alloc),
            .event_q = undefined,
            .sweep_edges = RbTree(u16, SweepEdge, Event, compareSweepEdge).init(alloc, undefined),
            .deferred_verts = CompactSinglyLinkedListBuffer(DeferredVertexNodeId, DeferredVertexNode).init(alloc),
            .out_verts = std.ArrayList(Vec2).init(alloc),
            .out_idxes = std.ArrayList(u16).init(alloc),
        };
        self.event_q = EventQueue.init(alloc, &self.events);
    }

    pub fn deinit(self: *Self) void {
        self.verts.deinit();
        self.events.deinit();
        self.event_q.deinit();
        self.sweep_edges.deinit();
        self.deferred_verts.deinit();
        self.out_verts.deinit();
        self.out_idxes.deinit();
    }

    pub fn clearBuffers(self: *Self) void {
        self.verts.clearRetainingCapacity();
        self.events.clearRetainingCapacity();
        self.event_q.len = 0;
        self.sweep_edges.clearRetainingCapacity();
        self.deferred_verts.clearRetainingCapacity();
        self.out_verts.clearRetainingCapacity();
        self.out_idxes.clearRetainingCapacity();
    }

    pub fn triangulatePolygon(self: *Self, polygon: []const Vec2) void {
        self.triangulatePolygons(&.{polygon});
    }

    /// Perform a plane sweep to triangulate a complex polygon in one pass.
    /// The output returns ccw triangle vertices and indexes ready to be fed into the gpu.
    /// This uses Bentley-Ottmann to handle self intersecting edges.
    /// Rules are followed to partition into y-monotone polygons and triangulate them.
    /// This is ported from the JS implementation (tessellator.js) where it is easier to prototype.
    /// Since the number of verts and indexes is not known beforehand, the output is an ArrayList.
    /// TODO: See if inline callbacks would be faster to directly push data to the batcher buffer.
    pub fn triangulatePolygons(self: *Self, polygons: []const []const Vec2) void {
        const sweep_edges = &self.sweep_edges;

        // Construct the initial events by traversing the polygon.
        self.initEvents(polygons);

        var cur_x: f32 = std.math.f32_min;
        var cur_y: f32 = std.math.f32_min;
        var cur_out_vert_idx: u16 = std.math.maxInt(u16);

        // Process the next event.
        while (self.event_q.removeOrNull()) |e_id| {
            const e = self.events.items[e_id];

            // If the point changed, allocate a new out vertex index.
            if (e.vert_x != cur_x or e.vert_y != cur_y) {
                self.out_verts.append(vec2(e.vert_x, e.vert_y)) catch unreachable;
                cur_out_vert_idx +%= 1;
                cur_x = e.vert_x;
                cur_y = e.vert_y;
            }

            // Set the out vertex index on the event.
            self.verts.items[e.vert_idx].out_idx = cur_out_vert_idx;

            if (debug) {
                const tag_str: []const u8 = if (e.tag == .Start) "Start" else "End";
                log("--process event {}, ({},{}) {s} {s}", .{e.vert_idx, e.vert_x, e.vert_y, tag_str, edgeToString(e.edge)});
                log("sweep edges: ", .{});
                var mb_cur = sweep_edges.first();
                while (mb_cur) |cur| {
                    const se = sweep_edges.get(cur).?;
                    log("{} -> {}", .{se.edge.start_idx, se.edge.end_idx});
                    mb_cur = sweep_edges.getNext(cur);
                }
            }

            if (e.tag == .Start) {
                // Check to remove a previous left edge and continue it's sub-polygon vertex queue.
                sweep_edges.ctx = e;
                const new_id = sweep_edges.insert(SweepEdge.init(e, self.verts.items)) catch unreachable;
                const new = sweep_edges.getPtr(new_id).?;

                log("start new sweep edge {}", .{new_id});

                const mb_left_id = sweep_edges.getPrev(new_id);
                // Update winding based on what is to the left.
                if (mb_left_id == null) {
                    new.interior_is_left = false;
                } else {
                    new.interior_is_left = !sweep_edges.get(mb_left_id.?).?.interior_is_left;
                }

                if (new.interior_is_left) {
                    log("initially interior to the left", .{});
                    // Initially appears to be a right edge but if it connects to the previous left, it becomes a left edge.
                    var left = sweep_edges.getPtrNoCheck(mb_left_id.?);
                    const e_vert_out_idx = self.verts.items[e.vert_idx].out_idx;
                    if (left.end_event_vert_uniq_idx == e_vert_out_idx) {
                        // Remove the previous ended edge, and takes it's place as the left edge.
                        defer sweep_edges.remove(mb_left_id.?) catch unreachable;
                        new.interior_is_left = false;

                        // Previous left edge and this new edge forms a regular left angle.
                        // Check for bad up cusp.
                        if (left.bad_up_cusp_uniq_idx != NullId) {
                            // This monotone polygon (a) should already have run it's triangulate steps from the left edge's end event.
                            //   \  /
                            //  a \/ b
                            //    ^ Bad cusp.
                            // \_
                            // ^ End event from left edge happened before, currently processing start event for the new connected edge.

                            // A line is connected from this vertex to the bad cusp to ensure that polygon (a) is monotone and polygon (b) is monotone.
                            // Since polygon (a) already ran it's triangulate step, it's done from this side of the polygon.
                            // This start event will create a new sweep edge, so transfer the deferred queue from the bad cusp's right side. (it is now the queue for this new left edge).
                            const bad_right = sweep_edges.getNoCheck(left.bad_up_cusp_right_sweep_edge_id);
                            bad_right.dumpQueue(self);
                            new.deferred_queue = bad_right.deferred_queue;
                            new.deferred_queue_size = bad_right.deferred_queue_size;
                            new.cur_side = bad_right.cur_side;

                            // Also run triangulate on polygon (b) for the new vertex since the end event was already run for polygon (a).
                            self.triangulateLeftStep(new, self.verts.items[e.vert_idx]);

                            left.bad_up_cusp_uniq_idx = NullId;
                            sweep_edges.removeDetached(left.bad_up_cusp_right_sweep_edge_id);

                            log("FIX BAD UP CUSP", .{});
                            new.dumpQueue(self);
                        } else {
                            new.deferred_queue = left.deferred_queue;
                            new.deferred_queue_size = left.deferred_queue_size;
                            new.cur_side = left.cur_side;
                        }
                    } else if (left.start_event_vert_uniq_idx == e_vert_out_idx) {
                        // Down cusp.
                        log("DOWN CUSP", .{});

                        const mb_right_id = sweep_edges.getNext(new_id);

                        if (mb_right_id != null) {
                            // Check for intersection with the edge to the right.
                            log("check right intersect", .{});

                            // TODO: Is there a preliminary check to avoid doing the math? One idea is to check the x_slopes but it would need to know
                            // if the compared edge is pointing down or up.
                            const right = sweep_edges.getPtrNoCheck(mb_right_id.?);
                            const res = computeTwoEdgeIntersect(e.edge, right.edge);
                            if (res.has_intersect) {
                                self.handleIntersectForStartEvent(new, right, res, vec2(e.vert_x, e.vert_y));
                            }
                        }
                        const mb_left_left_id = sweep_edges.getPrev(mb_left_id.?);
                        if (mb_left_left_id != null) {
                            log("check left intersect", .{});
                            const left_left = sweep_edges.getPtrNoCheck(mb_left_left_id.?);
                            const res = computeTwoEdgeIntersect(left.edge, left_left.edge);
                            // dump(edgeToString(left_left_edge.edge))
                            if (res.has_intersect) {
                                self.handleIntersectForStartEvent(left, left_left, res, vec2(e.vert_x, e.vert_y));
                            }
                        }
                    }
                } else {
                    log("initially interior to the right", .{});
                    // Initially appears to be a left edge but if it connects to a previous right, it becomes a right edge.
                    if (mb_left_id != null) {
                        const vert = self.verts.items[e.vert_idx];

                        // left edge has interior to the left.
                        var left = sweep_edges.get(mb_left_id.?).?;
                        if (left.end_event_vert_uniq_idx == vert.out_idx) {
                            // Remove previous ended edge.
                            sweep_edges.remove(mb_left_id.?) catch unreachable;
                            new.interior_is_left = true;
                            log("changed to interior is left", .{});
                        } else if (left.start_event_vert_uniq_idx == vert.out_idx) {
                            // Linked to previous start event's vertex.
                            // Handle bad down cusp.
                            // \       \/ 
                            //  \       b
                            //   \--a
                            //    \       v Bad down cusp.
                            //     \     /\     /
                            //      \   /  \   /

                            // The bad cusp is linked to the lowest visible vertex seen from the left edge. If vertex (a) exists that would be connected to the cusp.
                            // If it didn't exist the next lowest would be (b) a bad up cusp.

                            const left_left_id = sweep_edges.getPrev(mb_left_id.?).?;
                            const left_left = sweep_edges.getPtrNoCheck(left_left_id);
                            if (left_left.lowest_right_vert_idx == NullId) {
                                log("expected lowest right vert", .{});
                                unreachable;
                            }

                            const mono_right_side = sweep_edges.getNoCheck(left_left.lowest_right_vert_sweep_edge_id);

                            if (left_left.bad_up_cusp_uniq_idx == left.start_event_vert_uniq_idx) {
                                left_left.bad_up_cusp_uniq_idx = NullId;
                            }

                            // Once connected, the right side monotone polygon will continue the existing vertex queue of the connected point.
                            new.deferred_queue = mono_right_side.deferred_queue;
                            new.deferred_queue_size = mono_right_side.deferred_queue_size;
                            new.cur_side = mono_right_side.cur_side;

                            // If the right side polygon queue is the same as the left side polygon queue, the left queue is reset to the separation vertex and the bad cusp vertex.
                            if (left_left.deferred_queue == new.deferred_queue) {
                                left_left.deferred_queue = NullId;
                                left_left.deferred_queue_size = 0;
                                left_left.cur_side = .Right;
                                const mono_vert = self.verts.items[left_left.lowest_right_vert_idx];
                                left_left.enqueueDeferred(mono_vert, self);
                                if (vert.out_idx != mono_vert.out_idx) {
                                    left_left.enqueueDeferred(vert, self);
                                }
                            }

                            // Right side needs to run left triangulate step since there is no end event for this vertex.
                            self.triangulateLeftStep(new, vert);
                        }
                    }
                }

                if (!new.interior_is_left) {
                    // Even-odd rule.
                    // Interior is to the right.

                    const vert = self.verts.items[e.vert_idx];

                    // Initialize the deferred queue.
                    if (new.deferred_queue == NullId) {
                        new.enqueueDeferred(vert, self);
                        new.cur_side = .Left;

                        log("initialize queue", .{});
                        new.dumpQueue(self);
                    }

                    // The lowest right vert is set initializes to itself.
                    new.lowest_right_vert_idx = e.vert_idx;
                    new.lowest_right_vert_sweep_edge_id = new_id;
                } else {
                    // Interior is to the left.
                }
            } else {
                // End event.

                if (e.invalidated) {
                    // This end event was invalidated from an intersection event.
                    continue;
                }

                const active_id = findSweepEdgeForEndEvent(sweep_edges, e) orelse {
                    log("polygons: {any}", .{polygons});
                    stdx.panic("expected active edge");
                };
                const active = sweep_edges.getPtrNoCheck(active_id);
                log("active {} {}", .{active.vert_idx, active.to_vert_idx});

                const vert = self.verts.items[e.vert_idx];

                if (active.interior_is_left) {
                    // Interior is to the left.

                    log("interior to the left {}", .{active_id});

                    const left_id = sweep_edges.getPrev(active_id).?;
                    const left = sweep_edges.getPtrNoCheck(left_id);


                    // Check if it has closed the polygon. (up cusp)
                    if (vert.out_idx == left.end_event_vert_uniq_idx) {
                        // Check for bad up cusp.
                        if (left.bad_up_cusp_uniq_idx != NullId) {
                            const bad_right = sweep_edges.getPtrNoCheck(left.bad_up_cusp_right_sweep_edge_id);
                            self.triangulateLeftStep(bad_right, vert);
                            sweep_edges.removeDetached(left.bad_up_cusp_right_sweep_edge_id);
                            left.bad_up_cusp_uniq_idx = NullId; 
                            if (bad_right.deferred_queue_size >= 3) {
                                log("{any}", .{self.out_idxes.items});
                                bad_right.dumpQueue(self);
                                stdx.panic("did not expect left over vertices");
                            }
                        }
                        if (left.deferred_queue_size >= 3) {
                            log("{} {any}", .{left_id, self.out_idxes.items});
                            left.dumpQueue(self);
                            stdx.panic("did not expect left over vertices");
                        }
                        // Remove the left edge and this edge.
                        sweep_edges.remove(left_id) catch unreachable;
                        sweep_edges.remove(active_id) catch unreachable;
                    } else {
                        // Regular right side vertex.
                        self.triangulateRightStep(left, vert);

                        // Edge is only removed by the next connecting edge.
                        active.end_event_vert_uniq_idx = vert.out_idx;
                    }
                } else {
                    // Interior is to the right.
                    log("interior to the right {}", .{active_id});

                    const mb_left_id = sweep_edges.getPrev(active_id);

                    // Check if this forms a bad up cusp with the right edge to the left monotone polygon.
                    var removed = false;
                    if (mb_left_id != null) {
                        log("check for bad up cusp", .{});
                        const left = sweep_edges.getNoCheck(mb_left_id.?);
                        // dump(edgeToString(left_right_edge.edge))
                        if (vert.out_idx == left.end_event_vert_uniq_idx) {
                            const left_left_id = sweep_edges.getPrev(mb_left_id.?).?;
                            const left_left = sweep_edges.getPtrNoCheck(left_left_id);
                            // Bad up cusp.
                            left_left.bad_up_cusp_uniq_idx = vert.out_idx;
                            left_left.bad_up_cusp_right_sweep_edge_id = active_id;
                            left_left.lowest_right_vert_idx = e.vert_idx;
                            left_left.lowest_right_vert_sweep_edge_id = active_id;

                            // Remove the left edge.
                            sweep_edges.remove(mb_left_id.?) catch unreachable;
                            // Detach this edge, remove it when the bad up cusp is fixed.
                            sweep_edges.detach(active_id) catch unreachable;
                            removed = true;
                            // Continue.
                        }
                    }

                    active.dumpQueue(self);
                    self.triangulateLeftStep(active, vert);
                    active.dumpQueue(self);

                    if (!removed) {
                        // Don't remove the left edge of this sub-polygon yet.
                        // Record the end event's vert so the next start event that continues from this vert can persist the deferred vertices and remove this sweep edge.
                        // It can also be removed by a End right edge.
                        active.end_event_vert_uniq_idx = vert.out_idx;
                    }
                }
            }
        }
    }

    inline fn addTriangle(self: *Self, v1_out: u16, v2_out: u16, v3_out: u16) void {
        log("triangle {} {} {}", .{v1_out, v2_out, v3_out});
        self.out_idxes.appendSlice(&.{v1_out, v2_out, v3_out}) catch unreachable;
    }

    /// Parses the polygon pts and adds the initial events into the priority queue.
    fn initEvents(self: *Self, polygons: []const []const Vec2) void {
        for (polygons) |polygon| {
            // Find the starting point that is not equal to the last vertex point.
            // Since we are adding events to a priority queue, we need to make sure each add is final.
            var start_idx: u16 = 0;
            const last_pt = polygon[polygon.len-1];
            while (start_idx < polygon.len) : (start_idx += 1) {
                const pt = polygon[start_idx];

                // Add internal vertex even though we are skipping events for it to keep the idxes consistent with the input.
                const v = InternalVertex{
                    .pos = pt,
                    .idx = start_idx,
                };
                self.verts.append(v) catch unreachable;

                if (last_pt.x != pt.x or last_pt.y != pt.y) {
                    break;
                }
            }

            var last_v = self.verts.items[start_idx];
            var last_v_idx = start_idx;

            var i: u16 = start_idx + 1;
            while (i < polygon.len) : (i += 1) {
                const v_idx = @intCast(u16, self.verts.items.len);
                const v = InternalVertex{
                    .pos = polygon[i],
                    .idx = i,
                };
                self.verts.append(v) catch unreachable;

                if (last_v.pos.x == v.pos.x and last_v.pos.y == v.pos.y) {
                    // Don't connect two vertices that are on top of each other.
                    // Allowing this would require an edge case to make sure there is a start AND end event since that is currently derived from the vertex points.
                    // Push the vertex in anyway so there is consistency with the input.
                    continue;
                }

                const prev_edge = Edge.init(last_v_idx, last_v, v_idx, v);
                const event1_idx = @intCast(u32, self.events.items.len);
                var event1 = Event.init(last_v_idx, prev_edge, self.verts.items);
                var event2 = Event.init(v_idx, prev_edge, self.verts.items);
                if (event1.tag == .Start) {
                    event1.end_event_idx = event1_idx + 1;
                } else {
                    event2.end_event_idx = event1_idx;
                }
                self.events.append(event1) catch unreachable;
                self.event_q.add(event1_idx) catch unreachable;
                self.events.append(event2) catch unreachable;
                self.event_q.add(event1_idx + 1) catch unreachable;
                last_v = v;
                last_v_idx = v_idx;
            }
            // Link last pt to start pt.
            const edge = Edge.init(last_v_idx, last_v, start_idx, self.verts.items[start_idx]);
            const event1_idx = @intCast(u32, self.events.items.len);
            var event1 = Event.init(last_v_idx, edge, self.verts.items);
            var event2 = Event.init(start_idx, edge, self.verts.items);
            if (event1.tag == .Start) {
                event1.end_event_idx = event1_idx + 1;
            } else {
                event2.end_event_idx = event1_idx;
            }
            self.events.append(event1) catch unreachable;
            self.event_q.add(event1_idx) catch unreachable;
            self.events.append(event2) catch unreachable;
            self.event_q.add(event1_idx + 1) catch unreachable;
        }
    }

    fn triangulateLeftStep(self: *Self, left: *SweepEdge, vert: InternalVertex) void {
        if (left.cur_side == .Left) {
            log("same left side", .{});
            left.dumpQueue(self);

            // Same side.
            if (left.deferred_queue_size >= 2) {
                var last_id = left.deferred_queue;
                var last = self.deferred_verts.getNoCheck(last_id);
                if (last.vert_out_idx == vert.out_idx) {
                    // Ignore this point since it is the same as the last.
                    return; 
                }
                var cur_id = self.deferred_verts.getNextNoCheck(last_id);
                var i: u16 = 0;
                while (i < left.deferred_queue_size-1) : (i += 1) {
                    log("check to add inward tri {} {}", .{last_id, cur_id});
                    const cur = self.deferred_verts.getNoCheck(cur_id);
                    const cxp = vec2(last.vert_x - cur.vert_x, last.vert_y - cur.vert_y).cross(vec2(vert.pos.x - last.vert_x, vert.pos.y - last.vert_y));
                    if (cxp < 0) {
                        // Bends inwards. Fill triangles until we aren't bending inward.
                        self.addTriangle(vert.out_idx, cur.vert_out_idx, last.vert_out_idx);
                        self.deferred_verts.removeAssumeNoPrev(last_id) catch unreachable;
                    } else {
                        break;
                    }
                    last_id = cur_id;
                    last = cur;
                    cur_id = self.deferred_verts.getNextNoCheck(cur_id);
                }
                if (i > 0) {
                    const d_vert = self.deferred_verts.insertBeforeHeadNoCheck(last_id, DeferredVertexNode.init(vert)) catch unreachable;
                    left.deferred_queue = d_vert;
                    left.deferred_queue_size = left.deferred_queue_size - i + 1;
                } else {
                    left.enqueueDeferred(vert, self);
                }
            } else {
                left.enqueueDeferred(vert, self);
            }
        } else {
            log("changed to left side", .{});
            // Changed to left side.
            // Automatically create queue size - 1 triangles.
            var last_id = left.deferred_queue;
            var last = self.deferred_verts.getNoCheck(last_id);
            var cur_id = self.deferred_verts.getNextNoCheck(last_id);
            var i: u32 = 0;
            while (i < left.deferred_queue_size-1) : (i += 1) {
                const cur = self.deferred_verts.getNoCheck(cur_id);
                self.addTriangle(vert.out_idx, last.vert_out_idx, cur.vert_out_idx);
                last_id = cur_id;
                last = cur;
                cur_id = self.deferred_verts.getNextNoCheck(cur_id);
                // Delete last after it's assigned to current.
                self.deferred_verts.removeAssumeNoPrev(last_id) catch unreachable;
            }
            left.dumpQueue(self);
            self.deferred_verts.getNodePtrNoCheck(left.deferred_queue).next = NullId;
            left.deferred_queue_size = 1;
            left.enqueueDeferred(vert, self);
            left.cur_side = .Left;
            left.dumpQueue(self);
        }
    }

    fn triangulateRightStep(self: *Self, left: *SweepEdge, vert: InternalVertex) void {
        if (left.cur_side == .Right) {
            log("right side", .{});
            // Same side.
            if (left.deferred_queue_size >= 2) {
                var last_id = left.deferred_queue;
                var last = self.deferred_verts.getNoCheck(last_id);
                if (last.vert_out_idx == vert.out_idx) {
                    // Ignore this point since it is the same as the last.
                    return;
                }
                var cur_id = self.deferred_verts.getNextNoCheck(last_id);
                var i: u16 = 0;
                while (i < left.deferred_queue_size-1) : (i += 1) {
                    const cur = self.deferred_verts.getNoCheck(cur_id);
                    const cxp = vec2(last.vert_x - cur.vert_x, last.vert_y - cur.vert_y).cross(vec2(vert.pos.x - last.vert_x, vert.pos.y - last.vert_y));
                    if (cxp > 0) {
                        // Bends inwards. Fill triangles until we aren't bending inward.
                        self.addTriangle(vert.out_idx, last.vert_out_idx, cur.vert_out_idx);
                        self.deferred_verts.removeAssumeNoPrev(last_id) catch unreachable;
                    } else {
                        break;
                    }
                    last_id = cur_id;
                    last = cur;
                    cur_id = self.deferred_verts.getNextNoCheck(cur_id);
                }
                if (i > 0) {
                    const d_vert = self.deferred_verts.insertBeforeHeadNoCheck(last_id, DeferredVertexNode.init(vert)) catch unreachable;
                    left.deferred_queue = d_vert;
                    left.deferred_queue_size = left.deferred_queue_size - i + 1;
                } else {
                    left.enqueueDeferred(vert, self);
                }
            } else {
                left.enqueueDeferred(vert, self);
            }
        } else {
            log("changed to right side", .{});
            var last_id = left.deferred_queue;
            var last = self.deferred_verts.getNoCheck(last_id);
            var cur_id = self.deferred_verts.getNextNoCheck(last_id);
            var i: u32 = 0;
            while (i < left.deferred_queue_size-1) : (i += 1) {
                const cur = self.deferred_verts.getNoCheck(cur_id);
                self.addTriangle(vert.out_idx, cur.vert_out_idx, last.vert_out_idx);
                last_id = cur_id;
                last = cur;
                cur_id = self.deferred_verts.getNextNoCheck(cur_id);
                // Delete last after it's assigned to current.
                self.deferred_verts.removeAssumeNoPrev(last_id) catch unreachable;
            }
            self.deferred_verts.getNodePtrNoCheck(left.deferred_queue).next = NullId;
            left.deferred_queue_size = 1;
            left.enqueueDeferred(vert, self);
            left.cur_side = .Right;
            left.dumpQueue(self);
        }
    }

    /// Splits two edges at an intersect point.
    /// Assumes sweep edges have not processed their end events so they can be reinserted.
    /// Does not add new events if an event already exists to the intersect point.
    fn handleIntersectForStartEvent(self: *Self, sweep_edge_a: *SweepEdge, sweep_edge_b: *SweepEdge, intersect: IntersectResult, sweep_vert: Vec2) void {
        log("split intersect {}", .{intersect});

        // The intersect point must lie after the sweep_vert.
        if (intersect.y < sweep_vert.y or (intersect.y == sweep_vert.y and intersect.x <= sweep_vert.x)) {
            return;
        }

        var added_events = false;

        // Create new intersect vertex.
        const intersect_idx = @intCast(u16, self.verts.items.len);
        const intersect_v = InternalVertex{
            .pos = vec2(intersect.x, intersect.y),
            .idx = intersect_idx,
        };
        self.verts.append(intersect_v) catch unreachable;

        // TODO: Account for floating point error.
        const a_to_vert = self.verts.items[sweep_edge_a.to_vert_idx];
        if (a_to_vert.pos.x != intersect.x or a_to_vert.pos.y != intersect.y) {
            // log(edgeToString(sweep_edge_a.edge))
            log("adding edge a {} to {},{}", .{sweep_edge_a.vert_idx, intersect.x, intersect.y});
            added_events = true;

            // Invalidate sweep_edge_a's end event since the priority queue can not be modified.
            self.events.items[sweep_edge_a.end_event_idx].invalidated = true;

            // Keep original edge orientation when doing the split.
            var first_edge: Edge = undefined;
            var second_edge: Edge = undefined;
            const start = self.verts.items[sweep_edge_a.edge.start_idx];
            const end = self.verts.items[sweep_edge_a.edge.end_idx];
            if (sweep_edge_a.to_vert_idx == sweep_edge_a.edge.start_idx) {
                first_edge = Edge.init(intersect_idx, intersect_v, sweep_edge_a.edge.end_idx, end);
                second_edge = Edge.init(sweep_edge_a.edge.start_idx, start, intersect_idx, intersect_v);
            } else {
                first_edge = Edge.init(sweep_edge_a.edge.start_idx, start, intersect_idx, intersect_v);
                second_edge = Edge.init(intersect_idx, intersect_v, sweep_edge_a.edge.end_idx, end);
            }

            // Update sweep_edge_a to end at the intersect.
            sweep_edge_a.edge = first_edge;
            const a_orig_to_vert = sweep_edge_a.to_vert_idx;
            sweep_edge_a.to_vert_idx = intersect_idx;

            // Insert new sweep_edge_a end event.
            const evt_idx = @intCast(u32, self.events.items.len);
            var new_evt = Event.init(intersect_idx, first_edge, self.verts.items);
            self.events.append(new_evt) catch unreachable;
            self.event_q.add(evt_idx) catch unreachable;

            // Insert start/end event from the intersect to the end of the original sweep_edge_a.
            var event1 = Event.init(intersect_idx, second_edge, self.verts.items);
            var event2 = Event.init(a_orig_to_vert, second_edge, self.verts.items);
            if (event1.tag == .Start) {
                event1.end_event_idx = evt_idx + 2;
            } else {
                event2.end_event_idx = evt_idx + 1;
            }
            self.events.append(event1) catch unreachable;
            self.event_q.add(evt_idx + 1) catch unreachable;
            self.events.append(event2) catch unreachable;
            self.event_q.add(evt_idx + 2) catch unreachable;
        }

        const b_to_vert = self.verts.items[sweep_edge_b.to_vert_idx];
        if (b_to_vert.pos.x != intersect.x or b_to_vert.pos.y != intersect.y) {
            log("adding edge b {} to {},{}", .{sweep_edge_b.vert_idx, intersect.x, intersect.y});
            added_events = true;

            // Invalidate sweep_edge_b's end event since the priority queue can not be modified.
            log("invalidate: {} {}", .{sweep_edge_b.end_event_idx, self.events.items.len});
            self.events.items[sweep_edge_b.end_event_idx].invalidated = true;

            // Keep original edge orientation when doing the split.
            var first_edge: Edge = undefined;
            var second_edge: Edge = undefined;
            const start = self.verts.items[sweep_edge_b.edge.start_idx];
            const end = self.verts.items[sweep_edge_b.edge.end_idx];
            if (sweep_edge_b.to_vert_idx == sweep_edge_b.edge.start_idx) {
                first_edge = Edge.init(intersect_idx, intersect_v, sweep_edge_b.edge.end_idx, end);
                second_edge = Edge.init(sweep_edge_b.edge.start_idx, start, intersect_idx, intersect_v);
            } else {
                first_edge = Edge.init(sweep_edge_b.edge.start_idx, start, intersect_idx, intersect_v);
                second_edge = Edge.init(intersect_idx, intersect_v, sweep_edge_b.edge.end_idx, end);
            }

            // Update sweep_edge_b to end at the intersect.
            sweep_edge_b.edge = first_edge;
            const b_orig_to_vert = sweep_edge_b.to_vert_idx;
            sweep_edge_b.to_vert_idx = intersect_idx;

            // Insert new sweep_edge_b end event.
            const evt_idx = @intCast(u32, self.events.items.len);
            var new_evt = Event.init(intersect_idx, first_edge, self.verts.items);
            self.events.append(new_evt) catch unreachable;
            self.event_q.add(evt_idx) catch unreachable;

            // Insert start/end event from the intersect to the end of the original sweep_edge_b.
            var event1 = Event.init(intersect_idx, second_edge, self.verts.items);
            var event2 = Event.init(b_orig_to_vert, second_edge, self.verts.items);
            if (event1.tag == .Start) {
                event1.end_event_idx = evt_idx + 2;
            } else {
                event2.end_event_idx = evt_idx + 1;
            }
            self.events.append(event1) catch unreachable;
            self.event_q.add(evt_idx + 1) catch unreachable;
            self.events.append(event2) catch unreachable;
            self.event_q.add(evt_idx + 2) catch unreachable;
        }

        if (!added_events) {
            // No events were added, revert adding intersect point.
            _ = self.verts.pop();
        }
    }

};

fn edgeToString(edge: Edge) []const u8 {
    const S = struct {
        var buf: [100]u8 = undefined;
    };
    return std.fmt.bufPrint(&S.buf, "{} ({},{}) -> {} ({},{})", .{edge.start_idx, edge.start_pos.x, edge.start_pos.y, edge.end_idx, edge.end_pos.x, edge.end_pos.y}) catch unreachable;
}

fn compareEventIdx(events: *std.ArrayList(Event), a: u32, b: u32) std.math.Order {
    return compareEvent(events.items[a], events.items[b]);
}

/// Sort verts by y asc then x asc. Resolve same position by looking at the edge's xslope and whether it is active.
fn compareEvent(a: Event, b: Event) std.math.Order {
    if (a.vert_y < b.vert_y) {
        return .lt;
    } else if (a.vert_y > b.vert_y) {
        return .gt;
    } else {
        if (a.vert_x < b.vert_x) {
            return .lt;
        } else if (a.vert_x > b.vert_x) {
            return .gt;
        } else {
            if (a.tag == .End and b.tag == .Start) {
                return .lt;
            } else if (a.tag == .Start and b.tag == .End) {
                return .gt;
            } else if (a.tag == .End and b.tag == .End) {
                if (a.edge.x_slope > b.edge.x_slope) {
                    return .lt;
                } else if (a.edge.x_slope < b.edge.x_slope) {
                    return .gt;
                } else {
                    return .eq;
                }
            } else {
                if (a.edge.x_slope < b.edge.x_slope) {
                    return .lt;
                } else if (a.edge.x_slope > b.edge.x_slope) {
                    return .gt;
                } else {
                    return .eq;
                }
            }
        }
    }
}

/// Compare SweepEdges for insertion. Each sweep edge should be unique since the rb tree doesn't support duplicate values.
/// The slopes from the current sweep edges are used to find their x-intersect along the event's y line.
/// If compared sweep edge is a horizontal line, return gt so it's inserted after it. The horizontal edge can be assumed to intersect with the target event or it wouldn't be in the sweep edges.
fn compareSweepEdge(_: SweepEdge, b: SweepEdge, evt: Event) std.math.Order {
    if (!b.edge.is_horiz) {
        const x_intersect = b.edge.x_slope * (evt.vert_y - b.edge.start_pos.y) + b.edge.start_pos.x;
        if (std.math.absFloat(evt.vert_x - x_intersect) < std.math.epsilon(f32)) {
            // Since there is a chance of having floating point error, check with an epsilon.
            // Always return .gt so the left sweep edge can be reliably checked for a joining edge.
            return .gt;
        } else {
            if (evt.vert_x < x_intersect) {
                return .lt;
            } else if (evt.vert_x > x_intersect) {
                return .gt;
            } else {
                unreachable;
            }
        }
    } else {
        return .gt;
    }
}

fn findSweepEdgeForEndEvent(sweep_edges: *RbTree(u16, SweepEdge, Event, compareSweepEdge), e: Event) ?u16 {
    const target = vec2(e.vert_x, e.vert_y);
    const dummy = SweepEdge{
        .edge = undefined,
        .start_event_vert_uniq_idx = undefined,
        .vert_idx = undefined,
        .to_vert_idx = undefined,
        .end_event_vert_uniq_idx = undefined,
        .deferred_queue = undefined,
        .deferred_queue_size = undefined,
        .cur_side = undefined,
        .bad_up_cusp_uniq_idx = undefined,
        .bad_up_cusp_right_sweep_edge_id = undefined,
        .lowest_right_vert_idx = undefined,
        .lowest_right_vert_sweep_edge_id = undefined,
        .interior_is_left = undefined,
        .end_event_idx = undefined,
    };
    const id = sweep_edges.lookupCustom(dummy, target, compareSweepEdgeApprox) orelse return null;

    // Given a start index where a group of verts could have approx the same x-intersect value, find the one with the exact vert and to_vert.
    // The search ends on left/right when the x-intersect suddenly becomes greater than the epsilon.
    var se = sweep_edges.getNoCheck(id);
    if (se.to_vert_idx == e.vert_idx and se.vert_idx == e.to_vert_idx) {
        return id;
    }
    // Search left.
    var mb_cur = sweep_edges.getPrev(id);
    while (mb_cur) |cur| {
        se = sweep_edges.getNoCheck(cur);
        const x_intersect = getXIntersect(se.edge, target);
        if (std.math.absFloat(e.vert_x - x_intersect) > std.math.epsilon(f32)) {
            break;
        } else if (se.to_vert_idx == e.vert_idx and se.vert_idx == e.to_vert_idx) {
            return cur;
        }
        mb_cur = sweep_edges.getPrev(cur);
    }
    // Search right.
    mb_cur = sweep_edges.getNext(id);
    while (mb_cur) |cur| {
        se = sweep_edges.getNoCheck(cur);
        const x_intersect = getXIntersect(se.edge, target);
        if (std.math.absFloat(e.vert_x - x_intersect) > std.math.epsilon(f32)) {
            break;
        } else if (se.to_vert_idx == e.vert_idx and se.vert_idx == e.to_vert_idx) {
            return cur;
        }
        mb_cur = sweep_edges.getNext(id);
    }
    return null;
}

/// Finds the first edge with x-intersect that approximates the provided target vert's x.
/// This is needed since floating point error can lead to inconsistent divide and conquer for x-intersects that are close together (eg. two edges stemming from one vertex)
/// A follow up routine to find the exact edge should be run afterwards.
fn compareSweepEdgeApprox(_: SweepEdge, b: SweepEdge, target: Vec2) std.math.Order {
    const x_intersect = getXIntersect(b.edge, target);
    if (std.math.absFloat(target.x - x_intersect) < std.math.epsilon(f32)) {
        return .eq;
    } else if (target.x < x_intersect) {
        return .lt;
    } else {
        return .gt;
    }
}

// Assumes there is an intersect.
fn getXIntersect(edge: Edge, target: Vec2) f32 {
    if (!edge.is_horiz) {
        return edge.x_slope * (target.y - edge.start_pos.y) + edge.start_pos.x;
    } else {
        return target.x;
    }
}

const EventTag = enum(u1) {
    Start = 0,
    End = 1,
};

/// Polygon verts and edges are reduced to events.
/// Each event is centered on a vertex and has an outgoing or incoming edge.
/// If the edge is above the vertex, it's considered a End event.
/// If the edge is below the vertex, it's considered a Start event.
/// Events are sorted by y asc and the x asc.
/// To order events on the same vertex, the event with an active edge has priority.
/// If both events have active edges (both End events), the one that has a greater x-slope comes first. This means an active edge to the left comes first.
/// This helps end processing since the left edge still exists and contains state information about that fill region.
/// If both events have non active edges (both Start events), the one that has a lesser x-slope comes first.
const Event = struct {
    const Self = @This();

    /// The idx of the internal vertex that this event fires on.
    vert_idx: u16,

    /// Duped vert pos for compare func.
    vert_x: f32,
    vert_y: f32,

    tag: EventTag,

    edge: Edge,

    to_vert_idx: u16,

    /// If this is a start event, end_event_idx will point to the corresponding end event.
    end_event_idx: u32,

    /// Since an intersection creates new events and can not modify the priority queue,
    /// this flag is used to invalid an existing end event.
    invalidated: bool,

    fn init(vert_idx: u16, edge: Edge, verts: []const InternalVertex) Self {
        const vert = verts[vert_idx];
        var new = Self{
            .vert_idx = vert_idx,
            .vert_x = vert.pos.x,
            .vert_y = vert.pos.y,
            .edge = edge,
            .tag = undefined,
            .to_vert_idx = undefined,
            .end_event_idx = std.math.maxInt(u32),
            .invalidated = false,
        };
        // The start and end vertex of an edge is not to be confused with the EventType.
        // It is used to determine if the edge is above or below the vertex point.
        if (edge.start_idx == vert_idx) {
            new.to_vert_idx = edge.end_idx;
            const end_v = verts[edge.end_idx];
            if (end_v.pos.y < vert.pos.y or (end_v.pos.y == vert.pos.y and end_v.pos.x < vert.pos.x)) {
                new.tag = .End;
            } else {
                new.tag = .Start;
            }
        } else {
            new.to_vert_idx = edge.start_idx;
            const start_v = verts[edge.start_idx];
            if (start_v.pos.y < vert.pos.y or (start_v.pos.y == vert.pos.y and start_v.pos.x < vert.pos.x)) {
                new.tag = .End;
            } else {
                new.tag = .Start;
            }
        }
        return new;
    }
};

const Side = enum(u1) {
    Left = 0,
    Right = 1,
};

pub const SweepEdge = struct {
    const Self = @This();

    edge: Edge,
    start_event_vert_uniq_idx: u16,
    vert_idx: u16,
    to_vert_idx: u16,

    end_event_idx: u32,

    /// The End event that marks this edge for removal. This is set in the End event.
    end_event_vert_uniq_idx: u16,

    /// Points to the head vertex.
    deferred_queue: DeferredVertexNodeId,

    /// Current size of the queue.
    deferred_queue_size: u16,

    /// The current side being processed for monotone triangulation.
    cur_side: Side,

    /// Last seen bad up cusp. 
    bad_up_cusp_uniq_idx: u16,
    bad_up_cusp_right_sweep_edge_id: u16,
    lowest_right_vert_idx: u16,
    lowest_right_vert_sweep_edge_id: u16,

    /// Store the winding. This would be used by the fill rule to determine if the interior is to the left or right.
    interior_is_left: bool,

    /// A sweep edge is created from a Start event.
    fn init(e: Event, verts: []const InternalVertex) Self {
        const e_vert = verts[e.vert_idx];
        return .{
            .edge = e.edge,
            .start_event_vert_uniq_idx = e_vert.out_idx,
            .vert_idx = e.vert_idx,
            .to_vert_idx = e.to_vert_idx,
            .end_event_idx = e.end_event_idx,
            .end_event_vert_uniq_idx = std.math.maxInt(u16),
            .deferred_queue = NullId,
            .deferred_queue_size = 0,
            .cur_side = .Left,
            .bad_up_cusp_uniq_idx = NullId,
            .bad_up_cusp_right_sweep_edge_id = NullId,
            .lowest_right_vert_idx = NullId,
            .lowest_right_vert_sweep_edge_id = NullId,
            .interior_is_left = false,
        };
    }

    fn enqueueDeferred(self: *Self, vert: InternalVertex, tess: *Tessellator) void {
        const node = DeferredVertexNode.init(vert);
        self.deferred_queue = tess.deferred_verts.insertBeforeHeadNoCheck(self.deferred_queue, node) catch unreachable;
        self.deferred_queue_size += 1;
    }

    fn dumpQueue(self: Self, tess: *Tessellator) void {
        var buf: [200]u8 = undefined;
        var buf_stream = std.io.fixedBufferStream(&buf);
        var writer = buf_stream.writer();
        var cur_id = self.deferred_queue;
        while (cur_id != NullId) {
            const cur = tess.deferred_verts.getNoCheck(cur_id);
            std.fmt.format(writer, "{},", .{cur.vert_idx}) catch unreachable;
            const last = cur_id;
            cur_id = tess.deferred_verts.getNextNoCheck(cur_id);
            if (last == cur_id) {
                std.fmt.format(writer, "repeat pt - bad state", .{}) catch unreachable;
                break;
            }
        }
        var side_str: []const u8 = if (self.cur_side == .Right) "right" else "left";
        log("size: {}, side: {s}, idxes: {s}", .{self.deferred_queue_size, side_str, buf[0..buf_stream.pos]});
    }
};

/// This contains a vertex that still needs to be triangulated later when it can.
/// It is linked together in a singly linked list queue and is designed to behave like the monotone triangulation queue.
/// Since the triangulator does everything in one pass for complex polygons, every monotone polygon span in the sweep edges
/// needs to keep track of their deferred vertices since the edges are short lived.
pub const DeferredVertexNode = struct {
    const Self = @This();

    vert_idx: u16,

    // Duped vars.
    vert_out_idx: u16,
    vert_x: f32,
    vert_y: f32,

    fn init(vert: InternalVertex) Self {
        return .{
            .vert_idx = vert.idx,
            .vert_out_idx = vert.out_idx,
            .vert_x = vert.pos.x,
            .vert_y = vert.pos.y,
        };
    }
};

/// Contains start/end InternalVertex.
pub const Edge = struct {
    const Self = @This();

    /// Start vertex index.
    start_idx: u16,
    /// End vertex index.
    end_idx: u16,

    /// Duped start_pos for compareSweepEdge, getXIntersect.
    start_pos: Vec2,
    end_pos: Vec2,

    /// Vector from start to end pos.
    vec: Vec2,

    /// Change of x with respect to y.
    x_slope: f32,

    /// Whether the edge is horizontal.
    /// TODO: This may not be needed anymore.
    is_horiz: bool,

    fn init(start_idx: u16, start_v: InternalVertex, end_idx: u16, end_v: InternalVertex) Self {
        var new = Self{
            .start_idx = start_idx,
            .end_idx = end_idx,
            .start_pos = start_v.pos,
            .end_pos = end_v.pos,
            .vec = vec2(end_v.pos.x - start_v.pos.x, end_v.pos.y - start_v.pos.y),
            .x_slope = undefined,
            .is_horiz = undefined,
        };
        if (new.vec.y != 0) {
            new.x_slope = new.vec.x / new.vec.y;
            new.is_horiz = false;
        } else {
            new.x_slope = std.math.f32_max;
            new.is_horiz = true;
        }
        return new;
    }
};

/// Internal verts. During triangulation, these are using for event computations so there can be duplicates points.
pub const InternalVertex = struct {
    pos: Vec2,
    /// This is the index of the vertex from the given polygon.
    idx: u16,
    /// The vertex index of the resulting buffer. Set during process event.
    out_idx: u16 = undefined,
};

/// Avoids division by zero.
/// https://stackoverflow.com/questions/563198
/// For segments: p, p + r, q, q + s
/// To find t, u for p + tr, q + us
/// t = (q − p) X s / (r X s)
/// u = (q − p) X r / (r X s)
fn computeTwoEdgeIntersect(p: Edge, q: Edge) IntersectResult {
    const r_s = p.vec.cross(q.vec);
    if (r_s == 0) {
        return IntersectResult.initNull();
    }
    const qmp = vec2(q.start_pos.x - p.start_pos.x, q.start_pos.y - p.start_pos.y);
    const qmp_r = qmp.cross(p.vec);
    const u = qmp_r / r_s;
    if (u >= 0 and u <= 1) {
        // Must check intersect point is also on p.
        const qmp_s = qmp.cross(q.vec);
        const t_ = qmp_s / r_s;
        if (t_ >= 0 and t_ <= 1) {
            return .{
                .x = q.start_pos.x + q.vec.x * u,
                .y = q.start_pos.y + q.vec.y * u,
                .t = t_,
                .u = u,
                .has_intersect = true,
            };
        } else {
            return IntersectResult.initNull();
        }
    } else {
        return IntersectResult.initNull();
    }
}

const IntersectResult = struct {
    x: f32,
    y: f32,
    t: f32,
    u: f32,
    has_intersect: bool,

    fn initNull() IntersectResult {
        return .{
            .x = undefined,
            .y = undefined,
            .t = undefined,
            .u = undefined,
            .has_intersect = false,
        };
    }
};

fn testSimple(polygon: []const f32, exp_verts: []const f32, exp_idxes: []const u16) !void {
    var polygon_buf = std.ArrayList(Vec2).init(t.alloc);
    defer polygon_buf.deinit();
    var i: u32 = 0;
    while (i < polygon.len) : (i += 2) {
        polygon_buf.append(vec2(polygon[i], polygon[i+1])) catch unreachable;
    }
    var tessellator: Tessellator = undefined;
    tessellator.init(t.alloc);
    defer tessellator.deinit();
    tessellator.triangulatePolygon(polygon_buf.items);

    var exp_verts_buf = std.ArrayList(Vec2).init(t.alloc);
    defer exp_verts_buf.deinit();
    i = 0;
    while (i < exp_verts.len) : (i += 2) {
        exp_verts_buf.append(vec2(exp_verts[i], exp_verts[i+1])) catch unreachable;
    }
    try t.eqSlice(Vec2, tessellator.out_verts.items, exp_verts_buf.items);
    // log("{any}", .{tessellator.out_idxes.items});
    try t.eqSlice(u16, tessellator.out_idxes.items, exp_idxes);
}

test "One triangle ccw." {
    try testSimple(&.{
        100, 0,
        0, 0,
        0, 100,
    }, &.{
        0, 0,
        100, 0,
        0, 100,
    }, &.{ 2, 1, 0 });
}

test "One triangle cw." {
    try testSimple(&.{
        100, 0,
        0, 100,
        0, 0,
    }, &.{
        0, 0,
        100, 0,
        0, 100,
    }, &.{ 2, 1, 0 });
}

test "Square." {
    try testSimple(&.{
        0, 0,
        100, 0,
        100, 100,
        0, 100,
    }, &.{
        0, 0,
        100, 0,
        0, 100,
        100, 100,
    }, &.{
        2, 1, 0,
        3, 1, 2,
    });
}

test "Pentagon." {
    try testSimple(&.{
        100, 0,
        200, 100,
        200, 200,
        0, 200,
        0, 100,
    }, &.{
        100, 0,
        0, 100,
        200, 100,
        0, 200,
        200, 200,
    }, &.{
        2, 0, 1,
        3, 2, 1,
        4, 2, 3,
    });
}

test "Hexagon." {
    try testSimple(&.{
        100, 0,
        200, 100,
        200, 200,
        100, 300,
        0, 200,
        0, 100,
    }, &.{
        100, 0,
        0, 100,
        200, 100,
        0, 200,
        200, 200,
        100, 300,
    }, &.{
        2, 0, 1,
        3, 2, 1,
        4, 2, 3,
        5, 4, 3,
    });
}

test "Octagon." {
    try testSimple(&.{
        100, 0,
        200, 0,
        300, 100,
        300, 200,
        200, 300,
        100, 300,
        0, 200,
        0, 100,
    }, &.{
        100, 0,
        200, 0,
        0, 100,
        300, 100,
        0, 200,
        300, 200,
        100, 300,
        200, 300,
    }, &.{
        2, 1, 0,
        3, 1, 2,
        4, 3, 2,
        5, 3, 4,
        6, 5, 4,
        7, 5, 6,
    });
}

test "Rhombus." {
    try testSimple(&.{
        100, 0,
        200, 100,
        100, 200,
        0, 100,
    }, &.{
        100, 0,
        0, 100,
        200, 100,
        100, 200,
    }, &.{
        2, 0, 1,
        3, 2, 1,
    });
}

// Tests monotone partition with bad up cusp and valid right angle.
test "Square with concave top side." {
    try testSimple(&.{
        0, 0,
        100, 100,
        200, 0,
        200, 200,
        0, 200,
    }, &.{
        0, 0,
        200, 0,
        100, 100,
        0, 200,
        200, 200,
    }, &.{
        3, 2, 0,
        4, 2, 3,
        4, 1, 2,
    });
}

// Tests monotone partition with bad down cusp and valid right angle.
test "Square with concave bottom side." {
    try testSimple(&.{
        0, 0,
        200, 0,
        200, 200,
        100, 100,
        0, 200,
    }, &.{
        0, 0,
        200, 0,
        100, 100,
        0, 200,
        200, 200,
    }, &.{
        2, 1, 0,
        3, 2, 0,
        4, 1, 2,
    });
}

// Tests monotone partition with bad up cusp and valid up cusp.
test "V shape." {
    try testSimple(&.{
        0, 0,
        100, 100,
        200, 0,
        100, 200,
    }, &.{
        0, 0,
        200, 0,
        100, 100,
        100, 200,
    }, &.{
        3, 2, 0,
        3, 1, 2,
    });
}

// Tests monotone partition with bad down cusp and valid up cusp.
test "Upside down V shape." {
    try testSimple(&.{
        100, 0,
        200, 200,
        100, 100,
        0, 200,
    }, &.{
        100, 0,
        100, 100,
        0, 200,
        200, 200,
    }, &.{
        2, 1, 0,
        3, 0, 1,
    });
}

// Tests the sweep line with alternating interior/exterior sides.
test "Clockwise spiral." {
    try testSimple(&.{
        0, 0,
        500, 0,
        500, 500,
        200, 500,
        200, 200,
        300, 200,
        300, 400,
        400, 400,
        400, 100,
        100, 100,
        100, 500,
        0, 500,
    }, &.{
        0, 0,
        500, 0,
        100, 100,
        400, 100,
        200, 200,
        300, 200,
        300, 400,
        400, 400,
        0, 500,
        100, 500,
        200, 500,
        500, 500,
    }, &.{
        2, 1, 0,
        3, 1, 2,
        6, 5, 4,
        7, 1, 3,
        8, 2, 0,
        9, 2, 8,
        10, 7, 6,
        10, 6, 4,
        11, 7, 10,
        11, 1, 7,
    });
}

// Tests the sweep line with alternating interior/exterior sides.
test "CCW spiral." {
    try testSimple(&.{
        0, 0,
        500, 0,
        500, 500,
        400, 500,
        400, 100,
        100, 100,
        100, 400,
        200, 400,
        200, 200,
        300, 200,
        300, 500,
        0, 500,
    }, &.{
        0, 0,
        500, 0,
        100, 100,
        400, 100,
        200, 200,
        300, 200,
        100, 400,
        200, 400,
        0, 500,
        300, 500,
        400, 500,
        500, 500,
    }, &.{
        2, 1, 0,
        3, 1, 2,
        6, 2, 0,
        7, 5, 4,
        8, 7, 6,
        8, 6, 0,
        9, 7, 8,
        9, 5, 7,
        10, 1, 3,
        11, 1, 10,
    });
}

test "Overlapping point." {
    try testSimple(&.{
        0, 0,
        100, 100,
        200, 0,
        200, 200,
        100, 100,
        0, 200,
    }, &.{
        0, 0,
        200, 0,
        100, 100,
        0, 200,
        200, 200,
    }, &.{
        3, 2, 0,
        4, 1, 2,
    });
}

// Different windings on split polygons.
test "Self intersecting polygon." {
    try testSimple(&.{
        0, 200,
        0, 100,
        200, 100,
        200, 0,
    }, &.{
        200, 0,
        0, 100,
        100, 100,
        200, 100,
        0, 200,
    }, &.{
        3, 0, 2,
        4, 2, 1,
    });
}

// Test evenodd rule.
test "Overlapping triangles." {
    try testSimple(&.{
        0, 100,
        200, 0,
        200, 200,
        0, 100,
        250, 75,
        250, 125,
        0, 100,
    }, &.{
        200, 0,
        250, 75,
        200, 80,
        0, 100,
        200, 120,
        250, 125,
        200, 200,
    }, &.{
        3, 2, 0,
        4, 1, 2,
        5, 1, 4,
        6, 4, 3,
    });
}

// Begin mapbox test cases.

test "bad-diagonals.json" {
    try testSimple(&.{
        440,4152,
        440,4208,
        296,4192,
        368,4192,
        400,4200,
        400,4176,
        368,4192,
        296,4192,
        264,4200,
        288,4160,
        296,4192,
    }, &.{
        440,4152,
        288,4160,
        400,4176,
        296,4192,
        368,4192,
        264,4200,
        400,4200,
        440,4208,
    }, &.{
        3, 2, 0,
        4, 2, 3,
        5, 3, 1,
        6, 4, 3,
        6, 0, 2,
        7, 6, 3,
        7, 0, 6,
    });
}

// TODO: dude.json

// Case by case examples.

test "Rectangle with bottom-left wedge." {
    try testSimple(&.{
        56, 22,
        111, 22,
        111, 44,
        37, 44,
        56, 32,
    }, &.{
        56, 22,
        111, 22,
        56, 32,
        37, 44,
        111, 44,
    }, &.{
        2, 1, 0,
        3, 1, 2,
        4, 1, 3,
    });
}