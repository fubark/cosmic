// Dev mode: cosmic dev tessellator.js --test-api

const t = cs.test

// Experimental tessellator for complex polygons.
// This serves as a experimental model for the zig version.
// After the zig version is up to date, the js tessellator will still remain in case cosmic needs a web backend without wasm.

// Converted from std.sort.binarySearch.
function binarySearch(arr, val, cmp, ctx) {
    let start = 0;
    let end = arr.length;
    while (start < end) {
        const mid = start + Math.floor((end - start) / 2);
        const res = cmp(val, arr[mid], ctx);
        if (res == 0) {
            return mid;
        } else if (res == 1) {
            start = mid + 1;
        } else {
            end = mid;
        }
    }
    return -1;
}

// Use a compare function instead of less function. Returning a = b will result in a insert idx being after b.
function binarySearchInsertIdxCmp(arr, val, cmp, ctx) {
    if (arr.length == 0) {
        return 0;
    }
    let start = 0;
    let end = arr.length;
    while (start < end) {
        const mid_idx = Math.floor((start + end) / 2);
        const res = cmp(val, arr[mid_idx], ctx)
        if (res == -1 || res == 0) {
            end = mid_idx;
        } else {
            start = mid_idx + 1;
        }
    }
    return start;
}

// Returns insert idx. Converted from stdx.algo.binarySearchInsertIdx.
function binarySearchInsertIdx(arr, val, less, ctx) {
    if (arr.length == 0) {
        return 0;
    }
    let start = 0;
    let end = arr.length;
    while (start < end) {
        const mid_idx = Math.floor((start + end) / 2);
        if (less(val, arr[mid_idx], ctx)) {
            end = mid_idx;
        } else {
            start = mid_idx + 1;
        }
    }
    return start;
}

function numAsc(a, b) {
    return a < b
}

t.eq(binarySearchInsertIdx([], 1, numAsc), 0)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 0, numAsc), 0)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 1, numAsc), 1)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 2, numAsc), 1)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 3, numAsc), 2)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 4, numAsc), 2)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 5, numAsc), 3)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 6, numAsc), 3)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 7, numAsc), 4)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 8, numAsc), 4)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 9, numAsc), 5)
t.eq(binarySearchInsertIdx([1, 3, 5, 7, 9], 10, numAsc), 5)

t.eq(binarySearchInsertIdx([10, 10, 10, 10], 10, numAsc), 4)
t.eq(binarySearchInsertIdx([10, 10, 10, 10], 9, numAsc), 0)
t.eq(binarySearchInsertIdx([10, 10, 10, 10], 11, numAsc), 4)

// Polygon verts and edges are reduced to events.
// Each event is centered on a vertex and has an outgoing or incoming edge.
// If the edge is above the vertex, it's considered a End event.
// If the edge is below the vertex, it's considered a Start event.
// Events are sorted by y asc and the x asc.
// To order events on the same vertex, the event with an active edge has priority.
// If both events have active edges (both End events), the one that has a greater x-slope comes first. This means an active edge to the left comes first.
// This helps end processing since the left edge still exists and contains state information about that fill region.
// If both events have non active edges (both Start events), the one that has a lesser x-slope comes first.
class Event {
    constructor(vert, edge) {
        this.vert = vert
        // The start and end vertex of an edge is not to be confused with the EventType.
        // It is used to determine if the edge is above or below the vertex point.
        if (edge.start_v == vert) {
            this.to_vert = edge.end_v
            if (edge.end_v.y < vert.y || (edge.end_v.y == vert.y && edge.end_v.x < vert.x)) {
                this.type = EventType.End
            } else {
                this.type = EventType.Start
            }
        } else {
            this.to_vert = edge.start_v
            if (edge.start_v.y < vert.y || (edge.start_v.y == vert.y && edge.start_v.x < vert.x)) {
                this.type = EventType.End
            } else {
                this.type = EventType.Start
            }
        }
        this.edge = edge
    }
}

class EventType {
    static Start = 0
    static End = 1
}

// Contains start/end internal Vertexes.
class Edge {
    constructor(start_v, end_v) {
        this.start_v = start_v
        this.end_v = end_v
        this.vec = { x: end_v.x - start_v.x, y: end_v.y - start_v.y }
        if (this.vec.y != 0) {
            this.x_slope = this.vec.x / this.vec.y
            this.is_horiz = false
        } else {
            this.x_slope = Number.MAX_VALUE
            this.is_horiz = true
        }
    }
}

