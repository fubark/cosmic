const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;
const builtin = @import("builtin");
const graphics = @import("graphics");
const Window = graphics.Window;
const Graphics = graphics.Graphics;
const FontId = graphics.font.FontId;
const Image = graphics.Image;
const Color = graphics.Color;
const svg = graphics.svg;
const sdl = @import("sdl");
const WasmJsBuffer = stdx.wasm.WasmJsBuffer;

const log = stdx.log.scoped(.demo);

const IsWasm = builtin.target.cpu.arch == .wasm32;

var win: Window = undefined;
var g: Graphics = undefined;

var zig_logo_svg: []const u8 = undefined;
var tiger_head_draw_list: graphics.DrawCommandList = undefined;
var game_char_image: Image = undefined;
var last_frame_time_ns: u64 = undefined;
var font_id: FontId = undefined;


/// @buildCopy "../../deps/assets/zig-logo-dark.svg" "zig-logo-dark.svg"
/// @buildCopy "../../deps/assets/tiger-head.svg" "tiger-head.svg"
/// @buildCopy "../../deps/fonts/NunitoSans-Regular.ttf" "NunitoSans-Regular.ttf"
/// @buildCopy "../../deps/fonts/NotoColorEmoji.ttf" "NotoColorEmoji.ttf"
/// @buildCopy "../../deps/assets/game-char.png" "game-char.png"
pub fn main() !void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    win = try Window.init(alloc, .{
        .title = "Demo",
        .width = 1200,
        .height = 720,
        .resizable = false,
    });
    defer win.deinit();

    g.init(alloc, win.getWidth(), win.getHeight());
    defer g.deinit();

    try initAssets(alloc);
    defer deinitAssets(alloc);

    const timer = std.time.Timer.start() catch unreachable;
    last_frame_time_ns = timer.read();

    var loop = true;
    while (loop) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_QUIT => {
                    loop = false;
                    break;
                },
                else => {},
            }
        }

        const diff_ms = @intToFloat(f32, timer.read() - last_frame_time_ns) / 1e6;
        last_frame_time_ns = timer.read();

        update(diff_ms);
        std.time.sleep(15);
    }
}

// Main loop shared by desktop and web.
fn update(delta_ms: f32) void {
    g.beginFrame();

    // Shapes.
    g.setFillColor(Color.Red);
    g.fillRect(60, 100, 300, 200);

    g.setLineWidth(8);
    g.setStrokeColor(Color.Red.darker());
    g.drawRect(60, 100, 300, 200);

    g.translate(0, -120);
    g.rotateDeg(20);

    g.setFillColor(Color.Blue.withAlpha(150));
    g.fillRect(250, 200, 300, 200);
    g.resetTransform();

    // Text.
    g.setFont(font_id, 26);
    g.setFillColor(Color.Orange);
    g.fillText(140, 10, "The quick brown fox 🦊 jumps over the lazy dog. 🐶");
    g.rotateDeg(45);
    g.setFont(font_id, 48);
    g.setFillColor(Color.SkyBlue);
    g.fillText(140, 10, "The quick brown fox 🦊 jumps over the lazy dog. 🐶");
    g.resetTransform();

    // More shapes.
    g.setFillColor(Color.Green);
    g.fillCircle(550, 150, 100);
    g.setFillColor(Color.Green.darker());
    g.fillCircleSectorDeg(550, 150, 100, 0, 120);

    g.setStrokeColor(Color.Yellow);
    g.drawCircle(700, 200, 70);
    g.setStrokeColor(Color.Yellow.darker());
    g.drawCircleArcDeg(700, 200, 70, 0, 120);

    g.setFillColor(Color.Purple);
    g.fillEllipse(850, 70, 80, 40);
    g.setFillColor(Color.Purple.lighter());
    g.fillEllipseSectorDeg(850, 70, 80, 40, 0, 240);
    g.setStrokeColor(Color.Brown);
    g.drawEllipse(850, 70, 80, 40);
    g.setStrokeColor(Color.Brown.lighter());
    g.drawEllipseArcDeg(850, 70, 80, 40, 0, 120);

    g.setFillColor(Color.Red);
    g.fillTriangle(850, 70, 800, 170, 900, 170);
    g.setFillColor(Color.Brown);
    g.fillConvexPolygon(&.{
        vec2(1000, 70),
        vec2(960, 120),
        vec2(950, 170),
        vec2(1000, 200),
        vec2(1050, 170),
        vec2(1040, 120),
    });
    const polygon = [_]Vec2{
        vec2(990, 140),
        vec2(1040, 65),
        vec2(1040, 115),
        vec2(1090, 40),
    };
    g.setFillColor(Color.DarkGray);
    g.fillPolygon(&polygon);
    g.setStrokeColor(Color.Yellow);
    g.setLineWidth(3);
    g.drawPolygon(&polygon);

    g.setFillColor(Color.Blue.darker());
    g.fillRoundRect(70, 430, 200, 120, 30);
    g.setLineWidth(7);
    g.setStrokeColor(Color.Blue);
    g.drawRoundRect(70, 430, 200, 120, 30);

    g.setStrokeColor(Color.Orange);
    g.setLineWidth(3);
    g.drawPoint(220, 220);
    g.drawLine(240, 220, 300, 320);

    // Svg.
    g.translate(0, 570);
    g.setFillColor(Color.White);
    g.fillRect(0, 0, 400, 140);
    g.drawSvgContent(zig_logo_svg) catch unreachable;
    g.resetTransform();

    // Bigger Svg.
    if (IsWasm) {
        // It's much faster to use an svg image on web canvas.
        g.drawImageSized(670, 220, 500, 500, tiger_head_image.id);
    } else {
        g.translate(840, 360);
        g.executeDrawList(tiger_head_draw_list);
    }

    // g.drawSvgPathStr(0, 0,
    //     \\M394,106c-10.2,7.3-24,12-37.7,12c-29,0-51.1-20.8-51.1-48.3c0-27.3,22.5-48.1,52-48.1
    //     \\c14.3,0,29.2,5.5,38.9,14l-13,15c-7.1-6.3-16.8-10-25.9-10c-17,0-30.2,12.9-30.2,29.5c0,16.8,13.3,29.6,30.3,29.6
    //     \\c5.7,0,12.8-2.3,19-5.5L394,106z
    // ) catch unreachable;

    // Curves.
    g.resetTransform();
    g.setLineWidth(3);
    g.setStrokeColor(Color.Yellow);
    g.drawQuadraticBezierCurve(0, 0, 200, 0, 200, 200);
    g.drawCubicBezierCurve(0, 0, 200, 0, 0, 200, 200, 200);

    // Images.
    g.drawImageSized(450, 290, @intToFloat(f32, game_char_image.width) / 3, @intToFloat(f32, game_char_image.height) / 3, game_char_image.id);

    g.setFillColor(Color.Blue.lighter());
    const fps = 1000 / delta_ms;
    g.setFont(font_id, 26);
    g.fillTextFmt(1100, 10, "fps {d:.1}", .{fps});

    g.endFrame();
    win.swapBuffers();
}

