# Git smart HTTP Phase 11 HTTP/3 boundary hardening pass

Phase 11 hardens the experimental HTTP/3 boundary without claiming production HTTP/3 support.

The current source tree contains compile-visible HTTP/3 helpers, frame/varint/settings support, a conservative QPACK literal/static subset, binary-safe body-stream adapters, and an explicit HTTP/3 execution insertion point. It does not contain a production QUIC backend. Therefore real HTTP/3 network execution fails deterministically with `QUIC_Unsupported` or a more specific preflight status such as `HTTP3_Proxy_Unsupported`.

## Forced policy

`Force_HTTP_3` and `Streaming_Force_HTTP_3` remain forced. They do not silently fall back to HTTP/2 or HTTP/1.1. Without a production QUIC backend, forced buffered and streaming execution return deterministic unsupported/no-backend status before request bytes are sent.

Redirect and retry handling must preserve the forced HTTP/3 policy. No-backend or unsupported HTTP/3 status is not retried as HTTP/1.1.

## Prefer policy

`Prefer_HTTP_3` and `Streaming_Prefer_HTTP_3` may fall back only before request bytes or body bytes are sent and only when the configured fallback policy allows it. Fallback remains subject to the caller's TLS, proxy, retry, redirect, cookie, decompression, and diagnostics configuration.

When a proxy is configured, HTTP/3 over that proxy route is treated as unsupported unless a future proxy-compatible HTTP/3 route is explicitly implemented and documented. Fallback, when allowed, uses the configured HTTP proxy or SOCKS5 route for HTTP/1.1 or HTTP/2. No direct UDP/QUIC connection to the origin is opened behind an explicit proxy configuration.

## Proxy and security boundary

HTTP/3 does not bypass HTTP proxies or SOCKS5 proxies. `Force_HTTP_3` with either proxy kind returns `HTTP3_Proxy_Unsupported` before a QUIC open attempt. Proxy credentials remain scoped to the proxy configuration and are never moved into origin HTTP/3 headers or diagnostics.

TLS verification defaults are not weakened. The unavailable QUIC backend boundary does not perform partial or unsafe TLS; it returns deterministic unsupported status until a real QUIC/TLS 1.3 backend exists.

## Binary body-stream API

`Http_Client.HTTP3.Body_Streams` remains compile-visible and binary-safe. Its byte-array `Read_Some` overload preserves arbitrary DATA bytes, including NUL and high-bit octets, and does not perform UTF-8 validation, charset conversion, line-ending normalization, or NUL stripping. Reading an unopened/no-backend stream fails deterministically with `Not_Connected`.

## QPACK helper scope

The QPACK helpers intentionally cover only the conservative subset required by the experimental boundary. Unsupported indexed/dynamic-table forms and Huffman-coded strings fail deterministically with `HTTP3_QPACK_Error`. This helper availability is not production HTTP/3 network execution.

## Release coverage markers

Phase 11 adds dedicated AUnit coverage for:

- `Test_HTTP3_Force_No_Backend_Fails_Deterministically`
- `Test_HTTP3_Force_No_Fallback_To_HTTP2`
- `Test_HTTP3_Force_No_Fallback_To_HTTP1`
- `Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically`
- `Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically`
- `Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically`
- `Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy`
- `Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy`
- `Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy`
- `Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy`
- `Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically`
- `Test_HTTP3_Fallback_After_Request_Bytes_Disallowed`
- `Test_HTTP3_Experimental_Unsafe_Features_Rejected`
- `Test_HTTP3_No_Backend_Not_Retried_As_HTTP1`
- `Test_HTTP3_Redirect_Keeps_Forced_Policy`
- `Test_HTTP3_Body_Stream_Byte_Array_API_Compiles`
- `Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically`
- `Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically`

The examples `http3_force_no_backend.adb` and `http3_prefer_with_fallback.adb` are local-only examples. They label HTTP/3 as experimental/backend-dependent and do not contact external network hosts.


Completeness pass addition: the HTTP/3 body stream adapter also exposes `HTTP3.Body_Streams.Append_Data` for `Ada.Streams.Stream_Element_Array`, so future backend code and Git integrations can feed binary DATA payloads without constructing text strings.