class SweepEdge {
    constructor(event) {
        this.edge = event.edge
        this.start_event_vert_uniq_idx = event.vert.out_idx
        this.vert = event.vert
        this.to_vert = event.to_vert
        // The End event that marks this edge for removal. This is set in the End event.
        this.end_event_vert_uniq_idx = -1
        // Points to the head vertex.
        this.deferred_queue = null
        // Current size of the queue.
        this.deferred_queue_size = 0
        // The current side being processed for monotone triangulation.
        this.cur_side = null
        // Last seen bad up cusp. 
        this.bad_up_cusp_uniq_idx = -1
        this.bad_up_cusp_right_edge = null
        this.lowest_right_vert = null
        this.lowest_right_vert_edge = null
    }
    enqueueDeferred(vert) {
        const node = new DeferredVertexNode(vert, this.deferred_queue)
        this.deferred_queue = node
        this.deferred_queue_size += 1
    }
    dumpQueue() {
        const verts = []
        const out_verts = []
        let cur = this.deferred_queue
        while (cur != null) {
            verts.push(cur.vert.idx)
            out_verts.push(cur.vert.out_idx)
            cur = cur.next
        }
        dump(`size: ${this.deferred_queue_size}, side: ${this.cur_side == RightSide ? 'right' : 'left'}, verts: ${verts.join(',')}, out verts: ${out_verts.join(',')}`)
    }
}

class Vertex {
    constructor(x, y, idx) {
        this.x = x
        this.y = y
        // This is the index of the vertex from the provided polygon.
        this.idx = idx
        // The vertex index of the resulting buffer. Set during process event.
        this.out_idx = -1
    }
}

class DeferredVertexNode {
    constructor(vert, next) {
        this.vert = vert
        this.next = next
    }
}

