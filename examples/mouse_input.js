const Button = cs.input.MouseButton

const w = cs.window.create('Demo', 1200, 720)

w.onMouseDown(e => {
    if (e.button == Button.left) {
        puts('pressed left', e.clicks)
    } else if (e.button == Button.right) {
        puts('pressed right', e.clicks)
    }
    puts(e.button, e.x, e.y)
})

w.onMouseUp(e => {
    puts('mouse up', e.button, e.x, e.y, e.clicks)
})

w.onMouseMove(e => {
    puts(`mouse move ${e.x}, ${e.y}`)
})