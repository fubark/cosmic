# Cosmic UI

Standalone UI engine for GUI and games in Zig. It has a resemblance to Flutter or SwiftUI. Uses the [graphics module](https://github.com/fubark/cosmic/tree/master/graphics) to draw the widgets. Uses SDL for window/graphics context creation. See the [Web Demo](https://fubark.github.io/cosmic-site/zig-ui).

- [x] Declarative retained mode. Persists widget state and performs fast diffs to reuse existing widget instances.
- [x] Fast linear time layout algorithm.
- [x] Widgets defined as plain structs. Easy to navigate with your editor and ZLS.
- [x] Widget library. Button, Switch, Row, Column, Containers, Text (with layout), TextField, TextEditor, Color Picker, Popovers, Modals, and more. Collection is still growing.
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
| ✅ | Web with Wasm/WebGL2 [(Demo)](https://fubark.github.io/cosmic-site/zig-ui) | counter.wasm - 381 KB |
| ✅ | Linux x64, OpenGL, Vulkan | counter - 2.2 M |
| ✅ | Windows x64, OpenGL | counter.exe - 2.7 M |
| ✅ | macOS x64, OpenGL, Vulkan via MoltenVK | counter - 2.5 M |
| ✅ | macOS arm64, OpenGL, Vulkan via MoltenVK | counter - 2.8 M |
| Planned | Windows Vulkan backend |
| Undecided | Android/iOS |
| Future | WebGPU backend for Win/Mac/Linux/Web |

\* Static binary size. Compiled with -Drelease-safe.

\** Note for the Vulkan backend on macOS, you need to install MoltenVK. In a future release, the static lib will automatically be included. If you'd like to use OpenGL instead, enable it in cosmic/platform/backend.zig.

## Dependencies
Get the latest Zig compiler (0.10.0-dev) [here](https://ziglang.org/download/).

Clone the cosmic repo which includes:
- cosmic/ui: This module.
- cosmic/graphics: Used to draw the widgets.
- cosmic/platform: Used to facilitate events from the window.
- cosmic/stdx: Used for additional utilities.
- cosmic/lib/sdl: SDL2 source. Used to create a window and OpenGL 3.3 context. Built automatically.
- cosmic/lib/freetype2: Freetype2 font renderer backend used by default for desktop. Built automatically.
- cosmic/lib/stb: stb_truetype and stb_image source. Used to rasterize fonts and decode images. Built automatically.
- cosmic/lib/wasm: Wasm/js bootstrap and glue code.
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
When setting up your ui app, you need to create a ui.Module with a graphics context. The graphics context is how you can inject a rendering backend of your choosing. Use helper.App from examples/helper.zig  to set this up as well as window, a default allocator, and binding input to the ui. This is what it might look like:
```zig
var app: helper.App = undefined;

pub fn main() !void {
    app.init("Counter");
    defer app.deinit();
    app.runEventLoop(update);
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
            return c.build(Counter, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    app.ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height) catch unreachable;
}
```
Once it kicks off the event loop, it will start updating and rendering the ui given the window's size and a bootstrap function which tells it how to create the user's root widget. In this case it's a widget declared as `Counter`.

### Widget structure.
Widgets are defined as plain structs. You can define properties that can be fed into your widget with a special `props` property. The props struct can contain default values. Non default values will have comptime checks when they are copied over from Frames. Any other property besides the `props` is effectively state variables of a widget instance. Some public methods are reserved as widget hooks. These hooks are called at different times in the widget's lifecycle and include `init, postInit, deinit, build, postPropsUpdate, postUpdate, layout, render, renderCustom`. Not declaring one of them will automatically use a default implementation. Each hook contains a context param which lets you invoke useful logic related to the ui. Here is what a widget might look like:
```zig
pub const Counter = struct {
    props: struct {
        // A prop with a default value.
        text_color: Color = Color.Blue,

        // No default value, will check if parent provided the value at comptime.
        init_val: u32,
    },

    // This is a state variable.
    counter: u32,

    pub fn init(self: *Counter, c: *ui.InitContext) void {
        // Invoked when the widget instance was created but before all it's child widgets.
    }

    pub fn postInit(self: *Counter, c: *ui.InitContext) void {
        // Invoked after the widget instance and it's child widgets were created.
    }

    pub fn deinit(node: *Node, alloc: std.mem.Allocator) void {
        // Invoked when the widget instance is destroyed.
    }

    pub fn build(self: *Counter, c: *ui.BuildContext) ui.FrameId {
        // Invoked when the engine wants to know the structure of this Widget.
    }

    pub fn postPropsUpdate(self: *Counter) void {
        // Invoked when a widget has updated their props from the parent.
    }

    pub fn postUpdate(self: *Counter) void {
        // Invoked when a widget and it's children have finished updating. (They have resolved their instance trees from the diff operation.)
    }

    pub fn layout(self: *Counter, c: *ui.LayoutContext) ui.LayoutSize {
        // Invoked when the engine performs layout.
    }

    pub fn render(self: *Counter, c: *ui.RenderContext) void {
        // Invoked to render this widget. Afterwards, the children render steps will be invoked.
    }

    pub fn renderCustom(self: *Counter, c: *ui.RenderContext) void {
        // This supersedes the `render` hook and gives you full control over how the children are rendered.
        // This would be useful if you need post rendering steps or have a different order to render the children.
    }
}
```

### Declaring Widgets.
Before any widget instances are created, the engine needs to know the structure of your ui. This is when it invokes the `build` hooks:
```zig
    const w = ui.widgets;

    // ... in Counter struct.

    pub fn build(self: *Counter, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClick(self_: *Counter, _: MouseUpEvent) void {
                self_.counter += 1;
            }
        };

        return w.Center(.{},
            w.Row(.{ .expand = false }, &.{
                w.Padding(.{ .padding = 10, .pad_left = 30, .pad_right = 30 },
                    w.Text(.{
                        .text = c.fmt("{}", .{self.counter}),
                        .color = Color.White,
                    }),
                ),
                w.TextButton(.{
                    .text = "Count",
                    .onClick = c.funcExt(self, MouseUpEvent, S.onClick),
                    .corner_radius = 10,
                }),
            }),
        );
    }
```
`build` hooks lets you declare child widgets that the current widget is composed of. Behind the scenes this is creating Frames which contain metadata about the declarations. Using frames gives you a lot of freedom in `build` for widget composition. `BuildContext.build()` is used to build a widget which takes in the Widget type and a tuple that can contain the widget's props in addition to reserved props like `bind` and `id`. `BuildContext.list()` is used to group together frames.

The engine then proceeds to diff the structure provided by `build` against any existing instance tree. If a widget is missing it is created. If one already exists it's reused. When building a unit Widget (one that does not have any children) `build` should return `ui.NullFrameId`. When building a Widget that has multiple children, `BuildContext.fragment()` wraps a list of frame ids as a fragment frame.

### Widget Binding
Often times you'll want access to a child widget. Here's how you would do that with `WidgetRef` and the reserved `bind` prop.
```zig
const App = struct {
    slider: WidgetRef(w.SliderUI),

    pub fn build(self: *App, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onClick(self_: *App, _: MouseUpEvent) void {
                std.debug.print("slider value {}", .{self_.slider.getWidget().getValue()});
            }
        };
        return w.Slider(.{
            .bind = &self.slider,
            .init_val = 30,
        })
    }
};
```

### Events
Widgets can add event handlers and request focus for keyboard events:
```zig
const TextField = struct {
    // ...

    pub fn init(self: *TextField, c: *ui.InitContext) void {
        c.addMouseDownHandler(self, onMouseDown);
        c.addKeyDownHandler(self, onKeyDown);
    }

    fn onMouseDown(self: *TextField, e: ui.MouseDownEvent) void {
        e.ctx.requestFocus(onBlur);
    }

    // ...
};
```
Similarily you can remove handlers. If you forget, they will be cleaned up anyway when the widget is disposed.

### Layout
When the engine needs to perform layout, the `layout` hook is invoked. If the widget does not provide a hook, a default implementation is used. Each widget's `layout` is responsible for:
- Calling layout on it's children via `LayoutContext.computeLayout(), LayoutContext.computeLayoutStretch()`.
- Resizing the child LayoutSize returned to respect the current or parent constraints.
- Positioning the child relative to the current widget via `LayoutContext.setLayout()`.
- Returning the current widget's LayoutSize.

Following this pattern lets the engine perform layout in linear time while also providing the flexibility to define many different layout constraints.

### Render Widgets
When building your own custom widgets, you have the freedom to paint it any way you like using the graphics context. At render time the hook will already have the absolute positioning computed so you can paint with ease.
```zig
const RedSquare = struct {
    pub fn render(self: *Self, c: *ui.RenderContext) void {
        const alo = ctx.getAbsLayout();
        const g = c.g;
        g.setFillColor(Color.Red);
        g.fillRect(alo.x, alo.y, alo.width, alo.height);
    }
};
```
The `render` hook let's you draw the current widget. If there are child widgets, those would be drawn afterwards by default. To supersede the default behavior, use the `renderCustom` hook.

### Widget Library
For now you can checkout widgets.zig to see what each widget can do.

## License
Cosmic UI is free and open source under the MIT License.
