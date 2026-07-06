# Resource usage and performance hardening

The resource-hardening campaign hardens existing behavior without adding protocol features or changing public semantics. The library remains explicit and bounded: buffered APIs are bounded by configured response/header/body limits, streaming APIs avoid retaining full response bodies, upload and multipart producers read in bounded chunks, connection pooling is optional and bounded, async execution is explicit and bounded, caches are bounded, diagnostics are opt-in and redacted, and HTTP/2/HTTP/3 concurrency is bounded by their existing configuration models.

## Ownership inventory

| Resource | Owner | Bound or cleanup rule |
| --- | --- | --- |
| Plain TCP sockets | TCP transport and the owning client/stream execution path | Closed on explicit `Close`, failure, timeout, finalization safety net, or non-reusable response state. |
| TLS contexts/connections | TLS transport and the owning client/stream execution path | Closed with the transport owner; verification and client-certificate scope are not weakened for reuse. |
| QUIC/HTTP/3 backend objects | HTTP/3 execution and configured QUIC backend boundary | Allocated only when HTTP/3 is explicitly enabled and backend support is available; unsupported paths fail or fall back according to existing policy before unsafe transmission. |
| HTTP/2 streams | HTTP/2 connection state | Bounded by configured concurrent-stream and tracked-stream limits; reset/release paths discard unread queued bytes and credit receive windows. |
| HTTP/3 streams | HTTP/3 stream model/execution boundary | Bounded by explicit HTTP/3 options and backend availability; unsupported stream types remain rejected. |
| Connection-pool entries | `Http_Client.Connection_Pools.Connection_Pool` | Idle entries are bounded globally and per key; shutdown and close discard all retained entries. Credentials, proxies, SOCKS settings, TLS options, and client certificates remain part of the compatibility key. |
| Async workers and queue entries | `Http_Client.Async.Async_Client` | `Initialize` starts exactly `Max_Workers`; `Submit` is bounded by `Max_Queued`; `Shutdown` waits for workers; finalization requests shutdown as a safety net. |
| Request and response streams | Request-body producers and `Streaming_Response` | Explicit `Close` is idempotent. Streaming response finalization closes remaining transport state. Early close discards the connection rather than returning ambiguous state to a pool. |
| Multipart file-backed parts | Multipart/request-body producer layer | File contents are read incrementally. Known-length computation uses metadata and must not read entire files. |
| Cookie jars | Cookie package/high-level client configuration | Count, value-size, and header-size limits are enforced by jar configuration. Expiration cleanup is deterministic. |
| In-memory cache | `Http_Client.Cache` | Entry count, total body bytes, and single-entry body bytes are bounded. Oversized entries bypass storage unless strict policy says otherwise. |
| Persistent cache files | `Http_Client.Cache.Persistent` | Directory scans, metadata bytes, body bytes per entry, total stored bytes, and entry count are bounded. Lookups prefilter metadata before reading body files. |
| Encrypted persistent cache files | Persistent cache encryption layer | Metadata/body files remain encrypted at rest; authentication failures do not write decrypted persistent temporary data. Temporary and orphan files are ignored or cleaned during bounded scans. |
| Diagnostics events | `Http_Client.Diagnostics` | Disabled contexts return before event construction work is observable. Enabled contexts use bounded text fields and redaction before callbacks. |
| Decompression contexts | Decompression package/client execution | Decoded-size limits are enforced; corrupt streams fail cleanly without partial success. |
| HPACK/QPACK tables | HTTP/2 HPACK and HTTP/3 QPACK packages | Dynamic table limits remain explicit and must not index sensitive headers for speed. |
| SOCKS/HTTP proxy tunnels | Proxy/transport execution | Handshake buffers are bounded; tunnel state is closed on failure and is never reused across incompatible proxy or credential keys. |
| Local test servers | AUnit test fixtures | Loopback-only, bounded lifecycle, closed before test completion. |

## Resource counters

`Http_Client.Resources` provides process-local diagnostic counters for leak-oriented tests and benchmark smoke runs. The counters are observational only: they do not influence protocol behavior, retry policy, cache decisions, redaction, TLS verification, fallback, or public status semantics.

Tracked counters currently include open streaming responses, open async clients, configured async workers, idle pool entries, open persistent cache stores, and diagnostics events emitted. `Reset_All` exists for deterministic tests and benchmark executables.

## Size-limit policy

Every configured size or count limit should fail deterministically and leave ownership clean:

* Oversized response headers fail before a reusable connection is considered clean.
* Oversized buffered bodies return the documented body/response limit status.
* Streaming body limits apply to cumulative bytes returned by `Read_Some` without retaining the whole body.
* Oversized decompressed output fails without returning partial success.
* Oversized cache entries bypass storage unless strict cache behavior is explicitly configured.
* Diagnostics previews are truncated by bounded fields and redaction policy without modifying protocol data.

## Hot-path hardening rules

Resource-hardening code should preserve clarity while avoiding obvious accidental costs:

* Store normalized header keys once and use them for lookup/count/removal.
* Avoid quadratic string concatenation in parser and serialization loops.
* Avoid loading persistent cache body files during metadata-only checks.
* Avoid full-body buffering in response streaming, upload streaming, multipart file parts, and async request execution.
* Avoid allocating diagnostics strings when diagnostics are disabled.
* Keep exact-output tests for request serialization, header order, cache keys, redirects, retries, and diagnostics redaction.

## Testing expectations

Default AUnit tests remain deterministic, offline, and bounded. Resource-limit and cleanup tests are gating. Throughput benchmarks live outside the default AUnit path and report visibility data rather than pass/fail timing thresholds.
