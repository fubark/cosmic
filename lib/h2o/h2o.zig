const std = @import("std");
const uv = @import("uv");
const ssl = @import("openssl");

const c = @cImport({
    @cDefine("H2O_USE_LIBUV", "1");
    @cInclude("h2o.h");
    @cInclude("h2o/http1.h");
    @cInclude("h2o/http2.h");
});

// pub usingnamespace c;

const h2o_loop = uv.uv_loop_t;

pub extern fn h2o_config_init(config: *h2o_globalconf) void;
pub extern fn h2o_config_dispose(config: *h2o_globalconf) void;
pub extern fn h2o_config_register_host(config: *h2o_globalconf, host: h2o_iovec_t, port: u16) *h2o_hostconf;
pub extern fn h2o_config_register_path(hostconf: [*c]h2o_hostconf, path: [*c]const u8, flags: c_int) [*c]h2o_pathconf;
pub extern fn h2o_create_handler(conf: [*c]h2o_pathconf, sz: usize) ?*h2o_handler;
pub extern fn h2o_context_init(context: *h2o_context, loop: *h2o_loop, config: [*c]h2o_globalconf) void;
pub extern fn h2o_context_dispose(context: *h2o_context) void;
pub extern fn h2o_context_request_shutdown(context: *h2o_context) void;
pub extern fn h2o_accept(ctx: [*c]h2o_accept_ctx, sock: *h2o_socket) void; 
pub extern fn h2o_add_header(pool: *c.h2o_mem_pool_t, headers: *h2o_headers, token: *const h2o_token, orig_name: [*c]const u8, value: [*c]const u8, value_len: usize) isize;
pub extern fn h2o_set_header(pool: *c.h2o_mem_pool_t, headers: *h2o_headers, token: *const h2o_token, value: [*c]const u8, value_len: usize, overwrite_if_exists: c_int) isize;
pub extern fn h2o_set_header_by_str(pool: *c.h2o_mem_pool_t, headers: *h2o_headers, lowercase_name: [*c]const u8, lowercase_name_len: usize, maybe_token: c_int, value: [*c]const u8, value_len: usize, overwrite_if_exists: c_int) isize;
pub extern fn h2o_start_response(req: ?*h2o_req, generator: [*c]c.h2o_generator_t) void;
pub extern fn h2o_strdup(pool: *c.h2o_mem_pool_t, s: [*c]const u8, len: usize) c.h2o_iovec_t;
pub extern fn h2o_send(req: ?*h2o_req, bufs: [*c]c.h2o_iovec_t, bufcnt: usize, state: c.h2o_send_state_t) void;
pub extern fn h2o_uv_socket_create(handle: *uv.uv_handle_t, close_cb: uv.uv_close_cb) ?*h2o_socket;
pub extern fn h2o_ssl_register_alpn_protocols(ctx: *ssl.SSL_CTX, protocols: [*c]const h2o_iovec_t) void;
pub extern fn h2o_access_log_open_handle(path: [*c]const u8, fmt: [*c]const u8, escape: c_int) ?*c.h2o_access_log_filehandle_t;
pub extern fn h2o_access_log_register(pathconf: [*c]h2o_pathconf, handle: ?*anyopaque) [*c]*anyopaque;
pub extern fn h2o_timer_unlink(timer: *c.h2o_timer_t) void;

pub const H2O_LOGCONF_ESCAPE_APACHE = c.H2O_LOGCONF_ESCAPE_APACHE;
pub const H2O_LOGCONF_ESCAPE_JSON = c.H2O_LOGCONF_ESCAPE_JSON;

// Includes just http2
pub extern fn h2o_get_http2_alpn_protocols() [*c]const h2o_iovec_t;
// Includes http2 and http1
pub extern fn h2o_get_alpn_protocols() [*c]const h2o_iovec_t;
pub extern fn h2o_globalconf_size() usize;
pub extern fn h2o_hostconf_size() usize;
pub extern fn h2o_context_size() usize;
pub extern fn h2o_accept_ctx_size() usize;
pub extern fn h2o_httpclient_ctx_size() usize;
pub extern fn h2o_socket_size() usize;

pub extern const h2o__tokens: [100]h2o_token;
pub var H2O_TOKEN_CONTENT_TYPE: *const h2o_token = undefined;

pub fn init() void {
    // Initialize constants.
    H2O_TOKEN_CONTENT_TYPE = &h2o__tokens[31];

    // Verify struct sizes.
    // std.debug.print("sizes {} {}\n", .{ h2o_httpclient_ctx_size(), @sizeOf(h2o_httpclient_ctx) });
    std.debug.assert(h2o_globalconf_size() == @sizeOf(h2o_globalconf));
    std.debug.assert(h2o_hostconf_size() == @sizeOf(h2o_hostconf));
    std.debug.assert(h2o_httpclient_ctx_size() == @sizeOf(h2o_httpclient_ctx));
    std.debug.assert(h2o_context_size() == @sizeOf(h2o_context));
    std.debug.assert(h2o_accept_ctx_size() == @sizeOf(h2o_accept_ctx));
    std.debug.assert(h2o_socket_size() == @sizeOf(h2o_socket));
}

// Send states.
pub const H2O_SEND_STATE_IN_PROGRESS = c.H2O_SEND_STATE_IN_PROGRESS;
pub const H2O_SEND_STATE_FINAL = c.H2O_SEND_STATE_FINAL; // Indicates eof.
pub const H2O_SEND_STATE_ERROR = c.H2O_SEND_STATE_ERROR;

pub const h2o_generator_t = c.h2o_generator_t;

pub fn h2o_iovec_init(slice: []const u8) h2o_iovec_t {
    return .{
        .base = @ptrToInt(slice.ptr),
        .len = slice.len,
    };
}

pub const h2o_iovec_t = c.h2o_iovec_t;
pub const h2o_req_t = c.h2o_req_t;
pub const uv_loop_t = c.uv_loop_t;
pub const uv_loop_init = c.uv_loop_init;
pub const uv_tcp_t = c.uv_tcp_t;
pub const uv_accept = c.uv_accept;
pub const uv_close_cb = c.uv_close_cb;
pub const free = c.free;
pub const uv_tcp_init = c.uv_tcp_init;
pub const sockaddr_in = c.sockaddr_in;
pub const sockaddr = c.sockaddr;
pub const uv_ip4_addr = c.uv_ip4_addr;
pub const uv_tcp_bind = c.uv_tcp_bind;
pub const uv_strerror = c.uv_strerror;
pub const uv_close = c.uv_close;
pub const uv_handle_t = c.uv_handle_t;
pub const uv_listen = c.uv_listen;
pub const uv_stream_t = c.uv_stream_t;
pub const uv_run = c.uv_run;
pub const UV_RUN_DEFAULT = c.UV_RUN_DEFAULT;
pub const h2o_socket_t = c.h2o_socket_t;
pub const h2o_mem_alloc = c.h2o_mem_alloc;

