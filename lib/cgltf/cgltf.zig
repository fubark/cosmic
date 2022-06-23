const c = @cImport({
    @cInclude("cgltf.h");
});

pub usingnamespace c;

pub fn parse(options: [*c]const c.cgltf_options, data: ?*const anyopaque, size: c.cgltf_size, out_data: **c.cgltf_data) c.cgltf_result {
    return c.cgltf_parse(options, data, size, @ptrCast([*c][*c]c.cgltf_data, out_data));
}

pub fn checkSuccess(res: c.cgltf_result) !void {
    if (res != c.cgltf_result_success) {
        return error.GLTFerror;
    }
}

pub fn checkTrue(b: c.cgltf_bool) !void {
    if (b != 1) {
        return error.False;
    }
}