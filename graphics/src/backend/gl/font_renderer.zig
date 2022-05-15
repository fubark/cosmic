const stdx = @import("stdx");
const std = @import("std");
const stbtt = @import("stbtt");
const stbi = @import("stbi");

const graphics = @import("../../graphics.zig");
const gl = graphics.gl;
const Graphics = gl.Graphics;
const Font = graphics.font.Font;
const RenderFont = graphics.font.RenderFont;
const Glyph = graphics.font.Glyph;
const log = std.log.scoped(.font_renderer);

// LINKS:
// https://github.com/mooman219/fontdue (could be an alternative default to stbtt)

pub fn getOrLoadMissingGlyph(g: *Graphics, font: *Font, render_font: *RenderFont) *Glyph {
    if (render_font.missing_glyph) |*glyph| {
        return glyph;
    } else {
        const glyph = generateGlyph(g, font, render_font, 0);
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

        // Attempt to generate glyph.
        if (font.ttf_font.getGlyphId(cp) catch unreachable) |glyph_id| {
            const glyph = generateGlyph(g, font, render_font, glyph_id);
            const entry = render_font.glyphs.getOrPutValue(cp, glyph) catch unreachable;
            return entry.value_ptr;
        } else return null;
    }
}

// Loads data from ttf file into relevant FontAtlas.
// Then we set flag to indicate the FontAtlas was updated.
// New glyph metadata is stored into Font's glyph cache and returned.
fn generateGlyph(g: *Graphics, font: *const Font, render_font: *const RenderFont, glyph_id: u16) Glyph {
    if (font.ttf_font.hasColorBitmap()) {
        return generateColorBitmapGlyph(g, font, render_font, glyph_id);
    }
    if (!font.ttf_font.hasGlyphOutlines()) {
        // Font should have outline data or color bitmap.
        unreachable;
    }
    return generateOutlineGlyph(g, font, render_font, glyph_id);
}

// 1 pixel padding in glyphs so edge filtering doesn't mix with it's own glyph or neighboring glyphs.
// Must remember to consider padding when blitting using text shaping in start_render_text() and render_next_codepoint(), also measure_text()
const h_padding = Glyph.Padding * 2;
const v_padding = Glyph.Padding * 2;

fn generateOutlineGlyph(g: *Graphics, font: *const Font, render_font: *const RenderFont, glyph_id: u16) Glyph {
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
    stbtt.stbtt_GetGlyphBitmapBox(&font.stbtt_font, glyph_id, scale, scale, &x0, &y0, &x1, &y1);

    // log.warn("box {} {} {} {}", .{x0, y0, x1, y1});

    // Draw glyph into bitmap buffer.
    const glyph_width = @intCast(u32, x1 - x0) + h_padding;
    const glyph_height = @intCast(u32, y1 - y0) + v_padding;

    const pos = fc.main_atlas.nextPosForSize(glyph_width, glyph_height);
    const glyph_x = pos.x;
    const glyph_y = pos.y;

    // Don't include our extra padding when blitting to bitmap with stbtt.
    const buf_offset = (glyph_x + Glyph.Padding) + (glyph_y + Glyph.Padding) * fc.main_atlas.width;
    stbtt.stbtt_MakeGlyphBitmap(&font.stbtt_font, &fc.main_atlas.buf[buf_offset], @intCast(c_int, glyph_width - Glyph.Padding), @intCast(c_int, glyph_height - Glyph.Padding), @intCast(c_int, fc.main_atlas.width), scale, scale, glyph_id);
    fc.main_atlas.copyToCanonicalBuffer(glyph_x, glyph_y, glyph_width, glyph_height);

    const h_metrics = font.ttf_font.getGlyphHMetrics(glyph_id);
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
    g.font_cache.main_atlas.markDirtyBuffer();
    return glyph;
}

fn generateColorBitmapGlyph(g: *Graphics, font: *const Font, render_font: *const RenderFont, glyph_id: u16) Glyph {
    // Copy over png glyph data instead of going through the normal stbtt rasterizer.
    if (font.ttf_font.getGlyphColorBitmap(glyph_id) catch unreachable) |data| {
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

        const pos = fc.color_atlas.nextPosForSize(glyph_width, glyph_height);
        const glyph_x = pos.x;
        const glyph_y = pos.y;

        // Copy into atlas bitmap.
        const bitmap_len = @intCast(usize, src_width * src_height * channels);
        fc.color_atlas.copySubImageFrom(
            glyph_x + Glyph.Padding,
            glyph_y + Glyph.Padding,
            @intCast(usize, src_width),
            @intCast(usize, src_height),
            bitmap[0..bitmap_len],
        );

        // const h_metrics = font.ttf_font.getGlyphHMetrics(glyph_id);
        // log.info("adv: {}, lsb: {}", .{h_metrics.advance_width, h_metrics.left_side_bearing});

        var glyph = Glyph.init(glyph_id, fc.color_atlas.image);
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
        glyph.u0 = @intToFloat(f32, glyph_x) / @intToFloat(f32, fc.color_atlas.width);
        glyph.v0 = @intToFloat(f32, glyph_y) / @intToFloat(f32, fc.color_atlas.height);
        glyph.u1 = @intToFloat(f32, glyph_x + glyph_width) / @intToFloat(f32, fc.color_atlas.width);
        glyph.v1 = @intToFloat(f32, glyph_y + glyph_height) / @intToFloat(f32, fc.color_atlas.height);

        g.font_cache.color_atlas.markDirtyBuffer();
        return glyph;
    } else {
        stdx.panicFmt("expected color bitmap for glyph: {}", .{glyph_id});
    }
}