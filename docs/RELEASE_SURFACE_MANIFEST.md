# Release surface manifest

This manifest is the compact release-audit view of the public Ada units. It complements `PUBLIC_PACKAGES.md` by recording the intended compatibility class for every source package that an application can technically `with` from `src/`.

## Compatibility classes

- **Stable application API**: intended for ordinary application use after 1.0.
- **Stable low-level API**: public and documented, but protocol- or transport-specific; most callers should prefer higher-level packages.
- **Experimental API**: visible and tested, but not covered by the final 1.0 compatibility promise until a later deliberate production phase.
- **Implementation boundary**: visible because of the current crate layout or C bridge needs; callers should not treat byte layouts, queue internals, or storage records as compatibility promises beyond documented status/result behavior.

## Stable application API

| Package | Release role |
| --- | --- |
| `Http_Client` | Root namespace and version. |
| `Http_Client.Auth` | Basic authentication helper values and request wrappers. |
| `Http_Client.Auth.Bearer` | Bearer helper values and request wrappers. |
| `Http_Client.Auth.Digest` | Digest challenge parsing and caller-supplied response generation. |
| `Http_Client.Auth.Scopes` | Origin/proxy authentication scoping helpers. |
| `Http_Client.Async` | Explicit bounded task integration for buffered requests. |
| `Http_Client.Cache` | Bounded in-memory cache policy and store API. |
| `Http_Client.Cache.Persistent` | Explicit persistent and encrypted persistent cache store API. |
| `Http_Client.Cancellation` | Explicit cooperative cancellation token API. |
| `Http_Client.Clients` | High-level synchronous buffered and streaming client API. |
| `Http_Client.Cookies` | Explicit in-memory cookie jar. |
| `Http_Client.Decompression` | Opt-in decoded response helpers. |
| `Http_Client.Diagnostics` | Opt-in diagnostics, metrics, callbacks, and redaction. |
| `Http_Client.Alt_Svc` | Bounded Alt-Svc parser and alternative metadata. |
| `Http_Client.DNS_SVCB` | Deterministic HTTPS/SVCB resolver record modeling. |
| `Http_Client.HTTPS_Records` | HTTPS/SVCB service-record parsing and selection helpers. |
| `Http_Client.Protocol_Discovery` | Caller-owned protocol-discovery policy and bounded cache. |
| `Http_Client.Proxy_Discovery` | Explicit PAC/WPAD helper boundary; no implicit browser/system proxy import. |
| `Http_Client.Errors` | Result statuses and stable coarse categories. |
| `Http_Client.Headers` | Validated header-field collection. |
| `Http_Client.Multipart` | Multipart/form-data body construction. |
| `Http_Client.Proxies` | HTTP/SOCKS proxy configuration. |
| `Http_Client.Proxies.SOCKS` | SOCKS5 helper classification and reply handling. |
| `Http_Client.Request_Bodies` | Fixed-length upload body producers. |
| `Http_Client.Requests` | Protocol-neutral request model. |
| `Http_Client.Response_Streams` | Caller-owned streaming response API. |
| `Http_Client.Responses` | Protocol-neutral buffered response model and server-declared metadata convenience accessors. |
| `Http_Client.Retry` | Explicit bounded retry policy. |
| `Http_Client.Resources` | Optional observational resource counters for tests, diagnostics, and benchmark smoke checks. |
| `Http_Client.TLS.Client_Certificates` | Explicit client-certificate credentials. |
| `Http_Client.Types` | Common HTTP method/status-code types. |
| `Http_Client.URI` | Conservative absolute HTTP/HTTPS URI parser. |

## Stable low-level API

| Package | Release role |
| --- | --- |
| `Http_Client.Connection_Pools` | Bounded pooling policy and lifecycle tokens. |
| `Http_Client.HTTP1` | HTTP/1.1 request serialization. |
| `Http_Client.HTTP1.Reader` | Bounded HTTP/1.1 raw response framing. |
| `Http_Client.HTTP2` | HTTP/2 configuration, ALPN, and execution policy. |
| `Http_Client.HTTP2.Body_Streams` | HTTP/2 public body-stream adapter. |
| `Http_Client.HTTP2.Connection` | Bounded HTTP/2 connection/stream state. |
| `Http_Client.HTTP2.Frames` | HTTP/2 frame encoding/decoding helpers. |
| `Http_Client.HTTP2.HPACK` | HPACK subset utilities. |
| `Http_Client.HTTP2.Mapping` | HTTP/2 request/response header mapping. |
| `Http_Client.HTTP2.Settings` | HTTP/2 settings encoding and validation. |
| `Http_Client.HTTP2.Single_Stream` | Conservative single-stream HTTP/2 execution boundary. |
| `Http_Client.HTTP2.Streams` | HTTP/2 stream-state helpers. |
| `Http_Client.HTTP2.Uploads` | HTTP/2 upload-body integration. |
| `Http_Client.Transports` | Transport interface boundary. |
| `Http_Client.Transports.SOCKS` | SOCKS tunnel transport helper. |
| `Http_Client.Transports.TCP` | Plain TCP transport. |
| `Http_Client.Transports.TLS` | OpenSSL-backed TLS transport. |

## Experimental API

| Package | Release role |
| --- | --- |
| `Http_Client.HTTP3` | HTTP/3 candidate configuration and unsupported-execution boundary. |
| `Http_Client.HTTP3.Body_Streams` | Experimental byte-array body-stream boundary for HTTP/3 response data. |
| `Http_Client.HTTP3.Execution` | Buffered HTTP/3 execution insertion point; can call a supplied production backend callback and otherwise fails deterministically. |
| `Http_Client.HTTP3.Frames` | HTTP/3 varint/frame foundations. |
| `Http_Client.HTTP3.Mapping` | HTTP/3 request/response mapping foundations. |
| `Http_Client.HTTP3.QPACK` | Conservative no-dynamic-table QPACK subset. |
| `Http_Client.HTTP3.Settings` | HTTP/3 settings foundations. |
| `Http_Client.HTTP3.Streams` | HTTP/3 stream classification foundations. |
| `Http_Client.QUIC` | Unavailable QUIC backend boundary. |

## Implementation boundary

| Package | Release role |
| --- | --- |
| `Http_Client.Crypto` | Cryptographic bridge helper for cache encryption internals. |
| `Http_Client.HTTP2_Execution_Common` | Shared HTTP/2 execution helper boundary used by buffered and streaming execution paths; not an application API. |
| `Http_Client.Response_Streams.HTTP2_IO` | Private frame-read helper for pull-streaming HTTP/2 response execution; not an application API. |
| `Http_Client.TLS` | TLS bridge namespace used by transport/certificate units. |
| `Http_Client.Zlib_Decompression` | Adapter boundary around the external Ada `zlib` dependency; use `Http_Client.Decompression` for application policy. |

Applications should prefer stable application packages and treat experimental packages as compile-visible tests of future protocol boundaries. Program control should depend on `Http_Client.Errors.Result_Status`, result records, and documented options, not on private storage bytes or diagnostic message text.

## Protocol-discovery surface

Stable public protocol-discovery packages: `Http_Client.Alt_Svc`, `Http_Client.DNS_SVCB`, `Http_Client.HTTPS_Records`, `Http_Client.Protocol_Discovery`, and `Http_Client.Proxy_Discovery`. They expose conservative parsers, scripted resolver abstractions, bounded in-memory discovery cache ownership, explicit fallback policy, and proxy/SOCKS limitations. Discovery is disabled by default, does not persist metadata, does not use HTTP response caches as discovery storage, and does not bypass configured proxies.
