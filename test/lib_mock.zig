const gl = @import("gl");
const GLint = gl.GLint;
const GLsizei = gl.GLsizei;
const GLclampf = gl.GLclampf;
const GLenum = gl.GLenum;

// Mocked out external deps.

export fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;
}

export fn glClearColor(red: GLclampf, green: GLclampf, blue: GLclampf, alpha: GLclampf) void {
    _ = red;
    _ = green;
    _ = blue;
    _ = alpha;
}

export fn glDisable(cap: GLenum) void {
    _ = cap;
}

export fn glEnable(cap: GLenum) void {
    _ = cap;
}

export fn glGetIntegerv(pname: GLenum, params: [*c]GLint) void {
    _ = pname;
    _ = params;
}

export fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) void {
    _ = sfactor;
    _ = dfactor;
}

export fn lyon_init() void {}

export fn lyon_deinit() void {}

export fn glDeleteBuffers() void {}
export fn glDeleteVertexArrays() void {}
export fn glDeleteTextures() void {}
export fn glUniformMatrix4fv() void {}
export fn glUniform1i() void {}
export fn glBufferData() void {}
export fn glDrawElements() void {}
export fn glTexSubImage2D() void {}

export fn SDL_GL_DeleteContext() void {}
export fn SDL_DestroyWindow() void {}

export fn v8__Persistent__Reset() void {}
export fn v8__Boolean__New() void {}

export fn stbtt_GetGlyphBitmapBox() void {}
export fn stbtt_MakeGlyphBitmap() void {}

