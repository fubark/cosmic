const gl = @import("gl");

const graphics = @import("graphics.zig");

pub const Glyph = struct {
    pub const Padding = 1;

    // Glyph id used in the ttf file.
    glyph_id: u16,

    image: graphics.ImageDesc,

    // Top-left tex coords.
    u0: f32,
    v0: f32,

    // Bot-right tex coords.
    u1: f32,
    v1: f32,

    // for shaping, px amount from the current x,y pos to start drawing the glyph.
    // x_offset includes left_side_bearing and glyph bitmap left padding.
    // y_offset includes gap from font's max ascent to this glyph's ascent, and also the top bitmap padding.
    // Scaled to screen coords for the font size this glyph was rendered to the bitmap.
    x_offset: f32,
    y_offset: f32,

    // px pos and dim of glyph in bitmap.
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    // The dimensions we use when drawing with a quad.
    // For outline glyphs this is simply the glyph width/height.
    // For color glyphs this is scaled down from the glyph width/height to the bm font size.
    dst_width: f32,
    dst_height: f32,

    // font size or px/em of the underlying bitmap data. Used to calculate scaling when rendering.
    // A colored bitmap font could contain glyphs with different px/em, so this shouldn't be a shared value
    // at the font level but rather on the per glyph level.
    render_font_size: f32,

    // for shaping, px amount this codepoint should occupy for this font_size.
    advance_width: f32,

    is_color_bitmap: bool,

    pub fn init(glyph_id: u16, image: graphics.ImageDesc) @This() {
        return .{
            .glyph_id = glyph_id,
            .image = image,
            .is_color_bitmap = false,
            .u0 = 0,
            .v0 = 0,
            .u1 = 0,
            .v1 = 0,
            .x_offset = 0,
            .y_offset = 0,
            .render_font_size = 0,
            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .dst_width = 0,
            .dst_height = 0,
            .advance_width = 0,
        };
    }
};
