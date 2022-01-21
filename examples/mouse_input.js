const Button = cs.input.MouseButton

const w = cs.window.create('Demo', 1200, 720)

w.onMouseButton(e => {
    if (e.button == Button.left && e.pressed) {
        printLine('pressed left')
    } else if (e.button == Button.right && e.pressed) {
        printLine('pressed right')
    }
    printLine(e.button, e.pressed, e.x, e.y)
})

w.onMouseMove(e => {
    printLine(`mouse move ${e.x}, ${e.y}`)
})