# Interoperability and conformance matrix

This matrix is a release-validation aid, not a claim of universal compatibility.

The optional runner in `interop/` provides a first executable harness for Tier 2
and Tier 3 probes. It is deliberately separate from the offline AUnit suite and
is configured only through explicit endpoints supplied by the caller.

| Area | Tier 1 offline/unit/loopback | Tier 2 local extended | Tier 3 live external | Notes |
| --- | --- | --- | --- | --- |
| URI parsing | Yes | Not required | Not required | Strict absolute HTTP/HTTPS parser vectors. |
| HTTP/1.1 serialization | Yes | Optional server echo | Optional | Header order/body text assertions remain offline; fixed-length uploads use `Content-Length` and unknown-length uploads use explicit chunked transfer coding. |
| HTTP/1.1 response parsing/framing | Yes | Optional malformed local server | Optional | Buffered and streaming paths decode supported `Transfer-Encoding: chunked` response bodies and reject unsupported transfer codings. |
| Plain HTTP execution | Loopback | Local HTTP server | Configured HTTP endpoint | Public body/header exact text should not be brittle. |
| HTTPS/TLS defaults | TLS option tests | Local TLS server | Configured HTTPS endpoint | Default verification, hostname checks, SNI, HTTP CONNECT, SOCKS HTTPS, and optional mTLS stay explicit. |
| Bad TLS classification | Option/negative tests | Local bad-cert endpoint | Configured bad-cert endpoint | Success against an intentionally bad endpoint is a failure. |
| HTTP/2 ALPN and h2 execution | Offline protocol/HPACK tests | Local h2 endpoint | Configured h2 endpoint | Required-h2 tests need an endpoint that promises h2. |
| HTTP/3/QUIC boundary | Offline QPACK/frame/unsupported/proxy-rejection tests | Local QUIC backend if available | Configured h3 endpoint | Skips or reports unsupported without a real backend; proxy/SOCKS rejection is validated when configured. |
| Redirects | Loopback | Local redirect server | Configured redirect endpoint | Downgrade and credential stripping remain covered offline. |
| Cookies | Unit/loopback | Local controlled cookie endpoint | Optional only | Avoid volatile public cookies. |
| Compression | Unit/loopback | Local compressed endpoint | Configured compressed endpoint | Assert decoded behavior, not exact public body text. |
| Cache and persistent cache | Unit/loopback/persistent fixtures | Local cacheable endpoint | Optional controlled endpoint only | Public endpoints are too volatile for deterministic cache assertions. |
| Encrypted persistent cache | Offline corruption/tamper tests | Not required | Not required | No secret keys printed. |
| Basic/Bearer/Digest helpers | Unit tests and deterministic vectors | Local auth endpoint | Optional controlled endpoint | Basic and Bearer are live-runner capable; Digest remains helper/vector focused unless a controlled endpoint is added. No production credentials. |
| Client certificates | Option and scope tests | Local mTLS endpoint | Optional controlled endpoint | Dedicated test certificates only. |
| HTTP proxy | Loopback/protocol tests | Local proxy | Configured proxy | Proxy credentials must stay redacted. |
| SOCKS proxy | Byte-sequence/loopback tests | Local SOCKS proxy | Configured SOCKS proxy | SOCKS credentials must never become HTTP headers. |
| Async/task integration | Offline lifecycle tests | Low-load local timing tests | Optional low-load live tests | Avoid rate-limit or high-load public tests. |
| Diagnostics/metrics | Offline redaction tests | Local end-to-end traces | Optional redacted traces | Timing values should not be exact assertions. |
| Multipart/upload streaming | Exact-output/unit tests | Local echo endpoint | Optional controlled echo endpoint | Do not send sensitive files. |

Compatibility notes should name actual server versions only after they are tested. Keep them in release notes or a separate evidence log rather than hard-coded test assumptions.
