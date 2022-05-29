const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;

const graphics = @import("../../graphics.zig");
const FontGroupId = graphics.font.FontGroupId;
const FontId = graphics.font.FontId;
const Font = graphics.font.Font;
const VMetrics = graphics.font.VMetrics;
const RenderFont = graphics.gpu.RenderFont;
const FontGroup = graphics.font.FontGroup;
const gpu = graphics.gpu;
const Glyph = gpu.Glyph;
const TextMetrics = graphics.TextMetrics;
const FontAtlas = @import("font_atlas.zig").FontAtlas;
const Batcher = @import("batcher.zig").Batcher;
const font_renderer = @import("font_renderer.zig");
const FontDesc = graphics.font.FontDesc;
const log = std.log.scoped(.font_cache);

pub const RenderFontId = u32;

const RenderFontDesc = struct {
    font_id: RenderFontId,
    font_size: u16,
};

const RenderFontKey = struct {
    font_id: FontId,
    font_size: u16,
};

// Once we support SDFs we can increase this to 2^16
pub const MaxRenderFontSize = 256; // 2^8

pub const MinRenderFontSize = 1;

// Used to insert initial RenderFontDesc mru that will always be a cache miss.
const NullFontSize: u16 = 0;

pub const FontCache = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    fonts: std.ArrayList(Font),

    // Most recently used bm font indexed by FontId. This is checked before reaching for render_font_map.
    // When font is first, the render_font_size will be set to NullFontSize to force a cache miss.
    render_font_mru: std.ArrayList(RenderFontDesc),

    // Map to query from FontId + bitmap font size
    render_font_map: std.AutoHashMap(RenderFontKey, RenderFontId),

    render_fonts: std.ArrayList(RenderFont),
    font_groups: ds.CompactUnorderedList(FontGroupId, FontGroup),
    fonts_by_lname: ds.OwnedKeyStringHashMap(FontId),

    /// For outline glyphs and color bitmaps. Linear filtering enabled.
    main_atlas: FontAtlas,

    /// For bitmap font glyphs. Linear filtering disabled.
    bitmap_atlas: FontAtlas,

    // System fallback fonts. Used when user fallback fonts was not enough.
    system_fonts: std.ArrayList(FontId),

    pub fn init(self: *Self, alloc: std.mem.Allocator, gctx: *gpu.Graphics) void {
        self.* = .{
            .alloc = alloc,
            .main_atlas = undefined,
            .bitmap_atlas = undefined,
            .fonts = std.ArrayList(Font).init(alloc),
            .render_fonts = std.ArrayList(RenderFont).init(alloc),
            .render_font_mru = std.ArrayList(RenderFontDesc).init(alloc),
            .render_font_map = std.AutoHashMap(RenderFontKey, RenderFontId).init(alloc),
            .font_groups = ds.CompactUnorderedList(FontGroupId, FontGroup).init(alloc),
            .fonts_by_lname = ds.OwnedKeyStringHashMap(FontId).init(alloc),
            .system_fonts = std.ArrayList(FontId).init(alloc),
        };
        // For testing resizing:
        // const main_atlas_width = 128;
        // const main_atlas_height = 128;

        // Start with a larger width since we currently just grow the height.
        const main_atlas_width = 1024;
        const main_atlas_height = 1024;
        self.main_atlas.init(alloc, gctx, main_atlas_width, main_atlas_height, true);
        self.bitmap_atlas.init(alloc, gctx, 256, 256, false);
    }

    pub fn deinit(self: *Self) void {
        self.main_atlas.dumpBufferToDisk("main_atlas.bmp");
        self.bitmap_atlas.dumpBufferToDisk("bitmap_atlas.bmp");

        self.main_atlas.deinit();
        self.bitmap_atlas.deinit();

        var iter = self.font_groups.iterator();
        while (iter.next()) |*it| {
            it.deinit();
        }

        for (self.fonts.items) |*it| {
            it.deinit(self.alloc);
        }
        self.fonts.deinit();
        for (self.render_fonts.items) |*it| {
            it.deinit();
        }
        self.render_fonts.deinit();
        self.render_font_mru.deinit();
        self.render_font_map.deinit();
        self.fonts_by_lname.deinit();
        self.system_fonts.deinit();
        self.font_groups.deinit();
    }

    pub fn addSystemFont(self: *Self, id: FontId) !void {
        try self.system_fonts.append(id);
    }

    pub fn getPrimaryFontVMetrics(self: *Self, font_gid: FontGroupId, font_size: f32) VMetrics {
        const fgroup = self.getFontGroup(font_gid);
        var req_font_size = font_size;
        const render_font_size = computeRenderFontSize(fgroup.primary_font_desc, &req_font_size);
        const render_font = self.getOrCreateRenderFont(fgroup.primary_font, render_font_size);
        return render_font.getVerticalMetrics(req_font_size);
    }

    pub fn getFontVMetrics(self: *Self, font_id: FontId, font_size: f32) VMetrics {
        var req_font_size = font_size;
        const font = self.getFont(font_id);
        const desc = FontDesc{
            .font_type = font.font_type,
            .bmfont_scaler = font.bmfont_scaler,
        };
        const render_font_size = computeRenderFontSize(desc, &req_font_size);
        const render_font = self.getOrCreateRenderFont(font, render_font_size);
        return render_font.getVerticalMetrics(req_font_size);
    }

    // If a glyph is loaded, this will queue a gpu buffer upload.
    pub fn getOrLoadFontGroupGlyph(self: *Self, g: *gpu.Graphics, font_grp: *FontGroup, render_font_size: u16, cp: u21) GlyphResult {
        // Find glyph by iterating fonts until the glyph is found.
        for (font_grp.fonts) |font_id| {
            const render_font = self.getOrCreateRenderFont(font_id, render_font_size);
            const fnt = self.getFont(font_id);
            if (font_renderer.getOrLoadGlyph(g, fnt, render_font, cp)) |glyph| {
                return .{
                    .font = fnt,
                    .render_font = render_font,
                    .glyph = glyph,
                };
            }
        }

        // Find glyph in system fonts.
        for (self.system_fonts.items) |font_id| {
            const render_font = self.getOrCreateRenderFont(font_id, render_font_size);
            const fnt = self.getFont(font_id);
            if (font_renderer.getOrLoadGlyph(g, fnt, render_font, cp)) |glyph| {
                return .{
                    .font = fnt,
                    .render_font = render_font,
                    .glyph = glyph,
                };
            }
        }

        // If we still can't find it. Return the special missing glyph for the first user font.
        const font_id = font_grp.fonts[0];
        const render_font = self.getOrCreateRenderFont(font_id, render_font_size);
        const fnt = self.getFont(font_id);
        const glyph = font_renderer.getOrLoadMissingGlyph(g, fnt, render_font);
        return .{
            .font = fnt,
            .render_font = render_font,
            .glyph = glyph,
        };
    }

    // Assumes render_font_size is a valid size.
    pub fn getOrCreateRenderFont(self: *Self, font_id: FontId, render_font_size: u16) *RenderFont {
        const mru = self.render_font_mru.items[font_id];
        if (mru.font_size == render_font_size) {
            return &self.render_fonts.items[mru.font_id];
        } else {
            if (self.render_font_map.get(.{ .font_id = font_id, .font_size = render_font_size })) |render_font_id| {
                self.render_font_mru.items[font_id] = .{
                    .font_id = render_font_id,
                    .font_size = render_font_size,
                };
                return &self.render_fonts.items[render_font_id];
            } else {
                // Create.
                const render_font_id = @intCast(RenderFontId, self.render_fonts.items.len);
                const render_font = self.render_fonts.addOne() catch unreachable;
                const font = self.getFont(font_id);

                const ot_font = font.getOtFontBySize(render_font_size);
                switch (font.font_type) {
                    .Outline => render_font.initOutline(self.alloc, font.id, ot_font, render_font_size),
                    .Bitmap => render_font.initBitmap(self.alloc, font.id, ot_font, render_font_size),
                }

                self.render_font_map.put(.{ .font_id = font_id, .font_size = render_font_size }, render_font_id) catch unreachable;
                self.render_font_mru.items[font_id] = .{
                    .font_id = render_font_id,
                    .font_size = render_font_size,
                };
                return render_font;
            }
        }
    }

    // TODO: Use a hashmap.
    fn getFontId(self: *Self, name: []const u8) ?FontId {
        for (self.fonts) |it| {
            if (std.mem.eql(u8, it.name, name)) {
                return it.id;
            }
        }
        return null;
    }

    pub fn getFont(self: *Self, id: FontId) *Font {
        return &self.fonts.items[id];
    }

    pub fn getFontGroup(self: *const Self, id: FontGroupId) *FontGroup {
        return self.font_groups.getPtrNoCheck(id);
    }

    fn getFontGroupId(self: *Self, font_seq: []const FontId) ?FontGroupId {
        var iter = self.font_groups.iterator();
        while (iter.next()) |it| {
            if (it.fonts.len != font_seq.len) {
                continue;
            }
            var match = true;
            for (font_seq) |needle, i| {
                if (it.fonts[i] != needle) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return iter.cur_id;
            }
        }
        return null;
    }

    pub fn getOrLoadFontGroupByNameSeq(self: *Self, names: []const []const u8) ?FontGroupId {
        var font_id_seq = std.ArrayList(FontId).init(self.alloc);
        defer font_id_seq.deinit();

        var buf: [256]u8 = undefined;
        for (names) |name| {
            const len = std.math.min(buf.len, name.len);
            const lname = std.ascii.lowerString(buf[0..len], name[0..len]);
            const font_id = self.getOrLoadFontByLname(lname);
            font_id_seq.append(font_id) catch unreachable;
        }

        if (font_id_seq.items.len == 0) {
            return null;
        }
        return self.getOrLoadFontGroup(font_id_seq.items);
    }

    pub fn getOrLoadFontGroup(self: *Self, font_seq: []const FontId) FontGroupId {
        if (self.getFontGroupId(font_seq)) |font_gid| {
            return font_gid;
        } else {
            // Load font group.
            return self._addFontGroup(font_seq);
        }
    }

    fn _addFontGroup(self: *Self, font_seq: []const FontId) FontGroupId {
        var group: FontGroup = undefined;
        group.init(self.alloc, font_seq, self.fonts.items);
        return self.font_groups.add(group) catch unreachable;
    }

    pub fn addFontGroup(self: *Self, font_seq: []const FontId) ?FontGroupId {
        // Make sure that this font group doesn't already exist.
        if (self.getFontGroupId(font_seq) != null) {
            return null;
        }
        return self._addFontGroup(font_seq);
    }

    fn getOrLoadFontByLname(self: *Self, lname: []const u8) FontId {
        if (self.fonts_by_lname.get(lname)) |id| {
            return id;
        } else {
            unreachable;
        }
    }

    pub fn getOrLoadFontFromDataByLName(self: *Self, lname: []const u8, data: []const u8) FontId {
        if (self.fonts_by_lname.get(lname)) |id| {
            return id;
        } else {
            return self.addFont(data);
        }
    }

    pub fn addFontOTB(self: *Self, data: []const graphics.BitmapFontData) FontId {
        const next_id = @intCast(u32, self.fonts.items.len);

        var font: Font = undefined;
        font.initOTB(self.alloc, next_id, data);

        const lname = std.ascii.allocLowerString(self.alloc, font.name) catch unreachable;
        defer self.alloc.free(lname);

        self.fonts.append(font) catch unreachable;
        const mru = self.render_font_mru.addOne() catch unreachable;
        // Set to value to force cache miss.
        mru.font_size = NullFontSize;

        self.fonts_by_lname.put(lname, next_id) catch unreachable;
        return next_id;
    }

    pub fn addFontTTF(self: *Self, data: []const u8) FontId {
        const next_id = @intCast(u32, self.fonts.items.len);

        var font: Font = undefined;
        font.initTTF(self.alloc, next_id, data);

        const lname = std.ascii.allocLowerString(self.alloc, font.name) catch unreachable;
        defer self.alloc.free(lname);

        self.fonts.append(font) catch unreachable;
        const mru = self.render_font_mru.addOne() catch unreachable;
        // Set to value to force cache miss.
        mru.font_size = NullFontSize;

        self.fonts_by_lname.put(lname, next_id) catch unreachable;
        return next_id;
    }
};

