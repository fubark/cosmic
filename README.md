# Cosmic

Cosmic will be a single binary tool that lets you build apps (UI, Games, CLI) with just Javascript/TS. It will provide a text editor, graphics/animation/ui api, a script runtime and bundler to distribute your app. You won't need any additional tools. There's also plans to create an alternative scripting language called XScript.

## Progress
The Cosmic API is subject to change during the Alpha version. After version 1.0, the API will remain backwards compatible until the next major version.
- Cosmic Alpha version (*In progress.*)
  - Javascript API (*In progress.*)
  - Wasm/Wasi API (*Not started.*)

Along the way we'll build some cool libs for zig!
- 2D Graphics ([Source](https://github.com/fubark/cosmic/tree/master/graphics))
- UI and animation framework at the native level. (*In progress*)
- Javascript/WASM runtime.
  - V8 bindings ([Source](https://github.com/fubark/zig-v8))
- XScript, a new scripting language for the future. (*In progress*)
- General purpose text editor. (*In progress*)
- Incremental AST parser and tokenizer. ([Source](https://github.com/fubark/cosmic/tree/master/parser))
- Bundling/distribution. (*Not started.*)

## Contributing
We will be building the app primarily in Zig.
[Why Zig When There is Already C++, D, and Rust?](https://ziglang.org/learn/why_zig_rust_d_cpp)

Zig's toolchain is ideal for this project. Even though it has yet to reach 1.0, it's LLVM backend is stable and stage2 is just around the corner.

Currently, it's recommended to get a [master build](https://ziglang.org/download/) of zig or build from [source](https://github.com/ziglang/zig).

Once you have zig, checkout and run tests.
```sh
git clone https://github.com/fubark/cosmic.git
zig build get-deps
zig build test
```

Please star the repo and let's do this!

## Future

After Cosmic, we'll use what we built to start exploring a different way to browse/interact with the web. 

## License

Cosmic is free and open source under the MIT License.
