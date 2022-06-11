const std = @import("std");

pub const GraphicsBackend = enum(u3) {
    /// Stub for testing.
    Test = 0,
    /// Deprecated. Uses html canvas context for graphics. Kept for historical reference.
    WasmCanvas = 1,
    /// For Desktop and WebGL.
    OpenGL = 2,
    /// For Desktop only.
    Vulkan = 3,
    /// Dummy, lets switch statements always have an else clause.
    Dummy = 4,
};

pub fn getGraphicsBackend(step: *std.build.LibExeObjStep) GraphicsBackend {
    const target = step.target;
    if (step.kind == .@"test") {
        return .Test;
    } else if (target.getCpuArch() == .wasm32 or target.getCpuArch() == .wasm64) {
        // return .WasmCanvas;
        return .OpenGL;
    } else {
        // return .OpenGL;
        return .Vulkan;
    }
}