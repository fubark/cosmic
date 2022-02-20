const w = cs.window.create('Demo', 1200, 720)

const Color = cs.graphics.Color

const root = getMainScriptDir()

const g = w.getGraphics()
const my_font = g.addTtfFont(`${root}/assets/NunitoSans-Regular.ttf`)
// Note: The bundled NotoColorEmoji only has 2 glyphs for the purpose of the demo.
// If you want the full emoji set download it at: https://github.com/googlefonts/noto-emoji/releases
const emoji_font = g.addTtfFont(`${root}/assets/NotoColorEmoji.ttf`)
g.addFallbackFont(emoji_font)

const zig_logo_svg = cs.files.readText(`${root}/assets/zig-logo-dark.svg`)
const tiger_head_svg = cs.files.readText(`${root}/assets/tiger-head.svg`)
const tiger_head_draw_list = g.compileSvgContent(tiger_head_svg)
const game_char_image = g.newImage(`${root}/assets/game-char.png`)

w.onUpdate(g => {
    g.fillColor(Color.black)
    g.rect(0, 0, 1200, 720)

    // Shapes.
    g.fillColor(Color.red)
    g.rect(60, 100, 300, 200)

    g.lineWidth(8)
    g.strokeColor(Color.red.darker())
    g.rectOutline(60, 100, 300, 200)

    g.translate(0, -120)
    g.rotateDeg(20)

    g.fillColor(Color.blue.withAlpha(150))
    g.rect(250, 200, 300, 200)
    g.resetTransform()

    // Text.
    g.font(my_font, 26)
    g.fillColor(Color.orange)
    g.text(140, 10, 'The quick brown fox 🦊 jumps over the lazy dog. 🐶')
    g.rotateDeg(45)
    g.font(my_font, 48)
    g.fillColor(Color.skyBlue)
    g.text(140, 10, 'The quick brown fox 🦊 jumps over the lazy dog. 🐶')
    g.resetTransform()

    // More shapes.
    g.fillColor(Color.green)
    g.circle(550, 150, 100)
    g.fillColor(Color.green.darker())
    g.circleSectorDeg(550, 150, 100, 0, 120)

    g.strokeColor(Color.yellow)
    g.circleOutline(700, 200, 70)
    g.strokeColor(Color.yellow.darker())
    g.circleArcDeg(700, 200, 70, 0, 120)

    g.fillColor(Color.purple)
    g.ellipse(850, 70, 80, 40)
    g.fillColor(Color.purple.lighter())
    g.ellipseSectorDeg(850, 70, 80, 40, 0, 240)
    g.strokeColor(Color.brown)
    g.ellipse(850, 70, 80, 40)
    g.strokeColor(Color.brown.lighter())
    g.ellipseArcDeg(850, 70, 80, 40, 0, 120)

    g.fillColor(Color.red)
    g.triangle(850, 70, 800, 170, 900, 170)
    g.fillColor(Color.brown)
    g.convexPolygon([
        1000, 70,
        960, 120,
        950, 170,
        1000, 200,
        1050, 170,
        1040, 120,
    ])
    const polygon = [
        990, 140,
        1040, 65,
        1040, 115,
        1090, 40,
    ];
    g.fillColor(Color.darkGray)
    g.polygon(polygon)
    g.strokeColor(Color.yellow)
    g.lineWidth(3)
    g.polygonOutline(polygon)

    g.fillColor(Color.blue.darker())
    g.roundRect(70, 430, 200, 120, 30)
    g.lineWidth(7)
    g.strokeColor(Color.blue)
    g.roundRectOutline(70, 430, 200, 120, 30)

    g.strokeColor(Color.orange)
    g.lineWidth(3)
    g.point(220, 220)
    g.line(240, 220, 300, 320)

    // Svg.
    g.translate(0, 570)
    g.fillColor(Color.white)
    g.rect(0, 0, 400, 140)
    g.svgContent(zig_logo_svg)
    g.resetTransform()

    // Bigger Svg.
    g.translate(840, 360)
    g.executeDrawList(tiger_head_draw_list)

    // Curves.
    g.resetTransform()
    g.lineWidth(3)
    g.strokeColor(Color.yellow)
    g.quadraticBezierCurve(0, 0, 200, 0, 200, 200)
    g.cubicBezierCurve(0, 0, 200, 0, 0, 200, 200, 200)

    // Images.
    g.imageSized(450, 290, game_char_image.width/3, game_char_image.height/3, game_char_image)

    g.fillColor(Color.blue.lighter())
    g.font(my_font, 26)
    g.text(1100, 10, `fps ${w.getFps()}`)
})