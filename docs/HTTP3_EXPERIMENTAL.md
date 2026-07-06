# HTTP/3 experimental boundary

HTTP/3 and QUIC packages are experimental foundations. They validate configuration, ALPN token policy, fallback policy, frame varints, settings, stream classification, request/response mapping, and QPACK no-dynamic-table helpers.

This release provides no production QUIC backend and does not provide 0-RTT, server-push caching, proxy-compatible HTTP/3 routing, client-certificate-over-QUIC support, or browser-like fallback. Buffered HTTP/3 execution can use a caller-supplied `Http_Client.HTTP3.Execution.Buffered_Backend_Callback`; without one, enabling HTTP/3 fails deterministically.

HTTP/3 must not bypass configured HTTP/SOCKS proxies, diagnostics redaction, TLS/security policy, credential scope, or redirect/retry policy. `HTTP3_Required` applies only to HTTPS/QUIC-capable origins when the execution protocol policy is `Protocol_From_Configuration`; a plain `http://` request is rejected deterministically instead of falling through to HTTP/1.1 unless that specific execution sets `Force_HTTP_1_1`. While HTTP/3 is enabled, legacy cache execution wrappers are skipped unless the specific execution sets `Force_HTTP_1_1`, so a required HTTP/3 request does not accidentally execute through TCP-only HTTP/1.1/HTTP/2 paths and an explicitly forced HTTP/1.1 request still uses the HTTP/1.1 cache wrapper. A future production backend can add cache-aware HTTP/3 miss/revalidation routing deliberately.


## Execution boundary

`Http_Client.HTTP3.Execution` is the explicit buffered HTTP/3 insertion point. It validates request shape, maps HTTP/3 request headers, enforces proxy/client-certificate/fallback policy, and then either calls a supplied `Buffered_Backend_Callback` or fails deterministically before request bytes are sent. The boundary also rechecks the returned buffered body against `Max_Body_Size`, requires the synthetic response container version to be `HTTP_1_1`, applies `Max_Header_List_Size` to returned response headers and trailers, rejects HTTP/3-forbidden response headers, validates decoded `content-length` metadata, validates response trailers, rejects control characters in reason phrases, and rejects body bytes on HEAD/1xx/204/205/304 responses, so a backend cannot expose an oversized or protocol-invalid `Ok` response through this API. It never sends HTTP/3 frames over TCP/TLS and never bypasses configured HTTP or SOCKS proxies. Proxy and SOCKS policy rejection is evaluated before streaming-upload shape rejection so a forbidden proxy configuration is reported as `HTTP3_Proxy_Unsupported`; producer-backed upload bodies otherwise return `Unsupported_Feature` before backend execution. When a caller supplies an opt-in diagnostics context, the boundary emits structural unsupported-execution and QUIC start/failure events around the backend-open attempt, emits a redacted error event when a backend response is rejected by the boundary, and emits a redacted response-metadata event after a configured backend returns a validated response. These events carry status, origin, protocol, byte counts, and caller-provided correlation identifiers only, not credentials, cookies, request bodies, QUIC secrets, TLS material, or header values.


## Native QUIC backend seam

`Http_Client.QUIC` now has private Ada-side handle plumbing for a future native backend. The default C bridge in `src/c/http_client_quic_backend_bridge.c` deliberately reports unavailable support and returns `QUIC_Unsupported`; it is not a partial UDP implementation and does not mark connections open.

A production backend can replace that bridge with an audited implementation backed by ngtcp2/nghttp3, OpenSSL QUIC, or another QUIC/HTTP/3 stack. The bridge boundary is intentionally small: report availability, open a QUIC connection for a validated host/port/options tuple, return an opaque handle, and close that handle. Native status codes are mapped back into existing `Result_Status` values, so the public Ada API and HTTP/3 policy boundary do not need to change when the backend library becomes available.

The native open hook is only transport-level preparation. A usable HTTP/3 implementation still needs request stream creation, HTTP/3 SETTINGS/control streams, HEADERS/DATA I/O, QPACK handling, response collection, and integration with the existing `Buffered_Backend_Callback` validation path.

## Git smart HTTP buffered selection

Buffered Git smart HTTP requests may select the experimental HTTP/3 path through execution protocol policy:

```ada
Execution.Protocol_Policy := Http_Client.Clients.Prefer_HTTP_3;
-- or:
Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
```

`Prefer_HTTP_3` enables an HTTP/3 candidate with before-send fallback. `Force_HTTP_3` requires the HTTP/3 candidate and disables fallback. HTTP/3 still requires HTTPS, a caller-supplied buffered backend callback, no unsupported proxy path, and no unsupported client-certificate configuration. Git headers map to lowercase HTTP/3 ordinary fields, and buffered binary bodies remain byte-preserving. Public HTTP/3 response streaming and upload streaming are not promoted in this release.

## Phase 11 boundary hardening

This tree has no built-in production QUIC backend. The compile-visible HTTP/3 data model, frame helpers, conservative QPACK subset, settings helpers, body-stream adapters, and backend callback boundary are not themselves a QUIC/TLS network stack.

`Force_HTTP_3` and `Streaming_Force_HTTP_3` are no-fallback policies. Without a supplied buffered backend, they return deterministic unsupported/no-backend status, normally `QUIC_Unsupported` after the explicit HTTP/3 execution boundary is reached, or `HTTP3_Proxy_Unsupported` when a configured HTTP/SOCKS proxy would otherwise be bypassed. They do not downgrade to HTTP/2 or HTTP/1.1 and they are not retried as HTTP/1.1.

`Prefer_HTTP_3` and `Streaming_Prefer_HTTP_3` may fall back only before request bytes are sent and only according to `Fallback_Before_Send`. Fallback preserves the caller's TLS, proxy, retry, redirect, cookie, decompression, and diagnostics configuration. With an HTTP proxy or SOCKS5 proxy configured, no direct QUIC route to the origin is attempted; the HTTP/3 candidate reports `HTTP3_Proxy_Unsupported`, and any allowed fallback proceeds through the configured proxy route.

`Http_Client.HTTP3.Body_Streams` is binary-safe where compile-visible. It exposes `Ada.Streams.Stream_Element_Array` append and read APIs for DATA payload bytes and does not perform text conversion. Reading an unopened/no-backend stream fails deterministically with `Not_Connected`.

The QPACK helper subset rejects unsupported dynamic/indexed/Huffman-coded forms deterministically with `HTTP3_QPACK_Error`. Server push, 0-RTT, MASQUE, CONNECT-UDP, WebTransport, and HTTP/3 proxy tunneling are not implemented in this phase.

## Phase 13 HTTP/3 binary boundary note

The HTTP/3 surface remains experimental/backend-dependent. Compile-visible body-stream helpers are byte-array oriented. A no-backend or unsupported forced HTTP/3 execution fails deterministically and must not create partial header/body state or silently fall back under a forced policy.
