const C = cs.graphics.Color

class QuadBez {
    constructor(x0, y0, cx, cy, x1, y1) {
        this.x0 = x0
        this.y0 = y0
        this.cx = cx
        this.cy = cy
        this.x1 = x1
        this.y1 = y1 
    }
    mapToBasic() {
        const ddx = 2 * this.cx - this.x0 - this.x1;
        const ddy = 2 * this.cy - this.y0 - this.y1;
        const u0 = (this.cx - this.x0) * ddx + (this.cy - this.y0) * ddy;
        const u1 = (this.x1 - this.cx) * ddx + (this.y1 - this.cy) * ddy;
        const cross = (this.x1 - this.x0) * ddy - (this.y1 - this.y0) * ddx;
        const x0 = u0 / cross;
        const x1 = u1 / cross;
        // There's probably a more elegant formulation of this...
        const scale = Math.abs(cross) / (Math.hypot(ddx, ddy) * Math.abs(x1 - x0));
        return {x0: x0, x1: x1, scale: scale, cross: cross};
    }
}

class CubicBez {
    constructor(x0, y0, cx0, cy0, cx1, cy1, x1, y1) {
        this.x0 = x0
        this.y0 = y0
        this.cx0 = cx0
        this.cy0 = cy0
        this.cx1 = cx1
        this.cy1 = cy1
        this.x1 = x1
        this.y1 = y1
    }

    // quadratic bezier with matching endpoints and minimum max vector error
    midpointQBez() {
        const p1 = this.weightsum(-0.25, 0.75, 0.75, -0.25);
        return new QuadBez(this.x0, this.y0, p1.x, p1.y, this.x1, this.y1);
    }

    weightsum(c0, c1, c2, c3) {
        const x = c0 * this.x0 + c1 * this.cx0 + c2 * this.cx1 + c3 * this.x1;
        const y = c0 * this.y0 + c1 * this.cy0 + c2 * this.cy1 + c3 * this.y1;
        return new Point(x, y);
    }

    deriv(t) {
        const mt = 1 - t;
        const c0 = -3 * mt * mt;
        const c3 = 3 * t * t;
        const c1 = -6 * t * mt - c0;
        const c2 = 6 * t * mt - c3;
        return this.weightsum(c0, c1, c2, c3);
    }

