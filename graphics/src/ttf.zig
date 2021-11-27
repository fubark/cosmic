const std = @import("std");
const stdx = @import("stdx");

const string = stdx.string;
const ds = stdx.ds;
const algo = stdx.algo;
const log = stdx.log.scoped(.ttf);

// NOTES:
// Chrome does not support SVG in fonts but they support colored bitmaps.
// - https://bugs.chromium.org/p/chromium/issues/detail?id=306078#c53)
// - See also https://github.com/fontforge/fontforge/issues/677
// COLR table - https://docs.microsoft.com/en-us/typography/opentype/spec/colr
// CPAL table - https://docs.microsoft.com/en-us/typography/opentype/spec/cpal
// SVG table - https://docs.microsoft.com/en-us/typography/opentype/spec/svg
// SBIX table - https://docs.microsoft.com/en-us/typography/opentype/spec/sbix (promoted by apple)

// OTF data types: https://docs.microsoft.com/en-us/typography/opentype/spec/otff
// Use ttx from fonttools to create a human readable .ttx file from ttf: https://simoncozens.github.io/fonts-and-layout/opentype.html

// LINKS:
// https://github.com/RazrFalcon/ttf-parser
// https://github.com/nothings/stb/pull/750 (Pulling svg glyph data)

const PLATFORM_ID_UNICODE = 0;
const PLATFORM_ID_MACINTOSH = 1;
const PLATFORM_ID_WINDOWS = 3;

const UNICODE_EID_UNICODE_1_0 = 0; // deprecated
const UNICODE_EID_UNICODE_1_1 = 1; // deprecated

const WINDOWS_EID_SYMBOL = 0;
const WINDOWS_EID_UNICODE_BMP = 1;
const WINDOWS_EID_UNICODE_FULL_REPERTOIRE = 10; // Requires a format 12 glyph index

const BITMAP_FLAG_HORIZONTAL_METRICS: i8 = 1;

pub const NAME_ID_FONT_FAMILY: u16 = 1;

const FontError = error {
    InvalidFont,
    Unsupported,
};

// In font design units.
pub const VMetrics = struct {
    // max distance above baseline (positive units)
    ascender: i16,
    // max distance below baseline (negative units)
    descender: i16,
    // gap between the previous row's descent and current row's ascent.
    line_gap: i16,
};

// In font design units.
const GlyphHMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

const GlyphColorBitmap = struct {
    // In px units.
    width: u8,
    height: u8, 
    left_side_bearing: i8,
    bearing_y: i8,
    advance_width: u8,

    // How many px in the bitmap represent 1 em. This lets us scale the px units to the font size.
    x_px_per_em: u8,
    y_px_per_em: u8,
    png_data: []const u8,
};

const GlyphMapperIface = struct {
    const Self = @This();

    ptr: *c_void,
    get_glyph_id_fn: fn(*c_void, cp: u21) FontError!?u16,

    fn init(ptr: anytype) Self {
        const ImplPtr = @TypeOf(ptr);
        const gen = struct {
            fn getGlyphId(_ptr: *c_void, cp: u21) FontError!?u16 {
                const self = stdx.mem.ptrCastAlign(ImplPtr, _ptr);
                return self.getGlyphId(cp);
            }
        };

        return .{
            .ptr = ptr,
            .get_glyph_id_fn = gen.getGlyphId,
        };
    }

    // Maps codepoint to glyph index.
    fn getGlyphId(self: Self, cp: u21) FontError!?u16 {
        return self.get_glyph_id_fn(self.ptr, cp);
    }
};

