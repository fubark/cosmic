# Cosmic UI

Standalone UI engine for GUI and games in Zig. It has a resemblance to Flutter or SwiftUI. Uses the [graphics module](https://github.com/fubark/cosmic/tree/master/graphics) to draw the widgets. Uses SDL for window/graphics context creation. See the [Web Demo](https://fubark.github.io/cosmic-site/zig-ui).

- [x] Retained mode. Persists widget state and performs fast diffs to reuse existing widget instances.
- [x] Fast linear time layout algorithm.
- [x] Widgets defined as plain structs. Easy to navigate with your editor and ZLS.
- [x] Widget library. Collection is still growing.
- [x] Custom widgets. Easily create your own widgets with your own build/layout/render steps.
- [x] Draw with Canvas API / Vector graphics directly from a custom widget.
- [x] Register input handlers (mouse, keyboard, etc).
- [x] Register timer handlers.
- [x] Cross platform.
- [ ] Animation support.
- [ ] Transform support.
- [ ] Cross compilation. (Might work already, needs verification.)
- [ ] C bindings.

| Status | Platform | Size (counter.zig)* |
| --- | --- | --- |
| ✅ | Web with Wasm/WebGL2 [(Demo)](https://fubark.github.io/cosmic-site/zig-ui) | counter.wasm - 412 KB |
| ✅ | Linux x64 with OpenGL | counter - 2.2 M |
| ✅ | Windows x64 with OpenGL | counter.exe - 2.7 M |
| ✅ | macOS x64 with OpenGL | counter - 3.0 M |
| ✅ | macOS arm64 with OpenGL | counter - 2.8 M |
| Undecided | Android/iOS |
| Future | WebGPU backend for Win/Mac/Linux/Web |

\* Static binary size. Compiled with -Drelease-safe.

## Dependencies
Get the latest Zig compiler (0.10.0-dev) [here](https://ziglang.org/download/).

Clone the cosmic repo which includes:
- cosmic/ui: This module.
- cosmic/graphics: Used to draw the widgets.
- cosmic/platform: Used to facilitate events from the window.
- cosmic/stdx: Used for additional utilities.
- cosmic/lib/sdl: SDL2 source. Used to create a window and OpenGL 3.3 context. Built automatically.
- cosmic/lib/stb: stb_truetype and stb_image source. Used to rasterize fonts and decode images. Built automatically.
- cosmic/lib/wasm-js: Wasm/js bootstrap and glue code.
```sh
git clone https://github.com/fubark/cosmic.git
cd cosmic
```

## Run demo (Desktop)
```sh
zig build run -Dpath="ui/examples/counter.zig" -Dgraphics -Drelease-safe
```

## Run demo (Web/Wasm)

```sh
zig build wasm -Dpath="ui/examples/counter.zig" -Dgraphics -Drelease-safe
cd zig-out/wasm32-freestanding-musl/counter
python3 -m http.server
# Or "cosmic http ." if you have cosmic installed.
# Then fire up your browser to see the demo.
```

## Using as a Zig library.
The lib.zig in this ui module provides simple helpers for you add the package, build, and link this library in your own build.zig file. Here is how you would do that:
```zig
// build.zig
// cosmic repo should be a subdirectory.
const std = @import("std");
const ui = @import("cosmic/ui/lib.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // main.zig would be your app code. You could copy over examples/counter.zig as a template.
    const exe = b.addExecutable("myapp", "main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    ui.addPackage(exe, .{});
    ui.buildAndLink(exe, .{});

    exe.setOutputDir("zig-out");

    const run = exe.run();
    b.default_step.dependOn(&run.step);
}
```
Then run `zig build` in your own project directory and it will build and run your app.

## Using as a C Library.
* TODO: Provide c headers.

## License
Cosmic UI is free and open source under the MIT License.