// https://github.com/ziglang/zig/issues/1499
// Declare structs as needed if they contain bit fields.

pub const h2o_globalconf = extern struct {
    hosts: [*c][*c]h2o_hostconf,
    fallback_host: [*c]h2o_hostconf,
    configurators: c.h2o_linklist_t,
    server_name: c.h2o_iovec_t,
    max_request_entity_size: usize,
    max_delegations: c_uint,
    user: [*c]u8,
    usdt_selective_tracing: c_int,
    handshake_timeout: u64,
    http1: struct_unnamed_189,
    http2: struct_unnamed_190,
    http3: struct_unnamed_191,
    proxy: struct_unnamed_192,
    send_informational_mode: c.h2o_send_informational_mode_t,
    mimemap: ?*c.h2o_mimemap_t,
    filecache: struct_unnamed_193,
    statuses: h2o_status_callbacks,
    _num_config_slots: usize,
};

pub const h2o_hostconf = extern struct {
    global: [*c]h2o_globalconf,
    authority: struct_unnamed_172,
    strict_match: u8,
    paths: struct_unnamed_173,
    fallback_path: h2o_pathconf,
    mimemap: ?*c.h2o_mimemap_t,
    http2: struct_unnamed_188,
};

const struct_unnamed_188 = extern struct {
    fields: packed struct {
        /// whether if blocking assets being pulled should be given highest priority in case of clients that do not implement
        /// dependency-based prioritization
        reprioritize_blocking_assets: bool,

        /// if server push should be used
        push_preload: bool,
        
        /// if cross origin pushes should be authorized
        allow_cross_origin_push: bool,
    },
    /// casper settings
    capser: c.h2o_casper_conf_t
};

const struct_unnamed_172 = extern struct {
    hostport: c.h2o_iovec_t,
    host: c.h2o_iovec_t,
    port: u16,
};

const struct_unnamed_173 = extern struct {
    entries: [*c][*c]h2o_pathconf,
    size: usize,
    capacity: usize,
};

const struct_unnamed_174 = extern struct {
    entries: [*c]?*h2o_handler,
    size: usize,
    capacity: usize,
};

const struct_unnamed_185 = extern struct {
    entries: [*c][*c]h2o_filter,
    size: usize,
    capacity: usize,
};

const struct_unnamed_186 = extern struct {
    entries: [*c][*c]h2o_logger,
    size: usize,
    capacity: usize,
};

const struct_unnamed_187 = extern struct {
    fields: packed struct {
        /// if request-level errors should be emitted to stderr
        emit_request_errors: bool,
    },
};

pub const h2o_pathconf = extern struct {
    global: [*c]h2o_globalconf,
    path: c.h2o_iovec_t,
    handlers: struct_unnamed_174,
    _filters: struct_unnamed_185,
    _loggers: struct_unnamed_186,
    mimemap: ?*c.h2o_mimemap_t,
    env: [*c]c.h2o_envconf_t,
    error_log: struct_unnamed_187,
};

const h2o_filter = extern struct {
    _config_slot: usize,
    on_context_init: ?fn ([*c]h2o_filter, [*c]h2o_context) callconv(.C) void,
    on_context_dispose: ?fn ([*c]h2o_filter, [*c]h2o_context) callconv(.C) void,
    dispose: ?fn ([*c]h2o_filter) callconv(.C) void,
    on_setup_ostream: ?fn ([*c]h2o_filter, ?*c.h2o_req_t, [*c][*c]c.h2o_ostream_t) callconv(.C) void,
    on_informational: ?fn ([*c]h2o_filter, ?*c.h2o_req_t) callconv(.C) void,
};

pub const h2o_context = extern struct {
    loop: *h2o_loop,
    globalconf: *h2o_globalconf,
    queue: ?*c.h2o_multithread_queue_t,
    receivers: struct_unnamed_194,
    filecache: ?*c.h2o_filecache_t,
    storage: c.h2o_context_storage_t,
    shutdown_requested: c_int,
    http1: struct_unnamed_195,
    http2: struct_unnamed_197,
    http3: struct_unnamed_199,
    proxy: struct_unnamed_201,
    ssl: struct_unnamed_202,
    quic: c.struct_st_h2o_quic_aggregated_stats_t,
    _module_configs: [*c]?*anyopaque,
    _timestamp_cache: struct_unnamed_206,
    emitted_error_status: [10]u64,
    _pathconfs_inited: struct_unnamed_207,
};

const struct_unnamed_194 = extern struct {
    hostinfo_getaddr: c.h2o_multithread_receiver_t,
};

const struct_unnamed_196 = extern struct {
    request_timeouts: u64,
    request_io_timeouts: u64,
};

const struct_unnamed_195 = extern struct {
    _conns: c.h2o_linklist_t,
    events: struct_unnamed_196,
};

const struct_unnamed_197 = extern struct {
    _conns: c.h2o_linklist_t,
    _graceful_shutdown_timeout: c.h2o_timer_t,
    events: struct_unnamed_198,
};

const struct_unnamed_198 = extern struct {
    protocol_level_errors: [13]u64,
    read_closed: u64,
    write_closed: u64,
    idle_timeouts: u64,
    streaming_requests: u64,
};

const struct_unnamed_201 = extern struct {
    client_ctx: h2o_httpclient_ctx,
    connpool: c.h2o_httpclient_connection_pool_t,
};

const struct_unnamed_202 = extern struct {
    errors: u64,
    alpn_h1: u64,
    alpn_h2: u64,
    handshake_full: u64,
    handshake_resume: u64,
    handshake_accum_time_full: u64,
    handshake_accum_time_resume: u64,
};

const struct_unnamed_206 = extern struct {
    tv_at: c.struct_timeval,
    value: [*c]c.h2o_timestamp_string_t,
};

