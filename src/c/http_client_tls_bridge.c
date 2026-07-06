#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#endif

#define HC_TLS_OK 0
#define HC_TLS_CONNECTION_FAILED 1
#define HC_TLS_CA_STORE_FAILED 2
#define HC_TLS_HANDSHAKE_FAILED 3
#define HC_TLS_CERTIFICATE_FAILED 4
#define HC_TLS_HOSTNAME_FAILED 5
#define HC_TLS_WRITE_FAILED 6
#define HC_TLS_READ_FAILED 7
#define HC_TLS_END_OF_STREAM 8
#define HC_TLS_INTERNAL_ERROR 9
#define HC_TLS_CLIENT_CERT_LOAD_FAILED 10
#define HC_TLS_CLIENT_KEY_LOAD_FAILED 11
#define HC_TLS_CLIENT_KEY_MISMATCH 12
#define HC_TLS_CLIENT_CERT_REJECTED 13
#define HC_TLS_CLIENT_KEY_PASSPHRASE_REQUIRED 14
#define HC_TLS_CLIENT_KEY_PASSPHRASE_INVALID 15
#define HC_TLS_PROXY_TUNNEL_FAILED 16
#define HC_TLS_PROXY_AUTHENTICATION_REQUIRED 17
#define HC_TLS_SOCKS_UNSUPPORTED_VERSION 18
#define HC_TLS_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD 19
#define HC_TLS_SOCKS_AUTHENTICATION_FAILED 20
#define HC_TLS_SOCKS_CONNECT_FAILED 21
#define HC_TLS_SOCKS_GENERAL_SERVER_FAILURE 22
#define HC_TLS_SOCKS_CONNECTION_NOT_ALLOWED 23
#define HC_TLS_SOCKS_TTL_EXPIRED 24
#define HC_TLS_SOCKS_COMMAND_UNSUPPORTED 25
#define HC_TLS_SOCKS_MALFORMED_REPLY 26
#define HC_TLS_SOCKS_ADDRESS_TYPE_UNSUPPORTED 27
#define HC_TLS_SOCKS_REPLY_CONNECTION_REFUSED 28
#define HC_TLS_SOCKS_REPLY_NETWORK_UNREACHABLE 29
#define HC_TLS_SOCKS_REPLY_HOST_UNREACHABLE 30
#define HC_TLS_TIMEOUT 31
#define HC_TLS_MAX_HOST_LENGTH 253

typedef struct hc_tls_connection {
    SSL_CTX *ctx;
    BIO *bio;
    SSL *ssl;
    int client_certificate_configured;
    int read_timeout_ms;
    int write_timeout_ms;
    char selected_alpn[32];
} hc_tls_connection;


static int set_socket_timeout_ms(int fd, int option_name, int timeout_ms) {
    if (timeout_ms < 0) {
        return 1;
    }
#ifdef _WIN32
    {
        DWORD value = (DWORD)timeout_ms;
        return setsockopt((SOCKET)fd, SOL_SOCKET, option_name, (const char *)&value, sizeof(value)) == 0;
    }
#else
    {
        struct timeval value;
        value.tv_sec = timeout_ms / 1000;
        value.tv_usec = (timeout_ms % 1000) * 1000;
        return setsockopt(fd, SOL_SOCKET, option_name, &value, sizeof(value)) == 0;
    }
#endif
}