    subsegment(t0, t1) {
        let c = new Float64Array(8);
        const p0 = evalCBez(this, t0);
        const p3 = evalCBez(this, t1);
        c[0] = p0.x;
        c[1] = p0.y;
        const scale = (t1 - t0) / 3;
        const d1 = this.deriv(t0);
        c[2] = p0.x + scale * d1.x;
        c[3] = p0.y + scale * d1.y;
        const d2 = this.deriv(t1);
        c[4] = p3.x - scale * d2.x;
        c[5] = p3.y - scale * d2.y;
        c[6] = p3.x;
        c[7] = p3.y;
        return new CubicBez(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
    }
}

class Point {
    constructor(x, y) {
        this.x = x
        this.y = y
    }
    hypot2() {
        return this.x * this.x + this.y * this.y;
    }
}

function partitionCBez(c_bez, tol) {
    const tol1 = 0.1 * tol; // error for subdivision into quads
    const tol2 = tol - tol1; // error for subdivision of quads into lines
    const sqrt_tol2 = Math.sqrt(tol2);
    const err2 = c_bez.weightsum(1, -3, 3, -1).hypot2();
    const n_quads = Math.ceil(Math.pow(err2 / (432 * tol1 * tol1), 1./6));
    let quads = [];
    let sum = 0;
    for (let i = 0; i < n_quads; i++) {
        const t0 = i / n_quads;
        const t1 = (i + 1) / n_quads;
        const quad = c_bez.subsegment(t0, t1).midpointQBez();
        const params = quad.mapToBasic();
        const a0 = approx_myint(params.x0);
        const a1 = approx_myint(params.x1);
        const scale = Math.sqrt(params.scale);
        let val = Math.abs(a1 - a0) * scale;
        if (Math.sign(params.x0) != Math.sign(params.x1)) {
            // min x value in basic parabola to make sure we don't skip cusp
            const xmin = sqrt_tol2 / scale;
            const cusp_val = sqrt_tol2 * Math.abs(a1 - a0) / approx_myint(xmin);
            //console.log(i, val, cusp_val);
            // I *think* it will always be larger, but just in case...
            val = Math.max(val, cusp_val);
        }
        quads.push({
            quad: quad,
            a0: a0,
            a1: a1,
            val: val
        })
        sum += val;
    }
    const count = 0.5 * sum / sqrt_tol2;
    const n = Math.ceil(count);
    let result = [new Point(c_bez.x0, c_bez.y0)];
    let val = 0; // sum of vals from [0..i]
    let i = 0;
    for (let j = 1; j < n; j++) {
        const target = sum * j / n;
        while (val + quads[i].val < target) {
            val += quads[i].val;
            i++;
        }
        const a0 = quads[i].a0;
        const a1 = quads[i].a1;
        // Note: we can cut down on recomputing these
        const u0 = approx_inv_myint(a0);
        const u1 = approx_inv_myint(a1);
        const a = a0 + (a1 - a0) * (target - val) / quads[i].val;
        const u = approx_inv_myint(a);
        const t = (u - u0) / (u1 - u0);
        result.push(evalQBez(quads[i].quad, t));
    }
    result.push(new Point(c_bez.x1, c_bez.y1));
    return result;
}

function partitionQBez(q_bez, tol) {
    const params = q_bez.mapToBasic();
    const a0 = approx_myint(params.x0);
    const a1 = approx_myint(params.x1);
    const count =  0.5 * Math.abs(a1 - a0) * Math.sqrt(params.scale / tol);
    const n = Math.ceil(count);
    const u0 = approx_inv_myint(a0);
    const u1 = approx_inv_myint(a1);
    let result = [0];
    for (let i = 1; i < n; i++) {
        const u = approx_inv_myint(a0 + ((a1 - a0) * i) / n);
        const t = (u - u0) / (u1 - u0);
        result.push(t);
    }
    result.push(1);
    return result;  
}

// Compute an approximation to int (1 + 4x^2) ^ -0.25 dx
// This isn't especially good but will do.
function approx_myint(x) {
    const d = 0.67;
    return x / (1 - d + Math.pow(Math.pow(d, 4) + 0.25 * x * x, 0.25));
}

// Approximate the inverse of the function above.
// This is better.
function approx_inv_myint(x) {
    const b = 0.39;
    return x * (1 - b + Math.sqrt(b * b + 0.25 * x * x));
}

function evalQBez(q_bez, t) {
    const mt = 1 - t;
    const x = q_bez.x0 * mt * mt + 2 * q_bez.cx * t * mt + q_bez.x1 * t * t;
    const y = q_bez.y0 * mt * mt + 2 * q_bez.cy * t * mt + q_bez.y1 * t * t;
    return { x, y }
}

let pt1 = { x: 0, y: 0 }
let pt2 = { x: 0, y: 0 }
let cpt = { x: 0, y: 0 }
// For cubic bez.
let cpt2 = { x: 0, y: 0 }

let is_quad_bez = true
let pts = []
initBez()

function evalCBez(bez, t) {
    const mt = 1 - t;
    const c0 = mt * mt * mt;
    const c1 = 3 * mt * mt * t;
    const c2 = 3 * mt * t * t;
    const c3 = t * t * t;
    return bez.weightsum(c0, c1, c2, c3);
}

function initBez() {
    if (is_quad_bez) {
        pt1 = { x: 200, y: 450 }
        pt2 = { x: 600, y: 50 }
        cpt = { x: 400, y: 450 }
        pts = computeQBezPts(pt1, cpt, pt2)
    } else {
        pt1 = { x: 200, y: 450 }
        cpt = { x: 400, y: 450 }
        cpt2 = { x: 500, y: 100 }
        pt2 = { x: 600, y: 50 }
        pts = computeCBezPts(pt1, cpt, cpt2, pt2)
    }
}

function computeQBezPts(p1, c, p2) {
    const bez = new QuadBez(p1.x, p1.y, c.x, c.y, p2.x, p2.y);
    const t_values = partitionQBez(bez, 0.5)
    return t_values.map(t => {
        return evalQBez(bez, t);
    })
}

function computeCBezPts(p1, c1, c2, p2) {
    const bez = new CubicBez(p1.x, p1.y, c1.x, c1.y, c2.x, c2.y, p2.x, p2.y);
    return partitionCBez(bez, 0.5)
}

const w = cs.window.create(800, 600, 'Curve')
w.onUpdate(g => {
    g.fillColor(C.darkGray.darker().darker())
    g.rect(0, 0, 800, 600)

    g.lineWidth(5)
    g.strokeColor(C.yellow)
    let last = pts[0]
    for (let i = 1; i < pts.length; i += 1) {
        const pt = pts[i]
        g.line(last.x, last.y, pt.x, pt.y)
        last = pt
    }

    g.strokeColor(C.blue)
    g.lineWidth(10)
    for (const v of pts) {
        g.point(v.x, v.y)
    }

    g.strokeColor(C.red)
    g.point(pt1.x, pt1.y)
    g.point(cpt.x, cpt.y)
    g.point(pt2.x, pt2.y)
    if (!is_quad_bez) {
        g.point(cpt2.x, cpt2.y)
    }

    // g.strokeColor(C.blue)
    // g.lineWidth(20)
    // g.quadraticBezierCurve(pt1.x, pt1.y, cpt.x, cpt.y, pt2.x, pt2.y)
})

let drag_vert = null

w.onMouseDown(e => {
    const radius = 30
    if (e.button == cs.input.MouseButton.left) {
        if (dist(e, pt1) < radius) {
            drag_vert = pt1
        } else if (dist(e, pt2) < radius) {
            drag_vert = pt2
        } else if (dist(e, cpt) < radius) {
            drag_vert = cpt
        }
        if (!is_quad_bez) {
            if (dist(e, cpt2) < radius) {
                drag_vert = cpt2
            }
        }
    }
})

w.onMouseUp(e => {
    if (e.button == cs.input.MouseButton.left) {
        if (is_quad_bez) {
            pts = computeQBezPts(pt1, cpt, pt2)
        } else {
            pts = computeCBezPts(pt1, cpt, cpt2, pt2)
        }
        drag_vert = null
    }
})

w.onMouseMove(e => {
    if (drag_vert != null) {
        drag_vert.x = e.x
        drag_vert.y = e.y
        if (is_quad_bez) {
            pts = computeQBezPts(pt1, cpt, pt2)
        } else {
            pts = computeCBezPts(pt1, cpt, cpt2, pt2)
        }
    }
})

w.onKeyUp(e => {
    if (e.key == cs.input.Key.space) {
        is_quad_bez = !is_quad_bez
        initBez()
        drag_vert = null
    }
})

function dist(v1, v2) {
    const dx = v1.x - v2.x
    const dy = v1.y - v2.y
    return Math.sqrt(dx * dx + dy * dy)
}