const color = cs.graphics.Color

const main1 = cs.window.create('Main 1', 800, 600)
const child = main1.createChild('Child', 400, 300)
const main2 = cs.window.create('Main 2', 300, 400)

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