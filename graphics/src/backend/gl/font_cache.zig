const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;

const graphics = @import("../../graphics.zig");
const FontGroupId = graphics.font.FontGroupId;
const FontId = graphics.font.FontId;
const Font = graphics.font.Font;
const Glyph = graphics.font.Glyph;
const VMetrics = graphics.font.VMetrics;
const BitmapFont = graphics.font.BitmapFont;
const FontGroup = graphics.font.FontGroup;
const Graphics = graphics.gl.Graphics;
const TextMetrics = graphics.TextMetrics;
const FontAtlas = @import("font_atlas.zig").FontAtlas;
const Batcher = @import("batcher.zig").Batcher;
const font_renderer = @import("font_renderer.zig");
const log = std.log.scoped(.font_cache);

pub const BitmapFontId = u32;

const BitmapFontDesc = struct {
    bm_font_id: BitmapFontId,
    bm_font_size: u16,
};

const BitmapFontKey = struct {
    font_id: FontId,
    bm_font_size: u16,
};

// Once we support SDFs we can increase this to 2^16
pub const MaxBitmapFontSize = 256; // 2^8

pub const MinBitmapFontSize = 1;

// Used to insert initial BitmapFontDesc mru that will always be a cache miss.
const NullFontSize: u16 = 0;

pub const FontCache = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    fonts: std.ArrayList(Font),

    // Most recently used bm font indexed by FontId. This is checked before reaching for bm_font_map.
    // When font is first, the bm_font_size will be set to NullFontSize to force a cache miss.
    bm_font_mru: std.ArrayList(BitmapFontDesc),

    // Map to query from FontId + bitmap font size
    bm_font_map: std.AutoHashMap(BitmapFontKey, BitmapFontId),

    bm_fonts: std.ArrayList(BitmapFont),
    font_groups: ds.CompactUnorderedList(FontGroupId, FontGroup),
    fonts_by_lname: ds.OwnedKeyStringHashMap(FontId),

    // 1-channel atlas. most glyphs will use this.
    main_atlas: FontAtlas,

    // 4-channel atlas. For emojis. (eg. NotoColorEmoji.ttf)
    color_atlas: FontAtlas,

    // System fallback fonts. Used when user fallback fonts was not enough.
    system_fonts: std.ArrayList(FontId),

    pub fn init(self: *Self, alloc: std.mem.Allocator, g: *Graphics) void {
        // For testing resizing:
        // const bm_width = 128;
        // const bm_height = 128;

        // Start with a larger width since we currently just grow the height.
        const bm_width = 1024;
        const bm_height = 1024;

        self.* = .{
            .alloc = alloc,
            .main_atlas = undefined,
            .color_atlas = undefined,
            .fonts = std.ArrayList(Font).init(alloc),
            .bm_fonts = std.ArrayList(BitmapFont).init(alloc),
            .bm_font_mru = std.ArrayList(BitmapFontDesc).init(alloc),
            .bm_font_map = std.AutoHashMap(BitmapFontKey, BitmapFontId).init(alloc),
            .font_groups = ds.CompactUnorderedList(FontGroupId, FontGroup).init(alloc),
            .fonts_by_lname = ds.OwnedKeyStringHashMap(FontId).init(alloc),
            .system_fonts = std.ArrayList(FontId).init(alloc),
        };
        self.main_atlas.init(alloc, g, bm_width, bm_height, 1);
        self.color_atlas.init(alloc, g, bm_width, bm_height, 4);
    }

    pub fn deinit(self: *Self) void {
        // self.color_atlas.dumpBufferToDisk("color_font_atlas.bmp");
        // self.main_atlas.dumpBufferToDisk("main_font_atlas.bmp");

        self.color_atlas.deinit();
        self.main_atlas.deinit();

        var iter = self.font_groups.iterator();
        while (iter.next()) |*it| {
            it.deinit();
        }

        for (self.fonts.items) |*it| {
            it.deinit();
        }
        self.fonts.deinit();
        for (self.bm_fonts.items) |*it| {
            it.deinit();
        }
        self.bm_fonts.deinit();
        self.bm_font_mru.deinit();
        self.bm_font_map.deinit();
        self.fonts_by_lname.deinit();
        self.system_fonts.deinit();
        self.font_groups.deinit();
    }

    pub fn addSystemFont(self: *Self, id: FontId) !void {
        try self.system_fonts.append(id);
    }

    pub fn getPrimaryFontVMetrics(self: *Self, font_gid: FontGroupId, font_size: f32) VMetrics {
        const font_grp = self.getFontGroup(font_gid);
        var req_font_size = font_size;
        const bm_font_size = computeBitmapFontSize(&req_font_size);
        const bm_font = self.getOrCreateBitmapFont(font_grp.primary_font, bm_font_size);
        return bm_font.getVerticalMetrics(req_font_size);
    }

    // If a glyph is loaded, this will queue a gpu buffer upload.
    pub fn getOrLoadFontGroupGlyph(self: *Self, g: *Graphics, font_grp: *FontGroup, bm_font_size: u16, cp: u21) GlyphResult {
        // Find glyph by iterating fonts until the glyph is found.
        for (font_grp.fonts) |font_id| {
            const bm_font = self.getOrCreateBitmapFont(font_id, bm_font_size);
            const fnt = self.getFont(font_id);
            if (font_renderer.getOrLoadGlyph(g, fnt, bm_font, cp)) |glyph| {
                return .{
                    .font = fnt,
                    .bm_font = bm_font,
                    .glyph = glyph,
                };
            }
        }

        // Find glyph in system fonts.
        for (self.system_fonts.items) |font_id| {
            const bm_font = self.getOrCreateBitmapFont(font_id, bm_font_size);
            const fnt = self.getFont(font_id);
            if (font_renderer.getOrLoadGlyph(g, fnt, bm_font, cp)) |glyph| {
                return .{
                    .font = fnt,
                    .bm_font = bm_font,
                    .glyph = glyph,
                };
            }
        }

        // If we still can't find it. Return the special missing glyph for the first user font.
        const font_id = font_grp.fonts[0];
        const bm_font = self.getOrCreateBitmapFont(font_id, bm_font_size);
        const fnt = self.getFont(font_id);
        const glyph = font_renderer.getOrLoadMissingGlyph(g, fnt, bm_font);
        return .{
            .font = fnt,
            .bm_font = bm_font,
            .glyph = glyph,
        };
    }

    // Assumes bm_font_size is a valid size.
    pub fn getOrCreateBitmapFont(self: *Self, font_id: FontId, bm_font_size: u16) *BitmapFont {
        const mru = self.bm_font_mru.items[font_id];
        if (mru.bm_font_size == bm_font_size) {
            return &self.bm_fonts.items[mru.bm_font_id];
        } else {
            if (self.bm_font_map.get(.{ .font_id = font_id, .bm_font_size = bm_font_size })) |bm_font_id| {
                self.bm_font_mru.items[font_id] = .{
                    .bm_font_id = bm_font_id,
                    .bm_font_size = bm_font_size,
                };
                return &self.bm_fonts.items[bm_font_id];
            } else {
                // Create.
                const bm_font_id = @intCast(BitmapFontId, self.bm_fonts.items.len);
                const bm_font = self.bm_fonts.addOne() catch unreachable;
                const font = self.getFont(font_id);
                bm_font.init(self.alloc, font, bm_font_size);
                self.bm_font_map.put(.{ .font_id = font_id, .bm_font_size = bm_font_size }, bm_font_id) catch unreachable;
                self.bm_font_mru.items[font_id] = .{
                    .bm_font_id = bm_font_id,
                    .bm_font_size = bm_font_size,
                };
                return bm_font;
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
                return iter.idx - 1;
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
        group.init(self.alloc, font_seq);
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

    pub fn addFont(self: *Self, data: []const u8) FontId {
        const next_id = @intCast(u32, self.fonts.items.len);

        var font: Font = undefined;
        font.init(self.alloc, next_id, data);

        const lname = std.ascii.allocLowerString(self.alloc, font.name.slice) catch unreachable;
        defer self.alloc.free(lname);

        self.fonts.append(font) catch unreachable;
        const mru = self.bm_font_mru.addOne() catch unreachable;
        // Set to value to force cache miss.
        mru.bm_font_size = NullFontSize;

        self.fonts_by_lname.put(lname, next_id) catch unreachable;
        return next_id;
    }
};

// Glyph with font that owns it.
pub const GlyphResult = struct {
    font: *Font,
    bm_font: *BitmapFont,
    glyph: *Glyph,
};

// Computes bitmap font size and also updates the requested font size if necessary.
pub fn computeBitmapFontSize(font_size: *f32) u16 {
    if (font_size.* <= 16) {
        if (font_size.* < MinBitmapFontSize) {
            font_size.* = MinBitmapFontSize;
            return MinBitmapFontSize;
        } else {
            // Smaller font sizes are rounded up and get an exact bitmap font.
            font_size.* = @ceil(font_size.*);
            return @floatToInt(u16, font_size.*);
        }
    } else {
        if (font_size.* > MaxBitmapFontSize) {
            font_size.* = MaxBitmapFontSize;
            return MaxBitmapFontSize;
        } else {
            var next_pow = @floatToInt(u4, @ceil(std.math.log2(font_size.*)));
            return @as(u16, 1) << next_pow;
        }
    }
}
