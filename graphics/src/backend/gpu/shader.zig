const std = @import("std");
const stdx = @import("stdx");
const fatal = stdx.fatal;
const glslang = @import("glslang");

const log = stdx.log.scoped(.shader);

// Example using shaderc on command line:
// glslc -mfmt=num graphics/src/backend/vk/shaders/tex_vert.glsl -o -

pub const Stage = enum(u1) {
    Vertex = 0,
    Fragment = 1,
};

const IncludeContext = struct {
    alloc: std.mem.Allocator,
    mapping: std.StringHashMapUnmanaged([]const u8),
};

const CompileOptions = struct {
    include_map: ?std.StringHashMapUnmanaged([]const u8) = null,
};

/// GLSL to SPIRV.
pub fn compileGLSL(alloc: std.mem.Allocator, stage: Stage, src: [:0]const u8, opts: CompileOptions) ![]const u32 {
    const cstage: c_uint = switch (stage) {
        .Vertex => glslang.GLSLANG_STAGE_VERTEX,
        .Fragment => glslang.GLSLANG_STAGE_FRAGMENT,
    };
    const limits = glslang.glslang_default_resource();

    const S = struct {
        fn includeLocal(ptr: ?*anyopaque, header_name: [*c]const u8, includer_name: [*c]const u8, include_depth: usize) callconv(.C) [*c]glslang.glsl_include_result_t {
            _ = includer_name;
            _ = include_depth;
            const ctx = stdx.mem.ptrCastAlign(*IncludeContext, ptr);
            const res = ctx.alloc.create(glslang.glsl_include_result_t) catch fatal();
            const header_name_slice: []const u8 = std.mem.span(header_name);
            if (ctx.mapping.get(header_name_slice)) |data| {
                res.* = .{
                    .header_name = header_name,
                    .header_data = data.ptr,
                    .header_length = data.len,
                };
            } else {
                res.* = .{
                    // null header_name for failed include.
                    .header_name = null,
                    .header_data = null,
                    .header_length = 0,
                };
            }
            return res;
        }
        fn freeIncludeResult(ptr: ?*anyopaque, res: [*c]glslang.glsl_include_result_t) callconv(.C) c_int {
            const ctx = stdx.mem.ptrCastAlign(*IncludeContext, ptr);
            ctx.alloc.destroy(@ptrCast(*glslang.glsl_include_result_t, res));
            return 1;
        }
    };
    var input = glslang.glslang_input_t{
        .language = glslang.GLSLANG_SOURCE_GLSL,
        .stage = cstage,
        .client = glslang.GLSLANG_CLIENT_VULKAN,
        .client_version = glslang.GLSLANG_TARGET_VULKAN_1_0,
        .target_language = glslang.GLSLANG_TARGET_SPV,
        .target_language_version = glslang.GLSLANG_TARGET_SPV_1_0,
        .code = src.ptr,
        .default_version = 100,
        .default_profile = glslang.GLSLANG_NO_PROFILE,
        .force_default_version_and_profile = 0,
        .forward_compatible = 0,
        .messages = glslang.GLSLANG_MSG_DEFAULT_BIT,
        .resource = limits,
        .include_callbacks_ctx = null,
        .include_callbacks = .{
            .include_system = null,
            .include_local = null,
            .free_include_result = null,
        },
    };
    var include_ctx = IncludeContext{
        .alloc = alloc,
        .mapping = undefined,
    };
    if (opts.include_map) |include_map| {
        include_ctx.mapping = include_map;
        input.include_callbacks_ctx = &include_ctx;
        input.include_callbacks = .{
            .include_system = null,
            .include_local = S.includeLocal,
            .free_include_result = S.freeIncludeResult,
        };
    } 

    const shader = glslang.glslang_shader_create(&input);
    defer glslang.glslang_shader_delete(shader);

    if (glslang.glslang_shader_preprocess(shader, &input) == 0) {
        log.debug("Preprocess failed: {s}", .{glslang.glslang_shader_get_info_log(shader)});
        log.debug("{s}", .{glslang.glslang_shader_get_info_debug_log(shader)});
        return error.PreprocessFailed;
    }

    if (glslang.glslang_shader_parse(shader, &input) == 0) {
        log.debug("Parse failed: {s}", .{glslang.glslang_shader_get_info_log(shader)});
        log.debug("{s}", .{glslang.glslang_shader_get_info_debug_log(shader)});
        log.debug("GLSL: {s}", .{src});
        return error.ParseFailed;
    }

    const program = glslang.glslang_program_create();
    defer glslang.glslang_program_delete(program);

    glslang.glslang_program_add_shader(program, shader);

    if (glslang.glslang_program_link(program, glslang.GLSLANG_MSG_SPV_RULES_BIT | glslang.GLSLANG_MSG_VULKAN_RULES_BIT) == 0) {
        log.debug("Link failed: {s}", .{glslang.glslang_shader_get_info_log(shader)});
        log.debug("{s}", .{glslang.glslang_shader_get_info_debug_log(shader)});
        return error.LinkFailed;
    }

    glslang.glslang_program_SPIRV_generate(program, cstage);
    const size = glslang.glslang_program_SPIRV_get_size(program);

    const buf = try alloc.alloc(u32, size);
    glslang.glslang_program_SPIRV_get(program, buf.ptr);

    const spirv_messages = glslang.glslang_program_SPIRV_get_messages(program);
    if (spirv_messages != null) {
        log.debug("{s}", .{spirv_messages});
    }
    return buf;
}