const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("v8");

const api = @import("api.zig");
const api_graphics = @import("api_graphics.zig");
const log = stdx.log.scoped(.js_gen);

pub fn generate(alloc: std.mem.Allocator, path: []const u8) !void {
    const src = genApiSupplementJs(alloc);
    defer alloc.free(src);
    try std.fs.cwd().writeFile(path, src);
}

// cosmic 

/// Generates additional js code from api.zig declarations.
/// - Generates async functions that return a v8.Promise.
///   Errors from these promises should be recreated on the js side to create a proper stack trace.
/// - TODO: Generate non native js functions. Basically the api functions in api_init.js
fn genApiSupplementJs(alloc: std.mem.Allocator) []const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    const writer = buf.writer();

    const Packages: []const type = &.{
        api, 
        api_graphics,
    };

    var pkg_to_ns = std.StringHashMap([]const u8).init(alloc);
    pkg_to_ns.put("cs_audio", "audio") catch unreachable;
    pkg_to_ns.put("cs_core", "core") catch unreachable;
    pkg_to_ns.put("cs_files", "files") catch unreachable;
    pkg_to_ns.put("cs_graphics", "graphics") catch unreachable;
    pkg_to_ns.put("cs_http", "http") catch unreachable;
    pkg_to_ns.put("cs_input", "input") catch unreachable;
    pkg_to_ns.put("cs_net", "net") catch unreachable;
    pkg_to_ns.put("cs_test", "test") catch unreachable;
    pkg_to_ns.put("cs_window", "window") catch unreachable;
    pkg_to_ns.put("cs_worker", "worker") catch unreachable;
    pkg_to_ns.put("cs_dev", "dev") catch unreachable;

    writer.print(
        \\"use strict";
        \\
    , .{}) catch unreachable;

    inline for (Packages) |Pkg| {
        const PkgDecls = comptime std.meta.declarations(Pkg);
        inline for (PkgDecls) |PkgDecl| {
            if (PkgDecl.is_pub) {
                const PkgDeclType = @field(Pkg, PkgDecl.name);
                if (@typeInfo(@TypeOf(PkgDeclType)) == .Type) {
                    if (std.mem.startsWith(u8, PkgDecl.name, "cs_")) {
                        const ns = pkg_to_ns.get(PkgDecl.name) orelse {
                            log.debug("missing ns for {s}", .{PkgDecl.name});
                            unreachable;
                        };
                        const CsPkg = PkgDeclType;
                        const Decls = comptime std.meta.declarations(CsPkg);
                        inline for (Decls) |Decl| {
                            if (Decl.is_pub) {
                                const DeclType = @TypeOf(@field(CsPkg, Decl.name));
                                if (@typeInfo(DeclType) == .Fn) {
                                    // If return type is a v8.Promise, wrap it as an async function.
                                    if (@typeInfo(DeclType).Fn.return_type.? == v8.Promise) {
                                        const NumParams = @typeInfo(DeclType).Fn.args.len;
                                        const Params = switch(NumParams) {
                                            0 => "",
                                            1 => "p1",
                                            2 => "p1, p2",
                                            3 => "p1, p2, p3",
                                            else => unreachable,
                                        };
                                        writer.print(
                                            \\cs.{s}.{s} = async function({s}) {{
                                            \\    try {{ return await cs.{s}._{s}({s}) }} catch (e) {{ throw new ApiError(e) }}
                                            \\}}
                                            \\
                                            , .{
                                                ns, Decl.name, Params,
                                                ns, Decl.name, Params,
                                            }
                                        ) catch unreachable;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return buf.toOwnedSlice();
}