const c = @cImport({
    @cInclude("openssl/ssl.h");
});

pub usingnamespace c;

pub inline fn initLibrary() c_int {
    return c.OPENSSL_init_ssl(@as(c_int, 0), null);
}

pub inline fn addAllAlgorithms() c_int {
    return addAllAlgorithmsNoconf();
}

pub inline fn addAllAlgorithmsNoconf() c_int {
    return c.OPENSSL_init_crypto((c.OPENSSL_INIT_ADD_ALL_CIPHERS | c.OPENSSL_INIT_ADD_ALL_DIGESTS) | c.OPENSSL_INIT_LOAD_CONFIG, null);
}