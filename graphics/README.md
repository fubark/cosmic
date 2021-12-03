# Graphics

2D graphics library for GUI and games in Zig. See the [Web Demo](https://fubark.github.io/site/demo).

- [x] Create window with OpenGL(3.3) context.
- [x] Canvas API / Vector graphics
  - [x] Fill/stroke shapes.
  - [x] Complex polygons.
  - [x] Curves.
  - [x] SVG path rendering, SVG file support (subset of spec)
  - [ ] Line join styles.
- [x] Text rendering.
  - [x] Supports TTF/OTF fonts.
  - [x] Dynamic text sizes.
  - [x] Color emojis.
  - [x] Fallback font support. (for missing UTF-8 codepoints)
  - [ ] Bitmap fonts.
  - [ ] Smoother render on macOS with CoreText.
  - [ ] Smoother render on Windows with Direct2D.
- [x] Load/draw images. (JPG, PNG, BMP)
- [ ] Draw on in memory images with the same Canvas API.
- [x] Transforms.
- [x] Blending.
- [ ] Gradients.
- [ ] Custom Shaders.
- [ ] Cross platform.

| Status | Platform | Size (demo)* |
| --- | --- | --- |
| ✅ | Linux x64 with OpenGL [(Screenshot)](https://raw.githubusercontent.com/fubark/site/master/graphics-demo-linux.png) | demo - 1.7 MB |
| ✅ | Web with Wasm/Canvas [(Demo)](https://fubark.github.io/site/demo) | demo.wasm - 120 KB |
| Soon | Windows x64 with OpenGL | |
| Soon | macOS x64/arm64 with OpenGL | |
| Undecided | Android/iOS |
| Future | WebGPU backend for Win/Mac/Linux/Web |

  \* Size does not include font and image assets. Compiled with -Drelease-safe.

- [ ] Cross compilation.
- [ ] C bindings.

## Screenshot
![Linux Demo](https://raw.githubusercontent.com/fubark/site/master/graphics-demo-linux.png)

### Dependencies
You'll need OpenGL and SDL2 installed locally. Additionally you'll need to pull the vendor repo which has header files and assets for the demo:
```sh
zig build get-deps
```

### Run demo (Desktop)
```sh
zig build run -Dpath=graphics/examples/demo.zig -Dgraphics -Drelease-safe
```

### Run demo (Web/Wasm)

```sh
zig build wasm -Dpath=graphics/examples/demo.zig -Drelease-safe
cd zig-out/demo
python -m SimpleHTTPServer
```
Then fire up your browser to see the demo.

### Build lyon bindings
The library currently uses lyon to triangulate complex polygons and paths. Pulling the dependencies (zig build get-deps) will get prebuilt lyon bindings. If that doesn't work you'll need rust and cargo to do:
```sh
zig build lyon
```

### Usage
* To use this library in your own projects, use this repo as a template including build.zig and build your main just like demo.zig.
* This might be simpler once we have an official package manager for zig or when we have c bindings. There might also be a way to reuse lib project's build.zig.