fn addFontFromExeDir(alloc: std.mem.Allocator, path: []const u8) !FontId {
    const abs = try stdx.fs.pathFromExeDir(alloc, path);
    defer alloc.free(abs);
    return try g.addTTF_FontFromPath(abs);
}

fn initAssets(alloc: std.mem.Allocator) !void {
    const MaxFileSize = 20e6;

    font_id = try addFontFromExeDir(alloc, "NunitoSans-Regular.ttf");
    const emoji_font = try addFontFromExeDir(alloc, "NotoColorEmoji.ttf");
    g.addFallbackFont(emoji_font);

    const abs = try stdx.fs.pathFromExeDir(alloc, "game-char.png");
    defer alloc.free(abs);
    game_char_image = try g.createImageFromPath(abs);

    zig_logo_svg = try stdx.fs.readFileFromExeDir(alloc, "zig-logo-dark.svg", MaxFileSize);

    const tiger_head_svg = try stdx.fs.readFileFromExeDir(alloc, "tiger-head.svg", MaxFileSize);

    var parser = svg.SvgParser.init(alloc);
    defer parser.deinit();

    tiger_head_draw_list = try parser.parseAlloc(alloc, tiger_head_svg);
    alloc.free(tiger_head_svg);
}

fn deinitAssets(alloc: std.mem.Allocator) void {
    tiger_head_draw_list.deinit();
    alloc.free(zig_logo_svg);
}

var js_buf: *WasmJsBuffer = undefined;
var load_assets_p: stdx.wasm.Promise(void) = undefined;
var tiger_head_image: Image = undefined;

export fn wasmInit() *const u8 {
    if (!IsWasm) {
        unreachable;
    }
    const alloc = stdx.heap.getDefaultAllocator();
    stdx.wasm.init(alloc);
    js_buf = stdx.wasm.getJsBuffer();

    win = Window.init(alloc, .{
        .title = "Demo",
        .width = 1200,
        .height = 720,
    }) catch unreachable;

    g.init(alloc, win.getWidth(), win.getHeight());

    const MaxFileSize = 20e6;
    const p1 = stdx.fs.readFilePromise(alloc, "./zig-logo-dark.svg", MaxFileSize).thenCopyTo(&zig_logo_svg).autoFree();
    const p2 = g.createImageFromPathPromise("./game-char.png").thenCopyTo(&game_char_image).autoFree();
    const p3 = g.createImageFromPathPromise("./tiger-head.svg").thenCopyTo(&tiger_head_image).autoFree();
    load_assets_p = stdx.wasm.createAndPromise(&.{ p1.id, p2.id, p3.id });

    font_id = g.addTTF_FontFromPathForName("./NunitoSans-Regular.ttf", "Nunito Sans") catch unreachable;

    return js_buf.writeResult();
}

export fn wasmUpdate(cur_time_ms: f32) *const u8 {
    if (!IsWasm) {
        unreachable;
    }

    // Wait for assets to load in the browser before getting to main loop.
    if (!load_assets_p.isResolved()) {
        return js_buf.writeResult();
    }

    const now_ns = @floatToInt(u64, cur_time_ms * 1e6);
    const diff_ms = @intToFloat(f32, now_ns - last_frame_time_ns) / 1e6;
    last_frame_time_ns = now_ns;

    update(diff_ms);
    return js_buf.writeResult();
}
