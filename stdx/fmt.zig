const std = @import("std");
const stdx = @import("stdx.zig");
const log = stdx.log.scoped(.fmt);

fn FormatItemFn(comptime Context: type, comptime Writer: type) type {
    return fn(Context, Writer, u32, []const u8, std.fmt.FormatOptions) anyerror!void;
}

pub fn formatDynamic(writer: anytype, fmt: []const u8, ctx: anytype, formatItem: FormatItemFn(@TypeOf(ctx), @TypeOf(writer))) !void {
    var arg_idx: u32 = 0;

    var i: u32 = 0;
    while (i < fmt.len) {
        const start_index = i;

        while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        var end_index = i;
        var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        // Write out the literal
        if (start_index != end_index) {
            try writer.writeAll(fmt[start_index..end_index]);
        }

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            log.debug("missing opening {{", .{});
            return error.InvalidFormat;
        }

        // Get past the {
        std.debug.assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            log.debug("missing closing }}", .{});
            return error.InvalidFormat;
        }

        // Get past the }
        std.debug.assert(fmt[i] == '}');
        i += 1;

        const placeholder = try parsePlaceholder(fmt[fmt_begin..fmt_end]);
        const arg_pos = switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            // .named => |arg_name| meta.fieldIndex(ArgsType, arg_name) orelse
            //     @compileError("no argument with name '" ++ arg_name ++ "'"),
            else => return error.Unsupported,
        };
        _ = arg_pos;
        // TODO: Support arg position.

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            // .named => |arg_name| blk: {
            //     const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
            //         @compileError("no argument with name '" ++ arg_name ++ "'");
            //     _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
            //     break :blk @field(args, arg_name);
            // },
            else => return error.Unsupported,
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            // .named => |arg_name| blk: {
            //     const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
            //         @compileError("no argument with name '" ++ arg_name ++ "'");
            //     _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
            //     break :blk @field(args, arg_name);
            // },
            else => return error.Unsupported,
        };

        try formatItem(ctx, writer, arg_idx, placeholder.specifier_arg,
            std.fmt.FormatOptions{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            });
        arg_idx += 1;
    }
}

const Placeholder = struct {
    specifier_arg: []const u8,
    fill: u8,
    alignment: std.fmt.Alignment,
    arg: Specifier,
    width: Specifier,
    precision: Specifier,
};

fn parsePlaceholder(str: []const u8) !Placeholder {
    var parser = Parser{ .buf = str };

    // Parse the positional argument number
    const arg = try parser.specifier();

    // Parse the format specifier
    const specifier_arg = parser.until(':');

    // Skip the colon, if present
    if (parser.char()) |ch| {
        if (ch != ':') {
            log.debug("expected : or }}, found '{c}'", .{ch});
            return error.InvalidFormat;
        }
    }

    // Parse the fill character
    // The fill parameter requires the alignment parameter to be specified
    // too
    const fill = if (parser.peek(1)) |ch|
        switch (ch) {
            '<', '^', '>' => parser.char().?,
            else => ' ',
        }
    else
        ' ';

    // Parse the alignment parameter
    const alignment: std.fmt.Alignment = if (parser.peek(0)) |ch| init: {
        switch (ch) {
            '<', '^', '>' => _ = parser.char(),
            else => {},
        }
        break :init switch (ch) {
            '<' => std.fmt.Alignment.Left,
            '^' => std.fmt.Alignment.Center,
            else => std.fmt.Alignment.Right,
        };
    } else .Right;

    // Parse the width parameter
    const width = try parser.specifier();

    // Skip the dot, if present
    if (parser.char()) |ch| {
        if (ch != '.') {
            log.debug("expected . or }}, found '{c}'", .{ch});
            return error.InvalidFormat;
        }
    }

    // Parse the precision parameter
    const precision = try parser.specifier();

    if (parser.char()) |ch| {
        log.debug("extraneous trailing character '{c}'", .{ch});
        return error.InvalidFormat;
    }

    return Placeholder{
        .specifier_arg = specifier_arg[0..specifier_arg.len],
        .fill = fill,
        .alignment = alignment,
        .arg = arg,
        .width = width,
        .precision = precision,
    };
}

const Parser = struct {
    buf: []const u8,
    pos: usize = 0,

    // Returns a decimal number or null if the current character is not a
    // digit
    fn number(self: *@This()) ?usize {
        var r: ?usize = null;

        while (self.pos < self.buf.len) : (self.pos += 1) {
            switch (self.buf[self.pos]) {
                '0'...'9' => {
                    if (r == null) r = 0;
                    r.? *= 10;
                    r.? += self.buf[self.pos] - '0';
                },
                else => break,
            }
        }

        return r;
    }

    // Returns a substring of the input starting from the current position
    // and ending where `ch` is found or until the end if not found
    fn until(self: *@This(), ch: u8) []const u8 {
        const start = self.pos;

        if (start >= self.buf.len)
            return &[_]u8{};

        while (self.pos < self.buf.len) : (self.pos += 1) {
            if (self.buf[self.pos] == ch) break;
        }
        return self.buf[start..self.pos];
    }

    // Returns one character, if available
    fn char(self: *@This()) ?u8 {
        if (self.pos < self.buf.len) {
            const ch = self.buf[self.pos];
            self.pos += 1;
            return ch;
        }
        return null;
    }

    fn maybe(self: *@This(), val: u8) bool {
        if (self.pos < self.buf.len and self.buf[self.pos] == val) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    // Returns a decimal number or null if the current character is not a
    // digit
    fn specifier(self: *@This()) !Specifier {
        if (self.maybe('[')) {
            const arg_name = self.until(']');

            if (!self.maybe(']')) {
                log.debug("Expected closing }}", .{});
                return error.ParseError;
            }

            return Specifier{ .named = arg_name };
        }
        if (self.number()) |i|
            return Specifier{ .number = i };

        return Specifier{ .none = {} };
    }

    // Returns the n-th next character or null if that's past the end
    fn peek(self: *@This(), n: usize) ?u8 {
        return if (self.pos + n < self.buf.len) self.buf[self.pos + n] else null;
    }
};

const Specifier = union(enum) {
    none,
    number: usize,
    named: []const u8,
};