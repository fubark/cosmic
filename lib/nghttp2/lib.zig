const std = @import("std");

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("nghttp2", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

    const c_flags = &[_][]const u8{
        "-DNGHTTP2_STATICLIB=1",
    };

    const c_files = &[_][]const u8{
        // Copied from nghttp2/lib/CMakeLists.txt 
        "nghttp2_pq.c",
        "nghttp2_map.c",
        "nghttp2_queue.c",
        "nghttp2_frame.c",
        "nghttp2_buf.c",
        "nghttp2_stream.c",
        "nghttp2_outbound_item.c",
        "nghttp2_session.c",
        "nghttp2_submit.c",
        "nghttp2_helper.c",
        "nghttp2_npn.c",
        "nghttp2_hd.c",
        "nghttp2_hd_huffman.c",
        "nghttp2_hd_huffman_data.c",
        "nghttp2_version.c",
        "nghttp2_priority_spec.c",
        "nghttp2_option.c",
        "nghttp2_callbacks.c",
        "nghttp2_mem.c",
        "nghttp2_http.c",
        "nghttp2_rcbuf.c",
        "nghttp2_debug.c",
    };

    for (c_files) |file| {
        const path = b.fmt("{s}/vendor/lib/{s}", .{ root(), file });
        lib.addCSourceFile(path, c_flags);
    }

    // lib.disable_sanitize_c = true;

    lib.linkLibC();
    lib.addIncludeDir(fromRoot(b, "vendor/lib/includes"));

    return lib;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep) void {
    const lib = create(step.builder, step.target, step.build_mode) catch unreachable;
    linkLib(step, lib);
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    step.addAssemblyFile(path);
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable);
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ root(), rel_path }) catch unreachable;
}