// Perform a plane sweep to triangulate a complex polygon in one pass.
// The output returns ccw triangle vertices and indexes ready to be fed into the gpu.
// This uses Bentley-Ottmann to handle self intersecting edges.
// Rules are followed to partition into y-monotone polygons and triangulate them.
function triangulatePolygon(polygon) {
    // Verts to output.
    // No duplicate verts will be outputed to reduce size footprint.
    // Since some verts won't be discovered until during the processing of events (edge intersections),
    // verts are added as the events are processed. As a result, the verts are also in order y-asc and x-asc.
    const out_verts = []

    // Triangles to output are triplets of indexes that point to verts. They are in ccw direction.
    const out_indexes = []

    // Internal verts. There can be duplicate vertices in here.
    const verts = []

    // Construct the initial events by traversing the polygon.
    const events = []
    verts.push(new Vertex(
        polygon[0].x,
        polygon[0].y,
        0,
    ))
    let last_v = verts[0]
    for (let i = 1; i < polygon.length; i += 1) {
        const pt = polygon[i]
        const v = new Vertex(pt.x, pt.y, i)
        verts.push(v)

        if (last_v.x == v.x && last_v.y == v.y) {
            // Don't connect two vertices that are on top of each other.
            // Allowing this would require an edge case to make sure there is a start AND end event since that is currently derived from the vertex points.
            // Push the vertex in anyway so there is consistency with the input.
            continue
        }

        const prev_edge = new Edge(last_v, v)
        const start_e = new Event(last_v, prev_edge)
        events.push(start_e)
        const end_e = new Event(v, prev_edge)
        events.push(end_e)

        last_v = v
    }
    if (last_v.x == verts[0].x && last_v.y == verts[0].y) {
        // Change the events from vert0 -> vert1 to lastvert -> vert1.
        const after_first_v = events[1].vert
        const edge = new Edge(last_v, after_first_v)
        const start_e = new Event(last_v, edge)
        events[0] = start_e
        const end_e = new Event(after_first_v, edge)
        events[1] = end_e
    } else {
        const edge = new Edge(last_v, verts[0])
        const start_e = new Event(last_v, edge)
        events.push(start_e)
        const end_e = new Event(verts[0], edge)
        events.push(end_e)
    }

    // TODO: Use priority queue.
    // Sort verts by y asc then x asc. Resolve same position by looking at the edge's xslope and whether it is active.
    events.sort(compareEvent)

    function compareEvent(a, b) {
        if (a.vert.y < b.vert.y) {
            return -1
        } else if (a.vert.y > b.vert.y) {
            return 1
        } else {
            if (a.vert.x < b.vert.x) {
                return -1
            } else if (a.vert.x > b.vert.x) {
                return 1
            } else {
                if (a.type == EventType.End && b.type == EventType.Start) {
                    return -1
                } else if (a.type == EventType.Start && b.type == EventType.End) {
                    return 1
                } else if (a.type == EventType.End && b.type == EventType.End) {
                    if (a.edge.x_slope > b.edge.x_slope) {
                        return -1
                    } else if (a.edge.x_slope < b.edge.x_slope) {
                        return 1
                    } else {
                        return 0
                    }
                } else {
                    if (a.edge.x_slope < b.edge.x_slope) {
                        return -1
                    } else if (a.edge.x_slope > b.edge.x_slope) {
                        return 1
                    } else {
                        return 0
                    }
                }
            }
        }
    }

    for (const e of events) {
        dump(edgeToString(e.edge), e.type)
    }

    // TODO: Use BST.
    // Maintain a sorted array of currently intersecting edges by the sweep lines sorted by x value.
    const sweep_edges = []

    // Finds the insert idx into the sweep edges list for a given event. 
    // The slopes from the current sweep edges are used to find their x-intersect along the event's y line.
    // If a sweep edge is also a horizontal line, use the start endpoint's x. Note that this is different than getXIntersect where the horiz edge reports the target.x.
    function findSweepEdgeInsert(_, b, evt) {
        if (!b.edge.is_horiz) {
            const x_intersect = b.edge.x_slope * (evt.vert.y - b.edge.start_v.y) + b.edge.start_v.x
            if (Math.abs(evt.vert.x - x_intersect) < Number.EPSILON) {
                // Since there is a chance of having floating point error, check with an epsilon.
                // After x equality is met, check x_slope.
                return evt.edge.x_slope < b.edge.x_slope
            } else {
                return evt.vert.x < x_intersect
            }
        } else {
            return evt.vert.x < b.edge.start_v.x
        }
    }

    // Finds the first edge with x-intersect that approximates the provided target vert's x.
    // This is needed since floating point error can lead to inconsistent divide and conquer for x-intersects that are close together (eg. two edges stemming from one vertex)
    // A follow up routine to find the exact edge should be run afterwards.
    function compareSweepEdgeApprox(target, b) {
        const x_intersect = getXIntersect(b.edge, target)
        if (Math.abs(target.x - x_intersect) < Number.EPSILON) {
            return 0
        } else if (target.x < x_intersect) {
            return -1
        } else {
            return 1
        }
    }

    // Assumes there is an intersect.
    function getXIntersect(edge, target) {
        if (!edge.is_horiz) {
            return edge.x_slope * (target.y - edge.start_v.y) + edge.start_v.x
        } else {
            return target.x
        }
    }

    function findSweepEdgeForEndEvent(arr, e) {
        const idx = binarySearch(arr, e.vert, compareSweepEdgeApprox)
        if (idx == -1) {
            return -1
        }

        // Given a start index where a group of verts could have approx the same x-intersect value, find the one with the exact vert and to_vert.
        // The search ends on left/right when the x-intersect suddenly becomes greater than the epsilon.
        if (arr[idx].to_vert.idx == e.vert.idx && arr[idx].vert.idx == e.to_vert.idx) {
            return idx
        }
        // Search left.
        for (let i = idx - 1; i >= 0; i-=1) {
            const edge = arr[i].edge
            const x_intersect = getXIntersect(edge, e.vert)
            if (Math.abs(e.vert.x - x_intersect) > Number.EPSILON) {
                break
            } else if (arr[i].to_vert.idx == e.vert.idx && arr[i].vert.idx == e.to_vert.idx) {
                return i
            }
        }
        // Search right.
        for (let i = idx + 1; i < arr.length; i+=1) {
            const edge = arr[i].edge
            const x_intersect = getXIntersect(edge, e.vert)
            if (Math.abs(e.vert.x - x_intersect) > Number.EPSILON) {
                break
            } else if (arr[i].to_vert.idx == e.vert.idx && arr[i].vert.idx == e.to_vert.idx) {
                return i
            }
        }
        return -1
    }

    let scratch_event = {}

    // Splits two edges at an intersect point.
    // Assumes sweep edges have not processed their end events so they can be reinserted.
    // Does not add new events if an event already exists to the intersect point.
    function handleIntersectForStartEvent(sweep_edge_a, sweep_edge_b, intersect, sweep_vert) {
        dump('split intersect', intersect)

        // The intersect point must lie after the sweep_vert.
        if (intersect.y < sweep_vert.y || (intersect.y == sweep_vert.y && intersect.x <= sweep_vert.x)) {
            return
        }

        let added_events = false

        // Create new intersect vertex.
        const intersect_v = new Vertex(
            intersect.x,
            intersect.y,
            verts.length,
        )

        // TODO: Account for floating point error.
        if (sweep_edge_a.to_vert.x != intersect.x || sweep_edge_a.to_vert.y != intersect.y) {
            dump(edgeToString(sweep_edge_a.edge))
            dump(`adding edge a ${sweep_edge_a.vert.idx} to ${intersect.x},${intersect.y}`)
            added_events = true

            // Remove sweep_edge_a's end event.
            scratch_event.vert = sweep_edge_a.to_vert
            scratch_event.type = EventType.End
            scratch_event.edge = sweep_edge_a.edge
            let idx = binarySearch(events, scratch_event, compareEvent)
            events.splice(idx, 1)

            // Update sweep_edge_a to end at the intersect.
            const a_orig_to_vert = sweep_edge_a.to_vert
            if (sweep_edge_a.to_vert == sweep_edge_a.edge.start_v) {
                sweep_edge_a.edge.start_v = intersect_v
            } else {
                sweep_edge_a.edge.end_v = intersect_v
            }
            sweep_edge_a.to_vert = intersect_v

            // Insert new sweep_edge_a end event.
            let new_event = new Event(sweep_edge_a.to_vert, sweep_edge_a.edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)
            events.splice(idx, 0, new_event)

            // Insert start/end event from the intersect to the end of the original sweep_edge_a.
            let new_edge = new Edge(intersect_v, a_orig_to_vert)
            new_event = new Event(intersect_v, new_edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)

            events.splice(idx, 0, new_event)
            new_event = new Event(a_orig_to_vert, new_edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)
            events.splice(idx, 0, new_event)
        }

        if (sweep_edge_b.to_vert.x != intersect.x || sweep_edge_b.to_vert.y != intersect.y) {
            dump(`adding ${sweep_edge_b.vert.idx} to ${intersect.x},${intersect.y}`)
            added_events = true

            // Remove sweep_edge_b's end event.
            scratch_event.vert = sweep_edge_b.to_vert
            scratch_event.type = EventType.End
            scratch_event.edge = sweep_edge_b.edge
            let idx = binarySearch(events, scratch_event, compareEvent)
            events.splice(idx, 1)
        
            // Update sweep_edge_b to end at the intersect.
            const b_orig_to_vert = sweep_edge_b.to_vert
            if (sweep_edge_b.to_vert == sweep_edge_b.edge.start_v) {
                sweep_edge_b.edge.start_v = intersect_v
            } else {
                sweep_edge_b.edge.end_v = intersect_v
            }
            sweep_edge_b.to_vert = intersect_v

            // Insert new sweep_edge_b end event.
            let new_event = new Event(sweep_edge_b.to_vert, sweep_edge_b.edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)
            events.splice(idx, 0, new_event)

            // Insert start/end event from the intersect to the end of the original sweep_edge_b.
            let new_edge = new Edge(intersect_v, b_orig_to_vert)
            dump(edgeToString(new_edge))
            new_event = new Event(intersect_v, new_edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)
            events.splice(idx, 0, new_event)
            new_event = new Event(b_orig_to_vert, new_edge)
            idx = binarySearchInsertIdxCmp(events, new_event, compareEvent)
            events.splice(idx, 0, new_event)
        }

        if (added_events) {
            verts.push(intersect_v)
        }
    }

    function addTriangle(v1, v2, v3) {
        dump('triangle', v1.out_idx, v2.out_idx, v3.out_idx)
        out_indexes.push(v1.out_idx, v2.out_idx, v3.out_idx)
    }

    function triangulateRightStep(left_edge, vert) {
        if (left_edge.cur_side == RightSide) {
            dump('right side')
            // Same side.
            if (left_edge.deferred_queue_size >= 2) {
                let cur = left_edge.deferred_queue
                let last = cur
                if (last.vert.out_idx == vert.out_idx) {
                    // Ignore this point since it is the same as the last.
                    return 
                }
                cur = cur.next
                let i = 0
                for (i; i < left_edge.deferred_queue_size-1; i += 1) {
                    const cxp = cross(v2(last.vert.x - cur.vert.x, last.vert.y - cur.vert.y), v2(vert.x - last.vert.x, vert.y - last.vert.y))
                    if (cxp > 0) {
                        // Bends inwards. Fill triangles until we aren't bending inward.
                        addTriangle(vert, last.vert, cur.vert)
                    } else {
                        break
                    }
                    last = cur
                    cur = cur.next
                }
                if (i > 0) {
                    const d_vert = new DeferredVertexNode(vert, last)
                    left_edge.deferred_queue = d_vert
                    left_edge.deferred_queue_size = left_edge.deferred_queue_size - i + 1
                } else {
                    left_edge.enqueueDeferred(vert)
                }
            } else {
                left_edge.enqueueDeferred(vert)
            }
        } else {
            dump('changed to right side')
            // Changed to right side.
            // Automatically create queue size - 1 triangles
            let cur = left_edge.deferred_queue
            let last = cur
            cur = cur.next
            for (let i = 0; i < left_edge.deferred_queue_size-1; i += 1) {
                addTriangle(vert, cur.vert, last.vert)
                last = cur
                cur = cur.next
            }
            left_edge.deferred_queue.next = null
            left_edge.deferred_queue_size = 1
            left_edge.enqueueDeferred(vert)
            left_edge.cur_side = RightSide
            left_edge.dumpQueue()
        }
    }

    function triangulateLeftStep(left_edge, vert) {
        if (left_edge.cur_side == LeftSide) {
            dump('same left side')
            left_edge.dumpQueue()

            // Same side.
            if (left_edge.deferred_queue_size >= 2) {
                let cur = left_edge.deferred_queue
                let last = cur
                cur = cur.next
                if (last.vert.out_idx == vert.out_idx) {
                    // Ignore this point since it is the same as the last.
                    return 
                }
                let i = 0
                for (i; i < left_edge.deferred_queue_size-1; i += 1) {
                    const cxp = cross(v2(last.vert.x - cur.vert.x, last.vert.y - cur.vert.y), v2(vert.x - last.vert.x, vert.y - last.vert.y))
                    if (cxp < 0) {
                        // Bends inwards. Fill triangles until we aren't bending inward.
                        addTriangle(vert, cur.vert, last.vert)
                    } else {
                        break
                    }
                    last = cur
                    cur = cur.next
                }
                if (i > 0) {
                    const d_vert = new DeferredVertexNode(vert, last)
                    left_edge.deferred_queue = d_vert
                    left_edge.deferred_queue_size = left_edge.deferred_queue_size - i + 1
                } else {
                    left_edge.enqueueDeferred(vert)
                }
            } else {
                left_edge.enqueueDeferred(vert)
            }
        } else {
            // Changed to left side.
            // Automatically create queue size - 1 triangles.
            let cur = left_edge.deferred_queue
            let last = cur
            cur = cur.next
            dump('changed to left side')
            for (let i = 0; i < left_edge.deferred_queue_size-1; i += 1) {
                addTriangle(vert, last.vert, cur.vert)
                last = cur
                cur = cur.next
            }
            left_edge.deferred_queue.next = null
            left_edge.deferred_queue_size = 1
            left_edge.enqueueDeferred(vert)
            left_edge.cur_side = LeftSide
            left_edge.dumpQueue()
        }
    }

    const debug = true

    let cur_x = Number.MIN_VALUE
    let cur_y = Number.MIN_VALUE
    let cur_out_vert_idx = -1

    for (let i = 0; i < events.length; i += 1) {
        const e = events[i]

        // If the point changed, allocate a new out vertex index.
        if (e.vert.x != cur_x || e.vert.y != cur_y) {
            out_verts.push({
                x: e.vert.x,
                y: e.vert.y,
            })
            cur_out_vert_idx += 1
            cur_x = e.vert.x
            cur_y = e.vert.y
        }

        // Set the out vertex index on the event.
        e.vert.out_idx = cur_out_vert_idx

        if (debug) {
            dump(`process event ${e.vert.idx} (${e.vert.x},${e.vert.y}) ${e.type == EventType.Start ? 'Start' : 'End'} ${edgeToString(e.edge)}`)
            const items = sweep_edges.map(e => {
                return `${e.edge.start_v.idx} -> ${e.edge.end_v.idx}`
            })
            dump(`sweep edges: ${items.join(', ')}`)
        }

        if (e.type == EventType.Start) {
            let insert_idx = binarySearchInsertIdx(sweep_edges, {}, findSweepEdgeInsert, e)
            dump('start init insert idx', insert_idx)

            // Check to remove a previous left edge and continue it's sub-polygon vertex queue.
            let new_edge = new SweepEdge(e)
            if (insert_idx % 2 == 1) {
                // Initially appears to be a right edge but if it connects to the previous left, the insert_idx becomes a left edge.
                let left_edge = sweep_edges[insert_idx - 1]
                if (left_edge.end_event_vert_uniq_idx == e.vert.out_idx) {
                    // Remove the previous ended edge.
                    sweep_edges.splice(insert_idx-1, 1)
                    insert_idx -= 1

                    // Previous left edge and this new edge forms a regular left angle.
                    // Check for bad up cusp.
                    if (left_edge.bad_up_cusp_uniq_idx != -1) {
                        // This monotone polygon (a) should already have run it's triangulate steps from the left edge's end event.
                        //   \  /
                        //  a \/ b
                        //    ^ Bad cusp.
                        // \_
                        // ^ End event from left edge happened before, currently processing start event for the new connected edge.

                        // A line is connected from this vertex to the bad cusp to ensure that polygon (a) is monotone and polygon (b) is monotone.
                        // Since polygon (a) already ran it's triangulate step, it's done from this side of the polygon.
                        // This start event will create a new sweep edge, so transfer the deferred queue from the bad cusp's right side. (it is now the queue for this new left edge).
                        new_edge.deferred_queue = left_edge.bad_up_cusp_right_edge.deferred_queue
                        new_edge.deferred_queue_size = left_edge.bad_up_cusp_right_edge.deferred_queue_size
                        new_edge.cur_side = left_edge.bad_up_cusp_right_edge.cur_side

                        // Also run triangulate on polygon (b) for the new vertex since the end event was already run for polygon (a).
                        triangulateLeftStep(new_edge, e.vert)

                        left_edge.bad_up_cusp_uniq_idx = -1
                    } else {
                        new_edge.deferred_queue = left_edge.deferred_queue
                        new_edge.deferred_queue_size = left_edge.deferred_queue_size
                        new_edge.cur_side = left_edge.cur_side
                    }
                } else if (left_edge.start_event_vert_uniq_idx == e.vert.out_idx) {
                    // Down cusp.
                    dump('DOWN CUSP')

                    if (insert_idx < sweep_edges.length-1) {
                        // Check for intersection with the edge to the right.
                        dump('check right intersect')

                        // TODO: Is there a preliminary check to avoid doing the math? One idea is to check the x_slopes but it would need to know
                        // if the compared edge is pointing down or up.
                        const right_edge = sweep_edges[insert_idx]
                        const intersect = computeTwoEdgeIntersect(e.edge, right_edge.edge)
                        if (intersect != null) {
                            handleIntersectForStartEvent(new_edge, right_edge, intersect, e.vert)
                        }
                    }
                    if (insert_idx > 1) {
                        dump('check left intersect')
                        const left_edge = sweep_edges[insert_idx - 1]
                        const left_left_edge = sweep_edges[insert_idx - 2]
                        const intersect = computeTwoEdgeIntersect(left_edge.edge, left_left_edge.edge)
                        dump(edgeToString(left_left_edge.edge))
                        if (intersect != null) {
                            handleIntersectForStartEvent(left_edge, left_left_edge, intersect, left_edge.vert)
                        }
                    }
                }
            } else {
                // Initially appears to be a left edge but if it connects to a previous right, the insert_idx becomes a right edge.
                if (insert_idx > 0) {
                    const left_right_edge = sweep_edges[insert_idx-1]
                    if (left_right_edge.end_event_vert_uniq_idx == e.vert.out_idx) {
                        // Remove previous ended edge.
                        sweep_edges.splice(insert_idx-1, 1)
                        insert_idx -= 1
                    } else if (left_right_edge.start_event_vert_uniq_idx == e.vert.out_idx) {
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

                        const left_edge = sweep_edges[insert_idx-2]
                        if (left_edge.lowest_right_vert == null) {
                            throw new Error('expected lowest right vert')
                        }

                        const right_poly_edge = left_edge.lowest_right_vert_edge

                        if (left_edge.bad_up_cusp_uniq_idx == left_right_edge.start_event_vert_uniq_idx) {
                            left_edge.bad_up_cusp_uniq_idx = -1
                        }

                        // Once connected, the right side monotone polygon will continue the existing vertex queue of the connected point.
                        new_edge.deferred_queue = right_poly_edge.deferred_queue
                        new_edge.deferred_queue_size = right_poly_edge.deferred_queue_size
                        new_edge.cur_side = right_poly_edge.cur_side

                        // If the right side polygon queue is the same as the left side polygon queue, the left queue is reset to the separation vertex and the bad cusp vertex.
                        if (left_edge.deferred_queue == new_edge.deferred_queue) {
                            left_edge.deferred_queue = null
                            left_edge.deferred_queue_size = 0
                            left_edge.cur_side = RightSide
                            left_edge.enqueueDeferred(left_edge.lowest_right_vert)
                            if (e.vert.out_idx != left_edge.lowest_right_vert.out_idx) {
                                left_edge.enqueueDeferred(e.vert)
                            }
                        }

                        // Right side needs to run left triangulate step since there is no end event for this vertex.
                        triangulateLeftStep(new_edge, e.vert)
                    }
                }
            }
            sweep_edges.splice(insert_idx, 0, new_edge)
            dump('start', insert_idx)

            if (insert_idx % 2 == 0) {
                // Even-odd rule.
                // Interior is to the right.

                // Initialize the deferred queue.
                if (new_edge.deferred_queue == null) {
                    new_edge.enqueueDeferred(e.vert)
                    new_edge.cur_side = LeftSide
                }

                // The lowest right vert is set initializes to itself.
                new_edge.lowest_right_vert = e.vert
                new_edge.lowest_right_vert_edge = new_edge
            } else {
                // Interior is to the left.
                // throw new Error('handle interior left')
            }
        } else {
            // End event.

            let active_idx = findSweepEdgeForEndEvent(sweep_edges, e)
            if (active_idx == -1) {
                throw new Error('expected active edge')
            }

            if (active_idx % 2 == 1) {
                // Interior is to the left.

                dump('interior to the left', active_idx)

                const left_edge = sweep_edges[active_idx-1]

                // Check if it has closed the polygon. (up cusp)
                if (e.vert.out_idx == left_edge.end_event_vert_uniq_idx) {
                    // Check for bad up cusp.
                    if (left_edge.bad_up_cusp_uniq_idx != -1) {
                        triangulateLeftStep(left_edge.bad_up_cusp_right_edge, e.vert)
                        left_edge.bad_up_cusp_uniq_idx = -1
                        if (left_edge.bad_up_cusp_right_edge.deferred_queue_size >= 3) {
                            dump(out_indexes)
                            left_edge.dumpQueue()
                            throw new Error('did not expect left over vertices')
                        }
                    }
                    if (left_edge.deferred_queue_size >= 3) {
                        dump(out_indexes)
                        left_edge.dumpQueue()
                        throw new Error('did not expect left over vertices')
                    }
                    // Remove the left edge and this edge.
                    sweep_edges.splice(active_idx-1, 2)
                } else {
                    // Regular right side vertex.
                    triangulateRightStep(left_edge, e.vert)

                    // Edge is only removed by the next connecting edge.
                    sweep_edges[active_idx].end_event_vert_uniq_idx = e.vert.out_idx
                }
            } else {
                // Interior is to the right.
                dump('interior to the right', active_idx)

                const left_edge = sweep_edges[active_idx]
                dump(active_idx)

                // Check if this forms a bad up cusp with the right edge to the left monotone polygon.
                let removed = false
                if (active_idx > 0) {
                    dump('check for bad up cusp')
                    const left_right_edge = sweep_edges[active_idx-1]
                    dump(edgeToString(left_right_edge.edge))
                    if (e.vert.out_idx == left_right_edge.end_event_vert_uniq_idx) {
                        const left_left_edge = sweep_edges[active_idx-2]
                        // Bad up cusp.
                        left_left_edge.bad_up_cusp_uniq_idx = e.vert.out_idx
                        left_left_edge.bad_up_cusp_right_edge = left_edge
                        left_left_edge.lowest_right_vert = e.vert
                        left_left_edge.lowest_right_vert_edge = left_edge

                        // Remove the left-right edge and this edge.
                        // But continue
                        sweep_edges.splice(active_idx-1, 2)
                        removed = true
                    }
                }

                left_edge.dumpQueue()
                triangulateLeftStep(left_edge, e.vert)
                left_edge.dumpQueue()

                if (!removed) {
                    // Don't remove the left edge of this sub-polygon yet.
                    // Record the end event's vert so the next start event that continues from this vert can persist the deferred vertices and remove this sweep edge.
                    // It can also be removed by a End right edge.
                    sweep_edges[active_idx].end_event_vert_uniq_idx = e.vert.out_idx
                }
            }
        }
    }

    // Avoids division by zero.
    // https://stackoverflow.com/questions/563198
    // For segments: p, p + r, q, q + s
    // To find t, u for p + tr, q + us
    // t = (q − p) X s / (r X s)
    // u = (q − p) X r / (r X s)
    function computeTwoEdgeIntersect(p, q) {
        const r_s = cross(p.vec, q.vec)
        if (r_s == 0) {
            return null
        }
        const qmp = { x: q.start_v.x - p.start_v.x, y: q.start_v.y - p.start_v.y }
        const qmp_r = cross(qmp, p.vec)
        const u = qmp_r / r_s
        if (u >= 0 && u <= 1) {
            // Must check intersect point is also on p.
            const qmp_s = cross(qmp, q.vec)
            const t = qmp_s / r_s
            if (t >= 0&& t <= 1) {
                return { x: q.start_v.x + q.vec.x * u, y: q.start_v.y + q.vec.y * u, t, u }
            } else {
                return null
            }
        } else {
            return null
        }
    }

    function edgeToString(edge) {
        return `${edge.start_v.idx} (${edge.start_v.x},${edge.start_v.y}) -> ${edge.end_v.idx} (${edge.end_v.x},${edge.end_v.y})`
    }

    // Visit all edges to create new polygons.
    const res = {
        verts: out_verts,
        indexes: out_indexes,
    }
    return res
}

