const Color = cs.graphics.Color;

puts('Hello World!')

const w = cs.window.create('Demo', 1200, 720)
w.onUpdate(g => {
    g.fontSize(52)
    g.fillColor(Color.blue);
    g.text(400, 300, 'Hello World!')
})