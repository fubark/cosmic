// Draw paths and export their values.
// This is used to view and generate test cases for polygon triangulation and polyline conversion.

const C = cs.graphics.Color
const K = cs.input.Key

let view_x = 0
let view_y = 0
let scale = 1
const points = []
let selected_idx = 0

const args = getCliArgs()
for (let i = 0; i < args.length; i += 1) {
    const arg = args[i]
    if (arg == '-polygon') {
        const text = args[i + 1]
        const json_points = JSON.parse(text)
        let min_x = Number.MAX_VALUE
        let max_x = Number.MIN_VALUE
        let min_y = Number.MAX_VALUE
        let max_y = Number.MIN_VALUE
        for (const p of json_points) {
            const v = { x: p[0], y: p[1] }
            if (v.x < min_x) {
                min_x = v.x
            }
            if (v.x > max_x) {
                max_x = v.x
            }
            if (v.y < min_y) {
                min_y = v.y
            }
            if (v.y > max_y) {
                max_y = v.y
            }
            points.push(v)
        }
        view_x = min_x
        view_y = min_y
        const width = max_x - min_x
        const height = max_y - min_y
        if (width > height) {
            scale = 800 / width
        } else {
            scale = 600 / height
        }
    }
}

const w = cs.window.create(800, 600, 'Path Drawer')

const g = w.getGraphics()

// g.polygon([
//     440,4152,
//     440,4208,
//     296,4192,
//     368,4192,
//     400,4200,
//     400,4176,
//     368,4192,
//     296,4192,
//     264,4200,
//     288,4160,
//     296,4192,
// ])

// g.polygon([
//     0,100,
//     200,0,
//     200,200,
//     0,100,
//     250,100,
//     250,110
// ])

w.onUpdate(g => {
    g.fillColor({ r: 30, g: 30, b: 30, a: 255 })
    g.rect(0, 0, 800, 600)

    g.translate(-view_x, -view_y)
    g.scale(scale, scale)

    g.strokeColor(C.green)
    if (points.length > 0) {
        g.lineWidth(10)
        g.point(points[0].x, points[0].y)
        let last = points[points.length-1]
        for (let i = 0; i < points.length; i += 1) {
            const p = points[i]
            g.lineWidth(5)
            g.line(last.x, last.y, p.x, p.y)
            last = p
            g.lineWidth(10)
            g.point(p.x, p.y)
        }
        if (selected_idx >= 0 && selected_idx < points.length) {
            g.strokeColor(C.red)
            g.lineWidth(10)
            g.point(points[selected_idx].x, points[selected_idx].y)
        }
    }
})

w.onMouseUp(e => {
    if (e.button == cs.input.MouseButton.left) {
        points.push({ x: Math.round(e.x), y: Math.round(e.y) })
    } else {
        points.length = 0
    }
})

w.onKeyUp(e => {
    if (e.key == K.enter) {
        let str = ''
        for (const p of points) {
            str += `${p.x}, ${p.y}\n`
        }
        setClipboardText(str)
        puts('Copied to clipboard.')
    } else if (e.key == K.u) {
        points.pop()
    } else if (e.key == K.arrowRight) {
        selected_idx += 1
        if (selected_idx >= points.length) {
            selected_idx = 0
        }
    } else if (e.key == K.arrowLeft) {
        selected_idx -= 1
        if (selected_idx < 0) {
            selected_idx = points.length-1
        }
    }
})