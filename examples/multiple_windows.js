const color = cs.graphics.Color

const main1 = cs.window.create(800, 600, 'Main 1')
const child = main1.createChild(400, 300, 'Child')
const main2 = cs.window.create(300, 400, 'Main 2')
main2.position(0, 0)

main1.onUpdate(g => {
    g.fillColor(color.red)
    g.rect(0, 0, 200, 200)
})

child.onUpdate(g => {
    g.fillColor(color.blue)
    g.rect(0, 0, 200, 200)
})

main2.onUpdate(g => {
    g.fillColor(color.green)
    g.rect(0, 0, 200, 200)
})