const LeftSide = false
const RightSide = true

function v2(x, y) {
    return { x, y }
}

function v2i(x, y, idx) {
    return { x, y, idx }
}

function tri(v1, v2, v3) {
    return { v1, v2, v3 }
}

function cross(v1, v2) {
    return v1.x * v2.y - v1.y * v2.x
}

// For big polygons just check num triangles for now.
// TODO: Check that triangles fill the polygon.
function testBig(polygon, num_triangles) {
    const new_poly = []
    for (const point of polygon) {
        new_poly.push(v2(point[0], point[1]))
    }
    const triangles = triangulatePolygon(new_poly)
    t.eq(triangles.length, num_triangles)
}

function test(polygon, exp_verts, exp_indexes) {
    const verts = []
    for (const point of polygon) {
        verts.push(v2(point[0], point[1]))
    }
    const res = triangulatePolygon(verts)
    const norm_exp_verts = []
    for (const point of exp_verts) {
        norm_exp_verts.push(v2(point[0], point[1]))
    }
    t.eq(res.verts, norm_exp_verts)
    t.eq(res.indexes, exp_indexes)
}

// One triangle ccw.
test([
    [100, 0],
    [0, 0],
    [0, 100],
], [
    [0, 0],
    [100, 0],
    [0, 100],
], [ 2, 1, 0 ])

