[![Latest Build](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml/badge.svg)](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml)
[![Discord Server](https://img.shields.io/discord/828041790711136274.svg?color=7289da&label=Discord&logo=discord&style=flat-square)](https://discord.gg/YF82GYvBxQ)

# Cosmic

Cosmic is a general purpose runtime for Javascript and WASM. It aims to have broad applications by exposing native cross platform APIs: window management, 2D/3D graphics, UI widgets, filesystem, networking, and more. It also aims to streamline software tooling to provide the essentials to help you develop and maintain software.

## Progress
The Cosmic API is subject to change during the Alpha version. After version 1.0, the API will remain backwards compatible until the next major version. Check out the latest [API docs](https://cosmic-js.com/docs).
- Javascript API (*In progress.*)
- Wasm/Wasi API (*Not started.*)

Here are some zig libs we have built while working on Cosmic:
- 2D Graphics ([Source](https://github.com/fubark/cosmic/tree/master/graphics))
- UI and animation framework. (*In progress*)
- V8 bindings ([Source](https://github.com/fubark/zig-v8))
- General purpose text editor. (*In progress*)
- Incremental AST parser and tokenizer. ([Source](https://github.com/fubark/cosmic/tree/master/parser))

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
