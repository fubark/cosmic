const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const parser_ = @import("parser.zig");
const Parser = parser_.Parser;
const log = stdx.log.scoped(.cdata);

const EncodeValueContext = struct {
    encode_dict_ctx: *EncodeDictContext,
    writer: std.ArrayListUnmanaged(u8).Writer,
    cur_indent: *u32,

    fn indent(self: *EncodeValueContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent.* * 4);
    }

    pub fn encodeDict(self: *EncodeValueContext, val: anytype, encode_dict: fn (*EncodeDictContext, anytype) anyerror!void) !void {
        _ = try self.writer.write("{\n");

        self.cur_indent.* += 1;
        try encode_dict(self.encode_dict_ctx, val);
        self.cur_indent.* -= 1;

        try self.indent();
        _ = try self.writer.write("}");
    }
};

const EncodeDictContext = struct {
    encode_value_ctx: *EncodeValueContext,
    writer: std.ArrayListUnmanaged(u8).Writer,
    cur_indent: *u32,

    fn indent(self: *EncodeDictContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent.* * 4);
    }

    pub fn encodeString(self: *EncodeDictContext, key: []const u8, val: []const u8) !void {
        _ = try self.writer.print("{s}: '{s}'\n", .{key, val});
    }

    pub fn encodeList(self: *EncodeDictContext, key: []const u8, val: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: [\n", .{key});

        self.cur_indent.* += 1;
        for (val) |it| {
            try self.indent();
            try encode_value(self.encode_value_ctx, it);
            _ = try self.writer.write("\n");
        }
        self.cur_indent.* -= 1;

        try self.indent();
        _ = try self.writer.write("]\n");
    }

    pub fn encodeDict(self: *EncodeDictContext, key: []const u8, val: anytype, encode_dict: fn (*EncodeDictContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: {{\n", .{key});

        self.cur_indent.* += 1;
        try encode_dict(self, val);
        self.cur_indent.* -= 1;

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    pub fn encode(self: *EncodeDictContext, key: []const u8, val: anytype) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try self.encodeEntryEnd(val);
    }

    pub fn encodeAnyKey(self: *EncodeDictContext, key: anytype, val: anytype) !void {
        try self.indent();
        const T = @TypeOf(key);
        switch (T) {
            // Don't support string types since there can be many variations. Use `encode` instead.
            u32 => {
                _ = try self.writer.print("{}: ", .{key});
            },
            else => {
                log.debug("unsupported: {s}", .{@typeName(T)});
                return error.Unsupported;
            },
        }
        try self.encodeEntryEnd(val);
    }

    fn encodeEntryEnd(self: *EncodeDictContext, val: anytype) !void {
        const T = @TypeOf(val);
        switch (T) {
            []const u8 => {
                _ = try self.writer.print("'{s}'\n", .{val});
            },
            u32 => {
                _ = try self.writer.print("{}\n", .{val});
            },
            else => {
                log.debug("unsupported: {s}", .{@typeName(T)});
                return error.Unsupported;
            },
        }
    }
};

pub fn encode(alloc: std.mem.Allocator, val: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    var cur_indent: u32 = 0;
    var encode_dict_ctx = EncodeDictContext{
        .encode_value_ctx = undefined,
        .writer = buf.writer(alloc),
        .cur_indent = &cur_indent,
    };
    var encode_val_ctx = EncodeValueContext{
        .encode_dict_ctx = &encode_dict_ctx,
        .writer = buf.writer(alloc),
        .cur_indent = &cur_indent,
    };
    encode_dict_ctx.encode_value_ctx = &encode_val_ctx;
        
    try encode_value(&encode_val_ctx, val);
    return buf.toOwnedSlice(alloc);
}

const DecodeListIR = struct {
    alloc: std.mem.Allocator,
    res: parser_.ResultView,
    arr: []const parser_.NodeId,

    fn init(alloc: std.mem.Allocator, res: parser_.ResultView, list_id: parser_.NodeId) !DecodeListIR {
        const list = res.nodes.items[list_id];
        if (list.node_t != .arr_literal) {
            return error.NotAList;
        }

        var new = DecodeListIR{
            .alloc = alloc,
            .res = res,
            .arr = &.{},
        };

        // Construct list.
        var buf: std.ArrayListUnmanaged(parser_.NodeId) = .{};
        var item_id = list.head.child_head;
        while (item_id != NullId) {
            const item = res.nodes.items[item_id];
            try buf.append(alloc, item_id);
            item_id = item.next;
        }
        new.arr = buf.toOwnedSlice(alloc);
        return new;
    }

    fn deinit(self: *DecodeListIR) void {
        self.alloc.free(self.arr);
    }

    pub fn decodeDict(self: DecodeListIR, idx: u32) !DecodeDictIR {
        if (idx < self.arr.len) {
            return try DecodeDictIR.init(self.alloc, self.res, self.arr[idx]);
        } else return error.NoSuchEntry;
    }
};

const DecodeDictIR = struct {
    alloc: std.mem.Allocator,
    res: parser_.ResultView,
    map: std.StringHashMapUnmanaged(parser_.NodeId),

    fn init(alloc: std.mem.Allocator, res: parser_.ResultView, dict_id: parser_.NodeId) !DecodeDictIR {
        const dict = res.nodes.items[dict_id];
        if (dict.node_t != .dict_literal) {
            return error.NotADict;
        }

        var new = DecodeDictIR{
            .alloc = alloc,
            .res = res,
            .map = .{},
        };

        // Parse literal into map.
        var entry_id = dict.head.child_head;
        while (entry_id != NullId) {
            const entry = res.nodes.items[entry_id];
            const key = res.nodes.items[entry.head.left_right.left];
            switch (key.node_t) {
                .number,
                .ident => {
                    const str = res.getTokenString(key.start_token);
                    try new.map.put(alloc, str, entry.head.left_right.right);
                },
                else => return error.Unsupported,
            }
            entry_id = entry.next;
        }
        return new;
    }

    fn deinit(self: *DecodeDictIR) void {
        self.map.deinit(self.alloc);
    }
    
    pub fn dupeString(self: DecodeDictIR, key: []const u8) ![]const u8 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.res.nodes.items[val_id];
            if (val_n.node_t == .string) {
                const token_s = self.res.getTokenString(val_n.start_token);
                return try self.alloc.dupe(u8, token_s[1..token_s.len-1]);
            } else return error.NotAString;
        } else return error.NoSuchEntry;
    }

    pub fn getString(self: DecodeDictIR, key: []const u8) ![]const u8 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.res.nodes.items[val_id];
            if (val_n.node_t == .string) {
                const token_s = self.res.getTokenString(val_n.start_token);
                return token_s[1..token_s.len-1];
            } else return error.NotAString;
        } else return error.NoSuchEntry;
    }

    pub fn getU32(self: DecodeDictIR, key: []const u8) !u32 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.res.nodes.items[val_id];
            if (val_n.node_t == .number) {
                const token_s = self.res.getTokenString(val_n.start_token);
                return try std.fmt.parseInt(u32, token_s, 10);
            } else return error.NotANumber;
        } else return error.NoSuchEntry;
    }

    pub fn decodeList(self: DecodeDictIR, key: []const u8) !DecodeListIR {
        if (self.map.get(key)) |val_id| {
            return DecodeListIR.init(self.alloc, self.res, val_id);
        } else return error.NoSuchEntry;
    }

    pub fn decodeDict(self: DecodeDictIR, key: []const u8) !DecodeDictIR {
        if (self.map.get(key)) |val_id| {
            return try DecodeDictIR.init(self.alloc, self.res, val_id);
        } else return error.NoSuchEntry;
    }
};

