#include "h2o.h"

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