const struct_unnamed_207 = extern struct {
    entries: [*c][*c]h2o_pathconf,
    size: usize,
    capacity: usize,
};

const struct_unnamed_200 = extern struct {
    packet_forwarded: u64,
    forwarded_packet_received: u64,
};

const struct_unnamed_199 = extern struct {
    _conns: c.h2o_linklist_t,
    _graceful_shutdown_timeout: c.h2o_timer_t,
    events: struct_unnamed_200,
};

const h2o_httpclient_ctx = extern struct {
    loop: *c.h2o_loop_t,
    getaddr_receiver: *c.h2o_multithread_receiver_t,
    io_timeout: u64,
    connect_timeout: u64,
    first_byte_timeout: u64,
    keepalive_timeout: u64, // only used for http2 for now
    max_buffer_size: usize,
    
    fields: packed struct {
        tunnel_enabled: bool,
        force_cleartext_http2: bool,
    },

    protocol_selector: extern struct {
        ratio: c.h2o_httpclient_protocol_ratio_t,
        
        /// Each deficit is initialized to zero, then incremented by the respective percentage, and the protocol corresponding to the
        /// one with the highest value is chosen. Then, the chosen variable is decremented by 100.
        _deficits: [4]i16,
    },

    /// HTTP/2-specific settings
    http2: extern struct {
        latency_optimization: c.h2o_socket_latency_optimization_conditions_t,
        max_concurrent_streams: u32,
    },

    /// HTTP/3-specific settings; 1-to(0|1) relationship, NULL when h3 is not used
    http3: *h2o_http3client_ctx,
};

const h2o_http3client_ctx = extern struct {
    tls: ptls_context,
    quic: quicly_context,
    h3: h2o_quic_ctx,
    load_session: ?fn (?*h2o_httpclient_ctx, [*c]c.struct_sockaddr, [*c]const u8, [*c]c.ptls_iovec_t, [*c]c.ptls_iovec_t, ?*quicly_transport_parameters) callconv(.C) c_int,
};

const ptls_context = extern struct {
    /// PRNG to be used
    random_bytes: ?fn (buf: ?*anyopaque, len: usize) callconv (.C) void,

    get_time: *c.ptls_get_time_t,

    /// list of supported key-exchange algorithms terminated by NULL
    key_exchanges: **c.ptls_key_exchange_algorithm_t,

    /// list of supported cipher-suites terminated by NULL
    cipher_suites: **c.ptls_cipher_suite_t,

    /// list of certificates
    certificates: extern struct {
        list: *c.ptls_iovec_t,
        count: usize,
    },

    /// list of ESNI data terminated by NULL
    esni: **c.ptls_esni_context_t,

    on_client_hello: *c.ptls_on_client_hello_t,

    emit_certificate: *c.ptls_emit_certificate_t,

    sign_certificate: *c.ptls_sign_certificate_t,

    verify_certificate: *c.ptls_verify_certificate_t,

    /// lifetime of a session ticket (server-only)
    ticket_lifetime: u32,

    /// maximum permitted size of early data (server-only)
    max_early_data_size: u32,

    /// maximum size of the message buffer (default: 0 = unlimited = 3 + 2^24 bytes)
    max_buffer_size: usize,

    /// the field is obsolete; should be set to NULL for QUIC draft-17.  Note also that even though everybody did, it was incorrect
    /// to set the value to "quic " in the earlier versions of the draft.
    hkdf_label_prefix__obsolete: [*c]const u8,

    fields: packed struct {
        /// if set, psk handshakes use (ec)dhe
        require_dhe_on_psk: bool,
        /// if exporter master secrets should be recorded
        use_exporter: bool,
        /// if ChangeCipherSpec record should be sent during handshake. If the client sends CCS, the server sends one in response
        /// regardless of the value of this flag. See RFC 8446 Appendix D.3.
        send_change_cipher_spec: bool,
        /// if set, the server requests client certificates
        /// to authenticate the client.
        require_client_authentication: bool,
        /// if set, EOED will not be emitted or accepted
        omit_end_of_early_data: bool,
        /// This option turns on support for Raw Public Keys (RFC 7250).
        /// 
        /// When running as a client, this option instructs the client to request the server to send raw public keys in place of X.509
        /// certificate chain. The client should set its `certificate_verify` callback to one that is capable of validating the raw
        /// public key that will be sent by the server.
        ///
        /// When running as a server, this option instructs the server to only handle clients requesting the use of raw public keys. If
        /// the client does not, the handshake is rejected. Note however that the rejection happens only after the `on_client_hello`
        /// callback is being called. Therefore, applications can support both X.509 and raw public keys by swapping `ptls_context_t` to
        /// the correct one when that callback is being called (like handling swapping the contexts based on the value of SNI).
        use_raw_public_keys: bool,
        /// boolean indicating if the cipher-suite should be chosen based on server's preference
        server_cipher_preference: bool,
    },
    encrypt_ticket: *c.ptls_encrypt_ticket_t,
    save_ticket: *c.ptls_save_ticket_t,
    log_event: *c.ptls_log_event_t,
    update_open_count: *c.ptls_update_open_count_t,
    update_traffic_key: *c.ptls_update_traffic_key_t,
    decompress_certificate: *c.ptls_decompress_certificate_t,
    update_esni_key: *c.ptls_update_esni_key_t,
    on_extension: *c.ptls_on_extension_t,
};

