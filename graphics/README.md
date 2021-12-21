# Cosmic Graphics

2D graphics library for GUI and games in Zig. See the [Web Demo](https://fubark.github.io/cosmic-site/demo).

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
- [x] Cross platform.

| Status | Platform | Size (demo)* |
| --- | --- | --- |
| ✅ | Linux x64 with OpenGL [(Screenshot)](https://raw.githubusercontent.com/fubark/cosmic-site/master/graphics-demo-linux.png) | demo - 953 KB |
| ✅ | Web with Wasm/Canvas [(Demo)](https://fubark.github.io/cosmic-site/demo) | demo.wasm - 151 KB |
| ✅ | Windows x64 with OpenGL [(Screenshot)](https://raw.githubusercontent.com/fubark/cosmic-site/master/graphics-demo-win11.png) | demo.exe - 442 KB |
| ✅ | macOS x64 with OpenGL [(Screenshot)](https://raw.githubusercontent.com/fubark/cosmic-site/master/graphics-demo-macos.png) | demo - 620 KB |
| Soon | macOS arm64 with OpenGL | |
| Undecided | Android/iOS |
| Future | WebGPU backend for Win/Mac/Linux/Web |

  \* Size does not include dynamic libs (SDL2, lyon) and demo assets. Compiled with -Drelease-safe.

- [ ] Cross compilation.
- [ ] C bindings.

## Screenshot
<a href="https://raw.githubusercontent.com/fubark/cosmic-site/master/graphics-demo-linux.png"><img src="https://raw.githubusercontent.com/fubark/cosmic-site/master/graphics-demo-linux.png" alt="Linux Demo" height="300"></a>

### Dependencies
Get the Zig compiler (0.9.0) at [zig](https://ziglang.org/download/). On Linux you'll need SDL2 installed. You need to pull the vendor repo which has header files, prebuilt libs, and assets for the demo:
```sh
git clone https://github.com/fubark/cosmic.git
zig build get-deps
```

### Run demo (Desktop)
```sh
zig build run -Dpath="graphics/examples/demo.zig" -Dgraphics -Drelease-safe
```

### Run demo (Web/Wasm)

```sh
zig build wasm -Dpath="graphics/examples/demo.zig" -Drelease-safe
cd zig-out/demo
python3 -m http.server
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

## License
Cosmic Graphics is free and open source under the MIT License.