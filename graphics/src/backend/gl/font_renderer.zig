const stdx = @import("stdx");
const std = @import("std");
const stbtt = @import("stbtt");
const stbi = @import("stbi");
const ft = @import("freetype");

const graphics = @import("../../graphics.zig");
const gl = graphics.gl;
const Graphics = gl.Graphics;
const Font = graphics.font.Font;
const RenderFont = graphics.font.RenderFont;
const OpenTypeFont = graphics.font.OpenTypeFont;
const Glyph = graphics.font.Glyph;
const log = std.log.scoped(.font_renderer);

pub fn getOrLoadMissingGlyph(g: *Graphics, font: *Font, render_font: *RenderFont) *Glyph {
    if (render_font.missing_glyph) |*glyph| {
        return glyph;
    } else {
        const ot_font = font.getOtFontBySize(render_font.render_font_size);
        const glyph = generateGlyph(g, font, ot_font, render_font, 0);
        render_font.missing_glyph = glyph;
        return &render_font.missing_glyph.?;
    }
}

pub fn getOrLoadGlyph(g: *Graphics, font: *Font, render_font: *RenderFont, cp: u21) ?*Glyph {
    // var buf: [4]u8 = undefined;
    if (render_font.glyphs.getEntry(cp)) |entry| {
        // _ = std.unicode.utf8Encode(cp, &buf) catch unreachable;
        // log.debug("{} cache hit: {s}", .{render_font.render_font_size, buf});
        return entry.value_ptr;
    } else {
        // _ = std.unicode.utf8Encode(cp, &buf) catch unreachable;
        // log.debug("{} cache miss: {s}", .{render_font.render_font_size, buf});

        const ot_font = font.getOtFontBySize(render_font.render_font_size);

        // Attempt to generate glyph.
        if (ot_font.getGlyphId(cp) catch unreachable) |glyph_id| {
            const glyph = generateGlyph(g, font, ot_font, render_font, glyph_id);
            const entry = render_font.glyphs.getOrPutValue(cp, glyph) catch unreachable;
            return entry.value_ptr;
        } else return null;
    }
}

/// Rasterizes glyph from ot font and into a FontAtlas.
/// Then set flag to indicate the FontAtlas was updated.
/// New glyph metadata is stored into Font's glyph cache and returned.
/// Even though the ot_font can be retrieved from font, it's provided by the caller to avoid an extra lookup for bitmap fonts.
fn generateGlyph(g: *Graphics, font: *Font, ot_font: OpenTypeFont, render_font: *const RenderFont, glyph_id: u16) Glyph {
    if (ot_font.hasEmbeddedBitmap()) {
        // Bitmap fonts.
        return generateEmbeddedBitmapGlyph(g, ot_font, render_font, glyph_id);
    }
    if (ot_font.hasColorBitmap()) {
        return generateColorBitmapGlyph(g, ot_font, render_font, glyph_id);
    }
    if (!ot_font.hasGlyphOutlines()) {
        // Font should have outline data or color bitmap.
        unreachable;
    }
    return generateOutlineGlyph(g, font, render_font, glyph_id);
}

// 1 pixel padding in glyphs so edge filtering doesn't mix with it's own glyph or neighboring glyphs.
// Must remember to consider padding when blitting using text shaping in start_render_text() and render_next_codepoint(), also measure_text()
const h_padding = Glyph.Padding * 2;
const v_padding = Glyph.Padding * 2;

