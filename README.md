[![Latest Build](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml/badge.svg)](https://github.com/fubark/cosmic/actions/workflows/latest-build.yml)
[![Discord Server](https://img.shields.io/discord/828041790711136274.svg?color=7289da&label=Discord&logo=discord&style=flat-square)](https://discord.gg/YF82GYvBxQ)

# Cosmic

Cosmic is a general purpose runtime for JavaScript and WASM. It aims to have broad applications by exposing native cross platform APIs: window management, 2D/3D graphics, UI widgets, filesystem, networking, and more. It also aims to streamline software tooling to provide the essentials to help you develop and maintain software.

## Progress
The Cosmic API is subject to change during the Alpha version. After version 1.0, the API will remain backwards compatible until the next major version. Check out the latest [API docs](https://cosmic-js.com/docs).
- JavaScript API (*In progress.*)
- WASM/WASI API (*Not started.*)

Here are some Zig libs we have built while working on Cosmic:
- 2D Graphics ([Source](https://github.com/fubark/cosmic/tree/master/graphics))
- UI and animation framework. ([Source](https://github.com/fubark/cosmic/tree/master/ui))
- V8 bindings ([Source](https://github.com/fubark/zig-v8))
- General purpose text editor. (*In progress*)
- Incremental AST parser and tokenizer. ([Source](https://github.com/fubark/cosmic/tree/master/parser))

## Getting Started
You can download a prebuilt version of Cosmic from the Releases page.
Then checkout the repo to try a few examples:
```sh
git clone https://github.com/fubark/cosmic.git
cd cosmic
cosmic examples/paddleball.js
cosmic examples/demo.js
```

## Building
Get the latest Zig compiler (0.10.0-dev) [here](https://ziglang.org/download/). 

Once you have Zig, checkout, run tests, and build.
```sh
git clone https://github.com/fubark/cosmic.git
cd cosmic

# This will fetch the prebuilt v8 lib for your platform.
zig build get-v8-lib

# Generates supplementary js for some API functions.
# For the first time running this command, you'll need -Dfetch to get any deps.
zig build gen -Darg="api-js" -Darg="runtime/snapshots/gen_api.js" -Dfetch

# Run unit tests.
zig build test

# Run behavior tests.
zig build test-behavior

# Run js behavior tets.
zig build test-cosmic-js

# Build the main app. Final binary will be at ./zig-out/{platform}/main/main. Use -Drelease-safe for an optimized version.
zig build cosmic
```

## Docs
See the latest docs at [API docs](https://cosmic-js.com/docs).
Generate the docs locally with:
```sh
zig build gen -Darg="docs" -Darg="docs-out"
```

## Contributing
We will be building the app primarily in Zig.
[Why Zig When There is Already C++, D, and Rust?](https://ziglang.org/learn/why_zig_rust_d_cpp)

Zig's toolchain is ideal for this project. Even though it has yet to reach 1.0, it's LLVM backend is stable and stage2 is just around the corner.

There is a lot to be done! If you find the project interesting, consider submitting a PR. A good way to start is to submit or repond to an existing Github Issue. Please star the repo and let's do this!

If you have questions or suggestions, submit an issue or join the discord for more direct discourse.

## License

Cosmic is free and open source under the MIT License.
