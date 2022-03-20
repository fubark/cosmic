const Button = cs.input.MouseButton

const w = cs.window.create(1200, 720, 'Demo')

w.onMouseDown(e => {
    if (e.button == Button.left) {
        puts('pressed left', e.clicks)
    } else if (e.button == Button.right) {
        puts('pressed right', e.clicks)
    }
    dump('mouse down', e)
})

w.onMouseUp(e => {
    dump('mouse up', e)
})

w.onMouseMove(e => {
    dump('mouse move', e)
})