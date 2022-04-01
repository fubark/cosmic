const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const process = std.process;
const build_options = @import("build_options");
const graphics = @import("graphics");
const v8 = @import("v8");

const runtime = @import("../cosmic/runtime.zig");
const printFmt = runtime.printFmt;
const log = std.log.scoped(.doc_gen);
const gen = @import("../cosmic/gen.zig");
const api = @import("../cosmic/api.zig");
const api_graphics = @import("../cosmic/api_graphics.zig");
const cs_graphics = api_graphics.cs_graphics;

const doc_versions: []const DocVersion = &.{
    DocVersion{ .name = build_options.VersionName, .url = "/docs" },
};

const ModuleId = []const u8;
const modules: []const ModuleId = &.{
    "cs_audio",
    "cs_core",
    "cs_files",
    "cs_graphics",
    "cs_http",
    "cs_input",
    "cs_net",
    "cs_test",
    "cs_window",
    "cs_worker",
};

pub fn generate(alloc: std.mem.Allocator, docs_path: []const u8) !void {
    try std.fs.cwd().makePath(docs_path);

    // Copy over assets.
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "docs/pico.min.css"), std.fs.cwd(), fromPath(alloc, docs_path, "pico.min.css"), .{});
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "docs/docs.css"), std.fs.cwd(), fromPath(alloc, docs_path, "docs.css"), .{});
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "docs/hljs-tomorrow.css"), std.fs.cwd(), fromPath(alloc, docs_path, "hljs-tomorrow.css"), .{});
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "docs/hljs-tomorrow-night-blue.css"), std.fs.cwd(), fromPath(alloc, docs_path, "hljs-tomorrow-night-blue.css"), .{});
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "docs/highlight.min.js"), std.fs.cwd(), fromPath(alloc, docs_path, "highlight.min.js"), .{});

    const api_model = try genApiModel(alloc);

    var ctx = Context{
        .alloc = alloc,
        .buf = std.ArrayList(u8).init(alloc),
    };

    // Generate a page per module.
    for (modules) |mod_id| {
        const mod = api_model.get(mod_id).?;
        try genHtml(&ctx, mod_id, api_model);

        const page_file = try std.fmt.allocPrint(alloc, "{s}.html", .{ mod.name });
        const page_path = try std.fs.path.join(alloc, &.{ docs_path, page_file });
        try std.fs.cwd().writeFile(page_path, ctx.buf.toOwnedSlice());
    }

    // Generate the index page.
    try genHtml(&ctx, null, api_model);
    const index_path = try std.fs.path.join(alloc, &.{ docs_path, "index.html" });
    try std.fs.cwd().writeFile(index_path, ctx.buf.toOwnedSlice());
}

fn fromPath(alloc: std.mem.Allocator, path: []const u8, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(alloc, &[_][]const u8{ path, rel_path }) catch unreachable;
}

fn fromBuildRoot(alloc: std.mem.Allocator, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(alloc, &[_][]const u8{ build_options.BuildRoot, rel_path }) catch unreachable;
}

const Context = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    buf: std.ArrayList(u8),

    fn write(self: *Self, str: []const u8) void {
        self.buf.appendSlice(str) catch unreachable;
    }

    fn writeFmt(self: *Self, comptime format: []const u8, args: anytype) void {
        const str = std.fmt.allocPrint(self.alloc, format, args) catch unreachable;
        self.buf.appendSlice(str) catch unreachable;
    }
};

const Source = struct {
    path: []const u8,
    package: type,
};