const NullId = std.math.maxInt(u32);

// Currently uses cscript parser.
pub fn decodeDict(alloc: std.mem.Allocator, parser: *Parser, out: anytype, decode_dict: fn (DecodeDictIR, @TypeOf(out)) anyerror!void, cdata: []const u8) !void {
    const res = parser.parse(cdata);
    if (res.has_error) {
        log.debug("Parse Error: {s}", .{res.err_msg});
        return error.ParseError;
    }

    const root = res.nodes.items[res.root_id];
    if (root.head.child_head == NullId) {
        return error.NotADict;
    }
    const first_stmt = res.nodes.items[root.head.child_head];
    if (first_stmt.node_t != .expr_stmt) {
        return error.NotADict;
    }

    var dict = try DecodeDictIR.init(alloc, res, first_stmt.head.child_head);
    defer dict.deinit();
    try decode_dict(dict, out);
}

const TestRoot = struct {
    name: []const u8,
    list: []const TestListItem,
    map: std.AutoHashMapUnmanaged(u32, []const u8),

    fn deinit(self: *TestRoot, alloc: std.mem.Allocator) void {
        self.map.deinit(alloc);
    }
};

const TestListItem = struct {
    field: u32,
};

test "encode" {
    var root = TestRoot{
        .name = "project",
        .list = &.{
            .{ .field = 1 },
            .{ .field = 2 },
        },
        .map = .{},
    };
    try root.map.put(t.alloc, 1, "foo");
    try root.map.put(t.alloc, 2, "bar");
    defer root.deinit(t.alloc);

    const S = struct {
        fn encodeDict(ctx: *EncodeDictContext, val: anytype) !void {
            const T = @TypeOf(val);
            if (T == TestRoot) {
                try ctx.encode("name", val.name);
                try ctx.encodeList("list", val.list, encodeValue);
                try ctx.encodeDict("map", val.map, encodeDict);
            } else if (T == TestListItem) {
                try ctx.encode("field", val.field);
            } else if (T == std.AutoHashMapUnmanaged(u32, []const u8)) {
                var iter = val.iterator();
                while (iter.next()) |e| {
                    try ctx.encodeAnyKey(e.key_ptr.*, e.value_ptr.*);
                }
            } else {
                stdx.panicFmt("unsupported: {s}", .{@typeName(T)});
            }
        }
        fn encodeValue(ctx: *EncodeValueContext, val: anytype) !void {
            const T = @TypeOf(val);
            if (T == TestRoot) {
                try ctx.encodeDict(val, encodeDict);
            } else if (T == TestListItem) {
                try ctx.encodeDict(val, encodeDict);
            } else if (T == std.AutoHashMapUnmanaged(u32, []const u8)) {
                try ctx.encodeDict(val, encodeDict);
            } else {
                stdx.panicFmt("unsupported: {s}", .{@typeName(T)});
            }
        }
    };

    const res = try encode(t.alloc, root, S.encodeValue);
    defer t.alloc.free(res);
    try t.eqStr(res,
        \\{
        \\    name: 'project'
        \\    list: [
        \\        {
        \\            field: 1
        \\        }
        \\        {
        \\            field: 2
        \\        }
        \\    ]
        \\    map: {
        \\        1: 'foo'
        \\        2: 'bar'
        \\    }
        \\}
    );
}