export fn v8__HandleScope__CONSTRUCT() void {}
export fn v8__TryCatch__CONSTRUCT() void {}
export fn v8__Value__IsAsyncFunction() void {}
export fn v8__Function__Call() void {}
export fn v8__Function__New__DEFAULT2() void {}
export fn v8__ObjectTemplate__SetInternalFieldCount() void {}
export fn v8__ObjectTemplate__NewInstance() void {}
export fn v8__Object__SetInternalField() void {}
export fn v8__Promise__Then2() void {}
export fn v8__TryCatch__DESTRUCT() void {}
export fn v8__HandleScope__DESTRUCT() void {}
export fn v8__Object__GetInternalField() void {}
export fn v8__External__Value() void {}
export fn v8__Value__Uint32Value() void {}
export fn v8__Persistent__New() void {}
export fn v8__Value__NumberValue() void {}
export fn v8__Persistent__SetWeakFinalizer() void {}
export fn v8__WeakCallbackInfo__GetParameter() void {}
export fn curl_slist_free_all() void {}
export fn v8__Promise__Resolver__New() void {}
export fn v8__Promise__Resolver__GetPromise() void {}
export fn uv_timer_init() void {}
export fn uv_async_send() void {}
export fn TLS_server_method() void {}
export fn SSL_CTX_new() void {}
export fn OPENSSL_init_ssl() void {}
export fn OPENSSL_init_crypto() void {}
export fn SSL_CTX_set_options() void {}
export fn SSL_CTX_use_PrivateKey_file() void {}
export fn SSL_CTX_set_cipher_list() void {}
export fn SSL_CTX_set_ciphersuites() void {}
export fn SSL_CTX_use_certificate_chain_file() void {}
export fn h2o_get_alpn_protocols() void {}
export fn h2o_ssl_register_alpn_protocols() void {}
export fn v8__FunctionTemplate__GetFunction() void {}
export fn v8__Function__NewInstance() void {}
export fn uv_timer_start() void {}
export fn h2o_strdup() void {}
export fn h2o_set_header_by_str() void {}
export fn h2o_start_response() void {}
export fn h2o_send() void {}
export fn v8__FunctionCallbackInfo__Length() void {}
export fn v8__FunctionCallbackInfo__INDEX() void {}
export fn v8__ArrayBufferView__Buffer() void {}
export fn v8__ArrayBuffer__GetBackingStore() void {}
export fn std__shared_ptr__v8__BackingStore__get() void {}
export fn v8__BackingStore__ByteLength() void {}
export fn v8__BackingStore__Data() void {}
export fn std__shared_ptr__v8__BackingStore__reset() void {}
export fn v8__Value__IsObject() void {}
export fn v8__Object__Get() void {}
export fn v8__Object__Set() void {}
export fn v8__External__New() void {}
export fn v8__ObjectTemplate__New__DEFAULT() void {}
export fn v8__String__NewFromUtf8() void {}
export fn v8__TryCatch__HasCaught() void {}
export fn v8__TryCatch__Message() void {}
export fn v8__Message__GetSourceLine() void {}
export fn v8__Message__GetStartColumn() void {}
export fn v8__Message__GetEndColumn() void {}
export fn v8__TryCatch__StackTrace() void {}
export fn v8__TryCatch__Exception() void {}
export fn v8__Value__ToString() void {}
export fn v8__String__Utf8Length() void {}
export fn v8__String__WriteUtf8() void {}
export fn SDL_InitSubSystem() void {}
export fn SDL_GetError() void {}
export fn SDL_GetWindowID() void {}
export fn stbi_load_from_memory() void {}
export fn stbi_image_free() void {}
export fn glGenTextures() void {}
export fn glBindTexture() void {}
export fn glTexParameteri() void {}
export fn glTexImage2D() void {}
export fn curl_slist_append() void {}
export fn curl_easy_setopt() void {}
export fn curl_easy_perform() void {}
export fn curl_easy_getinfo() void {}
export fn curl_easy_init() void {}
export fn curl_multi_add_handle() void {}
export fn uv_tcp_init() void {}
export fn uv_strerror() void {}
export fn uv_ip4_addr() void {}
export fn uv_tcp_bind() void {}
export fn uv_listen() void {}
export fn h2o_config_register_host() void {}
export fn h2o_context_init() void {}
export fn h2o_context_request_shutdown() void {}
export fn uv_close() void {}
export fn uv_accept() void {}
export fn h2o_uv_socket_create() void {}
export fn h2o_accept() void {}
export fn uv_handle_get_type() void {}
export fn h2o_config_register_path() void {}
export fn h2o_create_handler() void {}
export fn v8__Integer__NewFromUnsigned() void {}
export fn v8__FunctionCallbackInfo__Data() void {}
export fn v8__Object__New() void {}
export fn v8__Exception__Error() void {}
export fn v8__Isolate__ThrowException() void {}
export fn SDL_GL_CreateContext() void {}
export fn glGetString() void {}
export fn SDL_GL_MakeCurrent() void {}
export fn SDL_GL_SetAttribute() void {}
export fn SDL_CreateWindow() void {}
export fn glActiveTexture() void {}
export fn stbtt_GetGlyphKernAdvance() void {}
export fn lyon_new_builder() void {}
export fn lyon_begin() void {}
export fn lyon_cubic_bezier_to() void {}
export fn lyon_end() void {}
export fn lyon_build_stroke() void {}
export fn lyon_quadratic_bezier_to() void {}
export fn lyon_add_polygon() void {}
export fn lyon_build_fill() void {}
export fn v8__Number__New() void {}
export fn v8__Promise__Resolver__Resolve() void {}
export fn v8__Promise__Resolver__Reject() void {}
export fn v8__Value__BooleanValue() void {}
export fn glBindVertexArray() void {}
export fn glBindBuffer() void {}
export fn glEnableVertexAttribArray() void {}
export fn glCreateShader() void {}
export fn glShaderSource() void {}
export fn glCompileShader() void {}
export fn glGetShaderiv() void {}
export fn glGetShaderInfoLog() void {}
export fn glDeleteShader() void {}
export fn glCreateProgram() void {}
export fn glAttachShader() void {}
export fn glLinkProgram() void {}
export fn glGetProgramiv() void {}
export fn glGetProgramInfoLog() void {}
export fn glDeleteProgram() void {}
export fn glDetachShader() void {}
export fn glGenVertexArrays() void {}
export fn glGenFramebuffers() void {}
export fn glBindFramebuffer() void {}
export fn glTexImage2DMultisample() void {}
export fn glFramebufferTexture2D() void {}
export fn glGenBuffers() void {}
export fn glVertexAttribPointer() void {}
export fn stbtt_InitFont() void {}
export fn lyon_line_to() void {}
export fn v8__Array__New2() void {}
export fn v8__ArrayBuffer__NewBackingStore() void {}
export fn v8__BackingStore__TO_SHARED_PTR() void {}
export fn v8__ArrayBuffer__New2() void {}
export fn v8__Uint8Array__New() void {}
export fn glUseProgram() void {}
export fn h2o_config_init() void {}
export fn v8__Message__GetStackTrace() void {}
export fn v8__StackTrace__GetFrameCount() void {}
export fn v8__StackTrace__GetFrame() void {}
export fn v8__StackFrame__GetFunctionName() void {}
export fn v8__StackFrame__GetScriptNameOrSourceURL() void {}
export fn v8__StackFrame__GetLineNumber() void {}
export fn v8__StackFrame__GetColumn() void {}