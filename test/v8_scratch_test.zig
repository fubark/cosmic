const std = @import("std");
const stdx = @import("stdx");
const v8 = @import("v8");
const t = stdx.testing;
const log = stdx.log.scoped(.v8_scratch);

// Playground to test v8 code.
// Run with: zig build test-file -Dpath="test/v8_scratch_test.zig"

test {
    t.setLogLevel(.debug);
    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    defer v8.deinitV8Platform();

    v8.initV8();
    defer _ = v8.deinitV8();

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);

    var iso = v8.Isolate.init(&params);
    defer iso.deinit();

    iso.enter();
    defer iso.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    // Body.
}