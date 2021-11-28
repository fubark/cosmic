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

const log = stdx.log.scoped(.demo);

const IsWasm = builtin.target.cpu.arch == .wasm32;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var win: Window = undefined;
var g: Graphics = undefined;

var zig_logo_svg: []const u8 = undefined;
var tiger_head_draw_list: graphics.DrawCommandList = undefined;
var game_char_image: Image = undefined;

var font_id: FontId = undefined;

/// @buildCopy "../../vendor/assets/zig-logo-dark.svg" "zig-logo-dark.svg"
/// @buildCopy "../../vendor/assets/tiger-head.svg" "tiger-head.svg"
/// @buildCopy "../../vendor/fonts/NunitoSans-Regular.ttf" "NunitoSans-Regular.ttf"
/// @buildCopy "../../vendor/fonts/NotoColorEmoji.ttf" "NotoColorEmoji.ttf"
/// @buildCopy "../../vendor/assets/game-char.png" "game-char.png"

pub fn main() !void {

    const alloc = if (IsWasm) std.heap.page_allocator else b: {
        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        break :b &gpa.allocator;
    };
    defer {
        if (!IsWasm) {
            _ = gpa.deinit();
        }
    }

    win = try Window.init(alloc, .{
        .title = "Demo",
        .width = 1200,
        .height = 720,
        .resizable = false,
    });
    defer win.deinit();

    g.init(alloc, win.inner.width, win.inner.height);
    defer g.deinit();

    const MaxFileSize = 1024 * 1000 * 20;

    const default_font = try stdx.fs.readFileFromExeDir(alloc, "NunitoSans-Regular.ttf", MaxFileSize);
    defer alloc.free(default_font);

    const default_emoji = try stdx.fs.readFileFromExeDir(alloc, "NotoColorEmoji.ttf", MaxFileSize);
    defer alloc.free(default_emoji);

    font_id = g.addTTF_Font(default_font);
    const emoji_font = g.addTTF_Font(default_emoji);
    g.addFallbackFont(emoji_font);

    const image_data = try stdx.fs.readFileFromExeDir(alloc, "game-char.png", MaxFileSize);
    game_char_image = try g.createImageFromData(image_data);
    alloc.free(image_data);

    zig_logo_svg = try stdx.fs.readFileFromExeDir(alloc, "zig-logo-dark.svg", MaxFileSize);
    defer alloc.free(zig_logo_svg);

    const tiger_head_svg = try stdx.fs.readFileFromExeDir(alloc, "tiger-head.svg", MaxFileSize);

    var parser = svg.SvgParser.init(alloc);
    defer parser.deinit();
    tiger_head_draw_list = try parser.parseAlloc(alloc, tiger_head_svg);
    defer tiger_head_draw_list.deinit();

    alloc.free(tiger_head_svg);

    while (update()) {
        std.time.sleep(30);
    }
}

fn update() bool {
    if (!IsWasm) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                sdl.SDL_QUIT => {
                    return false;
                },
                else => {},
            }
        }
    }

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
    g.fillCircleArcDeg(550, 150, 100, 0, 120);

    g.setStrokeColor(Color.Yellow);
    g.drawCircle(700, 200, 70);
    g.setStrokeColor(Color.Yellow.darker());
    g.drawCircleArcDeg(700, 200, 70, 0, 120);

    g.setFillColor(Color.Purple);
    g.fillEllipse(850, 70, 80, 40);
    g.setFillColor(Color.Purple.lighter());
    g.fillEllipseArcDeg(850, 70, 80, 40, 0, 240);
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

    // Bigger Svg.
    g.resetTransform();
    g.translate(840, 360);
    g.executeDrawList(tiger_head_draw_list);

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
    g.drawImageSized(450, 290, @intToFloat(f32, game_char_image.width)/3,@intToFloat(f32, game_char_image.height)/3, game_char_image.id);

    g.endFrame();
    win.swapBuffers();

    return true;
}