const quicly_context = extern struct {
    /// tls context to use
    tls: *ptls_context,

    /// Maximum size of packets that we are willing to send when path-specific information is unavailable. As a path-specific
    /// optimization, quicly acting as a server expands this value to `min(local.tp.max_udp_payload_size,
    /// remote.tp.max_udp_payload_size, max_size_of_incoming_datagrams)` when it receives the Transport Parameters from the client.
    initial_egress_max_udp_payload_size: u16,

    /// loss detection parameters
    loss: c.quicly_loss_conf_t,

    /// transport parameters
    transport_params: quicly_transport_parameters,

    /// number of packets that can be sent without a key update
    max_packets_per_key: u64,

    /// maximum number of bytes that can be transmitted on a CRYPTO stream (per each epoch)
    max_crypto_bytes: u64,

    /// initial CWND in terms of packet numbers
    initcwnd_packets: u32,

    /// (client-only) Initial QUIC protocol version used by the client. Setting this to a greased version will enforce version
    /// negotiation.
    initial_version: u32,

    /// (server-only) amplification limit before the peer address is validated
    pre_validation_amplification_limit: u16,

    /// How frequent the endpoint should induce ACKs from the peer, relative to RTT (or CWND) multiplied by 1024. As an example, 128
    /// will request the peer to send one ACK every 1/8 RTT (or CWND). 0 disables the use of the delayed-ack extension.
    ack_frequency: u16,

    fields: packed struct {
        /// expand client hello so that it does not fit into one datagram
        expand_client_hello: bool,
    },

    cid_encryptor: *c.quicly_cid_encryptor_t,

    /// callback called when a new stream is opened by remote peer
    stream_open: *c.quicly_stream_open_t,

    /// callbacks for scheduling stream data
    stream_scheduler: *c.quicly_stream_scheduler_t,

    /// callback for receiving datagram frame
    receive_datagram_frame: *c.quicly_receive_datagram_frame_t,

    /// callback called when a connection is closed by remote peer
    closed_by_remote: *c.quicly_closed_by_remote_t,

    /// returns current time in milliseconds
    now: *c.quicly_now_t,

    /// called wen a NEW_TOKEN token is being received
    save_resumption_token: *c.quicly_save_resumption_token_t,

    generate_resumption_token: *quicly_generate_resumption_token_t,

    /// crypto engine (offload API)
    crypto_engine: *c.quicly_crypto_engine_t,

    /// initializes a congestion controller for given connection.
    init_cc: *quicly_init_cc,

    /// optional refcount callback
    update_open_count: *c.quicly_update_open_count_t,
};

const quicly_generate_resumption_token_t = extern struct {
    cb: ?fn ([*c]struct_st_quicly_generate_resumption_token_t, ?*c.quicly_conn_t, [*c]c.ptls_buffer_t, [*c]quicly_address_token_plaintext_t) callconv(.C) c_int,
};

pub const struct_st_quicly_generate_resumption_token_t = extern struct {
    cb: ?fn ([*c]struct_st_quicly_generate_resumption_token_t, ?*c.quicly_conn_t, [*c]c.ptls_buffer_t, [*c]quicly_address_token_plaintext_t) callconv(.C) c_int,
};

const quicly_address_token_plaintext_t = extern struct {
    stub: c_int,
};

/// Transport Parameters; the struct contains "configuration parameters", ODCID is managed separately
const quicly_transport_parameters = extern struct {
    /// in octets
    max_stream_data: c.quicly_max_stream_data_t,

    /// in octets
    max_data: u64,

    /// in milliseconds
    max_idle_timeout: u64,

    max_streams_bidi: u64,

    max_streams_uni: u64,

    max_udp_payload_size: u64,

    /// quicly ignores the value set for quicly_context_t::transport_parameters
    ack_delay_exponent: u8,

    /// in milliseconds; quicly ignores the value set for quicly_context_t::transport_parameters
    max_ack_delay: u16,

    /// Delayed-ack extension. UINT64_MAX indicates that the extension is disabled or that the peer does not support it. Any local
    /// value other than UINT64_MAX indicates that the use of the extension should be negotiated.
    min_ack_delay_usec: u64,

    fields: packed struct {
        disable_active_migration: bool,
    },

    active_connection_id_limit: u64,

    max_datagram_frame_size: u16,
};

const quicly_sent_packet = extern struct {
    packet_numberr: u64,
    sent_at: i64,
    /// epoch to be acked in
    ack_epoch: u8,

    fields: packed struct {
        ack_eliciting: bool,
        /// if the frames being contained are considered inflight (becomes zero when deemed lost or when PTO fires)
        frames_in_flight: bool,
    },
    /// number of bytes in-flight for the packet, from the context of CC (becomes zero when deemed lost, but not when PTO fires)
    cc_bytes_in_flight: u16,
};

const union_unnamed_111 = extern union {
    packet: quicly_sent_packet,
    ack: struct_unnamed_112,
    stream: struct_unnamed_116,
    max_stream_data: struct_unnamed_117,
    max_data: struct_unnamed_118,
    max_streams: struct_unnamed_119,
    data_blocked: struct_unnamed_120,
    stream_data_blocked: struct_unnamed_121,
    streams_blocked: struct_unnamed_122,
    stream_state_sender: struct_unnamed_123,
    new_token: struct_unnamed_124,
    new_connection_id: struct_unnamed_125,
    retire_connection_id: struct_unnamed_126,
};

const quicly_sent_acked_cb = fn (map: *quicly_sentmap, packet: *const quicly_sent_packet, acked: c_int, data: *quicly_sent) callconv(.C) c_int;

const quicly_sent = extern struct {
    acked: quicly_sent_acked_cb,
    data: union_unnamed_111,
};

const quicly_sent_block = extern struct {
    next: [*c]quicly_sent_block,
    num_entries: usize,
    next_insert_at: usize,
    entries: [16]quicly_sent,
};

const quicly_sentmap = extern struct {
    head: [*c]quicly_sent_block,
    tail: [*c]quicly_sent_block,
    num_packets: usize,
    bytes_in_flight: usize,
    _pending_packet: [*c]quicly_sent,
};

const quicly_loss = extern struct {
    conf: [*c]const c.quicly_loss_conf_t,
    max_ack_delay: [*c]const u16,
    ack_delay_exponent: [*c]const u8,
    pto_count: i8,
    time_of_last_packet_sent: i64,
    largest_acked_packet_plus1: [4]u64,
    total_bytes_sent: u64,
    loss_time: i64,
    alarm_at: i64,
    rtt: c.quicly_rtt_t,
    sentmap: quicly_sentmap,
};

const quicly_cc_type = extern struct {
    name: [*c]const u8,
    cc_init: [*c]quicly_init_cc,
    cc_on_acked: ?fn ([*c]quicly_cc, [*c]const quicly_loss, u32, u64, u32, u64, i64, u32) callconv(.C) void,
    cc_on_lost: ?fn ([*c]quicly_cc, [*c]const quicly_loss, u32, u64, u64, i64, u32) callconv(.C) void,
    cc_on_persistent_congestion: ?fn ([*c]quicly_cc, [*c]const quicly_loss, i64) callconv(.C) void,
    cc_on_sent: ?fn ([*c]quicly_cc, [*c]const quicly_loss, u32, i64) callconv(.C) void,
    cc_switch: ?fn ([*c]quicly_cc) callconv(.C) c_int,
};