// TTF/OTF
// Struct holds useful data from TTF file.
pub const TTF_Font = struct {
    const Self = @This();

    start: usize,
    data: []const u8,

    // Offsets from &data[0].

    // https://docs.microsoft.com/en-us/typography/opentype/spec/head
    head_offset: usize,
    // https://docs.microsoft.com/en-us/typography/opentype/spec/hhea
    hhea_offset: usize,
    // https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx
    hmtx_offset: usize,

    // https://docs.microsoft.com/en-us/typography/opentype/spec/cbdt
    cbdt_offset: ?usize,

    // https://docs.microsoft.com/en-us/typography/opentype/spec/cblc
    cblc_offset: ?usize,
    glyf_offset: ?usize,
    cff_offset: ?usize,
    glyph_map_format: u16,
    glyph_mapper: GlyphMapperIface,
    glyph_mapper_box: ds.SizedBox,

    num_glyphs: usize,

    // From hhea.
    ascender: i16,
    descender: i16,
    line_gap: i16,

    // https://help.fontlab.com/fontlab-vi/Font-Sizes-and-the-Coordinate-System/
    // This is the height in font design units of the internal font size.
    // Note that the concept of font size isn't the maximum height of the font.
    // Units-per-em (UPM) is used to scale to user defined font size like pixels.
    units_per_em: u16,

    // start_offset is offset that begins the font data in a font collection file (ttc).
    // start_offset is 0 if it's a ttf/otf file.
    pub fn init(alloc: *std.mem.Allocator, data: []const u8, start_offset: usize) !Self {
        var new = Self{
            .data = data,
            .start = start_offset,
            .head_offset = undefined,
            .hhea_offset = undefined,
            .hmtx_offset = undefined,
            .cbdt_offset = null,
            .cblc_offset = null,
            .glyf_offset = null,
            .cff_offset = null,
            .glyph_mapper = undefined,
            .glyph_mapper_box = undefined,
            .glyph_map_format = 0,
            .num_glyphs = 0,
            .ascender = undefined,
            .descender = undefined,
            .line_gap = undefined,
            .units_per_em = undefined,
        };

        try new.loadTables(alloc);

        new.ascender = fromBigI16(&data[new.hhea_offset+4]);
        new.descender = fromBigI16(&data[new.hhea_offset+6]);
        new.line_gap = fromBigI16(&data[new.hhea_offset+8]);
        new.units_per_em = fromBigU16(&data[new.head_offset+18]);
        return new;
    }

    pub fn deinit(self: Self) void {
        self.glyph_mapper_box.deinit();
    }

    pub fn hasGlyphOutlines(self: *const Self) bool {
        return self.glyf_offset != null or self.cff_offset != null;
    }

    pub fn hasColorBitmap(self: *const Self) bool {
        return self.cbdt_offset != null;
    }

    pub fn getVerticalMetrics(self: *const Self) VMetrics {
        return .{
            .ascender = self.ascender,
            .descender = self.descender,
            .line_gap = self.line_gap,
        };
    }

    pub fn getGlyphHMetrics(self: *const Self, glyph_id: u16) GlyphHMetrics {
        // If glyph_id >= num_hmetrics, then the advance is in the last hmetric record,
        // and left side bearing is in array following the hmetric records.
        // See https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx
        const num_hmetrics = fromBigU16(&self.data[self.hhea_offset+34]);
        if (glyph_id < num_hmetrics) {
            return .{
                .advance_width = fromBigU16(&self.data[self.hmtx_offset+4*glyph_id]),
                .left_side_bearing = fromBigI16(&self.data[self.hmtx_offset+4*glyph_id+2]),
            };
        } else {
            return .{
                .advance_width = fromBigU16(&self.data[self.hmtx_offset + 4*(num_hmetrics-1)]),
                .left_side_bearing = fromBigI16(&self.data[self.hmtx_offset + 4*num_hmetrics + 2*(glyph_id - num_hmetrics)]),
            };
        }
    }

    // Given user font size unit, returns the scale needed to multiply with font design units.
    // eg. bitmap px font size, note the glyphs drawn onto the resulting bitmap can exceed the px font size, since
    // the concept of font size does not equate to the maximum height of the font.
    pub fn getScaleToUserFontSize(self: *const Self, size: f32) f32 {
        return size / @intToFloat(f32, self.units_per_em);
    }

    // Get's the color bitmap data for glyph id.
    // eg. NotoColorEmoji.ttf has png data.
    // Doesn't cache anything.
    pub fn getGlyphColorBitmap(self: *const Self, glyph_id: u16) !?GlyphColorBitmap {
        if (self.cbdt_offset == null) {
            return null;
        }
        // Retrieve bitmap location from cblc: https://docs.microsoft.com/en-us/typography/opentype/spec/cblc
        const num_bitmap_records = fromBigU32(&self.data[self.cblc_offset.?+4]);

        // log.debug("bitmap records: {}", .{num_bitmap_records});
        var i: usize = 0;
        while (i < num_bitmap_records) : (i += 1) {
            const b_offset = self.cblc_offset.? + 8 + i*48;
            const start_glyph_id = fromBigU16(&self.data[b_offset+40]);
            const end_glyph_id = fromBigU16(&self.data[b_offset+42]);

            const x_px_per_em = self.data[b_offset+44];
            const y_px_per_em = self.data[b_offset+45];
            const flags = @bitCast(i8, self.data[b_offset+47]);
            if (flags != BITMAP_FLAG_HORIZONTAL_METRICS) {
                // This record is not for horizontally text.
                continue;
            }
            // log.debug("ppem {} {} {}", .{x_px_per_em, y_px_per_em, flags});

            if (glyph_id >= start_glyph_id and glyph_id <= end_glyph_id) {
                // Scan more granular range in index subtables.
                const ist_start_offset = self.cblc_offset.? + fromBigU32(&self.data[b_offset+0]);
                const num_index_subtables = fromBigU32(&self.data[b_offset+8]);
                // log.debug("num subtables: {}", .{num_index_subtables});
                var ist_i: usize = 0;
                while (ist_i < num_index_subtables) : (ist_i += 1) {
                    // Start by looking at the IndexSubTableArray
                    const arr_offset = ist_start_offset + ist_i*8;
                    const arr_start_glyph_id = fromBigU16(&self.data[arr_offset+0]);
                    const arr_end_glyph_id = fromBigU16(&self.data[arr_offset+2]);
                    // log.debug("glyph id: {}", .{glyph_id});
                    if (glyph_id >= arr_start_glyph_id and glyph_id <= arr_end_glyph_id) {
                        // log.debug("index subtable array {} {}", .{arr_start_glyph_id, arr_end_glyph_id});
                        const ist_body_offset = ist_start_offset + fromBigU32(&self.data[arr_offset+4]);
                        const index_format = fromBigU16(&self.data[ist_body_offset+0]);
                        const image_format = fromBigU16(&self.data[ist_body_offset+2]);
                        const image_data_start_offset = self.cbdt_offset.? + fromBigU32(&self.data[ist_body_offset+4]);
                        // log.debug("format {} {}", .{index_format, image_format});

                        var glyph_data: []const u8 = undefined;
                        if (index_format == 1) {
                            const glyph_id_delta = glyph_id - arr_start_glyph_id;
                            const glyph_data_offset = fromBigU32(&self.data[ist_body_offset+8+glyph_id_delta*4]);
                            // There is always a data offset after the glyph, even the last glyph. Used to calculate glyph data size.
                            const next_glyph_data_offset = fromBigU32(&self.data[ist_body_offset+8+(glyph_id_delta+1)*4]);
                            // log.debug("glyph data {} {}", .{glyph_data_offset, next_glyph_data_offset});
                            glyph_data = self.data[image_data_start_offset+glyph_data_offset..image_data_start_offset+next_glyph_data_offset];
                        } else {
                            return FontError.Unsupported;
                        }

                        if (image_format == 17) {
                            // https://docs.microsoft.com/en-us/typography/opentype/spec/cbdt#format-17-small-metrics-png-image-data
                            // log.debug("data len: {}", .{fromBigU32(&glyph_data[5])});
                            return GlyphColorBitmap{
                                .width = glyph_data[1],
                                .height = glyph_data[0],
                                .left_side_bearing = @bitCast(i8, glyph_data[2]),
                                .bearing_y = @bitCast(i8, glyph_data[3]),
                                .advance_width = glyph_data[4],
                                .x_px_per_em = x_px_per_em,
                                .y_px_per_em = y_px_per_em,
                                .png_data = glyph_data[9..],
                            };
                        } else {
                            return FontError.Unsupported;
                        }
                    }
                }
            }
        }
        return null;
    }

    // Returns glyph id for utf codepoint.
    pub fn getGlyphId(self: *const Self, cp: u21) !?u16 {
        return self.glyph_mapper.getGlyphId(cp);
    }

    pub fn getFontFamilyName(self: *const Self, alloc: *std.mem.Allocator) ?string.BoxString {
        return self.getNameString(alloc, NAME_ID_FONT_FAMILY);
    }

    // stbtt has GetFontNameString but requires you to pass in specific platformId, encodingId and languageId.
    // This will return the first acceptable value for a given nameId. Useful for getting things like font family.
    pub fn getNameString(self: *const Self, alloc: *std.mem.Allocator, name_id: u16) ?string.BoxString {
        const pos = self.findTable("name".*) orelse return null;
        const data = self.data;
        const count = fromBigU16(&data[pos+2]);
        const string_data_pos = pos + fromBigU16(&data[pos+4]);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const loc = pos + 6 + 12*i;
            const platform_id = fromBigU16(&data[loc]);
            const encoding_id = fromBigU16(&data[loc+2]);
            // Currently only looks for unicode encoding.
            // https://github.com/RazrFalcon/fontdb/blob/master/src/lib.rs looks at mac roman as well.
            if (!isUnicodeEncoding(platform_id, encoding_id)) {
                continue;
            }
            // const lang_id = fromBigU16(&data[loc+4]);
            const it_name_id = fromBigU16(&data[loc+6]);
            if (it_name_id == name_id) {
                const len = fromBigU16(&data[loc+8]);
                const str_pos = string_data_pos + fromBigU16(&data[loc+10]);
                return fromBigUTF16(alloc, data[str_pos..str_pos+len]);
            }
        }
        return null;
    }

    // Based on https://github.com/RazrFalcon/ttf-parser/blob/master/src/tables/name.rs is_unicode_encoding
    fn isUnicodeEncoding(platform_id: u16, encoding_id: u16) bool {
        return switch (platform_id) {
            PLATFORM_ID_UNICODE => true,
            PLATFORM_ID_WINDOWS => switch (encoding_id) {
                WINDOWS_EID_SYMBOL,
                WINDOWS_EID_UNICODE_BMP,
                WINDOWS_EID_UNICODE_FULL_REPERTOIRE => true,
                else => false,
            },
            else => false,
        };
    }

    // Only retrieves offset info.
    // Returns error if minimum data isn't 
    fn loadTables(self: *Self, alloc: *std.mem.Allocator) !void {
        var loaded_glyph_map = false;
        var found_hhea = false;
        var found_hmtx = false;
        var found_head = false;
        errdefer {
            if (loaded_glyph_map) {
                self.glyph_mapper_box.deinit();
            }
        }
        const data = self.data;
        const start = self.start;
        const num_tables = fromBigU16(&data[start+4]);
        const tabledir = start + 12;
        var i: usize = 0;
        while (i < num_tables): (i += 1) {
            const loc = tabledir + 16*i;
            const val: [4]u8 = data[loc..loc+4][0..4].*;
            if (std.meta.eql(val, "CBDT".*)) {
                self.cbdt_offset = fromBigU32(&data[loc+8]);
            } else if (std.meta.eql(val, "CBLC".*)) {
                self.cblc_offset = fromBigU32(&data[loc+8]);
            } else if (std.meta.eql(val, "head".*)) {
                self.head_offset = fromBigU32(&data[loc+8]);
                found_head = true;
            } else if (std.meta.eql(val, "hhea".*)) {
                self.hhea_offset = fromBigU32(&data[loc+8]);
                found_hhea = true;
            } else if (std.meta.eql(val, "hmtx".*)) {
                self.hmtx_offset = fromBigU32(&data[loc+8]);
                found_hmtx = true;
            } else if (std.meta.eql(val, "glyf".*)) {
                self.glyf_offset = fromBigU32(&data[loc+8]);
            } else if (std.meta.eql(val, "CFF ".*)) {
                self.cff_offset = fromBigU32(&data[loc+8]);
            } else if (std.meta.eql(val, "maxp".*)) {
                const offset = fromBigU32(&data[loc+8]);
                // https://docs.microsoft.com/en-us/typography/opentype/spec/maxp
                self.num_glyphs = fromBigU16(&data[offset+4]);
            } else if (std.meta.eql(val, "cmap".*)) {
                const t_offset = fromBigU32(&data[loc+8]);
                // https://docs.microsoft.com/en-us/typography/opentype/spec/cmap
                const cmap_num_tables = fromBigU16(&data[t_offset + 2]);

                var cmap_i: usize = 0;
                // log.debug("cmap num tables: {}", .{cmap_num_tables});
                while (cmap_i < cmap_num_tables): (cmap_i += 1) {
                    const r_offset = t_offset + 4 + cmap_i * 8;
                    const platform_id = fromBigU16(&data[r_offset]);
                    const encoding_id = fromBigU16(&data[r_offset+2]);
                    // log.debug("platform: {} {}", .{platform_id, encoding_id});
                    if (isUnicodeEncoding(platform_id, encoding_id)) {
                        const st_offset = t_offset + fromBigU32(&data[r_offset+4]);
                        const format = fromBigU16(&data[st_offset]);
                        // log.debug("format: {}", .{format});
                        if (format == 14) {
                            // Unicode variation sequences
                            // https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-14-unicode-variation-sequences
                            // NotoColorEmoji.ttf
                            // TODO:
                            // Since we don't support UVS we can ignore this table for now.
                            // const mapper = UvsGlyphMapper.init(alloc, ds.Transient([]const u8).init(data), st_offset);
                            // self.glyph_mapper = @ptrCast(*ds.Opaque, mapper);
                            // self.deinit_glyph_mapper = @field(mapper, "deinit_fn");
                            // self.get_glyph_index_fn = @field(mapper, "get_glyph_index_fn");
                            // loaded_glyph_map = true;
                            continue;
                        } else if (format == 12) {
                            const mapper = ds.Box(SegmentedCoverageGlyphMapper).create(alloc) catch unreachable;
                            mapper.ptr.init(data, st_offset);
                            self.glyph_mapper = GlyphMapperIface.init(mapper.ptr);
                            self.glyph_mapper_box = mapper.toSized();
                            loaded_glyph_map = true;
                        } else if (format == 4) {
                            const mapper = ds.Box(SegmentGlyphMapper).create(alloc) catch unreachable;
                            mapper.ptr.init(data, st_offset);
                            self.glyph_mapper = GlyphMapperIface.init(mapper.ptr);
                            self.glyph_mapper_box = mapper.toSized();
                            loaded_glyph_map = true;
                        }
                        if (loaded_glyph_map) {
                            self.glyph_map_format = format;
                            break;
                        }
                    }
                }
            }
        }

        // Required.
        if (!loaded_glyph_map or !found_head or !found_hhea or !found_hmtx) {
            // No codepoint glyph index mapping found.
            return error.InvalidFont;
        }

        // Must have either glyph outlines or glyph color bitmap.
        if (!self.hasColorBitmap() and !self.hasGlyphOutlines()) {
            return error.InvalidFont;
        }
    }

    pub fn printTables(self: *const Self) void {
        const start = self.start;
        const num_tables = fromBigU16(&self.data[start+4]);
        const tabledir = start + 12;
        var i: usize = 0;
        while (i < num_tables): (i += 1) {
            const loc = tabledir + 16*i;
            const val: [4]u8 = stdx.mem.to_array_ptr(u8, &self.data[loc], 4).*;
            log.debug("table {s}", .{val});
        }
    }

    // Copied from stbtt__find_table
    fn findTable(self: *const Self, tag: [4]u8) ?usize {
        const start = self.start;
        const num_tables = fromBigU16(&self.data[start+4]);
        const tabledir = start + 12;
        var i: usize = 0;
        while (i < num_tables): (i += 1) {
            const loc = tabledir + 16*i;
            const val: [4]u8 = self.data[loc..loc+4][0..4].*;
            if (std.meta.eql(val, tag)) {
                return fromBigU32(&self.data[loc+8]);
            }
        }
        return null;
    }
};

