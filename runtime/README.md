### JavaScript Runtime

Initially, this was created to provide a scripting interface for cross platform graphics, ui, and io. Currently, this is on halt and a new scripting language is being built.

## Getting Started
You can download a prebuilt version of the runtime from the Releases page.
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