const quicly_cc = extern struct {
    type: [*c]const quicly_cc_type,
    cwnd: u32,
    ssthresh: u32,
    recovery_end: u64,
    state: union_unnamed_127,
    cwnd_initial: u32,
    cwnd_exiting_slow_start: u32,
    cwnd_minimum: u32,
    cwnd_maximum: u32,
    num_loss_episodes: u32,
};

const quicly_init_cc = extern struct {
    cb: ?fn ([*c]quicly_init_cc, [*c]quicly_cc, u32, i64) callconv(.C) void,
};

const struct_unnamed_114 = extern struct {
    start_length: u64,
    additional: [4]c.struct_st_quicly_sent_ack_additional_t,
};
const struct_unnamed_115 = extern struct {
    start_length: u8,
    additional: [7]c.struct_st_quicly_sent_ack_additional_t,
};
const union_unnamed_113 = extern union {
    ranges64: struct_unnamed_114,
    ranges8: struct_unnamed_115,
};
const struct_unnamed_112 = extern struct {
    start: u64,
    unnamed_0: union_unnamed_113,
};


const struct_unnamed_116 = extern struct {
    stream_id: c.quicly_stream_id_t,
    args: c.quicly_sendstate_sent_t,
};

const struct_unnamed_128 = extern struct {
    stash: u32,
};
const struct_unnamed_129 = extern struct {
    stash: u32,
    bytes_per_mtu_increase: u32,
};
const struct_unnamed_130 = extern struct {
    k: f64,
    w_max: u32,
    w_last_max: u32,
    avoidance_start: i64,
    last_sent_time: i64,
};
const union_unnamed_127 = extern union {
    reno: struct_unnamed_128,
    pico: struct_unnamed_129,
    cubic: struct_unnamed_130,
};

const struct_unnamed_117 = extern struct {
    stream_id: c.quicly_stream_id_t,
    args: quicly_maxsender_sent,
};

const struct_unnamed_118 = extern struct {
    args: quicly_maxsender_sent,
};

const struct_unnamed_119 = extern struct {
    uni: c_int,
    args: quicly_maxsender_sent,
};

const struct_unnamed_120 = extern struct {
    offset: u64,
};
const struct_unnamed_121 = extern struct {
    stream_id: c.quicly_stream_id_t,
    offset: u64,
};
const struct_unnamed_122 = extern struct {
    uni: c_int,
    args: quicly_maxsender_sent,
};
const struct_unnamed_123 = extern struct {
    stream_id: c.quicly_stream_id_t,
};
const struct_unnamed_124 = extern struct {
    is_inflight: c_int,
    generation: u64,
};
const struct_unnamed_125 = extern struct {
    sequence: u64,
};
const struct_unnamed_126 = extern struct {
    sequence: u64,
};

const quicly_maxsender_sent = extern struct {
    fields: packed struct {
        inflight: u1,
        value: u63,
    },
};

const quicly_cid_plaintext = extern struct {
    /// the internal "connection ID" unique to each connection (rather than QUIC's CID being unique to each path)
    master_id: u32,

    fields: packed struct {
        /// path ID of the connection; we issue up to 255 CIDs per connection (see QUICLY_MAX_PATH_ID)
        path_id: u8,
        /// for intra-node routing
        thread_id: u24,
    },
    /// for inter-node routing; available only when using a 16-byte cipher to encrypt CIDs, otherwise set to zero.
    node_id: u64
};

const h2o_quic_ctx = extern struct {
    loop: [*c]c.h2o_loop_t,
    sock: struct_unnamed_154,
    quic: ?*quicly_context,
    next_cid: quicly_cid_plaintext,
    conns_by_id: ?*c.struct_kh_h2o_quic_idmap_s,
    conns_accepting: ?*c.struct_kh_h2o_quic_acceptmap_s,
    notify_conn_update: h2o_quic_notify_connection_update_cb,
    acceptor: h2o_quic_accept_cb,
    accept_thread_divisor: u32,
    forward_packets: h2o_quic_forward_packets_cb,
    default_ttl: u8,
    use_gso: u8,
    preprocess_packet: h2o_quic_preprocess_packet_cb,
};

const struct_unnamed_154 = extern struct {
    sock: ?*c.h2o_socket_t,
    addr: c.struct_sockaddr_storage,
    addrlen: c.socklen_t,
    port: [*c]c.in_port_t,
};

const h2o_quic_notify_connection_update_cb = fn (ctx: *h2o_quic_ctx, conn: *h2o_quic_conn) callconv(.C) void;

const h2o_quic_conn = extern struct {
    ctx: [*c]h2o_quic_ctx,
    quic: ?*c.quicly_conn_t,
    callbacks: [*c]const h2o_quic_conn_callbacks,
    _timeout: c.h2o_timer_t,
    _accept_hashkey: u64,
};

const h2o_quic_conn_callbacks = extern struct {
    destroy_connection: ?fn ([*c]h2o_quic_conn) callconv(.C) void,
};

const h2o_quic_accept_cb = ?fn ([*c]h2o_quic_ctx, [*c]quicly_address_t, [*c]quicly_address_t, [*c]quicly_decoded_packet) callconv(.C) [*c]h2o_quic_conn;

const quicly_address_t = extern struct {
    stub: c_int,
};

const quicly_decoded_packet = extern struct {
    octets: c.ptls_iovec_t,
    cid: struct_unnamed_149,
    version: u32,
    token: c.ptls_iovec_t,
    encrypted_off: usize,
    datagram_size: usize,
    decrypted: struct_unnamed_151,
    _is_stateless_reset_cached: enum_unnamed_152,
};

const struct_unnamed_149 = extern struct {
    /// destination CID
    dest: extern struct {
        /// CID visible on wire
        encrypted: c.ptls_iovec_t,
        /// The decrypted CID, or `quicly_cid_plaintext_invalid`. Assuming that `cid_encryptor` is non-NULL, this variable would
        /// contain a valid value whenever `might_be_client_generated` is false. When `might_be_client_generated` is true, this
        /// value might be set to `quicly_cid_plaintext_invalid`. Note however that, as the CID itself is not authenticated,
        /// a packet might be bogus regardless of the value of the CID.
        /// When `cid_encryptor` is NULL, the value is always set to `quicly_cid_plaintext_invalid`.
        plaintext: quicly_cid_plaintext,
        /// If destination CID might be one generated by a client. This flag would be set for Initial and 0-RTT packets.
        fields: packed struct {
            might_be_client_generated: bool,
        },
    },
    /// source CID; {NULL, 0} if is a short header packet
    src: c.ptls_iovec_t,
};

