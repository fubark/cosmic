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

## How it works.

### Setup.
When setting up your ui app, you need to create a comptime ui.Config which contains all Widget types you will be using. This way the Widgets can map to ids and their vtables at comptime. Then you create ui.Module with the config and a graphics context. The graphics context is how you can inject a rendering backend of your choosing. This is what it might look like:
```zig
pub const MyConfig = b: {
    var config = ui.Config{
        .Imports = ui.widgets.BaseWidgets,
    };
    config.Imports = config.Imports ++ &[_]ui.Import{
        ui.Import.init(Counter),
    };
    break :b config;
};

pub fn main() !void {
    var app: helper.App = undefined;
    app.init("Counter");
    defer app.deinit();

    var ui_mod: ui.Module(MyConfig) = undefined;
    ui_mod.init(app.alloc, app.g);
    defer ui_mod.deinit();
    ui_mod.addInputHandlers(&app.dispatcher);

    app.runEventLoop(update);
}
```
You'll notice that we imported all widgets from the stock widget library as well as our custom root widget named Counter. It's also being wrapped around an App helper which sets up a window, a graphics context, a default allocator, feeds mouse/keyboard events into the ui module, and starts the app in an update loop.

### Widget structure.
Widgets are defined as plain structs. You can define properties that can be fed into your widget with a special `props` property. The props struct can contain default values. Non default values will have comptime checks when they are copied over from Frames. Any other property besides the `props` is effectively state variables of a widget instance. Some public methods are reserved as widget hooks. These hooks are called at different times in the widget's lifecycle and include `init, postInit, deinit, build, postUpdate, layout, render, postRender`. Not declaring one of them will automatically use a default implementation. Each hook contains a context param which lets you invoke useful logic related to the ui. Here is what a widget might look like:
```zig
pub const Counter = struct {
    const Self = @This();

    props: struct {
        // A prop with a default value.
        text_color: Color = Color.Blue,

        // No default value, will check if parent provided the value at comptime.
        init_val: u32,
    },

    // This is a state variable.
    counter: u32,

    pub fn init(self: *Self, comptime C: ui.Config, c: *C.Init()) void {
        // Invoked when the widget instance was created but before all it's child widgets.
    }

    pub fn postInit(self: *Self, comptime C: Config, c: *C.Init()) void {
        // Invoked after the widget instance and it's child widgets were created.
    }

    pub fn deinit(node: *Node, alloc: std.mem.Allocator) void {
        // Invoked when the widget instance is destroyed.
    }

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        // Invoked when the engine wants to know the structure of this Widget.
    }

    pub fn postUpdate(self: *Self) void {
        // Invoked when a widget is updated with props from the parent.
    }

    pub fn layout(self: *Self, comptime C: ui.Config, c: *C.Layout()) ui.LayoutSize {
        // Invoked when the engine performs layout.
    }

    pub fn render(self: *Self, c: *ui.RenderContext) void {
        // Invoked at render time before it's children are rendered.
    }

    pub fn postRender(self: *Self, c: *ui.RenderContext) void {
        // Invoked after it's children are rendered.
    }
}
```
### Declaring Widgets.
Before any widget instances are created, the engine needs to know the structure of your ui. This is when it invokes the `build` hooks:
```zig
    // ... in Counter struct.

    pub fn build(self: *Self, comptime C: ui.Config, c: *C.Build()) ui.FrameId {
        const S = struct {
            fn onClick(self_: *Self, _: MouseUpEvent) void {
                self_.counter += 1;
            }
        };

        return c.decl(Center, .{
            .child = c.decl(Row, .{
                .expand = false,
                .children = c.list(.{
                    c.decl(Padding, .{
                        .padding = 10,
                        .pad_left = 30,
                        .pad_right = 30,
                        .child = c.decl(Text, .{
                            .text = c.fmt("{}", .{self.counter}),
                            .color = Color.White,
                        }),
                    }),
                    c.decl(TextButton, .{
                        .text = "Count",
                        .onClick = c.funcExt(self, MouseUpEvent, S.onClick),
                        .corner_radius = 10,
                    }),
                }),
            }),
        });
    }
```
`build` creates frames which contain just the right amount of information to represent the structure. This includes the Widget type and props. The engine then proceeds to diff this structure against any existing instance tree. If a widget is missing it is created, if one already exists it's reused. When building a unit Widget (one that does not have any children) `build` should return `ui.NullFrameId`. When building a Widget that has multiple children, `ctx.fragment()` wraps a list of frame ids as a fragment frame.

### Layout
When the engine needs to perform layout, the `layout` hook is invoked. Each widget's `layout` is responsible for:
- Calling layout on it's children via `ctx.computeLayout, ctx.computeLayoutStretch`.
- Resizing the child LayoutSize returned to respect the current or parent constraints.
- Positioning the child relative to the current widget via `ctx.setLayout`.
- Returning the current widget's LayoutSize.

Following this pattern lets the engine perform layout in linear time while also providing the flexibility to define many different layout constraints.

### Widget Library
For now you can checkout widgets.zig to see what each widget can do.

## License
Cosmic UI is free and open source under the MIT License.