test "decodeDict" {
    const S = struct {
        fn decodeRoot(dict: DecodeDictIR, root: *TestRoot) !void {
            root.name = try dict.getString("name");

            var list: std.ArrayListUnmanaged(TestListItem) = .{};
            var list_ir = try dict.decodeList("list");
            defer list_ir.deinit();
            var i: u32 = 0;
            while (i < list_ir.arr.len) : (i += 1) {
                var item: TestListItem = undefined;
                var item_dict = try list_ir.decodeDict(i);
                defer item_dict.deinit();
                item.field = try item_dict.getU32("field");
                try list.append(t.alloc, item);
            }

            root.list = list.toOwnedSlice(t.alloc);
            root.map = .{};
            var map_dict = try dict.decodeDict("map");
            defer map_dict.deinit();
            var iter = map_dict.map.iterator();
            while (iter.next()) |entry| {
                const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
                const value = try map_dict.getString(entry.key_ptr.*);
                try root.map.put(t.alloc, key, value);
            }
        }
    };

    var parser = Parser.init(t.alloc);
    defer parser.deinit();

    var root: TestRoot = undefined;
    try decodeDict(t.alloc, &parser, &root, S.decodeRoot, 
        \\{
        \\    name: 'project'
        \\    list: [
        \\        {
        \\            field: 1
        \\        }
        \\        {
        \\            field: 2
        \\        }
        \\    ]
        \\    map: {
        \\        1: 'foo'
        \\        2: 'bar'
        \\    }
        \\}
    );
    defer {
        t.alloc.free(root.list);
        root.deinit(t.alloc);
    }

    try t.eqStr(root.name, "project");
    try t.eq(root.list[0].field, 1);
    try t.eq(root.list[1].field, 2);
    try t.eq(root.map.size, 2);
    try t.eqStr(root.map.get(1).?, "foo");
    try t.eqStr(root.map.get(2).?, "bar");
}