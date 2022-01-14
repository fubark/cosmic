#include "h2o.h"

// Not sure why we can't bind with zig's pub extern const
const h2o_iovec_t* h2o_get_http2_alpn_protocols() {
	return h2o_http2_alpn_protocols;
}

const h2o_iovec_t* h2o_get_alpn_protocols() {
	return h2o_alpn_protocols;
}

size_t h2o_globalconf_size() {
	return sizeof(h2o_globalconf_t);
}

size_t h2o_hostconf_size() {
	return sizeof(h2o_hostconf_t);
}

size_t h2o_context_size() {
	return sizeof(h2o_context_t);
}

size_t h2o_accept_ctx_size() {
	return sizeof(h2o_accept_ctx_t);
}

size_t h2o_httpclient_ctx_size() {
	return sizeof(h2o_httpclient_ctx_t);
}

size_t h2o_socket_size() {
	return sizeof(h2o_socket_t);
}