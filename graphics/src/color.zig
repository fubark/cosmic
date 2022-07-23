const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;
const log = stdx.log.scoped(.color);

pub const Color = extern union {
    channels: packed struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
    value: u32,

    // Standard colors.
    pub const StdRed = init(255, 0, 0, 255);
    pub const StdYellow = init(255, 255, 0, 255);
    pub const StdGreen = init(0, 255, 0, 255);
    pub const StdCyan = init(0, 255, 255, 255);
    pub const StdBlue = init(0, 0, 255, 255);
    pub const StdMagenta = init(255, 0, 255, 255);

    // Prettier default colors from raylib + extras.
    pub const LightGray = init(200, 200, 200, 255);
    pub const Gray = init(130, 130, 130, 255);
    pub const DarkGray = init(80, 80, 80, 255);
    pub const Yellow = init(253, 249, 0, 255);
    pub const Gold = init(255, 203, 0, 255);
    pub const Orange = init(255, 161, 0, 255);
    pub const Pink = init(255, 109, 194, 255);
    pub const Red = init(230, 41, 55, 255);
    pub const Maroon = init(190, 33, 55, 255);
    pub const Green = init(0, 228, 48, 255);
    pub const Lime = init(0, 158, 47, 255);
    pub const DarkGreen = init(0, 117, 44, 255);
    pub const SkyBlue = init(102, 191, 255, 255);
    pub const Blue = init(0, 121, 241, 255);
    pub const RoyalBlue = init(65, 105, 225, 255);
    pub const DarkBlue = init(0, 82, 172, 255);
    pub const Purple = init(200, 122, 255, 255);
    pub const Violet = init(135, 60, 190, 255);
    pub const DarkPurple = init(112, 31, 126, 255);
    pub const Beige = init(211, 176, 131, 255);
    pub const Brown = init(127, 106, 79, 255);
    pub const DarkBrown = init(76, 63, 47, 255);

    pub const White = init(255, 255, 255, 255);
    pub const Black = init(0, 0, 0, 255);
    pub const Transparent = init(0, 0, 0, 0);
    pub const Magenta = init(255, 0, 255, 255);

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{
            .channels = .{ .r = r, .g = g, .b = b, .a = a },
        };
    }

    pub fn initFloat(r: f32, g: f32, b: f32, a: f32) Color {
        return init(@floatToInt(u8, r * 255), @floatToInt(u8, g * 255), @floatToInt(u8, b * 255), @floatToInt(u8, a * 255));
    }

    pub fn withAlpha(self: Color, a: u8) Color {
        return init(self.channels.r, self.channels.g, self.channels.b, a);
    }

    pub fn lighter(self: Color) Color {
        return self.tint(0.25);
    }

    pub fn darker(self: Color) Color {
        return self.shade(0.25);
    }

    // Increase darkness, amt range: [0,1]
    pub fn shade(self: Color, amt: f32) Color {
        const factor = 1 - amt;
        return init(@floatToInt(u8, @intToFloat(f32, self.channels.r) * factor), @floatToInt(u8, @intToFloat(f32, self.channels.g) * factor), @floatToInt(u8, @intToFloat(f32, self.channels.b) * factor), self.channels.a);
    }

    // Increase lightness, amt range: [0,1]
    pub fn tint(self: Color, amt: f32) Color {
        return init(@floatToInt(u8, @intToFloat(f32, 255 - self.channels.r) * amt) + self.channels.r, @floatToInt(u8, @intToFloat(f32, 255 - self.channels.g) * amt) + self.channels.g, @floatToInt(u8, @intToFloat(f32, 255 - self.channels.b) * amt) + self.channels.b, self.channels.a);
    }

    pub fn parse(str: []const u8) !Color {
        switch (str.len) {
            3 => {
                // RGB
                const r = try std.fmt.parseInt(u8, str[0..1], 16);
                const g = try std.fmt.parseInt(u8, str[1..2], 16);
                const b = try std.fmt.parseInt(u8, str[2..3], 16);
                return init(r << 4 | r, g << 4 | g, b << 4 | b, 255);
            },
            4 => {
                // #RGB
                if (str[0] == '#') {
                    return parse(str[1..]);
                } else {
                    // log.debug("{s}", .{str});
                    return error.UnknownFormat;
                }
            },
            6 => {
                // RRGGBB
                const r = try std.fmt.parseInt(u8, str[0..2], 16);
                const g = try std.fmt.parseInt(u8, str[2..4], 16);
                const b = try std.fmt.parseInt(u8, str[4..6], 16);
                return init(r, g, b, 255);
            },
            7 => {
                // #RRGGBB
                if (str[0] == '#') {
                    return parse(str[1..]);
                } else {
                    return error.UnknownFormat;
                }
            },
            else => return error.UnknownFormat,
        }
    }

    pub fn toHsv(self: Color) [3]f32 {
        const r = @intToFloat(f32, self.channels.r) / 255;
        const g = @intToFloat(f32, self.channels.g) / 255;
        const b = @intToFloat(f32, self.channels.b) / 255;
 
        const cmax = std.math.max(r, std.math.max(g, b));
        const cmin = std.math.min(r, std.math.min(g, b));
        const diff = cmax - cmin;
        var h = @as(f32, -1);
        var s = @as(f32, -1);
         
        if (cmax == cmin) {
            h = 0;
        } else if (cmax == r) {
            h = @mod(60 * ((g - b) / diff) + 360, 360);
        } else if (cmax == g) {
            h = @mod(60 * ((b - r) / diff) + 120, 360);
        } else if (cmax == b) {
            h = @mod(60 * ((r - g) / diff) + 240, 360);
        }
 
        if (cmax == 0) {
            s = 0;
        } else {
            s = (diff / cmax);
        }
 
        const v = cmax;
        return [_]f32{ h, s, v };
    }

    /// hue is in degrees [0,360]
    /// assumes sat/val are clamped to: [0,1]
    pub fn fromHsv(hue: f32, sat: f32, val: f32) Color {
        var res = Color.init(0, 0, 0, 255);

        // red
        var k = std.math.mod(f32, 5 + hue/60.0, 6) catch unreachable;
        var t_ = 4.0 - k;
        k = if (t_ < k) t_ else k;
        k = if (k < 1) k else 1;
        k = if (k > 0) k else 0;
        res.channels.r = @floatToInt(u8, (val - val*sat*k)*255.0);

        // green
        k = std.math.mod(f32, 3.0 + hue/60.0, 6) catch unreachable;
        t_ = 4.0 - k;
        k = if (t_ < k) t_ else k;
        k = if (k < 1) k else 1;
        k = if (k > 0) k else 0;
        res.channels.g = @floatToInt(u8, (val - val*sat*k)*255.0);

        // blue
        k = std.math.mod(f32, 1.0 + hue/60.0, 6) catch unreachable;
        t_ = 4.0 - k;
        k = if (t_ < k) t_ else k;
        k = if (k < 1) k else 1;
        k = if (k > 0) k else 0;
        res.channels.b = @floatToInt(u8, (val - val*sat*k)*255.0);

        return res;
    }

    test "hsv to rgb" {
        try t.eq(Color.fromHsv(270, 0.6, 0.7).channels, Color.init(124, 71, 178, 255).channels);
    }

    pub fn fromU32(c: u32) Color {
        return init(
            @intCast(u8, c >> 24),
            @intCast(u8, c >> 16 & 0xFF),
            @intCast(u8, c >> 8 & 0xFF),
            @intCast(u8, c & 0xFF),
        );
    }

    pub fn toU32(self: Color) u32 {
        return @as(u32, self.channels.r) << 24 | @as(u24, self.channels.g) << 16 | @as(u16, self.channels.b) << 8 | self.channels.a;
    }

    pub fn toFloatArray(self: Color) [4]f32 {
        return .{
            @intToFloat(f32, self.channels.r) / 255,
            @intToFloat(f32, self.channels.g) / 255,
            @intToFloat(f32, self.channels.b) / 255,
            @intToFloat(f32, self.channels.a) / 255,
        };
    }
};

test "Color.Transparent" {
    try t.eq(0, Color.Transparent.value);
}

test "Color struct size" {
    try t.eq(@sizeOf(Color), 4);
}

test "toU32 fromU32" {
    const i = Color.Red.toU32();
    try t.eq(Color.fromU32(i).channels, Color.Red.channels);
}

test "from 3 digit hex" {
    try t.eq((try Color.parse("#ABC")).channels, Color.init(170, 187, 204, 255).channels);
}
