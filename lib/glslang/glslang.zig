
const c = @cImport({
    @cInclude("glslang/Include/glslang_c_interface.h");
    @cInclude("StandAlone/resource_limits_c.h");
});

pub usingnamespace c;