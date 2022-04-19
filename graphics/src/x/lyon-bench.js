// Compares the performance of triangulating and rendering the tiger head with cosmic, lyon, and tess2.
// cosmic must be built with "zig build cosmic -Drelease-safe -Dlyon -Dtess2"
// Note for tess2, you'll need a ./lib/libtess2 link point to its git repo.
// Since lyon is linked as a prebuilt release lib, it's only fair to compare with a release version of cosmic.

const w = cs.window.create(1200, 720, 'Demo')
const g = w.getGraphics()

const root = getMainScriptDir()
const tiger_head_svg = cs.files.readText(`${root}/../../../examples/assets/tiger-head.svg`)
const tiger_head_draw_list = g.compileSvgContent(tiger_head_svg)

const reps = 100

let start, ms

start = timerNow()
for (var i = 0; i < reps; i += 1) {
    g.executeDrawList(tiger_head_draw_list)
}
ms = (timerNow() - start) / 1000000n
dump(`tiger head (cosmic): ${ms}ms`)

start = timerNow()
for (var i = 0; i < reps; i += 1) {
    g.executeDrawListLyon(tiger_head_draw_list)
}
ms = (timerNow() - start) / 1000000n
dump(`tiger head (lyon): ${ms}ms`)

start = timerNow()
for (var i = 0; i < reps; i += 1) {
    g.executeDrawListTess2(tiger_head_draw_list)
}
ms = (timerNow() - start) / 1000000n
dump(`tiger head (tess2): ${ms}ms`)

exit(0)