// Parses comments and uses comptime to create api model.
fn genApiModel(alloc: std.mem.Allocator) !std.StringHashMap(Module) {
    var res = std.StringHashMap(Module).init(alloc);

    const srcs: []const Source = &.{
        .{ .path = "cosmic/api.zig", .package = api },
        .{ .path = "cosmic/api_graphics.zig", .package = api_graphics },
    };

    inline for (srcs) |src| {
        const path = fromBuildRoot(alloc, src.path);

        const file = std.fs.openFileAbsolute(path, .{ .read = true, .write = false }) catch unreachable;
        defer file.close();
        const source = file.readToEndAllocOptions(alloc, 10e6, null, @alignOf(u8), 0) catch unreachable;
        defer alloc.free(source);

        var tree = std.zig.parse(alloc, source) catch unreachable;
        defer tree.deinit(alloc);
        if (tree.errors.len > 0) {
            for (tree.errors) |err| {
                log.debug("Parse error: {s}", .{err});
            }
            unreachable;
        }

        const root_members = tree.rootDecls();
        for (root_members) |member| {
            if (tree.nodes.items(.tag)[member] == .simple_var_decl) {
                const ident_tok = tree.nodes.items(.main_token)[member] + 1;
                const ident_str = tree.tokenSlice(ident_tok);
                if (isModuleName(ident_str)) {
                    var module: Module = undefined;
                    log.debug("Parsing {s}", .{ident_str});

                    // Parse module metadata from doc comments.
                    try parseModuleMetadata(alloc, tree, member, ident_str, &module);

                    var funcs = std.ArrayList(FunctionInfo).init(alloc);
                    var types = std.ArrayList(TypeInfo).init(alloc);

                    const container_node = tree.nodes.items(.data)[member].rhs;

                    // Parse functions and types.
                    const Decls = comptime std.meta.declarations(src.package);
                    log.debug("{s} {}", .{ident_str, Decls.len});
                    inline for (Decls) |Decl| {
                        if (Decl.is_pub and Decl.data == .Type) {
                            if (std.mem.eql(u8, Decl.name, ident_str)) {
                                const ModuleDecls = comptime std.meta.declarations(Decl.data.Type);
                                inline for (ModuleDecls) |ModuleDecl| {
                                    if (ModuleDecl.is_pub) {
                                        if (ModuleDecl.data == .Fn) {
                                            const mb_func = try parseFunctionInfo(ModuleDecl, alloc, tree, container_node);
                                            if (mb_func) |func| {
                                                try funcs.append(func);
                                            }
                                        } else if (ModuleDecl.data == .Type) {
                                            // Type Declaration.
                                            var type_info = TypeInfo{
                                                .name = ModuleDecl.name,
                                                .desc = "",
                                                .fields = &.{},
                                                .constants = &.{},
                                                .methods = &.{},
                                                .is_enum = @typeInfo(ModuleDecl.data.Type) == .Enum,
                                                .is_enum_string_sumtype = @hasDecl(ModuleDecl.data.Type, "IsStringSumType"),
                                                .enum_values = &.{},
                                            };

                                            const child = findContainerChild(tree, container_node, ModuleDecl.name);
                                            const data = try parseMetadata(alloc, tree, child);
                                            type_info.desc = data.desc;

                                            // log.debug("{s} {}", .{ModuleDecl.name, tree.nodes.items(.tag)[child]});
                                            const type_container = tree.simpleVarDecl(child).ast.init_node;

                                            const AType = ModuleDecl.data.Type;
                                            parseTypeDecls(alloc, AType, tree, type_container, &type_info);

                                            if (@typeInfo(ModuleDecl.data.Type) == .Struct) {
                                                type_info.fields = parseTypeFields(alloc, ModuleDecl.data.Type) catch unreachable;
                                            } else if (@typeInfo(ModuleDecl.data.Type) == .Enum) {
                                                const to_lower = type_info.is_enum_string_sumtype;
                                                type_info.enum_values = getEnumValues(alloc, ModuleDecl.data.Type, to_lower) catch unreachable;
                                            }

                                            try types.append(type_info);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    module.funcs = funcs.toOwnedSlice();
                    module.types = types.toOwnedSlice();

                    try res.put(try alloc.dupe(u8, ident_str), module);
                }
            }
        }
    }

    for (modules) |mod_name| {
        if (!res.contains(mod_name)) {
            std.debug.panic("No api model for: {s}", .{mod_name});
        }
    }
    return res;
}

fn parseModuleMetadata(alloc: std.mem.Allocator, tree: std.zig.Ast, mod_node: std.zig.Ast.Node.Index, mod_name: []const u8, module: *Module) !void {
    var found_title = false;
    var found_ns = false;
    var found_name = false;
    var desc_buf = std.ArrayList(u8).init(alloc);

    var cur_tok = tree.firstToken(mod_node);
    while (cur_tok > 0) {
        cur_tok -= 1;
        if (tree.tokens.items(.tag)[cur_tok] == .doc_comment) {
            const comment = tree.tokenSlice(cur_tok);

            if (std.mem.indexOf(u8, comment, "@title")) |idx| {
                const title = std.mem.trim(u8, comment[idx + "@title".len..], " ");
                module.title = try alloc.dupe(u8, title);
                found_title = true;
                continue;
            }
            if (std.mem.indexOf(u8, comment, "@ns")) |idx| {
                const ns = std.mem.trim(u8, comment[idx + "@ns".len..], " ");
                module.ns = try alloc.dupe(u8, ns);
                found_ns = true;
                continue;
            }
            if (std.mem.indexOf(u8, comment, "@name")) |idx| {
                const name = std.mem.trim(u8, comment[idx + "@name".len..], " ");
                module.name = try alloc.dupe(u8, name);
                found_name = true;
                continue;
            }

            // Accumulate desc.
            if (desc_buf.items.len > 0) {
                // try desc_buf.insertSlice(0, "<br />");
                try desc_buf.insertSlice(0, " ");
            }
            try desc_buf.insertSlice(0, std.mem.trim(u8, comment[3..], " "));
        } else {
            break;
        }
    }
    module.desc = desc_buf.toOwnedSlice();

    if (!found_title) std.debug.panic("{s} is missing @title", .{mod_name});
    if (!found_ns) std.debug.panic("{s} is missing @ns", .{mod_name});
    if (!found_name) std.debug.panic("{s} is missing @name", .{mod_name});
}

pub fn parseTypeDecls(alloc: std.mem.Allocator, comptime T: type, tree: std.zig.Ast, type_container: std.zig.Ast.Node.Index, out: *TypeInfo) void {
    const Decls = comptime std.meta.declarations(T);
    var methods = std.ArrayList(FunctionInfo).init(alloc);
    var constants = std.ArrayList([]const u8).init(alloc);
    inline for (Decls) |Decl| {
        if (Decl.is_pub) {
            if (Decl.data == .Fn) {
                // Assume method.
                const mb_type_func = parseFunctionInfo(Decl, alloc, tree, type_container) catch unreachable;
                if (mb_type_func) |type_func| {
                    methods.append(type_func) catch unreachable;
                }
            } else if (Decl.data == .Var) {
                // Constant.
                const mb_constant = parseConstantInfo(Decl, alloc, tree, type_container) catch unreachable;
                if (mb_constant) |constant| {
                    constants.append(constant) catch unreachable;
                }
            }
        }
    }
    out.methods = methods.toOwnedSlice();
    out.constants = constants.toOwnedSlice();
}

fn parseTypeFields(alloc: std.mem.Allocator, comptime T: type) ![]const TypeField {
    var fields = std.ArrayList(TypeField).init(alloc);
    const Fields = std.meta.fields(T);
    inline for (Fields) |Field| {
        var field = TypeField{
            .name = Field.name,
            .type_name = "",
            .default_value = null,
            .optional = @typeInfo(Field.field_type) == .Optional,
        };
        if (@typeInfo(Field.field_type) == .Optional) {
            field.type_name = getJsTypeName(@typeInfo(Field.field_type).Optional.child);
        } else {
            field.type_name = getJsTypeName(Field.field_type);
        }
        if (Field.default_value != null) {
            field.default_value = try std.fmt.allocPrint(alloc, "{any}", .{Field.default_value.?});
        }
        try fields.append(field);
    }
    return fields.toOwnedSlice();
}

fn getEnumValues(alloc: std.mem.Allocator, comptime E: type, to_lower: bool) ![]const []const u8 {
    var values = std.ArrayList([]const u8).init(alloc);
    const Fields = std.meta.fields(E);
    inline for (Fields) |Field| {
        if (to_lower) {
            try values.append(runtime.ctLower(Field.name));
        } else {
            try values.append(Field.name);
        }
    }
    return values.toOwnedSlice();
}

fn parseConstantInfo(comptime VarDecl: std.builtin.TypeInfo.Declaration, alloc: std.mem.Allocator, tree: std.zig.Ast, container_node: std.zig.Ast.Node.Index) !?[]const u8 {
    _ = alloc;
    _ = tree;
    _ = container_node;
    if (std.mem.eql(u8, VarDecl.name, "IsStringSumType")) {
        return null;
    } else if (std.mem.eql(u8, VarDecl.name, "Default")) {
        return null;
    }
    // For now, just return the name.
    return VarDecl.name;
}

// container_node is the parent container that declares the function.
fn parseFunctionInfo(comptime FnDecl: std.builtin.TypeInfo.Declaration, alloc: std.mem.Allocator, tree: std.zig.Ast, container_node: std.zig.Ast.Node.Index) !?FunctionInfo {
    var func = FunctionInfo{
        .desc = "",
        .name = FnDecl.name,
        .params = &.{},
        .ret = undefined,
    };

    // Extract params.
    const ArgsTuple = std.meta.ArgsTuple(FnDecl.data.Fn.fn_type);
    const ArgFields = std.meta.fields(ArgsTuple);
    const FuncInfo = comptime gen.getJsFuncInfo(ArgFields);

    var params = std.ArrayList(FunctionParamInfo).init(alloc);

    // arg_names are currently empty.
    // https://github.com/ziglang/zig/issues/8259

    inline for (ArgFields) |Field, i| {
        if (FuncInfo.param_tags[i] == .Param) {
            const BaseType = if (@typeInfo(Field.field_type) == .Optional) @typeInfo(Field.field_type).Optional.child else Field.field_type;
            try params.append(.{
                .param_name = "",
                //.param_name = FnDecl.data.Fn.arg_names[Idx],
                .type_name = getJsTypeName(BaseType),
                .type_decl_mod = null,
                .optional = @typeInfo(Field.field_type) == .Optional,
            });
            // log.debug("{s}", .{@typeName(Field.field_type)});
        }
    }
    func.params = params.toOwnedSlice();

    const valid = try extractFunctionMetadata(alloc, tree, container_node, &func);
    if (!valid) return null;

    // Extract return.
    const ReturnType = FnDecl.data.Fn.return_type;
    if (@typeInfo(ReturnType) == .Optional) {
        const BaseType = @typeInfo(ReturnType).Optional.child;
        func.ret = .{
            .type_name = if (BaseType == void) null else getJsTypeName(BaseType),
            .type_decl_mod = null,
            .can_be_null = true,
        };
    } else if (@typeInfo(ReturnType) == .ErrorUnion) {
        const BaseType = @typeInfo(ReturnType).ErrorUnion.payload;
        // We are moving away from exceptions so an error union can return null.
        func.ret = .{
            .type_name = if (BaseType == void) null else getJsTypeName(BaseType),
            .type_decl_mod = null,
            .can_be_null = true,
        };
    } else {
        func.ret = .{
            .type_name = if (ReturnType == void) null else getJsTypeName(ReturnType),
            .type_decl_mod = null,
            .can_be_null = false,
        };
    }
    return func;
}

fn getJsTypeName(comptime T: type) []const u8 {
    return switch (T) {
        []const f32 => "Array",

        v8.Uint8Array,
        runtime.Uint8Array => "Uint8Array",
        []const api.cs_files.FileEntry => "[]FileEntry",
        api.cs_files.FileEntry => "FileEntry",

        v8.String,
        ds.Box([]const u8),
        []const u8 => "string",

        bool => "boolean",

        v8.Promise => "Promise",

        u8,
        f32,
        u32,
        i16,
        i32,
        u53,
        u16 => "number",

        u64 => "BigInt",

        v8.Value,
        *const anyopaque => "any",

        *const v8.C_FunctionCallbackInfo => "...any",

        std.StringHashMap([]const u8),
        v8.Persistent(v8.Object),
        v8.Object => "object",

        v8.Function => "function",

        api.cs_http.RequestOptions => "RequestOptions",
        stdx.http.Response => "Response",
        api.cs_files.PathInfo => "PathInfo",
        graphics.Image => "Image",
        graphics.Color => "Color",
        cs_graphics.Color => "Color",
        api.cs_files.FileKind => "FileKind",
        api.cs_http.RequestMethod => "RequestMethod",
        api.cs_http.ContentType => "ContentType",
        api.cs_input.MouseButton => "MouseButton",
        api.cs_input.Key => "Key",

        // Shouldn't be available but needed before @internal is parsed.
        std.mem.Allocator => "Allocator",

        else => {
            if (@typeInfo(T) == .Struct) {
                if (@hasDecl(T, "ManagedStruct")) {
                    return getJsTypeName(std.meta.fieldInfo(T, .val).field_type);
                } else if (@hasDecl(T, "ManagedSlice")) {
                    return getJsTypeName(std.meta.fieldInfo(T, .slice).field_type);
                } else {
                    return @typeName(T);
                }
            } else if (@typeInfo(T) == .Enum) {
                return @typeName(T);
            }
            std.debug.panic("Can't convert to js type name: {s}", .{ @typeName(T) });
        }
    };
}

fn findContainerChild(tree: std.zig.Ast, container_node: std.zig.Ast.Node.Index, name: []const u8) std.zig.Ast.Node.Index {
    var container: std.zig.Ast.full.ContainerDecl = undefined;
    if (tree.nodes.items(.tag)[container_node] == .container_decl) {
        container = tree.containerDecl(container_node);
    } else if (tree.nodes.items(.tag)[container_node] == .container_decl_trailing) {
        container = tree.containerDecl(container_node);
    } else if (tree.nodes.items(.tag)[container_node] == .container_decl_two_trailing) {
        var buf: [2]std.zig.Ast.Node.Index = undefined;
        container = tree.containerDeclTwo(&buf, container_node);
    } else if (tree.nodes.items(.tag)[container_node] == .container_decl_two) {
        var buf: [2]std.zig.Ast.Node.Index = undefined;
        container = tree.containerDeclTwo(&buf, container_node);
    } else {
        log.debug("Skipping {}", .{tree.nodes.items(.tag)[container_node]});
        unreachable;
    }

    for (container.ast.members) |member| {
        if (tree.nodes.items(.tag)[member] == .simple_var_decl) {
            // const a = struct {};
            const ident_tok = tree.nodes.items(.main_token)[member] + 1;
            if (std.mem.eql(u8, tree.tokenSlice(ident_tok), name)) {
                return member;
            }
        } else if (tree.nodes.items(.tag)[member] == .fn_decl) {
            // Filter by fn name.
            const proto_id = tree.nodes.items(.data)[member].lhs;
            if (tree.nodes.items(.tag)[proto_id] == .fn_proto_multi) {
                const fn_proto = tree.fnProtoMulti(proto_id);
                if (std.mem.eql(u8, tree.tokenSlice(fn_proto.name_token.?), name)) {
                    return proto_id;
                }
            } else if (tree.nodes.items(.tag)[proto_id] == .fn_proto_simple) {
                var buf: std.zig.Ast.Node.Index = undefined;
                const fn_proto = tree.fnProtoSimple(&buf, proto_id);
                if (std.mem.eql(u8, tree.tokenSlice(fn_proto.name_token.?), name)) {
                    return proto_id;
                }
            } else if (tree.nodes.items(.tag)[proto_id] == .fn_proto_one) {
                var buf: std.zig.Ast.Node.Index = undefined;
                const fn_proto = tree.fnProtoOne(&buf, proto_id);
                if (std.mem.eql(u8, tree.tokenSlice(fn_proto.name_token.?), name)) {
                    return proto_id;
                }
            } else {
                log.debug("unsupported: {}", .{tree.nodes.items(.tag)[proto_id]});
                continue;
            }
        }
        // log.debug("{}", .{tree.nodes.items(.tag)[member]});
    }
    std.debug.panic("Could not find: {s}", .{name});
}

const Metadata = struct {
    desc: []const u8,
    param_names: []const []const u8,
    internal: bool,
};

// Parse metadata from doc comments.
fn parseMetadata(alloc: std.mem.Allocator, tree: std.zig.Ast, node: std.zig.Ast.Node.Index) !Metadata {
    var res: Metadata = undefined;
    var buf = std.ArrayList(u8).init(alloc);

    var params = std.ArrayList([]const u8).init(alloc);

    // Start with the first token since we want to break on the first non comment.
    var cur_tok = tree.firstToken(node);
    while (cur_tok > 0) {
        cur_tok -= 1;
        if (tree.tokens.items(.tag)[cur_tok] == .doc_comment) {
            const comment = tree.tokenSlice(cur_tok);
            if (std.mem.indexOf(u8, comment, "@internal")) |_| {
                // Skip this function.
                res.internal = true;
                continue;
            }
            if (std.mem.indexOf(u8, comment, "@param")) |idx| {
                const name = std.mem.trim(u8, comment[idx + "@param".len..], " ");
                try params.insert(0, try alloc.dupe(u8, name));
                continue;
            }
            // Accumulate desc.
            if (buf.items.len > 0) {
                try buf.insertSlice(0, " ");
            }
            try buf.insertSlice(0, std.mem.trim(u8, comment[3..], " "));
        } else {
            break;
        }
    }
    res.desc = buf.toOwnedSlice();
    res.param_names = params.toOwnedSlice();
    return res;
}

// Finds the function in the container ast and extracts metadata in comments.
fn extractFunctionMetadata(alloc: std.mem.Allocator, tree: std.zig.Ast, container_node: std.zig.Ast.Node.Index, func: *FunctionInfo) !bool {
    // Skip devmode _DEV functions.
    if (std.mem.endsWith(u8, func.name, "_DEV")) {
        return false;
    }
    const child = findContainerChild(tree, container_node, func.name);

    const data = try parseMetadata(alloc, tree, child);
    if (data.internal) {
        return false;
    }
    func.desc = data.desc;
    for (data.param_names) |name, i| {
        if (i < func.params.len) {
            func.params[i].param_name = name;
        }
    }

    if (func.desc.len == 0) {
        log.debug("metadata not found for: {s}", .{func.name});
    }
    return true;
}

fn isModuleName(name: []const u8) bool {
    for (modules) |mod_name| {
        if (std.mem.eql(u8, mod_name, name)) {
            return true;
        }
    }
    return false;
}

fn genHtml(ctx: *Context, mb_mod_id: ?ModuleId, api_model: std.StringHashMap(Module)) !void {
    // Head.
    ctx.writeFmt(
        \\<!DOCTYPE html>
        \\<html data-theme="light">
        \\<head>
        \\  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1">
        \\  <link rel="stylesheet" href="pico.min.css" />
        \\  <link rel="stylesheet" href="docs.css" />
        \\  <link rel="stylesheet" href="hljs-tomorrow.css" />
        \\  <link rel="stylesheet" href="hljs-tomorrow-night-blue.css" />
        \\  <title>Cosmic Docs | {s}</title>
        \\  <script>
        \\    // Set correct theme before rest of page loads.
        \\    let theme = window.localStorage.getItem('theme')
        \\    if (!theme) {{
        \\      theme = 'light'
        \\    }}
        \\    document.documentElement.setAttribute('data-theme', theme);
        \\  </script>
        \\</head>
        \\<body>
        \\  <div class="top-nav grid">
        \\    <div><h3><span class="primary">Cosmic</span> Docs</h3></div>
        \\    <div class="top-menu"><a onclick="clickTheme()" href="#" role="button" class="outline">Theme</a></div>
        \\  </div>
        \\  <main class="container-fluid">
        , .{ build_options.VersionName }
    );
    defer ctx.write("</body></html>");

    // Side nav.
    ctx.write(
        \\<aside><div>
        \\<nav>
    );
    ctx.write("<select>");
    for (doc_versions) |version| {
        ctx.writeFmt("<option value=\"{s}\">{s}</option>", .{version.url, version.name});
    }
    ctx.write("</select>");
    {
        // General.
        ctx.write("<section class=\"main-links\"><ul>");
        ctx.write("<li><a href=\"index.html#about\">About</a></li>");
        ctx.write("<li><a href=\"index.html#start\">Getting Started</a></li>");
        ctx.write("<li><a href=\"index.html#tools\">Tools</a></li>");
        ctx.write("<li><a href=\"index.html#tutorial\">Tutorials</a></li>");
        ctx.write("<li><a href=\"index.html#community\">Community</a></li>");
        ctx.write("</ul></section>");

        // Api.
        ctx.write("<section><div class=\"category secondary\">API</div><ul>");
        for (modules) |mod_id| {
            const mod = api_model.get(mod_id).?;
            ctx.writeFmt("<li><a id=\"{s}\" href=\"{s}.html\">{s}</a></li>", .{mod.name, mod.name, mod.ns});
        }
        ctx.write("</ul></section>");
    }
    ctx.write("</nav></div></aside>");

    // Main.
    ctx.write(
        \\<div class="docs">
    );
    {
        if (mb_mod_id) |mod_id| {
            const mod = api_model.get(mod_id).?;
            ctx.writeFmt(
                \\<mark class="ns">{s}</mark>
                \\<h3>{s}</h3>
                \\<p>{s}</p>
                , .{ mod.ns, mod.title, mod.desc }
            );

            // List Functions
            for (mod.funcs) |func| {
                ctx.writeFmt(
                    \\<div class="func">
                    \\  <a id="{s}" href="#"><small class="secondary">{s}.</small>{s}</a> <span class="params">(&nbsp;
                    , .{ func.name, mod.ns, func.name }
                );
                // Params.
                for (func.params) |param, i| {
                    if (i > 0) {
                        ctx.write(", ");
                    }
                    if (param.optional) {
                        ctx.writeFmt("<span class=\"param\">{s}: <span class=\"secondary\">?{s}</span></span>", .{param.param_name, param.type_name});
                    } else {
                        ctx.writeFmt("<span class=\"param\">{s}: <span class=\"secondary\">{s}</span></span>", .{param.param_name, param.type_name});
                    }
                }
                ctx.write(" )</span>");

                // Return.
                const ret_type_name: []const u8 = if (func.ret.type_name) |name| name else "";
                ctx.writeFmt(" <span class=\"return\">{s}</span>", .{ ret_type_name});

                // Description.
                ctx.writeFmt(
                    \\</div>
                    \\<p class="func-desc">{s}</p>
                    , .{ func.desc }
                );
            }

            // List Types.
            for (mod.types) |info| {
                var type_kind: []const u8 = undefined;
                if (info.is_enum) {
                    if (info.is_enum_string_sumtype) {
                        type_kind = "string";
                    } else {
                        type_kind = "enum";
                    }
                } else {
                    type_kind = "object";
                }
                ctx.writeFmt(
                    \\<div class="type">
                    \\  <a id="{s}" href="#"><small class="secondary">{s}</small>.{s}</a> <span class="params">{s}</span>
                    , .{ info.name, mod.ns, info.name, type_kind }
                );

                if (info.is_enum) {
                    if (info.is_enum_string_sumtype) {
                        for (info.enum_values) |value| {
                            ctx.writeFmt(
                                \\<div class="indent field"><span class="primary">"{s}"</span></div>
                                , .{ value }
                            );
                        }
                    } else {
                        for (info.enum_values) |value| {
                            // List enum integers as constants.
                            ctx.writeFmt(
                                \\<div class="constant">
                                \\  <a id="{s}" href="#"><small class="secondary">{s}.</small>{s}.{s}</a>
                                , .{ value, mod.ns, info.name, value}
                            );
                            ctx.write(
                                \\</div>
                            );
                        }
                    }
                } else {
                    for (info.fields) |field| {
                        const optional: []const u8 = if (field.optional) "?" else "";
                        ctx.writeFmt(
                            \\<div class="indent field"><span class="primary">{s}</span>: {s}{s}</div>
                            , .{ field.name, optional, field.type_name }
                        );
                    }
                }

                ctx.writeFmt(
                    \\</div>
                    \\<p class="type-desc">{s}</p>
                    , .{ info.desc }
                );

                // Instance methods.
                for (info.methods) |func| {
                    ctx.writeFmt(
                        \\<div class="func">
                        \\  <a id="{s}" href="#"><small class="secondary">{s}.{s}</small><span class="method">{s}</span></a> <span class="params">(&nbsp;
                        , .{ func.name, mod.ns, info.name, func.name }
                    );
                    // Params.
                    for (func.params) |param, i| {
                        if (i > 0) {
                            ctx.write(", ");
                        }
                        if (param.optional) {
                            ctx.writeFmt("<span class=\"param\">{s}: <span class=\"secondary\">?{s}</span></span>", .{param.param_name, param.type_name});
                        } else {
                            ctx.writeFmt("<span class=\"param\">{s}: <span class=\"secondary\">{s}</span></span>", .{param.param_name, param.type_name});
                        }
                    }
                    ctx.write(" )</span>");

                    // Return.
                    const ret_type_name: []const u8 = if (func.ret.type_name) |name| name else "";
                    ctx.writeFmt(" <span class=\"return\">{s}</span>", .{ret_type_name});

                    // Description.
                    ctx.writeFmt(
                        \\</div>
                        \\<p class="func-desc">{s}</p>
                        , .{ func.desc }
                    );
                }

                // Constants.
                for (info.constants) |constant| {
                    ctx.writeFmt(
                        \\<div class="constant">
                        \\  <a id="{s}" href="#"><small class="secondary">{s}.</small>{s}.{s}</a>
                        , .{ constant, mod.ns, info.name, constant}
                    );

                    ctx.writeFmt(
                        \\</div>
                        \\<p class="constant-desc">{s}</p>
                        , .{ "" }
                    );
                }
            }
        } else {
            // Render index.html
            const content_path = fromBuildRoot(ctx.alloc, "docs/docs_main.html");
            const content = try std.fs.cwd().readFileAlloc(ctx.alloc, content_path, 10e6);
            defer ctx.alloc.free(content);
            ctx.write(content);
        }
    }
    ctx.write(
        \\</div>
    );

    // Right symbol nav.
    if (mb_mod_id) |mod_id| {
        const mod = api_model.get(mod_id).?;
        ctx.write(
            \\<aside class="symbols"><div>
            \\<nav><ul>
        );
        for (mod.funcs) |func| {
            ctx.writeFmt("<li><a href=\"#{s}\">{s}()</a></li>", .{func.name, func.name});
        }
        for (mod.types) |info| {
            ctx.writeFmt("<li><a href=\"#{s}\">{s}</a></li>", .{info.name, info.name});
            for (info.methods) |func| {
                ctx.writeFmt("<li class=\"indent\"><a href=\"#{s}\">{s}()</a></li>", .{func.name, func.name});
            }
            for (info.constants) |constant| {
                ctx.writeFmt("<li><a href=\"#{s}\">{s}.{s}</a></li>", .{constant, info.name, constant});
            }
        }
        ctx.write("</ul></nav></div></aside>");
    }
    ctx.write("</main>");

    // Script
    if (mb_mod_id) |mod_id| {
        const mod = api_model.get(mod_id).?;
        ctx.writeFmt(
            \\ <script>
            \\     document.getElementById('{s}').focus();
            \\ </script>
            , .{mod.name}
        );
    }
    ctx.write(
        \\<script src="highlight.min.js"></script>
        \\<script>
        \\  hljs.highlightAll();
        \\  function clickTheme() {
        \\    if (theme == 'light') {
        \\      theme = 'dark'
        \\    } else {
        \\      theme = 'light'
        \\    }
        \\    window.localStorage.setItem('theme', theme)
        \\    document.documentElement.setAttribute('data-theme', theme)
        \\  }
        \\</script>
    );
}

const DocVersion = struct {
    name: []const u8,
    url: []const u8,
};

const Module = struct {
    ns: []const u8,
    title: []const u8,
    name: []const u8,
    desc: []const u8,

    types: []const TypeInfo,
    funcs: []const FunctionInfo,
};

const TypeInfo = struct {
    name: []const u8,
    desc: []const u8,
    fields: []const TypeField,
    constants: []const []const u8,
    methods: []const FunctionInfo,

    is_enum: bool,

    // Whether the enum is a string sumtype or an actual object with keyed number values.
    is_enum_string_sumtype: bool,
    enum_values: []const []const u8,
};

const TypeField = struct {
    name: []const u8,
    type_name: []const u8,
    optional: bool,
    default_value: ?[]const u8,
};

const FunctionInfo = struct {
    desc: []const u8,
    name: []const u8,
    params: []FunctionParamInfo,
    ret: ReturnInfo,
};

const ReturnInfo = struct {
    // Null type name indicates no return type or undefined.
    type_name: ?[]const u8,
    type_decl_mod: ?ModuleId,
    can_be_null: bool,
};

const FunctionParamInfo = struct {
    param_name: []const u8,
    type_name: []const u8,
    type_decl_mod: ?ModuleId,
    optional: bool,
};