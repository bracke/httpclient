# Public package classification

This document freezes the intended 1.0 release public surface. Stable packages may be used by applications directly. Experimental packages may change before a later production milestone. Implementation packages are visible Ada units only because the current crate keeps source in one tree; ordinary users should not build application logic on them unless the relevant package comment explicitly says the type is stable.

## Stable application packages

- `Http_Client` — root namespace and version.
- `Http_Client.URI` — conservative absolute HTTP/HTTPS URI parsing, normalized accessors, and reusable host validation helpers.
- `Http_Client.Types` — common HTTP method and status-code types.
- `Http_Client.Errors` — result-status model and coarse status categories used for program control, diagnostics, and metrics.
- `Http_Client.Cancellation` — explicit cooperative cancellation token API for buffered and streaming operations.
- `Http_Client.Headers` — validated header-field collection.
- `Http_Client.Requests` — protocol-neutral request model.
- `Http_Client.Responses` — protocol-neutral buffered response model.
- `Http_Client.Clients` — high-level synchronous buffered and streaming client configuration.
- `Http_Client.Response_Streams` — explicit streaming response ownership.
- `Http_Client.Request_Bodies` — buffered and fixed-length upload producers.
- `Http_Client.Multipart` — multipart/form-data body construction.
- `Http_Client.Cookies` — explicit in-memory cookie jar.
- `Http_Client.Decompression` — opt-in bounded decoded response helpers.
- `Http_Client.Retry` — explicit bounded retry policy.
- `Http_Client.Auth`, `Http_Client.Auth.Bearer`, `Http_Client.Auth.Digest`, `Http_Client.Auth.Scopes` — caller-supplied authentication header helpers.
- `Http_Client.Proxies`, `Http_Client.Proxies.SOCKS` — explicit HTTP and SOCKS5 proxy configuration and protocol helpers.
- `Http_Client.Cache`, `Http_Client.Cache.Persistent` — explicit in-memory, persistent, and encrypted persistent cache APIs.
- `Http_Client.Diagnostics` — opt-in structured diagnostics, redaction, and metrics.
- `Http_Client.TLS.Client_Certificates` — explicit client-certificate credential configuration.
- `Http_Client.Async` — explicit bounded task integration for buffered requests.
- `Http_Client.Alt_Svc`, `Http_Client.DNS_SVCB`, `Http_Client.HTTPS_Records`, `Http_Client.Protocol_Discovery`, `Http_Client.Proxy_Discovery` — explicit, bounded Alt-Svc and HTTPS/SVCB protocol-discovery configuration, parsing, and in-memory metadata. Discovery is disabled by default and never implements proxy bypass or browser-like networking.

## Stable but low-level packages

These packages are stable enough for advanced users and tests, but most applications should prefer `Http_Client.Clients`.

- `Http_Client.HTTP1`, `Http_Client.HTTP1.Reader` — deterministic HTTP/1.1 serialization and bounded framing.
- `Http_Client.Transports`, `Http_Client.Transports.TCP`, `Http_Client.Transports.TLS`, `Http_Client.Transports.SOCKS` — explicit transport boundaries.
- `Http_Client.Connection_Pools` — bounded HTTP/1.1 pooling policy and tokens.
- `Http_Client.HTTP2`, `Http_Client.HTTP2.Settings`, `Http_Client.HTTP2.Mapping` — HTTP/2 configuration and mapping.
- `Http_Client.HTTP2.HPACK`, `Http_Client.HTTP2.Frames`, `Http_Client.HTTP2.Streams`, `Http_Client.HTTP2.Connection`, `Http_Client.HTTP2.Single_Stream`, `Http_Client.HTTP2.Body_Streams`, `Http_Client.HTTP2.Uploads` — bounded HTTP/2 protocol utilities and execution scaffolding.

## Experimental packages

- `Http_Client.HTTP3`
- `Http_Client.HTTP3.Execution`
- `Http_Client.HTTP3.Frames`
- `Http_Client.HTTP3.Mapping`
- `Http_Client.HTTP3.QPACK`
- `Http_Client.HTTP3.Settings`
- `Http_Client.HTTP3.Streams`
- `Http_Client.HTTP3.Body_Streams`
- `Http_Client.QUIC`

These packages exist to keep HTTP/3 configuration, frame, stream, QPACK, and fallback boundaries testable. They do not provide production HTTP/3 execution, an available QUIC backend, 0-RTT, server-push caching, or proxy-bypassing fallback.

## Implementation detail guidance

`Http_Client.Zlib_Decompression` is an implementation-boundary adapter for the external Ada `zlib` dependency. Application code should use `Http_Client.Decompression` rather than depending on the adapter internals.

`Http_Client.HTTP2_Execution_Common` is an implementation-boundary helper shared by the buffered single-stream and pull-streaming HTTP/2 execution paths. Application code should use `Http_Client.Clients`, `Http_Client.Response_Streams`, or the documented low-level HTTP/2 packages rather than depending on this helper.

`Http_Client.Response_Streams.HTTP2_IO` is a private frame-read helper for pull-streaming HTTP/2 response execution. Application code should use `Http_Client.Response_Streams` instead.

`Http_Client.Crypto` and OpenSSL bridge internals, cache file bytes, encrypted-cache record layout, SOCKS negotiation bytes, HTTP/2 frame dispatch internals, worker queues, and test fixtures are not compatibility promises unless they are explicitly documented in a stable package specification. Applications should depend on statuses, structured metadata, and documented record fields rather than diagnostic message text or private storage formats.

## Resource instrumentation package

`Http_Client.Resources` exposes optional process-local counters for diagnostics, benchmark smoke tests, and leak-oriented regression tests. The counters are observational only and must not be used by protocol code to choose retry, redirect, fallback, TLS, cache, authentication, or serialization behavior. Resetting counters is intended for deterministic tests and benchmark executables.
