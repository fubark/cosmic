const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const stbtt = @import("stbtt");

const ttf = @import("ttf.zig");
const log = stdx.log.scoped(.ttf_test);

test "NotoColorEmoji.ttf" {
    const file = std.fs.cwd().openFile("./vendor/fonts/NotoColorEmoji.ttf", .{}) catch unreachable;
    defer file.close();

    const data = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
    defer t.alloc.free(data);

    var font = ttf.TTF_Font.init(t.alloc, data, 0) catch unreachable;
    defer font.deinit();

    // font.print_tables();
    try t.expect(font.hasColorBitmap());
    try t.eq(font.glyph_map_format, 12);
    try t.eq(font.num_glyphs, 3378);
    try t.eq(font.units_per_em, 2048);

    {
        const cp = std.unicode.utf8Decode("⚡") catch unreachable;
        const glyph_id = font.getGlyphId(cp) catch unreachable;
        try t.eq(glyph_id, 113);

        const h_metrics = font.getGlyphHMetrics(glyph_id.?);
        try t.eq(h_metrics.advance_width, 2550);
        try t.eq(h_metrics.left_side_bearing, 0);

        const bitmap = font.getGlyphColorBitmap(glyph_id.?) catch unreachable orelse unreachable;
        try t.eq(bitmap.width, 136);
        try t.eq(bitmap.height, 128);
        try t.eq(bitmap.advance_width, 101);
        try t.eq(bitmap.left_side_bearing, 0);
        try t.eq(bitmap.png_data.len, 1465);
    }

    {
        const glyph_id = font.getGlyphId(10052) catch unreachable;
        try t.eq(glyph_id, 158);
    }

    // var cp: u21 = 1;
    // while (cp < 9889) : (cp += 1) {
    //     if (font.get_glyph_id(cp) catch unreachable) |glyph_id| {
    //         const bitmap = font.get_glyph_color_bitmap(glyph_id) catch unreachable orelse continue;
    //         std.log.warn("{} - {}x{} {} {}", .{cp, bitmap.width, bitmap.height, bitmap.advance_width, bitmap.left_side_bearing});
    //     }
    // }
}

test "NunitoSans-Regular.ttf" {
    const file = std.fs.cwd().openFile("./vendor/fonts/NunitoSans-Regular.ttf", .{}) catch unreachable;
    defer file.close();

    const data = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
    defer t.alloc.free(data);

    var font = ttf.TTF_Font.init(t.alloc, data, 0) catch unreachable;
    defer font.deinit();

    // font.print_tables();
    try t.expect(!font.hasColorBitmap());
    try t.eq(font.glyph_map_format, 4);

    {
        const cp = std.unicode.utf8Decode("⚡") catch unreachable;
        try t.eq(font.getGlyphId(cp) catch unreachable, null);
    }
    {
        const cp = std.unicode.utf8Decode("a") catch unreachable;
        // const idx = font.get_glyph_id(cp) catch unreachable;
        try t.eq(font.getGlyphId(cp) catch unreachable, 238);
    }
}

test "Ubuntu-R.ttf" {
    const file = std.fs.cwd().openFile("./vendor/fonts/Ubuntu-R.ttf", .{}) catch unreachable;
    defer file.close();

    const data = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
    defer t.alloc.free(data);

    var font = ttf.TTF_Font.init(t.alloc, data, 0) catch unreachable;
    defer font.deinit();
    // font.print_tables();
    try t.expect(!font.hasColorBitmap());
    try t.eq(font.glyph_map_format, 4);
    try t.eq(font.num_glyphs, 1264);
}

test "stbtt glyph sizing" {
    // Use this test to understand how stbtt sizes glyphs.

    const file = std.fs.cwd().openFile("./vendor/fonts/NunitoSans-Regular.ttf", .{}) catch unreachable;
    defer file.close();

    const data = file.readToEndAlloc(t.alloc, 1024 * 1024 * 10) catch unreachable;
    defer t.alloc.free(data);

    var font = try ttf.TTF_Font.init(t.alloc, data, 0);
    defer font.deinit();
    var stbtt_font: stbtt.fontinfo = undefined;
    stbtt.InitFont(&stbtt_font, data, 0) catch @panic("failed to load font");

    var x0: c_int = 0;
    var y0: c_int = 0;
    var x1: c_int = 0;
    var y1: c_int = 0;

    var cp = std.unicode.utf8Decode("h") catch unreachable;
    var glyph_id = (try font.getGlyphId(cp)).?;
    stbtt.stbtt_GetGlyphBitmapBox(&stbtt_font, glyph_id, 1, 1, &x0, &y0, &x1, &y1);
    log.warn("h {},{} {},{}", .{ x0, y0, x1, y1 });

    cp = std.unicode.utf8Decode("Č") catch unreachable;
    glyph_id = (try font.getGlyphId(cp)).?;
    stbtt.stbtt_GetGlyphBitmapBox(&stbtt_font, glyph_id, 1, 1, &x0, &y0, &x1, &y1);
    log.warn("Č {},{} {},{}", .{ x0, y0, x1, y1 });

    const scale = font.getScaleToUserFontSize(32);
    cp = std.unicode.utf8Decode("|") catch unreachable;
    glyph_id = (try font.getGlyphId(cp)).?;
    stbtt.stbtt_GetGlyphBitmapBox(&stbtt_font, glyph_id, scale, scale, &x0, &y0, &x1, &y1);
    log.warn("{},{} {},{}", .{ x0, y0, x1, y1 });
}
