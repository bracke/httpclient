#include <stdint.h>

/*
 * Native QUIC backend seam.
 *
 * This file intentionally provides an unavailable default implementation so
 * HttpClient can expose stable Ada-side QUIC handle plumbing without linking a
 * partial or fake QUIC stack. A future backend can replace these functions with
 * ngtcp2/nghttp3, OpenSSL QUIC, or another audited implementation while keeping
 * the Ada QUIC package and HTTP/3 policy boundary unchanged.
 */

enum http_client_quic_status {
    HTTP_CLIENT_QUIC_OK = 0,
    HTTP_CLIENT_QUIC_UNSUPPORTED = 1,
    HTTP_CLIENT_QUIC_CONNECTION_FAILED = 2,
    HTTP_CLIENT_QUIC_TIMEOUT = 3,
    HTTP_CLIENT_QUIC_TLS_HANDSHAKE_FAILED = 4,
    HTTP_CLIENT_QUIC_TLS_CERTIFICATE_FAILED = 5,
    HTTP_CLIENT_QUIC_INVALID_CONFIGURATION = 6,
    HTTP_CLIENT_QUIC_INVALID_URI = 7,
    HTTP_CLIENT_QUIC_INTERNAL_ERROR = 8
};

int http_client_quic_backend_available(void) {
    return 0;
}

int http_client_quic_backend_open(
    const char *host,
    int port,
    int idle_timeout_ms,
    int connection_timeout_ms,
    int max_datagram_size,
    int max_bidirectional_streams,
    int max_unidirectional_streams,
    void **out_handle) {
    (void)host;
    (void)port;
    (void)idle_timeout_ms;
    (void)connection_timeout_ms;
    (void)max_datagram_size;
    (void)max_bidirectional_streams;
    (void)max_unidirectional_streams;

    if (out_handle != 0) {
        *out_handle = 0;
    }

    return HTTP_CLIENT_QUIC_UNSUPPORTED;
}

void http_client_quic_backend_close(void *handle) {
    (void)handle;
}
