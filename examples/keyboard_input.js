const Key = cs.input.Key

const w = cs.window.create(1200, 720, 'Demo')

w.onKeyDown(e => {
    puts('key down', e.key, e.keyChar, e.isRepeat, e.shiftDown)
})

w.onKeyUp(e => {
    puts('key up', e.key, e.keyChar, e.shiftDown)
})