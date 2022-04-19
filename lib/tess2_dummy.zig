pub const TESStesselator = struct {
};

pub const TESSalloc = struct {
};

pub const TESSreal = f32;
pub const TESSindex = u32;

pub fn tessNewTess(alloc: ?*TESSalloc) ?*TESStesselator {
    _ = alloc;
    return undefined;
}

pub fn tessDeleteTess(tess: ?*TESStesselator) void {
    _ = tess;
}

pub fn tessAddContour(tess: ?*TESStesselator, size: c_int, pointer: ?*const anyopaque, stride: c_int, count: c_int) void {
    _ = tess;
    _ = size;
    _ = pointer;
    _ = stride;
    _ = count;
}

pub fn tessSetOption(tess: ?*TESStesselator, option: c_int, value: c_int) void {
    _ = tess;
    _ = option;
    _ = value;
}

pub fn tessTesselate(tess: ?*TESStesselator, windingRule: c_int, elementType: c_int, polySize: c_int, vertexSize: c_int, normal: *const TESSreal) c_int {
    _ = tess;
    _ = windingRule;
    _ = elementType;
    _ = polySize;
    _ = vertexSize;
    _ = normal;
    return undefined;
}

pub fn tessGetVertexCount(tess: ?*TESStesselator) c_int {
    _ = tess;
    return undefined;
}

pub fn tessGetVertices(tess: ?*TESStesselator) *const TESSreal {
    _ = tess;
    return undefined;
}

pub fn tessGetVertexIndices(tess: ?*TESStesselator) *const TESSindex {
    _ = tess;
    return undefined;
}

pub fn tessGetElementCount(tess: ?*TESStesselator) c_int {
    _ = tess;
    return undefined;
}

pub fn tessGetElements(tess: ?*TESStesselator) *const TESSindex {
    _ = tess;
    return undefined;
}