// Standard mapping that only supports Unicode Basic Multilingual Plane characters (U+0000 to U+FFFF)
// https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-4-segment-mapping-to-delta-values
// Example font: NunitoSans-Regular.ttf
const SegmentGlyphMapper = struct {
    const Self = @This();

    data: []const u8,
    offset: usize,
    num_segments: usize,

    fn init(self: *Self, data: []const u8, offset: usize) void {
        self.* = .{
            .data = data,
            .num_segments = fromBigU16(&data[offset+6]) >> 1,
            .offset = offset,
        };
        // log.debug("num segments: {}", .{new.num_segments});
    }

    // Does not cache records. 
    fn getGlyphId(self: *Self, cp: u21) FontError!?u16 {
        // This mapping only supports utf basic codepoints.
        if (cp > std.math.maxInt(u16)) {
            return null;
        }
        const S = struct {
            fn compare(ctx: *const SegmentGlyphMapper, target_cp: u16, idx: usize) std.math.Order {
                const end_code = fromBigU16(&ctx.data[ctx.offset + 14 + idx*2]);
                const start_code = fromBigU16(&ctx.data[ctx.offset + 16 + (ctx.num_segments+idx)*2]);
                if (target_cp > end_code) {
                    return .gt;
                } else if (target_cp < start_code) {
                    return .lt;
                } else {
                    return .eq;
                }
            }
        };
        const cp16 = @intCast(u16, cp);
        if (algo.binarySearchByIndex(self.num_segments, cp16, self, S.compare)) |i| {
            // log.debug("i {}", .{i});
            const start_code = fromBigU16(&self.data[self.offset + 16 + (self.num_segments+i)*2]);
            const id_range_offsets_loc = self.offset + 16 + (self.num_segments*3)*2;
            const id_range_offset_loc = id_range_offsets_loc + i*2;
            const id_range_offset = fromBigU16(&self.data[id_range_offset_loc]);
            if (id_range_offset == 0) {
                // Use id_delta
                const id_deltas_loc = self.offset + 16 + (self.num_segments*2)*2;
                // although id_delta a i16, since it's modulo 2^8, we can interpret it as u16 and just add with overflow.
                const id_delta = fromBigU16(&self.data[id_deltas_loc + i*2]);
                var res: u16 = undefined;
                _ = @addWithOverflow(u16, id_delta, cp16, &res);
                return res;
            } else {
                // Use id_range_offset
                const glyph_offset = id_range_offset_loc + (cp16 - start_code)*2 + id_range_offset;
                return fromBigU16(&self.data[glyph_offset]);
            }
        } else {
            return null;
        }
    }
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-12-segmented-coverage
// NotoColorEmoji.ttf
const SegmentedCoverageGlyphMapper = struct {
    const Self = @This();

    data: []const u8,
    offset: usize,
    num_group_records: usize,

    fn init(self: *Self, data: []const u8, offset: usize) void {
        self.* = .{
            .data = data,
            .num_group_records = fromBigU32(&data[offset+12]),
            .offset = offset,
        };
        // log.debug("num group records: {}", .{new.num_group_records});
    }

    // Does not cache records. Every query scans through all records for the codepoint.
    fn getGlyphId(self: *Self, cp: u21) FontError!?u16 {
        // TODO: groups are sorted by start char code so we can do binary search.
        var i: usize = 0;
        while (i < self.num_group_records) : (i += 1) {
            const g_offset = self.offset + 16 + i*12;
            const start_cp = fromBigU32(&self.data[g_offset]);
            const end_cp = fromBigU32(&self.data[g_offset+4]);
            // log.debug("range {} {}", .{start_cp, end_cp});
            if (cp >= start_cp and cp <= end_cp) {
                const start_glyph_id = fromBigU32(&self.data[g_offset+8]);
                const res = @intCast(u16, start_glyph_id + (cp - start_cp));
                // log.debug("{} - {} {} - {} {}", .{cp, start_cp, end_cp, start_glyph_id, res});
                return res;
            }
        }
        return null;
    }
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-14-unicode-variation-sequences
// https://ccjktype.fonts.adobe.com/2013/05/opentype-cmap-table-ramblings.html
// format 14 (not independent, works in conjunction with format 4 or 12)
// NotoColorEmoji.ttf
const UvsGlyphMapper = struct {
    const Self = @This();

    data: []const u8,
    offset: usize,

    num_records: usize,

    fn init(self: *Self, data: []const u8, offset: usize) *Self {
        self.* = .{
            .data = data,
            .num_records = fromBigU32(&data.value[offset+6]),
            .offset = offset,
        };
        log.debug("num uvs records: {}", .{self.num_records});
    }

    // Does not cache records. Every query scans through all records for the codepoint + variation selector.
    // Starting working on this but realized this isn't what we need atm since we don't support UVS.
    // Unfinished, code left here to resume if we do support UVS.
    fn getGlyphId(self: *Self, cp: u21, var_selector: u21) FontError!u16 {
        var i: usize = 0;
        while (i < self.num_records) : (i += 1) {
            const vs_offset = self.offset + 10 + i*11;

            const record_var_selector = fromBigU24(&self.data.value[vs_offset]);
            if (var_selector != record_var_selector) {
                continue;
            }

            const def_offset = fromBigU32(&self.data.value[vs_offset+3]);
            const non_def_offset = fromBigU32(&self.data.value[vs_offset+7]);
            log.debug("def/nondef {} {}", .{def_offset, non_def_offset});
            if (def_offset > 0) {
                const num_range_records = fromBigU32(&self.data.value[self.offset + def_offset]);

                var range_i: usize = 0;
                while (range_i < num_range_records) : (range_i += 1) {
                    // TODO: since range records are ordered by starting cp, we can do binary search.
                    const r_offset = self.offset + def_offset + 4 + range_i*4;
                    const start_cp = fromBigU24(&self.data.value[r_offset]);
                    const additional_count = self.data.value[r_offset+3];
                    if (cp >= start_cp and cp <= start_cp + additional_count) {
                        // TODO
                    }
                    // log.debug("range: {} {}", .{start_cp, additional_count});
                }
                log.debug("num ranges: {}", .{num_range_records});
            } else if (non_def_offset > 0) {
                log.debug("TODO: non default uvs table", .{});
                return FontError.Unsupported;
            } else {
                return FontError.InvalidFont;
            }
        }
        return 0;
    }
};

fn fromBigUTF16(alloc: *std.mem.Allocator, data: []const u8) string.BoxString {
    const utf16 = std.mem.bytesAsSlice(u16, data);

    const aligned = alloc.alloc(u16, utf16.len) catch unreachable;
    defer alloc.free(aligned);
    for (utf16) |it, i| {
        aligned[i] = it;
    }

    const utf8 = stdx.unicode.utf16beToUtf8Alloc(alloc, aligned) catch unreachable;
    return string.BoxString.init(alloc, utf8);
}

// TTF files use big endian.
fn fromBigU16(ptr: *const u8) u16 {
    const arr_ptr = @intToPtr(*[2]u8, @ptrToInt(ptr));
    return std.mem.readIntBig(u16, arr_ptr);
}

fn fromBigI16(ptr: *const u8) i16 {
    const arr_ptr = @intToPtr(*[2]u8, @ptrToInt(ptr));
    return std.mem.readIntBig(i16, arr_ptr);
}

fn fromBigU24(ptr: *const u8) u24 {
    const arr_ptr = @intToPtr(*[3]u8, @ptrToInt(ptr));
    return std.mem.readIntBig(u24, arr_ptr);
}

fn fromBigU32(ptr: *const u8) u32 {
    const arr_ptr = @intToPtr(*[4]u8, @ptrToInt(ptr));
    return std.mem.readIntBig(u32, arr_ptr);
}