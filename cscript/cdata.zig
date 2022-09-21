const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const parser_ = @import("parser.zig");
const Parser = parser_.Parser;
const log = stdx.log.scoped(.cdata);

pub const EncodeListContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    fn indent(self: *EncodeListContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }
    
    pub fn encodeDict(self: *EncodeListContext, val: anytype, encode_dict: fn (*EncodeDictContext, @TypeOf(val)) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.write("{\n");

        var dict_ctx = EncodeDictContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_dict(&dict_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }
};

pub const EncodeValueContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    fn indent(self: *EncodeValueContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }

    pub fn encodeAsDict(self: *EncodeValueContext, val: anytype, encode_dict: fn (*EncodeDictContext, @TypeOf(val)) anyerror!void) !void {
        _ = try self.writer.write("{\n");

        var dict_ctx = EncodeDictContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_dict(&dict_ctx, val);

        try self.indent();
        _ = try self.writer.write("}");
    }
};

pub const EncodeDictContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    fn indent(self: *EncodeDictContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }

    pub fn encodeSlice(self: *EncodeDictContext, key: []const u8, slice: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: [\n", .{key});

        var val_ctx = EncodeValueContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        self.cur_indent += 1;
        for (slice) |it| {
            try self.indent();
            try encode_value(&val_ctx, it);
            _ = try self.writer.write("\n");
        }
        self.cur_indent -= 1;

        try self.indent();
        _ = try self.writer.write("]\n");
    }

    pub fn encodeAsList(self: *EncodeDictContext, key: []const u8, val: anytype, encode_list: fn (*EncodeListContext, @TypeOf(val)) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: [\n", .{key});

        var list_ctx = EncodeListContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_list(&list_ctx, val);

        try self.indent();
        _ = try self.writer.write("]\n");
    }

    pub fn encodeAsDict(self: *EncodeDictContext, key: []const u8, val: anytype, encode_dict: fn (*EncodeDictContext, @TypeOf(val)) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: {{\n", .{key});

        var dict_ctx = EncodeDictContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_dict(&dict_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    pub fn encodeAsDict2(self: *EncodeDictContext, key: []const u8, val: anytype, encode_dict: fn (*EncodeDictContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{ key });

        _ = try self.writer.write("{\n");

        var dict_ctx = EncodeDictContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_dict(&dict_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    pub fn encode(self: *EncodeDictContext, key: []const u8, val: anytype) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try self.encodeValue(val);
    }

    pub fn encodeString(self: *EncodeDictContext, key: []const u8, val: []const u8) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try self.encodeString_(val);
    }

    pub fn encodeAnyToDict(self: *EncodeDictContext, key: anytype, val: anytype, encode_dict: fn (*EncodeDictContext, @TypeOf(val)) anyerror!void) !void {
        try self.encodeAnyKey_(key);
        _ = try self.writer.write("{\n");

        var dict_ctx = EncodeDictContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_dict(&dict_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    fn encodeAnyKey_(self: *EncodeDictContext, key: anytype) !void {
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
    }

    pub fn encodeAnyToString(self: *EncodeDictContext, key: anytype, val: []const u8) !void {
        try self.encodeAnyKey_(key);
        try self.encodeString_(val);
    }

    fn encodeString_(self:* EncodeDictContext, str: []const u8) !void {
        self.tmp_buf.clearRetainingCapacity();
        if (std.mem.indexOfScalar(u8, str, '\n') == null) {
            _ = stdx.mem.replaceIntoList(u8, str, "'", "\\'", self.tmp_buf);
            _ = try self.writer.print("'{s}'\n", .{self.tmp_buf.items});
        } else {
            _ = stdx.mem.replaceIntoList(u8, str, "`", "\\`", self.tmp_buf);
            _ = try self.writer.print("`{s}`\n", .{self.tmp_buf.items});
        }
    }

    pub fn encodeAnyToValue(self: *EncodeDictContext, key: anytype, val: anytype) !void {
        try self.encodeAnyKey_(key);
        try self.encodeValue(val);
    }

    fn encodeValue(self: *EncodeDictContext, val: anytype) !void {
        const T = @TypeOf(val);
        switch (T) {
            u32 => {
                _ = try self.writer.print("{}\n", .{val});
            },
            else => {
                @compileError("unsupported: " ++ @typeName(T));
            },
        }
    }
};

pub fn encode(alloc: std.mem.Allocator, user_ctx: ?*anyopaque, val: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    var tmp_buf = std.ArrayList(u8).init(alloc);
    defer tmp_buf.deinit();
    var val_ctx = EncodeValueContext{
        .writer = buf.writer(alloc),
        .cur_indent = 0,
        .user_ctx = user_ctx,
        .tmp_buf = &tmp_buf,
    };
    try encode_value(&val_ctx, val);
    return buf.toOwnedSlice(alloc);
}

pub const DecodeListIR = struct {
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

    pub fn deinit(self: *DecodeListIR) void {
        self.alloc.free(self.arr);
    }

    pub fn decodeDict(self: DecodeListIR, idx: u32) !DecodeDictIR {
        if (idx < self.arr.len) {
            return try DecodeDictIR.init(self.alloc, self.res, self.arr[idx]);
        } else return error.NoSuchEntry;
    }
};

pub const DecodeDictIR = struct {
    alloc: std.mem.Allocator,
    res: parser_.ResultView,

    /// Preserve order of entries.
    map: std.StringArrayHashMapUnmanaged(parser_.NodeId),

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

    pub fn deinit(self: *DecodeDictIR) void {
        self.map.deinit(self.alloc);
    }

    pub fn iterator(self: DecodeDictIR) std.StringArrayHashMapUnmanaged(parser_.NodeId).Iterator {
        return self.map.iterator();
    }
    
    pub fn allocString(self: DecodeDictIR, key: []const u8) ![]const u8 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.res.nodes.items[val_id];
            if (val_n.node_t == .string) {
                const token_s = self.res.getTokenString(val_n.start_token);
                var buf = std.ArrayList(u8).init(self.alloc);
                defer buf.deinit();
                _ = stdx.mem.replaceIntoList(u8, token_s[1..token_s.len-1], "\\'", "'", &buf);
                const replaces = std.mem.replace(u8, buf.items, "\\`", "`", buf.items);
                buf.items.len -= replaces;
                return buf.toOwnedSlice();
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
pub fn decodeDict(alloc: std.mem.Allocator, parser: *Parser, ctx: anytype, out: anytype, decode_dict: fn (DecodeDictIR, @TypeOf(ctx), @TypeOf(out)) anyerror!void, cdata: []const u8) !void {
    const res = try parser.parse(cdata);
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
    try decode_dict(dict, ctx, out);
}

const TestRoot = struct {
    name: []const u8,
    list: []const TestListItem,
    map: []const TestMapItem,
};

const TestListItem = struct {
    field: u32,
};

const TestMapItem = struct {
    id: u32,
    val: []const u8,
};

test "encode" {
    var root = TestRoot{
        .name = "project",
        .list = &.{
            .{ .field = 1 },
            .{ .field = 2 },
        },
        .map = &.{
            .{ .id = 1, .val = "foo" },
            .{ .id = 2, .val = "bar" },
            .{ .id = 3, .val = "ba'r" },
            .{ .id = 4, .val = "bar\nbar" },
            .{ .id = 5, .val = "bar `bar`\nbar" },
        },
    };

    const S = struct {
        fn encodeRoot(ctx: *EncodeDictContext, val: TestRoot) !void {
            try ctx.encodeString("name", val.name);
            try ctx.encodeSlice("list", val.list, encodeValue);
            try ctx.encodeAsDict("map", val.map, encodeMap);
        }
        fn encodeMap(ctx: *EncodeDictContext, val: []const TestMapItem) !void {
            for (val) |it| {
                try ctx.encodeAnyToString(it.id, it.val);
            }
        }
        fn encodeItem(ctx: *EncodeDictContext, val: TestListItem) !void {
            try ctx.encode("field", val.field);
        }
        fn encodeValue(ctx: *EncodeValueContext, val: anytype) !void {
            const T = @TypeOf(val);
            if (T == TestRoot) {
                try ctx.encodeAsDict(val, encodeRoot);
            } else if (T == TestListItem) {
                try ctx.encodeAsDict(val, encodeItem);
            } else {
                stdx.panicFmt("unsupported: {s}", .{@typeName(T)});
            }
        }
    };

    const res = try encode(t.alloc, null, root, S.encodeValue);
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
        \\        3: 'ba\'r'
        \\        4: `bar
        \\bar`
        \\        5: `bar \`bar\`
        \\bar`
        \\    }
        \\}
    );
}

test "decodeDict" {
    const S = struct {
        fn decodeRoot(dict: DecodeDictIR, _: void, root: *TestRoot) !void {
            root.name = try dict.allocString("name");

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

            var map_items: std.ArrayListUnmanaged(TestMapItem) = .{};
            var map_dict = try dict.decodeDict("map");
            defer map_dict.deinit();
            var iter = map_dict.iterator();
            while (iter.next()) |entry| {
                const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
                const value = try map_dict.allocString(entry.key_ptr.*);
                try map_items.append(t.alloc, .{ .id = key, .val = value });
            }
            root.map = map_items.toOwnedSlice(t.alloc);
        }
    };

    var parser = Parser.init(t.alloc);
    defer parser.deinit();

    var root: TestRoot = undefined;
    try decodeDict(t.alloc, &parser, {}, &root, S.decodeRoot, 
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
        \\        3: 'ba\'r'
        \\        4: `bar
        \\bar`
        \\        5: `bar \`bar\`
        \\bar`
        \\    }
        \\}
    );
    defer {
        t.alloc.free(root.list);
        t.alloc.free(root.name);
        for (root.map) |it| {
            t.alloc.free(it.val);
        }
        t.alloc.free(root.map);
    }

    try t.eqStr(root.name, "project");
    try t.eq(root.list[0].field, 1);
    try t.eq(root.list[1].field, 2);
    try t.eq(root.map.len, 5);
    try t.eq(root.map[0].id, 1);
    try t.eqStr(root.map[0].val, "foo");
    try t.eq(root.map[1].id, 2);
    try t.eqStr(root.map[1].val, "bar");
    try t.eq(root.map[2].id, 3);
    try t.eqStr(root.map[2].val, "ba'r");
    try t.eq(root.map[3].id, 4);
    try t.eqStr(root.map[3].val, "bar\nbar");
    try t.eq(root.map[4].id, 5);
    try t.eqStr(root.map[4].val, "bar `bar`\nbar");
}