// One triangle cw.
test([
    [100, 0],
    [0, 100],
    [0, 0],
], [
    [0, 0],
    [100, 0],
    [0, 100],
], [ 2, 1, 0 ])

// Square.
test([
    [0, 0],
    [100, 0],
    [100, 100],
    [0, 100],
], [
    [0, 0],
    [100, 0],
    [0, 100],
    [100, 100],
], [
    2, 1, 0,
    3, 1, 2,
])

// Pentagon.
test([
    [100, 0],
    [200, 100],
    [200, 200],
    [0, 200],
    [0, 100],
], [
    [100, 0],
    [0, 100],
    [200, 100],
    [0, 200],
    [200, 200],
], [
    2, 0, 1,
    3, 2, 1,
    4, 2, 3,
])

// Hexagon.
test([
    [100, 0],
    [200, 100],
    [200, 200],
    [100, 300],
    [0, 200],
    [0, 100],
], [
    [100, 0],
    [0, 100],
    [200, 100],
    [0, 200],
    [200, 200],
    [100, 300],
], [
    2, 0, 1,
    3, 2, 1,
    4, 2, 3,
    5, 4, 3,
])

// Octagon.
test([
    [100, 0],
    [200, 0],
    [300, 100],
    [300, 200],
    [200, 300],
    [100, 300],
    [0, 200],
    [0, 100],
], [
    [100, 0],
    [200, 0],
    [0, 100],
    [300, 100],
    [0, 200],
    [300, 200],
    [100, 300],
    [200, 300],
], [
    2, 1, 0,
    3, 1, 2,
    4, 3, 2,
    5, 3, 4,
    6, 5, 4,
    7, 5, 6,
])

