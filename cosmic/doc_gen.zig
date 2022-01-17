const std = @import("std");
const stdx = @import("stdx");
const process = std.process;
const build_options = @import("build_options");

const runtime = @import("runtime.zig");
const printFmt = runtime.printFmt;
const log = std.log.scoped(.doc_gen);
const api = @import("api.zig");

const doc_versions: []const DocVersion = &.{
    DocVersion{ .name = build_options.VersionName, .url = "/docs" },
};

const modules: []const []const u8 = &.{
    "cs_core",
    "cs_files",
    "cs_graphics",
    "cs_http",
    "cs_window",
};

pub fn main() !void {
    // Fast temporary memory allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    if (args.len == 1) {
        printFmt("Provide directory path.\n", .{});
        process.exit(0);
    }
    var arg_idx: usize = 1;
    const docs_path = nextArg(args, &arg_idx).?;
    try std.fs.cwd().makePath(docs_path);

    // Copy over assets.
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "vendor/docs/pico.min.css"), std.fs.cwd(), fromPath(alloc, docs_path, "pico.min.css"), .{});
    try std.fs.cwd().copyFile(fromBuildRoot(alloc, "vendor/docs/docs.css"), std.fs.cwd(), fromPath(alloc, docs_path, "docs.css"), .{});

    const api_model = try genApiModel(alloc);

    var ctx = Context{
        .alloc = alloc,
        .buf = std.ArrayList(u8).init(alloc),
    };
    try genHtml(&ctx, api_model);

    const index_path = try std.fs.path.join(alloc, &.{ docs_path, "index.html" });
    try std.fs.cwd().writeFile(index_path, ctx.buf.items);
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

// Parses comments and uses comptime to create api model.
fn genApiModel(alloc: std.mem.Allocator) !std.StringHashMap(Module) {
    var res = std.StringHashMap(Module).init(alloc);

    const srcs: []const []const u8 = &.{
        "cosmic/api.zig",
    };

    for (srcs) |src_path| {
        const path = fromBuildRoot(alloc, src_path);

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
                    _ = module;

                    var found_title = false;
                    var found_ns = false;
                    var found_name = false;
                    var desc_buf = std.ArrayList(u8).init(alloc);

                    // Parse module metadata from doc comments.
                    var cur_tok = tree.firstToken(member);
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

                    if (!found_title) std.debug.panic("{s} is missing @title", .{ident_str});
                    if (!found_ns) std.debug.panic("{s} is missing @ns", .{ident_str});
                    if (!found_name) std.debug.panic("{s} is missing @name", .{ident_str});

                    // Parse functions and types.



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

fn isModuleName(name: []const u8) bool {
    for (modules) |mod_name| {
        if (std.mem.eql(u8, mod_name, name)) {
            return true;
        }
    }
    return false;
}

fn genHtml(ctx: *Context, api_model: std.StringHashMap(Module)) !void {
    // Head.
    ctx.writeFmt(
        \\<!DOCTYPE html>
        \\<html data-theme="light">
        \\<head>
        \\  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1">
        \\  <link rel="stylesheet" href="pico.min.css" />
        \\  <link rel="stylesheet" href="docs.css" />
        \\  <title>Cosmic Docs | {s}</title>
        \\</head>
        \\<body>
        \\  <main class="container">
        , .{ build_options.VersionName }
    );
    defer ctx.write(
        \\  </main>
        \\</body>
        \\</html>
    );

    // Side nav.
    ctx.write(
        \\<aside>
        \\<h3><span class="primary">Cosmic</span> Docs</h3>
        \\<nav>
    );
    ctx.write("<select>");
    for (doc_versions) |version| {
        ctx.writeFmt("<option value=\"{s}\">{s}</option>", .{version.url, version.name});
    }
    ctx.write("</select>");
    {
        // General.
        ctx.write("<section><div class=\"category secondary\">General</div><ul>");
        ctx.write("<li><a href=\"#start\">Getting Started</a></li>");
        ctx.write("<li><a href=\"#tools\">Tools</a></li>");
        ctx.write("</ul></section>");

        // Api.
        ctx.write("<section><div class=\"category secondary\">API</div><ul>");
        for (modules) |mod_name| {
            const mod = api_model.get(mod_name).?;
            _ = mod;

            ctx.writeFmt("<li><a href=\"#{s}\">{s}</a></li>", .{mod.name, mod.ns});
        }
        ctx.write("</ul></section>");
    }
    ctx.write("</nav></aside>");

    // Main.
    ctx.write(
        \\<div class="docs">
    );
    {
        for (modules) |mod_name| {
            const module = api_model.get(mod_name).?;
            _ = module;

            ctx.writeFmt(
                \\<section id="{s}">
                \\<mark class="ns">{s}</mark>
                \\<h3>{s}</h3>
                \\<p>{s}</p>
                \\</section>
                , .{ module.name, module.ns, module.title, module.desc }
            );
        }
    }
    ctx.write(
        \\</div>
    );
}

fn nextArg(args: [][]const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
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
    funcs: []const FunctionInfo,
};

const FunctionInfo = struct {
    desc: []const u8,
    name: []const u8,
    args: []const []const u8,
    ret: []const u8,
};