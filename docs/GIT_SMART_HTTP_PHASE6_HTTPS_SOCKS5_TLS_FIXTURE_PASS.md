# Git Smart HTTP Phase 6 — HTTPS-over-SOCKS5 TLS Fixture Pass

Phase 6 adds deterministic local HTTPS-over-SOCKS5 end-to-end coverage on top of the Phase 4 direct TLS origin fixture and the Phase 5 HTTP CONNECT proxy fixture.

The tested path is:

```text
client -> local SOCKS5 proxy -> SOCKS5 greeting/authentication -> SOCKS5 CONNECT origin-host:origin-port -> TLS handshake through the SOCKS tunnel -> local HTTPS origin -> HTTP/1.1 request/response
```

Positive SOCKS5/TLS tests use `tests/fixtures/tls/ca.crt`; they do not use unsafe certificate-verification disable. Certificate validation remains enabled by default. Hostname verification and SNI use the origin hostname, not the SOCKS proxy hostname.

## Fixture coverage

The new `tests/src/http_client_socks5_proxy_fixture.c` fixture binds loopback on an ephemeral port, accepts one SOCKS5 client connection, captures only pre-tunnel SOCKS negotiation bytes, validates no-authentication or username/password negotiation, parses IPv4 and DNS-name CONNECT requests, returns deterministic SOCKS replies, and tunnels bytes bidirectionally after a successful CONNECT reply.

The fixture can inject deterministic failure behavior for unsupported version replies, no acceptable authentication methods, username/password auth failure, malformed username/password auth replies, general CONNECT failure, host unreachable, connection refused, malformed CONNECT replies, close before CONNECT reply, and tunnel close during the TLS handshake.

## AUnit coverage

`tests/src/http_client-socks5_tls_tests.adb` covers:

- `Test_SOCKS5_TLS_GET_No_Auth_With_Configured_CA_Succeeds`
- `Test_SOCKS5_TLS_GET_Username_Password_With_Configured_CA_Succeeds`
- `Test_SOCKS5_TLS_Streaming_GET_No_Auth_Succeeds`
- `Test_SOCKS5_TLS_Binary_Body_Preserved`
- `Test_SOCKS5_TLS_Chunked_Response_Preserved`
- `Test_SOCKS5_TLS_Proxy_Sees_Only_SOCKS_Handshake_Before_Tunnel`
- `Test_SOCKS5_TLS_POST_Buffered_Binary_Body`
- `Test_SOCKS5_TLS_POST_Fixed_Length_Stream`
- `Test_SOCKS5_TLS_POST_Chunked_Upload`
- `Test_SOCKS5_TLS_Request_Trailers_After_Chunked_Upload`
- `Test_SOCKS5_TLS_Expect_Continue_With_Trailers`
- `Test_SOCKS5_TLS_Localhost_SNI_Uses_Origin_Host`
- `Test_SOCKS5_TLS_Certificate_Failure_After_Tunnel`
- `Test_SOCKS5_TLS_Hostname_Failure_After_Tunnel`
- `Test_SOCKS5_No_Acceptable_Methods_Returns_Deterministic_Status`
- `Test_SOCKS5_Username_Password_Auth_Failure_Returns_Deterministic_Status`
- `Test_SOCKS5_Malformed_Auth_Response_Returns_Deterministic_Status`
- `Test_SOCKS5_Connect_General_Failure_Returns_Deterministic_Status`
- `Test_SOCKS5_Connect_Host_Unreachable_Returns_Deterministic_Status`
- `Test_SOCKS5_Connect_Connection_Refused_Returns_Deterministic_Status`
- `Test_SOCKS5_Malformed_Connect_Reply_Returns_Deterministic_Status`
- `Test_SOCKS5_Close_Before_Reply_Returns_Deterministic_Status`
- `Test_SOCKS5_Tunnel_Close_During_TLS_Returns_Deterministic_Status`
- `Test_SOCKS5_Unsupported_Version_Returns_Deterministic_Status`

## Credential and header isolation

SOCKS-visible pre-tunnel bytes are limited to SOCKS greeting, optional username/password sub-negotiation, and SOCKS CONNECT metadata. The tests assert that Origin `Authorization`, `Cookie`, `Git-Protocol`, Git `Content-Type`, request path/query, and request body bytes are not visible to the SOCKS proxy before the tunnel is established.

SOCKS username/password credentials are used only in RFC 1929 username/password sub-negotiation. The origin fixture asserts that SOCKS credentials do not appear in the HTTP request inside the TLS tunnel.

## Streaming and binary safety

The Phase 6 tests exercise byte-array streaming through SOCKS5 with small caller buffers, fixed `Content-Length` responses, chunked transfer decoding through the TLS tunnel, and binary response bodies containing NUL, CR, LF, and bytes above 127. Body paths remain binary-safe and use `Ada.Streams.Stream_Element_Array` where response bytes are asserted.

## Negative behavior

SOCKS authentication, CONNECT, malformed-reply, tunnel-close, certificate, and hostname failures return deterministic `Http_Client.Errors.Result_Status` values. Failed SOCKS/TLS paths close the connection rather than attempting questionable reuse.

SOCKS5 UDP ASSOCIATE, BIND, SOCKS4, SOCKS4a, PAC/WPAD, browser proxy discovery, Tor control behavior, and external network fixtures remain out of scope.