// Glyph with font that owns it.
pub const GlyphResult = struct {
    font: *Font,
    render_font: *RenderFont,
    glyph: *Glyph,
};

// Computes bitmap font size and also updates the requested font size if necessary.
pub fn computeRenderFontSize(desc: FontDesc, font_size: *f32) u16 {
    switch (desc.font_type) {
        .Outline => {
            if (font_size.* <= 16) {
                if (font_size.* < MinRenderFontSize) {
                    font_size.* = MinRenderFontSize;
                    return MinRenderFontSize;
                } else {
                    // Smaller font sizes are rounded up and get an exact bitmap font.
                    font_size.* = @ceil(font_size.*);
                    return @floatToInt(u16, font_size.*);
                }
            } else {
                if (font_size.* > MaxRenderFontSize) {
                    font_size.* = MaxRenderFontSize;
                    return MaxRenderFontSize;
                } else {
                    var next_pow = @floatToInt(u4, @ceil(std.math.log2(font_size.*)));
                    return @as(u16, 1) << next_pow;
                }
            }
        },
        .Bitmap => {
            if (font_size.* < MinRenderFontSize) {
                font_size.* = MinRenderFontSize;
            } else if (font_size.* > MaxRenderFontSize) {
                font_size.* = MaxRenderFontSize;
            }
            // First take floor.
            const req_font_size = @floatToInt(u32, font_size.*);
            if (req_font_size >= desc.bmfont_scaler.mapping.len) {
                // Look at the last mapping and scale upwards.
                const mapping = desc.bmfont_scaler.mapping[desc.bmfont_scaler.mapping.len-1];
                const scale = req_font_size / mapping.render_font_size;
                font_size.* = @intToFloat(f32, mapping.render_font_size * scale);
                return mapping.render_font_size;
            } else {
                const mapping = desc.bmfont_scaler.mapping[req_font_size];
                font_size.* = @intToFloat(f32, mapping.final_font_size);
                return mapping.render_font_size;
            }
        },
    }
}