fn generateOutlineGlyph(g: *Graphics, font: *Font, render_font: *const RenderFont, glyph_id: u16) Glyph {
    const scale = render_font.scale_from_ttf;
    const fc = &g.font_cache;

    // negative y indicates upwards dist from baseline.
    // positive y indicates downwards dist from baseline.
    // x0, y0 represents top left.
    // x1, y1 represents bot right.
    var x0: c_int = 0;
    var y0: c_int = 0;
    var x1: c_int = 0;
    var y1: c_int = 0;

    var glyph_x: u32 = 0;
    var glyph_y: u32 = 0;
    var glyph_width: u32 = 0;
    var glyph_height: u32 = 0;

    switch (graphics.FontRendererBackend) {
        .Freetype => {
            var err = ft.FT_Set_Pixel_Sizes(font.impl, 0, render_font.render_font_size);
            if (err != 0) {
                stdx.panicFmt("freetype error {}", .{err});
            }
            err = ft.FT_Load_Glyph(font.impl, glyph_id, ft.FT_LOAD_DEFAULT);
            if (err != 0) {
                stdx.panicFmt("freetype error {}", .{err});
            }
            err = ft.FT_Render_Glyph(font.impl.glyph, ft.FT_RENDER_MODE_NORMAL);
            if (err != 0) {
                stdx.panicFmt("freetype error {}", .{err});
            }
            const src_width = font.impl.glyph[0].bitmap.width;
            const src_height = font.impl.glyph[0].bitmap.rows;

            x0 = font.impl.glyph[0].bitmap_left;
            y0 = -font.impl.glyph[0].bitmap_top;

            // log.debug("glyph {any} {} {}", .{font.impl.glyph[0].bitmap, x0, y0});

            if (src_width > 0) {
                glyph_width = src_width + h_padding;
                glyph_height = src_height + v_padding;

                const pos = fc.main_atlas.packer.allocRect(glyph_width, glyph_height);
                glyph_x = pos.x;
                glyph_y = pos.y;

                // Debug: Dump specific glyph.
                // if (glyph_id == 76) {
                //     _ = stbi.stbi_write_bmp("test.bmp", @intCast(c_int, src_width), @intCast(c_int, src_height), 1, font.impl.glyph[0].bitmap.buffer);
                //     log.debug("{} {} {}", .{src_width, src_height, x0});
                // }

                fc.main_atlas.copySubImageFrom1Channel(glyph_x + Glyph.Padding, glyph_y + Glyph.Padding, src_width, src_height, font.impl.glyph[0].bitmap.buffer[0..src_width*src_height]);
                fc.main_atlas.markDirtyBuffer();
            } else {
                // Some characters will be blank like the space char.
                glyph_width = 0;
                glyph_height = 0;
                glyph_x = 0;
                glyph_y = 0;
            }
        },
        .Stbtt => {
            stbtt.stbtt_GetGlyphBitmapBox(&font.impl, glyph_id, scale, scale, &x0, &y0, &x1, &y1);
            // Draw glyph into bitmap buffer.
            const src_width = @intCast(u32, x1 - x0);
            const src_height = @intCast(u32, y1 - y0);
            glyph_width = src_width + h_padding;
            glyph_height = src_height + v_padding;

            const pos = fc.main_atlas.packer.allocRect(glyph_width, glyph_height);
            glyph_x = pos.x;
            glyph_y = pos.y;

            g.raster_glyph_buffer.resize(src_width * src_height) catch @panic("error");
            // Don't include extra padding when blitting to bitmap with stbtt.
            stbtt.stbtt_MakeGlyphBitmap(&font.impl, g.raster_glyph_buffer.items.ptr, @intCast(c_int, src_width), @intCast(c_int, src_height), @intCast(c_int, src_width), scale, scale, glyph_id);
            fc.main_atlas.copySubImageFrom1Channel(glyph_x + Glyph.Padding, glyph_y + Glyph.Padding, src_width, src_height, g.raster_glyph_buffer.items);
            fc.main_atlas.markDirtyBuffer();
        },
    }

    // log.debug("box {} {} {} {}", .{x0, y0, x1, y1});

    const h_metrics = font.ot_font.getGlyphHMetrics(glyph_id);
    // log.info("adv: {}, lsb: {}", .{h_metrics.advance_width, h_metrics.left_side_bearing});

    var glyph = Glyph.init(glyph_id, fc.main_atlas.image);
    glyph.is_color_bitmap = false;
    // Include padding in offsets.
    // glyph.x_offset = scale * @intToFloat(f32, h_metrics.left_side_bearing) - Glyph.Padding;
    glyph.x_offset = @intToFloat(f32, x0) - Glyph.Padding;
    // log.warn("lsb: {} x: {}", .{scale * @intToFloat(f32, h_metrics.left_side_bearing), x0});
    glyph.y_offset = @round(render_font.ascent) - @intToFloat(f32, -y0) - Glyph.Padding;
    glyph.x = glyph_x;
    glyph.y = glyph_y;
    glyph.width = glyph_width;
    glyph.height = glyph_height;
    glyph.render_font_size = @intToFloat(f32, render_font.render_font_size);
    glyph.dst_width = @intToFloat(f32, glyph_width);
    glyph.dst_height = @intToFloat(f32, glyph_height);
    glyph.advance_width = scale * @intToFloat(f32, h_metrics.advance_width);
    glyph.u0 = @intToFloat(f32, glyph_x) / @intToFloat(f32, fc.main_atlas.width);
    glyph.v0 = @intToFloat(f32, glyph_y) / @intToFloat(f32, fc.main_atlas.height);
    glyph.u1 = @intToFloat(f32, glyph_x + glyph_width) / @intToFloat(f32, fc.main_atlas.width);
    glyph.v1 = @intToFloat(f32, glyph_y + glyph_height) / @intToFloat(f32, fc.main_atlas.height);
    return glyph;
}

