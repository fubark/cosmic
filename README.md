# Cosmic

Cosmic will be a desktop app that explores a different way to browse/interact with the web. It will empower users with builtin tools to create and edit web content. The same app that browses the web also streamlines how things are built and shipped. Cosmic will also support a versatile document for doing general purpose computing. Think of the utility of excel sheets but with other forms of input and scripting. This will accomplish most tasks that don't need specialized software and encourage people to reuse computations/workflows that are shared on the web.

## Components
Here are several software components we will need to make this work, in no particular order:
- 2D vector graphics.
- Font rendering.
- UI and animation framework at the native level. Inspired by [Flutter](https://github.com/flutter/flutter).
- Javascript sandbox and WASM runtime powered by V8. Inspired by [Deno](https://github.com/denoland/deno).
- General purpose text editor.
- Incremental AST parser and tokenizer.
- Configurable key bindings.
- Permissioned ops to desktop. User code/apps should be able to do more and still be safe.
- Basic HTML/CSS support. The goal is not to support the entire spec, but just enough so the existing web can still be viewed.
- Image/Video decoding.
- DNS/HTTP/HTTPS Client.
- P2P and direct connections to trusted parties. The web should still operate without a central broker.
- Terminal emulation. To the extent of using native tools.
- and more...

## Design
As we make progress, the code will be uploaded into this monorepo.
Once the project has gotten to a reasonable state, we can start to explore some of these questions:
- Why can't every piece of content we see be scraped, reused, repurposed, and transferrable?
- How can we make "view source" be a transparent window so you can change software at your discretion? How should software be built to allow that?
- Why can't there be one way to seamlessly install software and run native performance apps? Why do we need appstores?
- Why can't our web client have a solid UI framework so we don't have to create slow and bloated frontend frameworks?
- Why can't we connect directly to trusted parties without going through a server?
- How can coding be more accessible at different levels of abstraction?
- Why isn't there one way (95%+ use cases) to code and ship software so people have a clear path to learn and be productive?
- Why do we dismiss reusing old software even though they still work?
- and more...

## Contributing
We will be building the app primarily in Zig.
[Why Zig When There is Already C++, D, and Rust?](https://ziglang.org/learn/why_zig_rust_d_cpp)

Zig's toolchain is ideal for this project. Even though it has yet to reach 1.0, it's LLVM backend is stable and stage2 is just around the corner.

Currently, it's recommended to build zig from [source](https://github.com/ziglang/zig).

Please star the repo and let's do this!

## License

Cosmic will be free and open source under the MIT License.