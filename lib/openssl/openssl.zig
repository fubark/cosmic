const c = @cImport({
    @cInclude("openssl/ssl.h");
});

pub usingnamespace c;