fn generateColorBitmapGlyph(g: *Graphics, ot_font: OpenTypeFont, render_font: *const RenderFont, glyph_id: u16) Glyph {
    // Copy over png glyph data instead of going through the normal stbtt rasterizer.
    if (ot_font.getGlyphColorBitmap(glyph_id) catch unreachable) |data| {
        // const scale = render_font.scale_from_ttf;
        const fc = &g.font_cache;

        // Decode png.
        var src_width: c_int = undefined;
        var src_height: c_int = undefined;
        var channels: c_int = undefined;
        const bitmap = stbi.stbi_load_from_memory(&data.png_data[0], @intCast(c_int, data.png_data.len), &src_width, &src_height, &channels, 0);
        defer stbi.stbi_image_free(bitmap);
        // log.debug("color glyph {}x{} {}x{}", .{data.width, data.height, src_width, src_height});

        const glyph_width = @intCast(u32, src_width) + h_padding;
        const glyph_height = @intCast(u32, src_height) + v_padding;

        const pos = fc.main_atlas.packer.allocRect(glyph_width, glyph_height);
        const glyph_x = pos.x;
        const glyph_y = pos.y;

        // Copy into atlas bitmap.
        const bitmap_len = @intCast(usize, src_width * src_height * channels);
        fc.main_atlas.copySubImageFrom(
            glyph_x + Glyph.Padding,
            glyph_y + Glyph.Padding,
            @intCast(usize, src_width),
            @intCast(usize, src_height),
            bitmap[0..bitmap_len],
        );
        fc.main_atlas.markDirtyBuffer();

        // const h_metrics = font.ttf_font.getGlyphHMetrics(glyph_id);
        // log.info("adv: {}, lsb: {}", .{h_metrics.advance_width, h_metrics.left_side_bearing});

        var glyph = Glyph.init(glyph_id, fc.main_atlas.image);
        glyph.is_color_bitmap = true;

        const scale_from_xpx = @intToFloat(f32, render_font.render_font_size) / @intToFloat(f32, data.x_px_per_em);
        const scale_from_ypx = @intToFloat(f32, render_font.render_font_size) / @intToFloat(f32, data.y_px_per_em);

        // Include padding in offsets.
        glyph.x_offset = scale_from_xpx * @intToFloat(f32, data.left_side_bearing - Glyph.Padding);
        glyph.y_offset = render_font.ascent - scale_from_ypx * @intToFloat(f32, data.bearing_y - Glyph.Padding);
        // log.debug("{} {} {}", .{glyph.y_offset, data.bearing_y, data.height });
        // glyph.y_offset = 0;
        glyph.x = glyph_x;
        glyph.y = glyph_y;
        glyph.width = glyph_width;
        glyph.height = glyph_height;
        glyph.render_font_size = @intToFloat(f32, render_font.render_font_size);

        // The quad dimensions for color glyphs is scaled to how much pixels should be drawn for the bm font size.
        // This should be smaller than the underlying bitmap glyph but that's ok since the uvs will make sure we extract the right pixels.
        glyph.dst_width = scale_from_xpx * @intToFloat(f32, glyph_width);
        glyph.dst_height = scale_from_ypx * @intToFloat(f32, glyph_height);
        // log.debug("{} {}", .{glyph.dst_width, glyph.dst_height});

        // In NotoColorEmoji.ttf it seems like the advance_width from the color bitmap data is more accurate than what
        // we get from ttf_font.get_glyph_hmetrics.
        // glyph.advance_width = scale_from_xpx * @intToFloat(f32, h_metrics.advance_width);
        // log.debug("{} {} {}", .{scale * @intToFloat(f32, h_metrics.advance_width), data.advance_width, data.width});
        glyph.advance_width = scale_from_xpx * @intToFloat(f32, data.advance_width);
        glyph.u0 = @intToFloat(f32, glyph_x) / @intToFloat(f32, fc.main_atlas.width);
        glyph.v0 = @intToFloat(f32, glyph_y) / @intToFloat(f32, fc.main_atlas.height);
        glyph.u1 = @intToFloat(f32, glyph_x + glyph_width) / @intToFloat(f32, fc.main_atlas.width);
        glyph.v1 = @intToFloat(f32, glyph_y + glyph_height) / @intToFloat(f32, fc.main_atlas.height);
        return glyph;
    } else {
        stdx.panicFmt("expected color bitmap for glyph: {}", .{glyph_id});
    }
}

