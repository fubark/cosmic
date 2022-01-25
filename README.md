[![Latest Build](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml/badge.svg)](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml)
# Cosmic

Cosmic will be a simple and productive JavaScript/WASM runtime. It aims to have broad applications with a rich standard library. It also aims to streamline development tooling to provide everything you'll need to ship and maintain software.

## Progress
The Cosmic API is subject to change during the Alpha version. After version 1.0, the API will remain backwards compatible until the next major version.
- Cosmic Alpha version (*In progress.*, [Website](https://cosmic-js.com))
  - Javascript API (*In progress.*)
  - Wasm/Wasi API (*Not started.*)

Along the way we'll build some cool libs for zig!
- 2D Graphics ([Source](https://github.com/fubark/cosmic/tree/master/graphics))
- UI and animation framework at the native level. (*In progress*)
- Javascript/WASM runtime.
  - V8 bindings ([Source](https://github.com/fubark/zig-v8))
- General purpose text editor. (*In progress*)
- Incremental AST parser and tokenizer. ([Source](https://github.com/fubark/cosmic/tree/master/parser))
- Bundling/distribution. (*Not started.*)

## Contributing
We will be building the app primarily in Zig.
[Why Zig When There is Already C++, D, and Rust?](https://ziglang.org/learn/why_zig_rust_d_cpp)

Zig's toolchain is ideal for this project. Even though it has yet to reach 1.0, it's LLVM backend is stable and stage2 is just around the corner.

Get the Zig compiler (0.9.0) [here](https://ziglang.org/download/). 

Once you have zig, checkout and run tests.
```sh
git clone https://github.com/fubark/cosmic.git
zig build get-deps
zig build test
```

Please star the repo and let's do this!

## License

Cosmic is free and open source under the MIT License.
