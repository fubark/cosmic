const std = @import("std");
const stdx = @import("stdx");
const Vec2 = stdx.math.Vec2;
const vec2 = Vec2.init;
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const graphics = @import("graphics");
const Window = graphics.Window;
const Graphics = graphics.Graphics;
const FontId = graphics.font.FontId;
const Image = graphics.Image;
const Color = graphics.Color;
const platform = @import("platform");

const log = stdx.log.scoped(.demo);

var dispatcher: platform.EventDispatcher = undefined;
var win: Window = undefined;
var g: *Graphics = undefined;
var quit = false;

var zig_logo_svg: []const u8 = undefined;
var tiger_head_image: graphics.ImageId = undefined;
var game_char_image: Image = undefined;
var last_frame_time_ns: u64 = undefined;
var font_id: FontId = undefined;

pub fn main() !void {
    const alloc = stdx.heap.getDefaultAllocator();
    defer stdx.heap.deinitDefaultAllocator();

    dispatcher = platform.EventDispatcher.init(alloc);
    defer dispatcher.deinit();

    win = try Window.init(alloc, .{
        .title = "Demo",
        .width = 1200,
        .height = 720,
        .resizable = true,
        .high_dpi = true,
        .anti_alias = true,
    });
    defer win.deinit();
    win.addDefaultHandlers(&dispatcher);

    const S = struct {
        fn onQuit(_: ?*anyopaque) void {
            quit = true;
        }
    };
    dispatcher.addOnQuit(null, S.onQuit);

    g = win.getGraphics();

    try initAssets(alloc);
    defer deinitAssets(alloc);

    var timer = std.time.Timer.start() catch unreachable;
    last_frame_time_ns = timer.read();
    while (!quit) {
        const diff_ms = @intToFloat(f32, timer.read() - last_frame_time_ns) / 1e6;
        last_frame_time_ns = timer.read();

        dispatcher.processEvents();
        update(diff_ms);
        std.time.sleep(15);
    }
}

// Main loop shared by desktop and web.
fn update(delta_ms: f32) void {
    win.beginFrame();

    g.setFillColor(Color.Black);
    g.fillRect(0, 0, @intToFloat(f32, win.getWidth()), @intToFloat(f32, win.getHeight()));

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

    // Gradients.
    g.setFillGradient(400, 500, Color.Red, 700, 700, Color.Blue);
    g.fillRect(400, 500, 300, 200);

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

    // Rasterize big svg.
    g.drawImage(650, 150, tiger_head_image);

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

    win.endFrame();
    win.swapBuffers();
}

fn initAssets(alloc: std.mem.Allocator) !void {
    const MaxFileSize = 20e6;

    font_id = try g.addTTF_FontFromPath(srcPath() ++ "/../../examples/assets/NunitoSans-Regular.ttf");
    const emoji_font = try g.addTTF_FontFromPath(srcPath() ++ "/../../examples/assets/NotoColorEmoji.ttf");
    g.addFallbackFont(emoji_font);

    const game_char_data = try std.fs.cwd().readFileAlloc(alloc, srcPath() ++ "/../../examples/assets/game-char.png", MaxFileSize);
    defer alloc.free(game_char_data);
    game_char_image = try g.createImage(game_char_data);

    zig_logo_svg = try std.fs.cwd().readFileAlloc(alloc, srcPath() ++ "/../../examples/assets/zig-logo-dark.svg", MaxFileSize);

    const tiger_head_svg = try std.fs.cwd().readFileAlloc(alloc, srcPath() ++ "/../../examples/assets/tiger-head.svg", MaxFileSize);
    defer alloc.free(tiger_head_svg);

    var parser = graphics.svg.SvgParser.init(alloc);
    defer parser.deinit();

    rasterizeTigerHead(tiger_head_svg);
}

fn deinitAssets(alloc: std.mem.Allocator) void {
    alloc.free(zig_logo_svg);
}

fn rasterizeTigerHead(tiger_head_svg: []const u8) void {
    // Renders the svg to an image and then the image is drawn.
    // The graphics context also supports drawing the svg directly to the main frame buffer, although it isn't recommended for large svgs like the tiger head.
    tiger_head_image = g.createImageFromBitmap(600, 600, null, true);
    g.bindImageBuffer(tiger_head_image);
    g.setFillColor(Color.Transparent);
    g.fillRect(0, 0, 600, 600);
    g.translate(200, 200);
    g.drawSvgContent(tiger_head_svg) catch unreachable;
    g.flushDraw();
}

// Below is the bootstrap code for wasm.

var galloc: std.mem.Allocator = undefined;
var zig_logo_id: u32 = undefined;
var game_char_id: u32 = undefined;
var nunito_font_id: u32 = undefined;
var noto_emoji_id: u32 = undefined;
var tiger_head_id: u32 = undefined;
var loaded_assets: u32 = 0;

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() *const u8 {
        const alloc = stdx.heap.getDefaultAllocator();
        galloc = alloc;
        stdx.wasm.init(alloc);

        dispatcher = platform.EventDispatcher.init(alloc);
        win = Window.init(alloc, .{
            .title = "Demo",
            .width = 1200,
            .height = 720,
            .anti_alias = true,
        }) catch unreachable;
        win.addDefaultHandlers(&dispatcher);
        g = win.getGraphics();

        const S = struct {
            fn onFetchResult(_: ?*anyopaque, e: platform.FetchResultEvent) void {
                if (e.fetch_id == zig_logo_id) {
                    zig_logo_svg = galloc.dupe(u8, e.buf) catch unreachable;
                    loaded_assets += 1;
                } else if (e.fetch_id == game_char_id) {
                    game_char_image = g.createImage(e.buf) catch unreachable;
                    loaded_assets += 1;
                } else if (e.fetch_id == nunito_font_id) {
                    font_id = g.addTTF_Font(e.buf);
                    loaded_assets += 1;
                } else if (e.fetch_id == tiger_head_id) {
                    rasterizeTigerHead(e.buf);
                    loaded_assets += 1;
                } else if (e.fetch_id == noto_emoji_id) {
                    const emoji_font = g.addTTF_Font(e.buf);
                    g.addFallbackFont(emoji_font);
                    loaded_assets += 1;
                }
            }
        };
        dispatcher.addOnFetchResult(null, S.onFetchResult);

        // TODO: Should be able to create async resources. In the case of fonts, it would use the default font. In the case of images it would be blank.
        zig_logo_id = stdx.fs.readFileWasm("./zig-logo-dark.svg");
        game_char_id = stdx.fs.readFileWasm("./game-char.png");
        nunito_font_id = stdx.fs.readFileWasm("./NunitoSans-Regular.ttf");
        noto_emoji_id = stdx.fs.readFileWasm("./NotoColorEmoji.ttf");
        tiger_head_id = stdx.fs.readFileWasm("./tiger-head.svg");

        return stdx.wasm.js_buffer.writeResult();
    }

    export fn wasmUpdate(cur_time_ms: f32, input_len: u32) *const u8 {
        stdx.wasm.js_buffer.input_buf.items.len = input_len;
        dispatcher.processEvents();

        // Wait for assets to load in the browser before getting to main loop.
        if (loaded_assets < 5) {
            return stdx.wasm.js_buffer.writeResult();
        }

        const now_ns = @floatToInt(u64, cur_time_ms * 1e6);
        const diff_ms = @intToFloat(f32, now_ns - last_frame_time_ns) / 1e6;
        last_frame_time_ns = now_ns;

        update(diff_ms);
        return stdx.wasm.js_buffer.writeResult();
    }
} else struct {};

fn srcPath() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}