// Rhombus.
test([
    [100, 0],
    [200, 100],
    [100, 200],
    [0, 100],
], [
    [100, 0],
    [0, 100],
    [200, 100],
    [100, 200],
], [
    2, 0, 1,
    3, 2, 1,
])

// Square with concave top side.
// Tests monotone partition with bad up cusp and valid right angle.
test([
    [0, 0],
    [100, 100],
    [200, 0],
    [200, 200],
    [0, 200],
], [
    [0, 0],
    [200, 0],
    [100, 100],
    [0, 200],
    [200, 200],
], [
    3, 2, 0,
    4, 2, 3,
    4, 1, 2,
])

// Square with concave bottom side.
// Tests monotone partition with bad down cusp and valid right angle.
test([
    [0, 0],
    [200, 0],
    [200, 200],
    [100, 100],
    [0, 200],
], [
    [0, 0],
    [200, 0],
    [100, 100],
    [0, 200],
    [200, 200],
], [
    2, 1, 0,
    3, 2, 0,
    4, 1, 2,
])

// V shape.
// Tests monotone partition with bad up cusp and valid up cusp.
test([
    [0, 0],
    [100, 100],
    [200, 0],
    [100, 200],
], [
    [0, 0],
    [200, 0],
    [100, 100],
    [100, 200],
], [
    3, 2, 0,
    3, 1, 2,
])

