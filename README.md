# Cosmic

Cosmic will be a single binary GUI/CLI tool that lets you build apps (ui, games, cli) with just Javascript/TS. It will provide a text editor, graphics/animation/ui api, a script runtime and bundler to distribute your app. You won't need any additional tools. There's also plans to create an alternative scripting language called XScript.

## Progress
Along the way we'll build some cool libs for zig! In no particular order:
- 2D Graphics [(Source)](https://github.com/fubark/cosmic/tree/master/graphics)
- UI and animation framework at the native level. *(In progress)*
- Javascript/WASM runtime powered by v8. *(In progress)*
- XScript, a new scripting language for the future. *(In progress)*
- General purpose text editor. *(In progress)*
- Incremental AST parser and tokenizer. [(Source)](https://github.com/fubark/cosmic/tree/master/parser)
- Main Cosmic app. *(Not started.)*
- Bundling/distribution. *(Not started.)*

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

The repo is organized by libs we are building. Each library has their own README which will explain what they are and their progress. There is currently no main app for Cosmic.

Please star the repo and let's do this!

## Future

After Cosmic, we'll use what we built to start exploring a different way to browse/interact with the web. 

## License

Cosmic will be free and open source under the MIT License.