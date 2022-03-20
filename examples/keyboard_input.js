const Key = cs.input.Key

const w = cs.window.create(1200, 720, 'Demo')

w.onKeyDown(e => {
    dump('key down', e)
})

w.onKeyUp(e => {
    dump('key up', e)
})