const struct_unnamed_151 = extern struct {
    pn: u64,
    key_phase: u64,
};

const enum_unnamed_152 = c_uint;

const h2o_quic_forward_packets_cb = ?fn ([*c]h2o_quic_ctx, [*c]const u64, u32, [*c]quicly_address_t, [*c]quicly_address_t, u8, [*c]quicly_decoded_packet, usize) callconv(.C) c_int;
const h2o_quic_preprocess_packet_cb = ?fn ([*c]h2o_quic_ctx, [*c]c.struct_msghdr, [*c]quicly_address_t, [*c]quicly_address_t, [*c]u8) callconv(.C) c_int;

const h2o_logger = extern struct {
    _config_slot: usize,
    on_context_init: ?fn ([*c]h2o_logger, [*c]h2o_context) callconv(.C) void,
    on_context_dispose: ?fn ([*c]h2o_logger, [*c]h2o_context) callconv(.C) void,
    dispose: ?fn ([*c]h2o_logger) callconv(.C) void,
    log_access: ?fn ([*c]h2o_logger, ?*c.h2o_req_t) callconv(.C) void,
};

const struct_unnamed_189 = extern struct {
    req_timeout: u64,
    req_io_timeout: u64,
    upgrade_to_http2: c_int,
    callbacks: h2o_protocol_callbacks,
};

const struct_unnamed_190 = extern struct {
    /// idle timeout (in milliseconds)
    idle_timeout: u64,
    /// graceful shutdown timeout (in milliseconds)
    graceful_shutdown_timeout: u64,
    /// maximum number of HTTP2 requests (per connection) to be handled simultaneously internally.
    /// H2O accepts at most 256 requests over HTTP/2, but internally limits the number of in-flight requests to the value
    /// specified by this property in order to limit the resources allocated to a single connection.
    max_concurrent_requests_per_connection: usize,
    /// maximum number of HTTP2 streaming requests (per connection) to be handled simultaneously internally.
    max_concurrent_streaming_requests_per_connection: usize,
    /// maximum number of streams (per connection) to be allowed in IDLE / CLOSED state (used for tracking dependencies).
    max_streams_for_priority: usize,
    /// size of the stream-level flow control window (once it becomes active)
    active_stream_window_size: u32,
    /// conditions for latency optimization
    latency_optimization: c.h2o_socket_latency_optimization_conditions_t,
    /// list of callbacks
    callbacks: h2o_protocol_callbacks,
    origin_frame: c.h2o_iovec_t,
};

const struct_unnamed_191 = extern struct {
    /// idle timeout (in milliseconds)
    idle_timeout: u64,
    /// graceful shutdown timeout (in milliseconds)
    graceful_shutdown_timeout: u64,
    /// receive window size of the unblocked request stream
    active_stream_window_size: u32,
    /// See quicly_context_t::ack_frequency
    ack_frequency: u16,

    fields: packed struct {
        /// a boolean indicating if the delayed ack extension should be used (default true)
        allow_delayed_ack: bool,
        /// a boolean indicating if UDP GSO should be used when possible
        use_gso: bool,

        padding: u6,
    },

    /// the callbacks
    callbacks: h2o_protocol_callbacks,
};

const struct_unnamed_192 = extern struct {
    /// io timeout (in milliseconds)
    io_timeout: u64,
    /// io timeout (in milliseconds)
    connect_timeout: u64,
    /// io timeout (in milliseconds)
    first_byte_timeout: u64,
    /// keepalive timeout (in milliseconds)
    keepalive_timeout: u64,

    fields: packed struct {
        /// a boolean flag if set to true, instructs the proxy to close the frontend h1 connection on behalf of the upstream
        forward_close_connection: bool,
        /// a boolean flag if set to true, instructs the proxy to preserve the x-forwarded-proto header passed by the client
        preserve_x_forwarded_proto: bool,
        /// a boolean flag if set to true, instructs the proxy to preserve the server header passed by the origin
        preserve_server_header: bool,
        /// a boolean flag if set to true, instructs the proxy to emit x-forwarded-proto and x-forwarded-for headers
        emit_x_forwarded_headers: bool,
        /// a boolean flag if set to true, instructs the proxy to emit a via header
        emit_via_header: bool,
        /// a boolean flag if set to true, instructs the proxy to emit a date header, if it's missing from the upstream response
        emit_missing_date_header: bool,

        padding: u26,
    },

    /// maximum size to buffer for the response
    max_buffer_size: usize,

    http2: extern struct {
        max_concurrent_streams: u32,
    },

    /// See the documentation of `h2o_httpclient_t::protocol_selector.ratio`.
    protocol_ratio: extern struct {
        http2: i8,
        http3: i8,
    },

    /// global socketpool
    global_socket_pool: c.h2o_socketpool_t,
};

const h2o_protocol_callbacks = extern struct {
    request_shutdown: ?fn ([*c]h2o_context) callconv(.C) void,
    foreach_request: ?fn ([*c]h2o_context, ?fn (?*c.h2o_req_t, ?*anyopaque) callconv(.C) c_int, ?*anyopaque) callconv(.C) c_int,
};

const struct_unnamed_193 = extern struct {
    capacity: usize,
};

const h2o_status_callbacks = extern struct {
    entries: [*c][*c]const h2o_status_handler,
    size: usize,
    capacity: usize,
};

const h2o_status_handler = extern struct {
    name: c.h2o_iovec_t,
    final: ?fn (?*anyopaque, [*c]h2o_globalconf, ?*c.h2o_req_t) callconv(.C) c.h2o_iovec_t,
    init: ?fn () callconv(.C) ?*anyopaque,
    per_thread: ?fn (?*anyopaque, [*c]h2o_context) callconv(.C) void,
};

pub const h2o_accept_ctx = extern struct {
    ctx: [*c]h2o_context,
    hosts: [*c][*c]h2o_hostconf,
    ssl_ctx: ?*ssl.SSL_CTX,
    http2_origin_frame: [*c]c.h2o_iovec_t,
    expect_proxy_line: c_int,
    libmemcached_receiver: [*c]c.h2o_multithread_receiver_t,
};