static int apply_bio_socket_timeouts(BIO *bio, int read_timeout_ms, int write_timeout_ms) {
    int fd = -1;

    if (bio == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

    fd = BIO_get_fd(bio, NULL);
    if (fd < 0) {
        return HC_TLS_INTERNAL_ERROR;
    }

    if (!set_socket_timeout_ms(fd, SO_RCVTIMEO, read_timeout_ms)) {
        return HC_TLS_INTERNAL_ERROR;
    }
    if (!set_socket_timeout_ms(fd, SO_SNDTIMEO, write_timeout_ms)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    return HC_TLS_OK;
}

static int c_string_exceeds_limit(const char *text, size_t limit) {
    size_t index;

    if (text == NULL) {
        return 0;
    }

    for (index = 0; index <= limit; ++index) {
        if (text[index] == '\0') {
            return 0;
        }
    }

    return 1;
}

static int build_alpn_wire_list(const char *csv, unsigned char *out, size_t out_size, unsigned int *out_len) {
    const char *start;
    const char *p;
    size_t used = 0;

    if (out_len == NULL) {
        return 0;
    }
    *out_len = 0;

    if (csv == NULL || csv[0] == '\0') {
        return 1;
    }

    start = csv;
    p = csv;
    for (;;) {
        if (*p == ',' || *p == '\0') {
            size_t len = (size_t)(p - start);
            if (len == 0 || len > 255 || used + 1 + len > out_size) {
                return 0;
            }
            out[used++] = (unsigned char)len;
            memcpy(out + used, start, len);
            used += len;

            if (*p == '\0') {
                break;
            }
            start = p + 1;
        }
        ++p;
    }

    *out_len = (unsigned int)used;
    return 1;
}

static int is_ipv4_literal(const char *host) {
    int dots = 0;
    int value = 0;
    int digits = 0;

    if (host == NULL || *host == '\0') {
        return 0;
    }

    for (const char *p = host; ; ++p) {
        if (*p >= '0' && *p <= '9') {
            value = value * 10 + (*p - '0');
            if (value > 255) {
                return 0;
            }
            ++digits;
            if (digits > 3) {
                return 0;
            }
        } else if (*p == '.' || *p == '\0') {
            if (digits == 0) {
                return 0;
            }
            if (*p == '.') {
                ++dots;
                value = 0;
                digits = 0;
            } else {
                return dots == 3;
            }
        } else {
            return 0;
        }
    }
}

static int is_ipv6_literal(const char *host) {
    if (host == NULL || *host == '\0') {
        return 0;
    }

    return strchr(host, ':') != NULL;
}

static int is_ip_literal(const char *host) {
    return is_ipv4_literal(host) || is_ipv6_literal(host);
}

static int format_host_port(char *out, size_t out_size, const char *host, int port) {
    int length;

    if (host == NULL || out == NULL || port <= 0 || port > 65535) {
        return 0;
    }

    if (is_ipv6_literal(host) && host[0] != '[') {
        length = snprintf(out, out_size, "[%s]:%d", host, port);
    } else {
        length = snprintf(out, out_size, "%s:%d", host, port);
    }

    return length >= 0 && length < (int)out_size;
}

static int is_dns_name_for_sni(const char *host) {
    int saw_alpha = 0;
    int last_was_dot = 1;

    if (host == NULL || *host == '\0' || is_ip_literal(host)) {
        return 0;
    }

    for (const char *p = host; *p != '\0'; ++p) {
        unsigned char ch = (unsigned char)*p;
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
            saw_alpha = 1;
            last_was_dot = 0;
        } else if ((ch >= '0' && ch <= '9') || ch == '-') {
            last_was_dot = 0;
        } else if (ch == '.') {
            if (last_was_dot) {
                return 0;
            }
            last_was_dot = 1;
        } else {
            return 0;
        }
    }

    return saw_alpha && !last_was_dot;
}


static int client_key_password_cb(char *buf, int size, int rwflag, void *userdata) {
    const char *pass = (const char *)userdata;
    size_t len;

    (void)rwflag;

    if (buf == NULL || size <= 0 || pass == NULL) {
        return 0;
    }

    len = strlen(pass);
    if (len >= (size_t)size) {
        return 0;
    }

    if (len > 0) {
        memcpy(buf, pass, len);
    }
    return (int)len;
}


static int client_key_load_failure_status(const char *client_key_passphrase) {
    unsigned long err = ERR_peek_last_error();
    int reason = ERR_GET_REASON(err);
    int has_explicit_passphrase = client_key_passphrase != NULL;

#ifdef PEM_R_BAD_PASSWORD_READ
    if (reason == PEM_R_BAD_PASSWORD_READ) {
        return has_explicit_passphrase
            ? HC_TLS_CLIENT_KEY_PASSPHRASE_INVALID
            : HC_TLS_CLIENT_KEY_PASSPHRASE_REQUIRED;
    }
#endif
#ifdef PEM_R_BAD_DECRYPT
    if (reason == PEM_R_BAD_DECRYPT) {
        return has_explicit_passphrase
            ? HC_TLS_CLIENT_KEY_PASSPHRASE_INVALID
            : HC_TLS_CLIENT_KEY_PASSPHRASE_REQUIRED;
    }
#endif
#ifdef EVP_R_BAD_DECRYPT
    if (reason == EVP_R_BAD_DECRYPT) {
        return has_explicit_passphrase
            ? HC_TLS_CLIENT_KEY_PASSPHRASE_INVALID
            : HC_TLS_CLIENT_KEY_PASSPHRASE_REQUIRED;
    }
#endif

    return HC_TLS_CLIENT_KEY_LOAD_FAILED;
}

static int configure_client_certificate(
    SSL_CTX *ctx,
    const char *client_cert_file,
    const char *client_key_file,
    const char *client_key_passphrase)
{
    const int has_cert = client_cert_file != NULL && client_cert_file[0] != '\0';
    const int has_key = client_key_file != NULL && client_key_file[0] != '\0';

    if (!has_cert && !has_key) {
        return HC_TLS_OK;
    }

    if (!has_cert || !has_key || ctx == NULL) {
        return HC_TLS_CLIENT_CERT_LOAD_FAILED;
    }

    if (SSL_CTX_use_certificate_chain_file(ctx, client_cert_file) != 1) {
        return HC_TLS_CLIENT_CERT_LOAD_FAILED;
    }

    if (client_key_passphrase != NULL) {
        SSL_CTX_set_default_passwd_cb(ctx, client_key_password_cb);
        SSL_CTX_set_default_passwd_cb_userdata(ctx, (void *)client_key_passphrase);
    } else {
        SSL_CTX_set_default_passwd_cb(ctx, client_key_password_cb);
        SSL_CTX_set_default_passwd_cb_userdata(ctx, NULL);
    }

    ERR_clear_error();
    if (SSL_CTX_use_PrivateKey_file(ctx, client_key_file, SSL_FILETYPE_PEM) != 1) {
        return client_key_load_failure_status(client_key_passphrase);
    }

    if (SSL_CTX_check_private_key(ctx) != 1) {
        return HC_TLS_CLIENT_KEY_MISMATCH;
    }

    return HC_TLS_OK;
}

static void cleanup_partial(hc_tls_connection *conn) {
    if (conn != NULL) {
        if (conn->bio != NULL) {
            BIO_free_all(conn->bio);
            conn->bio = NULL;
            conn->ssl = NULL;
        }
        if (conn->ctx != NULL) {
            SSL_CTX_free(conn->ctx);
            conn->ctx = NULL;
        }
        free(conn);
    }
}

static int verification_failure_status(SSL *ssl) {
    long verify_result;

    if (ssl == NULL) {
        return HC_TLS_HANDSHAKE_FAILED;
    }

    verify_result = SSL_get_verify_result(ssl);
    if (verify_result == X509_V_OK) {
        return HC_TLS_HANDSHAKE_FAILED;
    }

#ifdef X509_V_ERR_HOSTNAME_MISMATCH
    if (verify_result == X509_V_ERR_HOSTNAME_MISMATCH) {
        return HC_TLS_HOSTNAME_FAILED;
    }
#endif
#ifdef X509_V_ERR_IP_ADDRESS_MISMATCH
    if (verify_result == X509_V_ERR_IP_ADDRESS_MISMATCH) {
        return HC_TLS_HOSTNAME_FAILED;
    }
#endif

    return HC_TLS_CERTIFICATE_FAILED;
}

static int client_certificate_alert_status(void) {
    unsigned long err = ERR_peek_last_error();
    int reason = ERR_GET_REASON(err);

#ifdef SSL_R_TLSV13_ALERT_CERTIFICATE_REQUIRED
    if (reason == SSL_R_TLSV13_ALERT_CERTIFICATE_REQUIRED) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_SSLV3_ALERT_BAD_CERTIFICATE
    if (reason == SSL_R_SSLV3_ALERT_BAD_CERTIFICATE) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_SSLV3_ALERT_UNSUPPORTED_CERTIFICATE
    if (reason == SSL_R_SSLV3_ALERT_UNSUPPORTED_CERTIFICATE) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_TLSV1_ALERT_UNKNOWN_CA
    if (reason == SSL_R_TLSV1_ALERT_UNKNOWN_CA) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_SSLV3_ALERT_CERTIFICATE_REVOKED
    if (reason == SSL_R_SSLV3_ALERT_CERTIFICATE_REVOKED) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_SSLV3_ALERT_CERTIFICATE_EXPIRED
    if (reason == SSL_R_SSLV3_ALERT_CERTIFICATE_EXPIRED) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif
#ifdef SSL_R_SSLV3_ALERT_CERTIFICATE_UNKNOWN
    if (reason == SSL_R_SSLV3_ALERT_CERTIFICATE_UNKNOWN) {
        return HC_TLS_CLIENT_CERT_REJECTED;
    }
#endif

    return HC_TLS_HANDSHAKE_FAILED;
}

static int handshake_failure_status(SSL *ssl, int disable_verification, int client_certificate_configured) {
    int status;

    if (client_certificate_configured) {
        status = client_certificate_alert_status();
        if (status == HC_TLS_CLIENT_CERT_REJECTED) {
            return status;
        }
    }

    if (disable_verification) {
        return HC_TLS_HANDSHAKE_FAILED;
    }

    return verification_failure_status(ssl);
}



static int bio_write_all(BIO *bio, const unsigned char *data, size_t length, int write_timeout_ms) {
    size_t sent = 0;

    if (bio == NULL || (data == NULL && length != 0)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    while (sent < length) {
        int n = BIO_write(bio, data + sent, (int)(length - sent));
        if (n <= 0) {
            if (BIO_should_retry(bio)) {
                if (write_timeout_ms > 0) {
                    return HC_TLS_TIMEOUT;
                }
                continue;
            }
            return HC_TLS_WRITE_FAILED;
        }
        sent += (size_t)n;
    }

    return HC_TLS_OK;
}

static int bio_read_exact(BIO *bio, unsigned char *buffer, size_t length, int read_timeout_ms) {
    size_t got = 0;

    if (bio == NULL || (buffer == NULL && length != 0)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    while (got < length) {
        int n = BIO_read(bio, buffer + got, (int)(length - got));
        if (n <= 0) {
            if (BIO_should_retry(bio)) {
                if (read_timeout_ms > 0) {
                    return HC_TLS_TIMEOUT;
                }
                continue;
            }
            return HC_TLS_SOCKS_MALFORMED_REPLY;
        }
        got += (size_t)n;
    }

    return HC_TLS_OK;
}

static int host_is_ipv4_literal_for_socks(const char *host, unsigned char out[4]) {
    int dots = 0;
    int value = 0;
    int digits = 0;
    int octet = 0;

    if (host == NULL || host[0] == '\0') {
        return 0;
    }

    for (const char *p = host; ; ++p) {
        if (*p >= '0' && *p <= '9') {
            value = value * 10 + (*p - '0');
            if (value > 255) {
                return 0;
            }
            ++digits;
            if (digits > 3) {
                return 0;
            }
        } else if (*p == '.' || *p == '\0') {
            if (digits == 0 || octet >= 4) {
                return 0;
            }
            if (out != NULL) {
                out[octet] = (unsigned char)value;
            }
            ++octet;
            if (*p == '.') {
                ++dots;
                value = 0;
                digits = 0;
            } else {
                return dots == 3 && octet == 4;
            }
        } else {
            return 0;
        }
    }
}

static int socks_host_is_encodable(const char *host) {
    size_t len;

    if (host == NULL) {
        return 0;
    }

    len = strlen(host);
    if (len == 0 || len > 255) {
        return 0;
    }

    for (const unsigned char *p = (const unsigned char *)host; *p != '\0'; ++p) {
        if (*p < 33 || *p == 127 || *p == '/' || *p == '\\' || *p == '@' ||
            *p == ':' || *p == '[' || *p == ']') {
            return 0;
        }
    }

    return 1;
}

static int socks_status_from_reply_code(unsigned char code) {
    switch (code) {
        case 0: return HC_TLS_OK;
        case 1: return HC_TLS_SOCKS_GENERAL_SERVER_FAILURE;
        case 2: return HC_TLS_SOCKS_CONNECTION_NOT_ALLOWED;
        case 3: return HC_TLS_SOCKS_REPLY_NETWORK_UNREACHABLE;
        case 4: return HC_TLS_SOCKS_REPLY_HOST_UNREACHABLE;
        case 5: return HC_TLS_SOCKS_REPLY_CONNECTION_REFUSED;
        case 6: return HC_TLS_SOCKS_TTL_EXPIRED;
        case 7: return HC_TLS_SOCKS_COMMAND_UNSUPPORTED;
        case 8: return HC_TLS_SOCKS_ADDRESS_TYPE_UNSUPPORTED;
        default: return HC_TLS_SOCKS_CONNECT_FAILED;
    }
}

static int tunnel_socks5(
    BIO *bio,
    const char *host,
    int port,
    int auth_method,
    const char *username,
    const char *password,
    int dns_mode,
    int read_timeout_ms,
    int write_timeout_ms)
{
    unsigned char greeting[3];
    unsigned char reply[4];
    unsigned char ipv4[4];
    unsigned char request[512];
    size_t used = 0;
    size_t host_len;
    int status;

    if (bio == NULL || host == NULL || host[0] == '\0' || port <= 0 || port > 65535) {
        return HC_TLS_INTERNAL_ERROR;
    }

    if (auth_method != 0 && auth_method != 1) {
        return HC_TLS_INTERNAL_ERROR;
    }

    greeting[0] = 0x05;
    greeting[1] = 0x01;
    greeting[2] = (unsigned char)(auth_method == 1 ? 0x02 : 0x00);
    status = bio_write_all(bio, greeting, sizeof(greeting), write_timeout_ms);
    if (status != HC_TLS_OK) {
        return HC_TLS_SOCKS_CONNECT_FAILED;
    }

    status = bio_read_exact(bio, reply, 2, read_timeout_ms);
    if (status != HC_TLS_OK) {
        return status;
    }
    if (reply[0] != 0x05) {
        return HC_TLS_SOCKS_UNSUPPORTED_VERSION;
    }
    if (reply[1] == 0xff || reply[1] != greeting[2]) {
        return HC_TLS_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD;
    }

    if (auth_method == 1) {
        size_t user_len = username != NULL ? strlen(username) : 0;
        size_t pass_len = password != NULL ? strlen(password) : 0;
        unsigned char auth[513];
        size_t auth_used = 0;

        if (user_len == 0 || user_len > 255 || pass_len == 0 || pass_len > 255) {
            return HC_TLS_INTERNAL_ERROR;
        }

        auth[auth_used++] = 0x01;
        auth[auth_used++] = (unsigned char)user_len;
        memcpy(auth + auth_used, username, user_len);
        auth_used += user_len;
        auth[auth_used++] = (unsigned char)pass_len;
        memcpy(auth + auth_used, password, pass_len);
        auth_used += pass_len;

        status = bio_write_all(bio, auth, auth_used, write_timeout_ms);
        if (status != HC_TLS_OK) {
            return HC_TLS_SOCKS_CONNECT_FAILED;
        }
        status = bio_read_exact(bio, reply, 2, read_timeout_ms);
        if (status != HC_TLS_OK) {
            return status;
        }
        if (reply[0] != 0x01) {
            return HC_TLS_SOCKS_UNSUPPORTED_VERSION;
        }
        if (reply[1] != 0x00) {
            return HC_TLS_SOCKS_AUTHENTICATION_FAILED;
        }
    }

    request[used++] = 0x05;
    request[used++] = 0x01;
    request[used++] = 0x00;
    if (host_is_ipv4_literal_for_socks(host, ipv4)) {
        request[used++] = 0x01;
        memcpy(request + used, ipv4, sizeof(ipv4));
        used += sizeof(ipv4);
    } else {
        if (dns_mode == 1) {
            return HC_TLS_SOCKS_ADDRESS_TYPE_UNSUPPORTED;
        }
        if (!socks_host_is_encodable(host)) {
            return HC_TLS_INTERNAL_ERROR;
        }
        host_len = strlen(host);
        request[used++] = 0x03;
        request[used++] = (unsigned char)host_len;
        memcpy(request + used, host, host_len);
        used += host_len;
    }
    request[used++] = (unsigned char)((port >> 8) & 0xff);
    request[used++] = (unsigned char)(port & 0xff);

    status = bio_write_all(bio, request, used, write_timeout_ms);
    if (status != HC_TLS_OK) {
        return HC_TLS_SOCKS_CONNECT_FAILED;
    }

    status = bio_read_exact(bio, reply, 4, read_timeout_ms);
    if (status != HC_TLS_OK) {
        return status;
    }
    if (reply[0] != 0x05) {
        return HC_TLS_SOCKS_UNSUPPORTED_VERSION;
    }
    if (reply[2] != 0x00) {
        return HC_TLS_SOCKS_MALFORMED_REPLY;
    }

    switch (reply[3]) {
        case 0x01:
            status = bio_read_exact(bio, request, 6, read_timeout_ms);
            break;
        case 0x03:
            status = bio_read_exact(bio, request, 1, read_timeout_ms);
            if (status == HC_TLS_OK) {
                if (request[0] == 0) {
                    return HC_TLS_SOCKS_MALFORMED_REPLY;
                }
                status = bio_read_exact(bio, request, (size_t)request[0] + 2, read_timeout_ms);
            }
            break;
        case 0x04:
            status = bio_read_exact(bio, request, 18, read_timeout_ms);
            break;
        default:
            return HC_TLS_SOCKS_ADDRESS_TYPE_UNSUPPORTED;
    }
    if (status != HC_TLS_OK) {
        return status;
    }

    return socks_status_from_reply_code(reply[1]);
}

static int append_to_request(char *buffer, size_t buffer_size, size_t *used, const char *text) {
    size_t len;

    if (buffer == NULL || used == NULL || text == NULL) {
        return 0;
    }

    len = strlen(text);
    if (*used + len >= buffer_size) {
        return 0;
    }

    memcpy(buffer + *used, text, len);
    *used += len;
    buffer[*used] = '\0';
    return 1;
}

static int proxy_authorization_is_safe(const char *value) {
    const unsigned char *p;

    if (value == NULL || value[0] == '\0') {
        return 1;
    }

    for (p = (const unsigned char *)value; *p != '\0'; ++p) {
        if (*p == '\r' || *p == '\n' || *p < 32 || *p == 127) {
            return 0;
        }
    }

    return 1;
}

static int build_connect_request(
    char *buffer,
    size_t buffer_size,
    const char *host,
    int port,
    const char *proxy_authorization)
{
    char authority[512];
    size_t used = 0;

    if (buffer == NULL || host == NULL || port <= 0 || port > 65535) {
        return 0;
    }

    if (!proxy_authorization_is_safe(proxy_authorization)) {
        return 0;
    }

    if (!format_host_port(authority, sizeof(authority), host, port)) {
        return 0;
    }

    buffer[0] = '\0';
    if (!append_to_request(buffer, buffer_size, &used, "CONNECT ") ||
        !append_to_request(buffer, buffer_size, &used, authority) ||
        !append_to_request(buffer, buffer_size, &used, " HTTP/1.1\r\nHost: ") ||
        !append_to_request(buffer, buffer_size, &used, authority) ||
        !append_to_request(buffer, buffer_size, &used, "\r\n")) {
        return 0;
    }

    if (proxy_authorization != NULL && proxy_authorization[0] != '\0') {
        if (!append_to_request(buffer, buffer_size, &used, "Proxy-Authorization: ") ||
            !append_to_request(buffer, buffer_size, &used, proxy_authorization) ||
            !append_to_request(buffer, buffer_size, &used, "\r\n")) {
            return 0;
        }
    }

    return append_to_request(buffer, buffer_size, &used, "Proxy-Connection: keep-alive\r\n\r\n");
}

static int parse_connect_status_code(const char *response, size_t length) {
    size_t i;
    int code = 0;

    if (response == NULL || length < 12) {
        return 0;
    }

    if (memcmp(response, "HTTP/", 5) != 0) {
        return 0;
    }

    for (i = 5; i < length; ++i) {
        if (response[i] == ' ') {
            break;
        }
        if (response[i] == '\r' || response[i] == '\n') {
            return 0;
        }
    }

    if (i + 3 >= length) {
        return 0;
    }

    while (i < length && response[i] == ' ') {
        ++i;
    }

    if (i + 2 >= length ||
        response[i] < '0' || response[i] > '9' ||
        response[i + 1] < '0' || response[i + 1] > '9' ||
        response[i + 2] < '0' || response[i + 2] > '9') {
        return 0;
    }

    code = (response[i] - '0') * 100 + (response[i + 1] - '0') * 10 + (response[i + 2] - '0');
    return code;
}

static int tunnel_http_connect(BIO *bio, const char *host, int port, const char *proxy_authorization, int read_timeout_ms, int write_timeout_ms) {
    char request[2048];
    char response[65536];
    size_t used = 0;
    int code;

    if (bio == NULL || !build_connect_request(request, sizeof(request), host, port, proxy_authorization)) {
        return HC_TLS_PROXY_TUNNEL_FAILED;
    }

    {
        size_t sent = 0;
        size_t request_len = strlen(request);
        while (sent < request_len) {
            int n = BIO_write(bio, request + sent, (int)(request_len - sent));
            if (n <= 0) {
                if (BIO_should_retry(bio)) {
                    if (write_timeout_ms > 0) {
                        return HC_TLS_TIMEOUT;
                    }
                    continue;
                }
                return HC_TLS_PROXY_TUNNEL_FAILED;
            }
            sent += (size_t)n;
        }
    }

    while (used + 1 < sizeof(response)) {
        int n = BIO_read(bio, response + used, (int)(sizeof(response) - used - 1));
        size_t i;
        if (n <= 0) {
            if (BIO_should_retry(bio)) {
                if (read_timeout_ms > 0) {
                    return HC_TLS_TIMEOUT;
                }
                continue;
            }
            return HC_TLS_PROXY_TUNNEL_FAILED;
        }
        used += (size_t)n;
        response[used] = '\0';
        for (i = 3; i < used; ++i) {
            if (response[i - 3] == '\r' && response[i - 2] == '\n' &&
                response[i - 1] == '\r' && response[i] == '\n') {
                code = parse_connect_status_code(response, used);
                if (code == 407) {
                    return HC_TLS_PROXY_AUTHENTICATION_REQUIRED;
                }
                if (code >= 200 && code <= 299) {
                    return HC_TLS_OK;
                }
                return HC_TLS_PROXY_TUNNEL_FAILED;
            }
        }
    }

    return HC_TLS_PROXY_TUNNEL_FAILED;
}

static int configure_tls_connection_common(
    hc_tls_connection *conn,
    const char *host,
    int disable_verification,
    const char *ca_file,
    const char *ca_dir,
    int send_sni,
    const char *alpn_protocols,
    int read_timeout_ms,
    int write_timeout_ms,
    const char *client_cert_file,
    const char *client_key_file,
    const char *client_key_passphrase)
{
    unsigned char alpn_wire[64];
    unsigned int alpn_wire_len = 0;
    int client_credential_status;

    (void)send_sni;

    if (conn == NULL || host == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

    conn->read_timeout_ms = read_timeout_ms;
    conn->write_timeout_ms = write_timeout_ms;

    if (!build_alpn_wire_list(alpn_protocols, alpn_wire, sizeof(alpn_wire), &alpn_wire_len)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    if (OPENSSL_init_ssl(0, NULL) != 1) {
        return HC_TLS_INTERNAL_ERROR;
    }

    conn->ctx = SSL_CTX_new(TLS_client_method());
    if (conn->ctx == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

#ifdef TLS1_2_VERSION
    if (SSL_CTX_set_min_proto_version(conn->ctx, TLS1_2_VERSION) != 1) {
        return HC_TLS_INTERNAL_ERROR;
    }
#endif

    if (alpn_wire_len > 0) {
        if (SSL_CTX_set_alpn_protos(conn->ctx, alpn_wire, alpn_wire_len) != 0) {
            return HC_TLS_INTERNAL_ERROR;
        }
    }

    conn->client_certificate_configured =
        client_cert_file != NULL && client_cert_file[0] != '\0';

    client_credential_status = configure_client_certificate(
        conn->ctx, client_cert_file, client_key_file, client_key_passphrase);
    if (client_credential_status != HC_TLS_OK) {
        return client_credential_status;
    }

    if (!disable_verification) {
        const int has_explicit_ca =
            (ca_file != NULL && ca_file[0] != '\0') ||
            (ca_dir != NULL && ca_dir[0] != '\0');

        if (has_explicit_ca) {
            if (SSL_CTX_load_verify_locations(
                    conn->ctx,
                    (ca_file != NULL && ca_file[0] != '\0') ? ca_file : NULL,
                    (ca_dir != NULL && ca_dir[0] != '\0') ? ca_dir : NULL) != 1) {
                return HC_TLS_CA_STORE_FAILED;
            }
        } else if (SSL_CTX_set_default_verify_paths(conn->ctx) != 1) {
            return HC_TLS_CA_STORE_FAILED;
        }

        SSL_CTX_set_verify(conn->ctx, SSL_VERIFY_PEER, NULL);
    } else {
        SSL_CTX_set_verify(conn->ctx, SSL_VERIFY_NONE, NULL);
    }

    return HC_TLS_OK;
}

static int configure_ssl_common(
    hc_tls_connection *conn,
    const char *host,
    int disable_verification,
    int send_sni)
{
    if (conn == NULL || conn->ssl == NULL || host == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

    SSL_set_mode(conn->ssl, SSL_MODE_AUTO_RETRY);

    if (!disable_verification) {
        X509_VERIFY_PARAM *param = SSL_get0_param(conn->ssl);
        if (is_ip_literal(host)) {
            if (X509_VERIFY_PARAM_set1_ip_asc(param, host) != 1) {
                return HC_TLS_HOSTNAME_FAILED;
            }
        } else {
            if (SSL_set1_host(conn->ssl, host) != 1) {
                return HC_TLS_HOSTNAME_FAILED;
            }
        }
    }

    if (send_sni && is_dns_name_for_sni(host)) {
        if (SSL_set_tlsext_host_name(conn->ssl, host) != 1) {
            return HC_TLS_HANDSHAKE_FAILED;
        }
    }

    return HC_TLS_OK;
}

int hc_tls_open(
    hc_tls_connection **out,
    const char *host,
    int port,
    int disable_verification,
    const char *ca_file,
    const char *ca_dir,
    int send_sni,
    const char *alpn_protocols,
    int read_timeout_ms,
    int write_timeout_ms,
    const char *client_cert_file,
    const char *client_key_file,
    const char *client_key_passphrase)
{
    hc_tls_connection *conn = NULL;
    char target[2048];
    long verify_result;
    unsigned char alpn_wire[64];
    unsigned int alpn_wire_len = 0;
    int client_credential_status;

    if (out == NULL || host == NULL || host[0] == '\0' || port <= 0 || port > 65535) {
        return HC_TLS_INTERNAL_ERROR;
    }

    *out = NULL;

    if (c_string_exceeds_limit(host, HC_TLS_MAX_HOST_LENGTH)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    conn = (hc_tls_connection *)calloc(1, sizeof(*conn));
    if (conn == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }
    conn->read_timeout_ms = read_timeout_ms;
    conn->write_timeout_ms = write_timeout_ms;

    if (!build_alpn_wire_list(alpn_protocols, alpn_wire, sizeof(alpn_wire), &alpn_wire_len)) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    if (OPENSSL_init_ssl(0, NULL) != 1) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    conn->ctx = SSL_CTX_new(TLS_client_method());
    if (conn->ctx == NULL) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

#ifdef TLS1_2_VERSION
    if (SSL_CTX_set_min_proto_version(conn->ctx, TLS1_2_VERSION) != 1) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }
#endif

    if (alpn_wire_len > 0) {
        if (SSL_CTX_set_alpn_protos(conn->ctx, alpn_wire, alpn_wire_len) != 0) {
            cleanup_partial(conn);
            return HC_TLS_INTERNAL_ERROR;
        }
    }

    conn->client_certificate_configured =
        client_cert_file != NULL && client_cert_file[0] != '\0';

    client_credential_status = configure_client_certificate(
        conn->ctx, client_cert_file, client_key_file, client_key_passphrase);
    if (client_credential_status != HC_TLS_OK) {
        cleanup_partial(conn);
        return client_credential_status;
    }

    if (!disable_verification) {
        const int has_explicit_ca =
            (ca_file != NULL && ca_file[0] != '\0') ||
            (ca_dir != NULL && ca_dir[0] != '\0');

        if (has_explicit_ca) {
            if (SSL_CTX_load_verify_locations(
                    conn->ctx,
                    (ca_file != NULL && ca_file[0] != '\0') ? ca_file : NULL,
                    (ca_dir != NULL && ca_dir[0] != '\0') ? ca_dir : NULL) != 1) {
                cleanup_partial(conn);
                return HC_TLS_CA_STORE_FAILED;
            }
        } else if (SSL_CTX_set_default_verify_paths(conn->ctx) != 1) {
            cleanup_partial(conn);
            return HC_TLS_CA_STORE_FAILED;
        }

        SSL_CTX_set_verify(conn->ctx, SSL_VERIFY_PEER, NULL);
    } else {
        SSL_CTX_set_verify(conn->ctx, SSL_VERIFY_NONE, NULL);
    }

    conn->bio = BIO_new_ssl_connect(conn->ctx);
    if (conn->bio == NULL) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    BIO_get_ssl(conn->bio, &conn->ssl);
    if (conn->ssl == NULL) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    SSL_set_mode(conn->ssl, SSL_MODE_AUTO_RETRY);

    if (!disable_verification) {
        X509_VERIFY_PARAM *param = SSL_get0_param(conn->ssl);
        if (is_ip_literal(host)) {
            if (X509_VERIFY_PARAM_set1_ip_asc(param, host) != 1) {
                cleanup_partial(conn);
                return HC_TLS_HOSTNAME_FAILED;
            }
        } else {
            if (SSL_set1_host(conn->ssl, host) != 1) {
                cleanup_partial(conn);
                return HC_TLS_HOSTNAME_FAILED;
            }
        }
    }

    if (send_sni && is_dns_name_for_sni(host)) {
        if (SSL_set_tlsext_host_name(conn->ssl, host) != 1) {
            cleanup_partial(conn);
            return HC_TLS_HANDSHAKE_FAILED;
        }
    }

    if (!format_host_port(target, sizeof(target), host, port)) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    BIO_set_conn_hostname(conn->bio, target);

    if (BIO_do_connect(conn->bio) != 1) {
        cleanup_partial(conn);
        return HC_TLS_CONNECTION_FAILED;
    }

    {
        int timeout_status = apply_bio_socket_timeouts(conn->bio, read_timeout_ms, write_timeout_ms);
        if (timeout_status != HC_TLS_OK) {
            cleanup_partial(conn);
            return timeout_status;
        }
    }

    ERR_clear_error();
    if (BIO_do_handshake(conn->bio) != 1) {
        int status = handshake_failure_status(
            conn->ssl,
            disable_verification,
            conn->client_certificate_configured);
        cleanup_partial(conn);
        return status;
    }

    if (!disable_verification) {
        verify_result = SSL_get_verify_result(conn->ssl);
        if (verify_result != X509_V_OK) {
            int status = verification_failure_status(conn->ssl);
            cleanup_partial(conn);
            return status;
        }
    }

    {
        const unsigned char *selected = NULL;
        unsigned int selected_len = 0;
        SSL_get0_alpn_selected(conn->ssl, &selected, &selected_len);
        if (selected != NULL && selected_len > 0) {
            size_t copy_len = selected_len < sizeof(conn->selected_alpn) - 1
                ? (size_t)selected_len
                : sizeof(conn->selected_alpn) - 1;
            memcpy(conn->selected_alpn, selected, copy_len);
            conn->selected_alpn[copy_len] = '\0';
        } else {
            conn->selected_alpn[0] = '\0';
        }
    }

    *out = conn;
    return HC_TLS_OK;
}


int hc_tls_open_through_http_proxy(
    hc_tls_connection **out,
    const char *host,
    int port,
    const char *proxy_host,
    int proxy_port,
    const char *proxy_authorization,
    int disable_verification,
    const char *ca_file,
    const char *ca_dir,
    int send_sni,
    const char *alpn_protocols,
    int read_timeout_ms,
    int write_timeout_ms,
    const char *client_cert_file,
    const char *client_key_file,
    const char *client_key_passphrase)
{
    hc_tls_connection *conn = NULL;
    BIO *plain = NULL;
    BIO *ssl_bio = NULL;
    char proxy_target[2048];
    long verify_result;
    int status;

    if (out == NULL || host == NULL || host[0] == '\0' ||
        proxy_host == NULL || proxy_host[0] == '\0' ||
        port <= 0 || port > 65535 || proxy_port <= 0 || proxy_port > 65535) {
        return HC_TLS_INTERNAL_ERROR;
    }

    *out = NULL;

    if (c_string_exceeds_limit(host, HC_TLS_MAX_HOST_LENGTH) ||
        c_string_exceeds_limit(proxy_host, HC_TLS_MAX_HOST_LENGTH)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    conn = (hc_tls_connection *)calloc(1, sizeof(*conn));
    if (conn == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

    status = configure_tls_connection_common(
        conn,
        host,
        disable_verification,
        ca_file,
        ca_dir,
        send_sni,
        alpn_protocols,
        read_timeout_ms,
        write_timeout_ms,
        client_cert_file,
        client_key_file,
        client_key_passphrase);
    if (status != HC_TLS_OK) {
        cleanup_partial(conn);
        return status;
    }

    if (!format_host_port(proxy_target, sizeof(proxy_target), proxy_host, proxy_port)) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    plain = BIO_new_connect(proxy_target);
    if (plain == NULL) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    if (BIO_do_connect(plain) != 1) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_CONNECTION_FAILED;
    }

    status = apply_bio_socket_timeouts(plain, read_timeout_ms, write_timeout_ms);
    if (status != HC_TLS_OK) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    status = tunnel_http_connect(plain, host, port, proxy_authorization, read_timeout_ms, write_timeout_ms);
    if (status != HC_TLS_OK) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    ssl_bio = BIO_new_ssl(conn->ctx, 1);
    if (ssl_bio == NULL) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    BIO_get_ssl(ssl_bio, &conn->ssl);
    if (conn->ssl == NULL) {
        BIO_free_all(ssl_bio);
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    status = configure_ssl_common(conn, host, disable_verification, send_sni);
    if (status != HC_TLS_OK) {
        BIO_free_all(ssl_bio);
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    conn->bio = BIO_push(ssl_bio, plain);
    plain = NULL;
    ssl_bio = NULL;

    ERR_clear_error();
    if (BIO_do_handshake(conn->bio) != 1) {
        status = handshake_failure_status(
            conn->ssl,
            disable_verification,
            conn->client_certificate_configured);
        cleanup_partial(conn);
        return status;
    }

    if (!disable_verification) {
        verify_result = SSL_get_verify_result(conn->ssl);
        if (verify_result != X509_V_OK) {
            status = verification_failure_status(conn->ssl);
            cleanup_partial(conn);
            return status;
        }
    }

    {
        const unsigned char *selected = NULL;
        unsigned int selected_len = 0;
        SSL_get0_alpn_selected(conn->ssl, &selected, &selected_len);
        if (selected != NULL && selected_len > 0) {
            size_t copy_len = selected_len < sizeof(conn->selected_alpn) - 1
                ? (size_t)selected_len
                : sizeof(conn->selected_alpn) - 1;
            memcpy(conn->selected_alpn, selected, copy_len);
            conn->selected_alpn[copy_len] = '\0';
        } else {
            conn->selected_alpn[0] = '\0';
        }
    }

    *out = conn;
    return HC_TLS_OK;
}


int hc_tls_open_through_socks_proxy(
    hc_tls_connection **out,
    const char *host,
    int port,
    const char *proxy_host,
    int proxy_port,
    int socks_auth_method,
    const char *socks_username,
    const char *socks_password,
    int socks_dns_mode,
    int disable_verification,
    const char *ca_file,
    const char *ca_dir,
    int send_sni,
    const char *alpn_protocols,
    int read_timeout_ms,
    int write_timeout_ms,
    const char *client_cert_file,
    const char *client_key_file,
    const char *client_key_passphrase)
{
    hc_tls_connection *conn = NULL;
    BIO *plain = NULL;
    BIO *ssl_bio = NULL;
    char proxy_target[2048];
    long verify_result;
    int status;

    if (out == NULL || host == NULL || host[0] == '\0' ||
        proxy_host == NULL || proxy_host[0] == '\0' ||
        port <= 0 || port > 65535 || proxy_port <= 0 || proxy_port > 65535) {
        return HC_TLS_INTERNAL_ERROR;
    }

    *out = NULL;

    if (c_string_exceeds_limit(host, HC_TLS_MAX_HOST_LENGTH) ||
        c_string_exceeds_limit(proxy_host, HC_TLS_MAX_HOST_LENGTH)) {
        return HC_TLS_INTERNAL_ERROR;
    }

    conn = (hc_tls_connection *)calloc(1, sizeof(*conn));
    if (conn == NULL) {
        return HC_TLS_INTERNAL_ERROR;
    }

    status = configure_tls_connection_common(
        conn,
        host,
        disable_verification,
        ca_file,
        ca_dir,
        send_sni,
        alpn_protocols,
        read_timeout_ms,
        write_timeout_ms,
        client_cert_file,
        client_key_file,
        client_key_passphrase);
    if (status != HC_TLS_OK) {
        cleanup_partial(conn);
        return status;
    }

    if (!format_host_port(proxy_target, sizeof(proxy_target), proxy_host, proxy_port)) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    plain = BIO_new_connect(proxy_target);
    if (plain == NULL) {
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    if (BIO_do_connect(plain) != 1) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_CONNECTION_FAILED;
    }

    status = apply_bio_socket_timeouts(plain, read_timeout_ms, write_timeout_ms);
    if (status != HC_TLS_OK) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    status = tunnel_socks5(
        plain,
        host,
        port,
        socks_auth_method,
        socks_username,
        socks_password,
        socks_dns_mode,
        read_timeout_ms,
        write_timeout_ms);
    if (status != HC_TLS_OK) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    ssl_bio = BIO_new_ssl(conn->ctx, 1);
    if (ssl_bio == NULL) {
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    BIO_get_ssl(ssl_bio, &conn->ssl);
    if (conn->ssl == NULL) {
        BIO_free_all(ssl_bio);
        BIO_free_all(plain);
        cleanup_partial(conn);
        return HC_TLS_INTERNAL_ERROR;
    }

    status = configure_ssl_common(conn, host, disable_verification, send_sni);
    if (status != HC_TLS_OK) {
        BIO_free_all(ssl_bio);
        BIO_free_all(plain);
        cleanup_partial(conn);
        return status;
    }

    conn->bio = BIO_push(ssl_bio, plain);
    plain = NULL;
    ssl_bio = NULL;

    ERR_clear_error();
    if (BIO_do_handshake(conn->bio) != 1) {
        status = handshake_failure_status(
            conn->ssl,
            disable_verification,
            conn->client_certificate_configured);
        cleanup_partial(conn);
        return status;
    }

    if (!disable_verification) {
        verify_result = SSL_get_verify_result(conn->ssl);
        if (verify_result != X509_V_OK) {
            status = verification_failure_status(conn->ssl);
            cleanup_partial(conn);
            return status;
        }
    }

    {
        const unsigned char *selected = NULL;
        unsigned int selected_len = 0;
        SSL_get0_alpn_selected(conn->ssl, &selected, &selected_len);
        if (selected != NULL && selected_len > 0) {
            size_t copy_len = selected_len < sizeof(conn->selected_alpn) - 1
                ? (size_t)selected_len
                : sizeof(conn->selected_alpn) - 1;
            memcpy(conn->selected_alpn, selected, copy_len);
            conn->selected_alpn[copy_len] = '\0';
        } else {
            conn->selected_alpn[0] = '\0';
        }
    }

    *out = conn;
    return HC_TLS_OK;
}

const char *hc_tls_selected_alpn(hc_tls_connection *conn) {
    if (conn == NULL) {
        return NULL;
    }
    return conn->selected_alpn;
}

const char *hc_tls_version(hc_tls_connection *conn) {
    const char *version;

    if (conn == NULL || conn->ssl == NULL) {
        return NULL;
    }

    version = SSL_get_version(conn->ssl);
    return version != NULL ? version : "";
}

const char *hc_tls_cipher_name(hc_tls_connection *conn) {
    const SSL_CIPHER *cipher;
    const char *name;

    if (conn == NULL || conn->ssl == NULL) {
        return NULL;
    }

    cipher = SSL_get_current_cipher(conn->ssl);
    if (cipher == NULL) {
        return "";
    }

    name = SSL_CIPHER_get_name(cipher);
    return name != NULL ? name : "";
}

int hc_tls_write_all(hc_tls_connection *conn, const char *data, int length) {
    int offset = 0;

    if (conn == NULL || conn->ssl == NULL || length < 0 || (length > 0 && data == NULL)) {
        return HC_TLS_WRITE_FAILED;
    }

    while (offset < length) {
        ERR_clear_error();
        int written = SSL_write(conn->ssl, data + offset, length - offset);
        if (written <= 0) {
            int ssl_error = SSL_get_error(conn->ssl, written);
            if (ssl_error == SSL_ERROR_WANT_READ || ssl_error == SSL_ERROR_WANT_WRITE) {
                if (conn->write_timeout_ms > 0) {
                    return HC_TLS_TIMEOUT;
                }
                continue;
            }
            if (conn->client_certificate_configured &&
                client_certificate_alert_status() == HC_TLS_CLIENT_CERT_REJECTED) {
                return HC_TLS_CLIENT_CERT_REJECTED;
            }
            return HC_TLS_WRITE_FAILED;
        }
        offset += written;
    }

    return HC_TLS_OK;
}

int hc_tls_read_some(hc_tls_connection *conn, char *buffer, int length, int *count) {
    int amount;
    int ssl_error;

    if (count != NULL) {
        *count = 0;
    }

    if (conn == NULL || conn->ssl == NULL || buffer == NULL || length < 0 || count == NULL) {
        return HC_TLS_READ_FAILED;
    }

    if (length == 0) {
        return HC_TLS_OK;
    }

    for (;;) {
        ERR_clear_error();
        amount = SSL_read(conn->ssl, buffer, length);
        if (amount > 0) {
            *count = amount;
            return HC_TLS_OK;
        }

        ssl_error = SSL_get_error(conn->ssl, amount);
        if (ssl_error == SSL_ERROR_WANT_READ || ssl_error == SSL_ERROR_WANT_WRITE) {
            if (conn->read_timeout_ms > 0) {
                return HC_TLS_TIMEOUT;
            }
            continue;
        }
        if (ssl_error == SSL_ERROR_ZERO_RETURN) {
            return HC_TLS_END_OF_STREAM;
        }
        if (conn->client_certificate_configured &&
            client_certificate_alert_status() == HC_TLS_CLIENT_CERT_REJECTED) {
            return HC_TLS_CLIENT_CERT_REJECTED;
        }

        return HC_TLS_READ_FAILED;
    }
}


int hc_tls_read_some_with_timeout(hc_tls_connection *conn, char *buffer, int length, int *count, int timeout_ms) {
    int old_timeout;
    int status;
    int fd = -1;

    if (conn == NULL || conn->bio == NULL) {
        if (count != NULL) {
            *count = 0;
        }
        return HC_TLS_READ_FAILED;
    }

    old_timeout = conn->read_timeout_ms;
    if (BIO_get_fd(conn->bio, &fd) >= 0 && fd >= 0) {
        if (!set_socket_timeout_ms(fd, SO_RCVTIMEO, timeout_ms)) {
            if (count != NULL) {
                *count = 0;
            }
            return HC_TLS_INTERNAL_ERROR;
        }
    }
    conn->read_timeout_ms = timeout_ms;

    status = hc_tls_read_some(conn, buffer, length, count);

    if (fd >= 0) {
        if (!set_socket_timeout_ms(fd, SO_RCVTIMEO, old_timeout)) {
            cleanup_partial(conn);
            return HC_TLS_INTERNAL_ERROR;
        }
    }
    conn->read_timeout_ms = old_timeout;
    return status;
}

int hc_tls_close(hc_tls_connection *conn) {
    if (conn != NULL) {
        if (conn->ssl != NULL) {
            /*
             * Client-side close is a resource-retirement operation for the Ada
             * transport.  Do not perform a blocking TLS close-notify exchange
             * here: HTTP/2 single-stream execution retires the TLS connection
             * after a complete response, and some peers do not answer
             * close_notify promptly on otherwise valid completed streams.
             *
             * SSL_set_quiet_shutdown marks the SSL object as already shut down
             * so SSL_free/cleanup closes the underlying socket without a
             * network round-trip.  This keeps Close deterministic while the
             * HTTP layer remains responsible for reading protocol END_STREAM.
             */
            SSL_set_quiet_shutdown(conn->ssl, 1);
        }
        cleanup_partial(conn);
    }
    return HC_TLS_OK;
}