// Upside down V shape.
// Tests monotone partition with bad down cusp and valid up cusp.
test([
    [100, 0],
    [200, 200],
    [100, 100],
    [0, 200],
], [
    [100, 0],
    [100, 100],
    [0, 200],
    [200, 200],
], [
    2, 1, 0,
    3, 0, 1,
])

// Clockwise spiral.
// Tests the sweep line with alternating interior/exterior sides.
test([
    [0, 0],
    [500, 0],
    [500, 500],
    [200, 500],
    [200, 200],
    [300, 200],
    [300, 400],
    [400, 400],
    [400, 100],
    [100, 100],
    [100, 500],
    [0, 500]
], [
    [0, 0],
    [500, 0],
    [100, 100],
    [400, 100],
    [200, 200],
    [300, 200],
    [300, 400],
    [400, 400],
    [0, 500],
    [100, 500],
    [200, 500],
    [500, 500],
], [
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
])

// CCW spiral.
// Tests the sweep line with alternating interior/exterior sides.
test([
    [0, 0],
    [500, 0],
    [500, 500],
    [400, 500],
    [400, 100],
    [100, 100],
    [100, 400],
    [200, 400],
    [200, 200],
    [300, 200],
    [300, 500],
    [0, 500],
], [
    [0, 0],
    [500, 0],
    [100, 100],
    [400, 100],
    [200, 200],
    [300, 200],
    [100, 400],
    [200, 400],
    [0, 500],
    [300, 500],
    [400, 500],
    [500, 500],
], [
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
])