/// basic structure of a handler (an object that MAY generate a response)
/// The handlers should register themselves to h2o_context_t::handlers.
pub const h2o_handler = extern struct {
    _config_slot: usize,
    on_context_init: ?fn(self: *h2o_handler, ctx: *h2o_context) callconv(.C) void,
    on_context_dispose: ?fn(self: *h2o_handler, ctx: *h2o_context) callconv(.C) void,
    dispose: ?fn(self: *h2o_handler) callconv(.C) void,
    on_req: ?fn(self: *h2o_handler, req: *h2o_req) callconv(.C) c_int,
    /// If the flag is set, protocol handler may invoke the request handler before receiving the end of the request body. The request
    /// handler can determine if the protocol handler has actually done so by checking if `req->proceed_req` is set to non-NULL.
    /// In such case, the handler should replace `req->write_req.cb` (and ctx) with its own callback to receive the request body
    /// bypassing the buffer of the protocol handler. Parts of the request body being received before the handler replacing the
    /// callback is accessible via `req->entity`.
    /// The request handler can delay replacing the callback to a later moment. In such case, the handler can determine if
    /// `req->entity` already contains a complete request body by checking if `req->proceed_req` is NULL.
    fields: packed struct {
        supports_request_streaming: bool,
    },
};

const h2o_conn_callbacks = extern struct {
    get_sockname: ?fn ([*c]h2o_conn, [*c]c.struct_sockaddr) callconv(.C) c.socklen_t,
    get_peername: ?fn ([*c]h2o_conn, [*c]c.struct_sockaddr) callconv(.C) c.socklen_t,
    get_ptls: ?fn ([*c]h2o_conn) callconv(.C) ?*c.ptls_t,
    skip_tracing: ?fn ([*c]h2o_conn) callconv(.C) c_int,
    push_path: ?fn (?*h2o_req, [*c]const u8, usize, c_int) callconv(.C) void,
    get_debug_state: ?fn (?*h2o_req, c_int) callconv(.C) [*c]c.h2o_http2_debug_state_t,
    num_reqs_inflight: ?fn ([*c]h2o_conn) callconv(.C) u32,
    get_tracer: ?fn ([*c]h2o_conn) callconv(.C) [*c]c.quicly_tracer_t,
    get_rtt: ?fn ([*c]h2o_conn) callconv(.C) i64,
    log_: union_unnamed_208,
};

const union_unnamed_208 = extern union {
    unnamed_0: struct_unnamed_209,
    callbacks: [1]?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};

const struct_unnamed_211 = extern struct {
    protocol_version: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    session_reused: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    cipher: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    cipher_bits: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    session_id: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    server_name: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    negotiated_protocol: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};

const struct_unnamed_212 = extern struct {
    request_index: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};
const struct_unnamed_213 = extern struct {
    stream_id: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_received: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_received_exclusive: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_received_parent: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_received_weight: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_actual: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_actual_parent: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    priority_actual_weight: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};
const struct_unnamed_214 = extern struct {
    stream_id: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    quic_stats: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    quic_version: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};

const struct_unnamed_210 = extern struct {
    cc_name: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
    delivery_rate: ?fn (?*h2o_req) callconv(.C) c.h2o_iovec_t,
};

const struct_unnamed_209 = extern struct {
    transport: struct_unnamed_210,
    ssl: struct_unnamed_211,
    http1: struct_unnamed_212,
    http2: struct_unnamed_213,
    http3: struct_unnamed_214,
};

pub const h2o_conn = extern struct {
    ctx: [*c]h2o_context,
    hosts: [*c][*c]h2o_hostconf,
    connected_at: c.struct_timeval,
    id: u64,
    callbacks: [*c]const h2o_conn_callbacks,
    _uuid: struct_unnamed_215,
};

const struct_unnamed_215 = extern struct {
    str: [37]u8,
    is_initialized: u8,
};

pub const h2o_headers = extern struct {
    entries: [*c]h2o_header,
    size: usize,
    capacity: usize,
};

pub const h2o_header = extern struct {
    name: [*c]c.h2o_iovec_t,
    orig_name: [*c]const u8,
    value: c.h2o_iovec_t,
    flags: h2o_header_flags,
};

const h2o_header_flags = packed struct {
    dont_compress: bool,
    pad: u7,
};

const h2o_res = extern struct {
    status: c_int,
    reason: [*c]const u8,
    content_length: usize,
    headers: h2o_headers,
    mime_attr: [*c]c.h2o_mime_attributes_t,
    original: struct_unnamed_183,
};

const struct_unnamed_183 = extern struct {
    status: c_int,
    headers: h2o_headers,
};