fn generateEmbeddedBitmapGlyph(g: *Graphics, ot_font: OpenTypeFont, render_font: *const RenderFont, glyph_id: u16) Glyph {
    const fc = &g.font_cache;

    if (ot_font.getGlyphBitmap(g.alloc, glyph_id) catch @panic("error")) |ot_glyph| {
        defer ot_glyph.deinit(g.alloc);
        const dst_width: u32 = ot_glyph.width + h_padding;
        const dst_height: u32 = ot_glyph.height + v_padding;

        const dst_pos = fc.bitmap_atlas.packer.allocRect(dst_width, dst_height);

        fc.bitmap_atlas.copySubImageFrom1Channel(dst_pos.x + Glyph.Padding, dst_pos.y + Glyph.Padding, ot_glyph.width, ot_glyph.height, ot_glyph.data);
        fc.bitmap_atlas.markDirtyBuffer();

        var glyph = Glyph.init(glyph_id, fc.bitmap_atlas.image);
        glyph.is_color_bitmap = false;

        glyph.x_offset = @intToFloat(f32, ot_glyph.bearing_x) - Glyph.Padding;
        glyph.y_offset = render_font.ascent + @intToFloat(f32, -ot_glyph.bearing_y) - Glyph.Padding;
        glyph.x = dst_pos.x;
        glyph.y = dst_pos.y;
        glyph.width = dst_width;
        glyph.height = dst_height;
        glyph.render_font_size = @intToFloat(f32, render_font.render_font_size);
        glyph.dst_width = @intToFloat(f32, dst_width);
        glyph.dst_height = @intToFloat(f32, dst_height);
        glyph.advance_width = @intToFloat(f32, ot_glyph.advance);
        glyph.u0 = @intToFloat(f32, dst_pos.x) / @intToFloat(f32, fc.bitmap_atlas.width);
        glyph.v0 = @intToFloat(f32, dst_pos.y) / @intToFloat(f32, fc.bitmap_atlas.height);
        glyph.u1 = @intToFloat(f32, dst_pos.x + dst_width) / @intToFloat(f32, fc.bitmap_atlas.width);
        glyph.v1 = @intToFloat(f32, dst_pos.y + dst_height) / @intToFloat(f32, fc.bitmap_atlas.height);
        return glyph;
    } else {
        stdx.panicFmt("expected embedded bitmap for glyph: {}", .{glyph_id});
    }
}