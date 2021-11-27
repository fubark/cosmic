# Graphics

2D graphics library for GUI and games in Zig. See the ~~[Web Demo](https://)~~.

- [x] Create window with OpenGL context.
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

| Status | Platform | Footprint |
| --- | --- | --- |
| ✓ | Linux x64 with OpenGL [(Screenshot)](https://raw.githubusercontent.com/fubark/site/master/graphics-demo-linux.png) | |
| Soon | Web with Wasm/Canvas ~~[(Demo)](https://)~~ | |
| Soon | Windows x64 with OpenGL | |
| Soon | macOS x64/arm64 with OpenGL | |
| Undecided | Android/iOS |
| Future | WebGPU backend for Win/Mac/Linux/Web |

- [ ] Cross compilation.
- [ ] C bindings.

## Screenshot
![Linux Demo](https://raw.githubusercontent.com/fubark/site/master/graphics-demo-linux.png)

## Usage

### Build Demo

TBD