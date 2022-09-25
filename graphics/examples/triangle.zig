// Run app with:
// zig build run -Dpath="graphics/examples/triangle.zig" -Dgraphics
const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const graphics = @import("graphics");
const Color = graphics.Color;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    try app.init("Triangle");
    defer app.deinit();
    app.runEventLoop(update);
}

fn update(delta_ms: f32) anyerror!void {
    _ = delta_ms;
    const gctx = app.gctx;
    gctx.setFillColor(Color.Red);
    gctx.fillTriangle(600, 100, 900, 600, 300, 600);
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() [*]const u8 {
        return helper.wasmInit(&app, "Triangle");
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) [*]const u8 {
        return helper.wasmUpdate(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        app.deinit();
        stdx.wasm.deinit();
    }
} else struct {};