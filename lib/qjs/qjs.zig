const c = @cImport({
    @cInclude("quickjs.h");
    @cInclude("quickjs-libc.h");
});

pub usingnamespace c;