/// a HTTP request
pub const h2o_req = struct {
    /// the underlying connection
    conn: *h2o_conn,
    
    /// the request sent by the client (as is)
    input: extern struct {
        /// scheme (http, https, etc.)
        scheme: *const c.h2o_url_scheme_t,
        /// authority (a.k.a. the Host header; the value is supplemented if missing before the handlers are being called)
        authority: c.h2o_iovec_t,
        /// method
        method: c.h2o_iovec_t,
        /// abs-path of the request (unmodified)
        path: c.h2o_iovec_t,
        /// offset of '?' within path, or SIZE_MAX if not found
        query_at: usize,
    },
    /// the host context
    hostconf: *h2o_hostconf,
    /// the path context
    pathconf: *h2o_pathconf,
    /// filters and the size of it
    filters: **h2o_filter,
    num_filters: usize,
    /// loggers and the size of it
    loggers: **h2o_logger,
    num_loggers: usize,
    /// the handler that has been executed
    handler: *h2o_handler,
    /// scheme (http, https, etc.)
    scheme: *const c.h2o_url_scheme_t,
    /// authority (of the processing request)
    authority: c.h2o_iovec_t,
    /// method (of the processing request)
    method: c.h2o_iovec_t,
    /// abs-path of the processing request
    path: c.h2o_iovec_t,
    /// offset of '?' within path, or SIZE_MAX if not found
    query_at: usize,
    /// normalized path of the processing request (i.e. no "." or "..", no query)
    path_normalized: c.h2o_iovec_t,
    /// Map of indexes of `path_normalized` into the next character in `path`; built only if `path` required normalization
    norm_indexes: *usize,
    /// authority's prefix matched with `*` against defined hosts
    authority_wildcard_match: c.h2o_iovec_t,
    /// filters assigned per request
    prefilters: *c.h2o_req_prefilter_t,
    /// additional information (becomes available for extension-based dynamic content)
    filereq: *c.h2o_filereq_t,
    /// overrides (maybe NULL)
    overrides: *c.h2o_req_overrides_t,
    /// the HTTP version (represented as 0xMMmm (M=major, m=minor))
    version: c_int,
    /// list of request headers
    headers: h2o_headers,
    /// the request entity (base == NULL if none), can't be used if the handler is streaming the body
    entity: c.h2o_iovec_t,
    /// amount of request body being received
    req_body_bytes_received: usize,
    /// If different of SIZE_MAX, the numeric value of the received content-length: header
    content_length: usize,
    /// timestamp when the request was processed
    processed_at: c.h2o_timestamp_t,

    /// additional timestamps
    timestamps: extern struct {
        request_begin_at: c.timeval,
        request_body_begin_at: c.timeval,
        response_start_at: c.timeval,
        response_end_at: c.timeval,
    },
    /// proxy stats
    proxy_stats: extern struct {
        bytes_written: extern struct {
            total: u64,
            header: u64,
            body: u64,
        },
        bytes_read: extern struct {
            total: u64,
            header: u64,
            body: u64,
        },
        timestamps: c.h2o_httpclient_timings_t,
        conn: c.h2o_httpclient_conn_properties_t,
    },
    /// the response
    res: h2o_res,
    /// number of bytes sent by the generator (excluding headers)
    bytes_sent: u64,
    /// the number of times the request can be reprocessed (excluding delegation)
    remaining_reprocesses: u32,
    /// the number of times the request can be delegated
    remaining_delegations: u32,

    /// Optional callback used to establish a tunnel. When a tunnel is being established to upstream, the generator fills the
    /// response headers, then calls this function directly, bypassing the ordinary `h2o_send` chain.
    establish_tunnel: fn (req: *c.h2o_req_t, tunnel: *c.h2o_tunnel_t, idle_timeout: u64) void,

    /// environment variables
    env: c.h2o_iovec_vector_t,

    /// error log for the request (`h2o_req_log_error` must be used for error logging)
    error_logs: *c.h2o_buffer_t,

    /// error log redirection called by `h2o_req_log_error`. By default, the error is appended to `error_logs`. The callback is
    /// replaced by mruby middleware to send the error log to the rack handler.
    error_log_delegate: extern struct {
        cb: fn (data: *anyopaque, prefix: c.h2o_iovec_t, msg: c.h2o_iovec_t) callconv(.C) void,
        data: *anyopaque,
    },

    /// flags

    fields: packed struct {
        /// whether or not the connection is persistent.
        //  Applications should set this flag to zero in case the connection cannot be kept keep-alive (due to an error etc.)
        http1_is_persistent: bool,
        /// whether if the response has been delegated (i.e. reproxied).
        /// For delegated responses, redirect responses would be handled internally.
        res_is_delegated: bool,
        /// set by the generator if the protocol handler should replay the request upon seeing 425
        reprocess_if_too_early: bool,
        /// set by the prxy handler if the http2 upstream refused the stream so the client can retry the request
        upstream_refused: bool,
        /// if h2o_process_request has been called
        process_called: bool,
    },

    /// whether if the response should include server-timing header. Logical OR of H2O_SEND_SERVER_TIMING_*
    send_server_timing: u32,

    /// Whether the producer of the response has explicitly disabled or
    /// enabled compression. One of H2O_COMPRESS_HINT_*
    compress_hint: u8,

    /// the Upgrade request header (or { NULL, 0 } if not available)
    upgrade: c.h2o_iovec_t,

    /// preferred chunk size by the ostream
    preferred_chunk_size: usize,

    /// callback and context for receiving request body (see h2o_handler_t::supports_request_streaming for details)
    write_req: extern struct {
        cb: c.h2o_write_req_cb,
        ctx: *anyopaque,
    },

    /// callback and context for receiving more request body (see h2o_handler_t::supports_request_streaming for details)
    proceed_req: c.h2o_proceed_req_cb,

    /// internal structure
    _generator: *c.h2o_generator_t,
    _ostr_top: *c.h2o_ostream_t,
    _next_filter_index: usize,
    _timeout_entry: c.h2o_timer_t,

    /// per-request memory pool (placed at the last since the structure is large) 
    pool: c.h2o_mem_pool_t,
};

pub const h2o_token = extern struct {
    buf: c.h2o_iovec_t,
    flags: h2o_token_flags,
};

const h2o_token_flags = extern struct {
    http2_static_table_name_index: u8, // non-zero if any
    fields: packed struct {
        proxy_should_drop_for_req: bool,
        proxy_should_drop_for_res: bool,
        is_init_header_special: bool,
        http2_should_reject: bool,
        copy_for_push_request: bool,
        dont_compress: bool, // consult `h2o_header_t:dont_compress` as well 
        likely_to_repeat: bool,
        padding: u1,
    },
};

/// abstraction layer for sockets (SSL vs. TCP)
pub const h2o_socket = struct {
    data: *anyopaque,
    ssl: *c.st_h2o_socket_ssl_t,
    input: *c.h2o_buffer_t,
    /// total bytes read (above the TLS layer)
    bytes_read: u64,
    /// total bytes written (above the TLS layer)
    bytes_written: u64,

    fields: packed struct {
        /// boolean flag to indicate if sock is NOT being traced
        _skip_tracing: bool,

        padding: u7,
    },
    on_close: extern struct {
        cb: fn (data: *anyopaque) callconv(.C) void,
        data: *anyopaque,
    },
    _cb: extern struct {
        read: c.h2o_socket_cb,
        write: c.h2o_socket_cb,
    },
    _peername: *c.st_h2o_socket_addr_t,
    _sockname: *c.st_h2o_socket_addr_t,
    _write_buf: extern struct {
        cnt: usize,
        bufs: *c.h2o_iovec_t,
        u: extern union {
            alloced_ptr: *c.h2o_iovec_t,
            smallbufs: [4]c.h2o_iovec_t,
        },
    },
    _latency_optimization: extern struct {
        state: u8, // one of H2O_SOCKET_LATENCY_STATE_* 
        fields: packed struct {
            notsent_is_minimized: bool,
            padding: u7,
        },
        suggested_tls_payload_size: usize, // suggested TLS record payload size, or SIZE_MAX when no need to restrict 
        suggested_write_size: usize,       // SIZE_MAX if no need to optimize for latency 
    },
};
