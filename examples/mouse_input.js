const Button = cs.input.MouseButton

const w = cs.window.create('Demo', 1200, 720)

w.onMouseDown(e => {
    if (e.button == Button.left) {
        printLine('pressed left', e.clicks)
    } else if (e.button == Button.right) {
        printLine('pressed right', e.clicks)
    }
    printLine(e.button, e.x, e.y)
})

w.onMouseUp(e => {
    printLine('mouse up', e.button, e.x, e.y, e.clicks)
})

w.onMouseMove(e => {
    printLine(`mouse move ${e.x}, ${e.y}`)
})