// Overlapping point.
test([
    [0, 0],
    [100, 100],
    [200, 0],
    [200, 200],
    [100, 100],
    [0, 200],
], [
    [0, 0],
    [200, 0],
    [100, 100],
    [0, 200],
    [200, 200],
], [
    3, 2, 0,
    4, 1, 2,
])

// Self intersecting polygon.
// Different windings on split polygons.
test([
    [0, 200],
    [0, 100],
    [200, 100],
    [200, 0],
], [
    [200, 0],
    [0, 100],
    [100, 100],
    [200, 100],
    [0, 200],
], [
    3, 0, 2,
    4, 2, 1,
])

// Overlapping triangles.
// Test evenodd rule.
test([
    [0, 100],
    [200, 0],
    [200, 200],
    [0, 100],
    [250, 75],
    [250, 125],
    [0, 100],
], [
    [200, 0],
    [250, 75],
    [200, 80],
    [0, 100],
    [200, 120],
    [250, 125],
    [200, 200],
], [
    3, 2, 0,
    4, 1, 2,
    5, 1, 4,
    6, 4, 3,
])

// Begin mapbox test cases.

// bad-diagonals.json
test([
    [440,4152],[440,4208],[296,4192],[368,4192],[400,4200],[400,4176],[368,4192],[296,4192],[264,4200],[288,4160],[296,4192]
], [
    [440,4152],
    [288,4160],
    [400,4176],
    [296,4192],
    [368,4192],
    [264,4200],
    [400,4200],
    [440,4208],
], [
    3, 2, 0,
    4, 2, 3,
    5, 3, 1,
    6, 4, 3,
    6, 0, 2,
    7, 6, 3,
    7, 0, 6,
])

// dude.json

puts('PASSED ALL TESTS')