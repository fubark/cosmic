const Color = cs.graphics.Color;

printLine('Hello World!')

const w = cs.window.create('Demo', 1200, 720)
w.onUpdate(g => {
    g.setFontSize(52)
    g.setFillColor(Color.blue);
    g.text(400, 300, 'Hello World!')
})