# Release notes: 1.0.0

Date: 2026-05-17

This release packages the audited `httpclient` Ada 2022 crate as a binary-safe HTTP/HTTPS client for explicit, correctness-oriented applications. It is the release-engineering baseline after the Phase 15 final audit and does not add a new protocol feature beyond the verified release baseline.

## Summary

`httpclient` 1.0.0 provides stable HTTP/1.1 execution, binary-safe streaming and upload APIs, conservative TLS defaults, explicit HTTP and SOCKS proxy routing, safe high-level redirect defaults, bounded high-level response decompression, redirect/retry safety controls, HTTP/2 multiplexing with trailer support, and deterministic HTTP/3 experimental boundaries.

The release is suitable as the HttpClient-side dependency for an external Git smart HTTP transport. It does not include a downstream `Version.Transport.Http` adapter, Git object parsing, pkt-line parsing, or packfile parsing.

## Git smart HTTP readiness

The release includes crate-local support and compile-checked examples for Git smart HTTP transport shapes:

- byte-array request and response body paths for Git pkt-line and packfile data;
- streaming response reads through `Ada.Streams.Stream_Element_Array` buffers;
- fixed-length and unknown-length chunked request uploads;
- request trailers where the public trailer API applies;
- explicit `Expect: 100-continue` handling with early-final response behavior;
- custom CA, HTTPS-over-HTTP-CONNECT, and HTTPS-over-SOCKS5 examples;
- proxy credential isolation and origin credential isolation across direct, CONNECT, and SOCKS paths;
- redirect and retry defaults that avoid unsafe replay of non-replayable Git upload bodies.

## Compression and decompression

High-level buffered client decompression is enabled by default. Streaming decompression remains disabled by default. The basic streaming path does not add `Accept-Encoding` automatically. When explicitly enabled, gzip, zlib-wrapped deflate, and raw deflate are supported according to the configured decompression policy. Decoded-size limits are enforced incrementally, and decoded bytes remain binary-safe.

Compression/decompression depends on the external Ada `Zlib` crate through the isolated `Http_Client.Zlib_Decompression` adapter. This release does not include a C zlib bridge and does not add direct `-lz` linkage.

## Protocol support

- HTTP/1.1 is the stable primary execution path.
- HTTP/2 supports bounded client-side multiplexing, binary-safe body streams, uploads, flow-control accounting, deterministic GOAWAY/RST handling, per-stream decompression, request/response trailers as trailing HEADERS, DATA receive-window replenishment with WINDOW_UPDATE, explicit response-DATA crediting for multiplexed transports, and HPACK decoding for raw and Huffman-encoded string literals.
- Fixed HTTP/2 interoperability with servers that use legal HPACK Huffman-encoded header names or values; malformed Huffman payloads still fail deterministically with `HPACK_Huffman_Error`.
- HTTP/3 remains experimental and backend-dependent. `Force_HTTP_3` without a backend fails deterministically and does not silently fall back. `Prefer_HTTP_3` fallback behavior is explicit and tested. HTTP/3 does not bypass configured HTTP or SOCKS proxies.

Unsupported protocol features remain deterministic limitations unless a later release deliberately implements them. This includes h2c, HTTP/2 server push, HTTP/2 priority-tree behavior, extended CONNECT, production HTTP/3 execution without a backend, MASQUE, CONNECT-UDP, WebTransport, and browser-style networking policy.

## Security and correctness notes

TLS certificate validation and hostname verification are enabled by default. Unsafe verification disablement is explicit and must not be used in positive HTTPS examples or tests. Custom CA configuration is supported for deterministic local fixtures and deployments that require private trust roots.

Retries, cookies, caches, diagnostics, proxies, SOCKS, async execution, and protocol discovery remain explicit caller choices rather than hidden global/browser-like behavior. High-level buffered defaults follow safe redirects and expose a bounded decoded response view; `Strict_Client_Configuration` preserves no-redirect/no-transform behavior. Diagnostics redact sensitive headers and do not log body bytes by default.

Header validation rejects injection names and values according to the documented policy. Duplicate/conflicting `Content-Length`, transfer-framing conflicts, HTTP/2 framing-header misuse, invalid trailers, malformed compressed data, timeouts, cancellations, and unsupported forced protocol policies return deterministic statuses.

## Packaging and verification

The intended release verification command set is:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
./tools/bin/check_git_smart_http_release
alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr
```

The source archive should include source, project files, Alire manifest, documentation, examples, tests, tools, benchmark sources, and license files. It should exclude generated object files, executables, `.ali` files, temporary archives, local dependency caches, scratch logs, local editor files, private credentials, accidental secrets, C test fixtures, and pthread-based test support. Ada task-based local TLS/proxy fixtures are included for release verification.

## Known limitations

- HTTP/3 production execution requires an actual backend and remains experimental/backend-dependent in this release.
- h2c is not implemented.
- HTTP/2 server push is not implemented.
- Browser behavior is intentionally absent, including browser profile import, service workers, preload behavior, browser cache integration, automatic proxy discovery, and automatic credential-store integration.
- MASQUE, CONNECT-UDP, WebTransport, SOCKS UDP ASSOCIATE, SOCKS BIND, Tor control behavior, NTLM, Negotiate/SPNEGO, Kerberos, OAuth/OIDC/SAML token acquisition, and automatic login flows are absent.
- Platform-specific OpenSSL and CA-store discovery remain deployment/toolchain concerns; custom CA configuration is available where deterministic trust roots are needed.
- Cancellation is cooperative and checked at documented execution and streaming checkpoints.

## Tag metadata

Suggested tag: `v1.0.0`

Use the final local commit that contains this release note, `docs/POST_RELEASE_BASELINE.md`, the version bump to `1.0.0`, and the final verification record. Do not claim that a tag was pushed unless the maintainer actually pushes it through the project release workflow.

## IPv6 literal URLs

HTTP and HTTPS URLs may use IPv6 address literals in the standard bracketed authority form:

```ada
Status := Http_Client.Clients.Get
  ("http://[::1]:8080/",
   Result);
```

Support matrix:

| Host form | Status | Notes |
| --- | --- | --- |
| DNS hostnames | Supported | Normal DNS name parsing and TLS DNS-name verification apply. |
| IPv4 literals | Supported | TLS requires a matching IPv4 IP subjectAltName for HTTPS. |
| IPv6 literals | Supported in bracketed URI form, such as `http://[::1]/`. | Socket/TLS code receives the unbracketed address internally; emitted URI authorities and Host headers remain bracketed. |
| IPv6 zone identifiers | Unsupported | Scoped forms such as `http://[fe80::1%25lo0]/` fail deterministically. |
| h2c | Unsupported | Plain HTTP/2 cleartext upgrade remains out of scope. |

HTTPS to an IPv6 literal keeps certificate verification enabled. The certificate must contain a matching IPv6 IP subjectAltName; DNS-only certificates fail hostname/IP verification.


- Preserved HTTP/2 RST_STREAM REFUSED_STREAM error-code semantics with HTTP2_Stream_Refused so retry-eligible requests are no longer collapsed into generic HTTP2_Stream_Reset failures.
- Normalized HTTP/2 request mapping to strip HTTP/1.1-only compatibility headers, allow legal `TE: trailers`, and synthesize `content-length` for known non-empty h2 request bodies so strict peers do not reset otherwise valid streams.

- HTTP/2: request HPACK encoding now uses static-table indexes for common pseudo-header names and exact static fields, improving interoperability with reset-prone HTTP/2 endpoints without hiding active-stream resets behind HTTP/1.1 fallback.

- Normalized HTTP/2 request mapping so `Expect: 100-continue` is not forwarded on HTTP/2 requests, avoiding strict peer stream resets caused by HTTP/1.1-only expectation semantics.

- Fixed single-stream HTTP/2 request execution so fixed-length producer-backed request bodies are serialized as DATA before END_STREAM instead of sending an empty stream that strict peers can reset.

HTTP/2 peer RST_STREAM frames are mapped to the most specific existing result status when the reset code is known. RST_STREAM frames are mapped to the most specific existing result status, so PROTOCOL_ERROR, FLOW_CONTROL_ERROR, FRAME_SIZE_ERROR, COMPRESSION_ERROR, REFUSED_STREAM, and HTTP_1_1_REQUIRED no longer collapse into only HTTP2_STREAM_RESET.
- TLS-backed HTTP/2 frame reads and writes honor configured read/write timeout intent through the OpenSSL bridge where platform socket timeouts are available. High-level HTTPS execution now also applies top-level request timeouts as the TLS default when TLS-specific timeouts are unset, so stalled h2 peers can return `Timeout` instead of blocking indefinitely.

- Added `h2_wire_probe`, a diagnostic tool that prints outbound and inbound
  HTTP/2 bytes and parsed frame summaries for direct TLS/ALPN h2 connections.
  This keeps failing HTTP/2 exchanges observable instead of masking them with
  fallback behavior.

- `tools/bin/h2_wire_probe` sends connection- and stream-level WINDOW_UPDATE frames after response DATA so large HTTP/2 responses can complete instead of stalling at the initial receive window.


HTTP/2 buffered execution advertises a larger default receive window and sends an initial connection-level WINDOW_UPDATE before request HEADERS, then continues to replenish receive windows while DATA is consumed. This prevents large responses from stalling at the HTTP/2 initial 65,535-byte connection window.

- Avoid slow HTTP/2 completion caused by blocking TLS close-notify waits after a completed stream.


### HTTP/2 buffered response limit adjustment

- HTTP/2 interoperability fixes now allow large real-world pages to complete instead of stalling at the initial flow-control window.
- The default buffered response/body limit is raised from 1 MiB to 16 MiB so successful large HTTP/2 responses do not immediately fail with `RESPONSE_TOO_LARGE`.
- Explicit caller-configured limits remain authoritative; smaller configured limits still fail deterministically with `RESPONSE_TOO_LARGE`.


## Download-to-file convenience API

Added `Http_Client.Clients.Download_To_File` and `Execute_To_File` for streaming response bodies directly to files without buffering the complete body in memory. Buffered APIs remain bounded by `Max_Body_Size`; file downloads use the separate `Download_Options.Max_Download_Size`, which defaults to `Default_Max_Download_Size` and is much higher than the buffered body cap. The default file mode is `Replace_Atomically`, with deterministic cleanup of partial temporary files unless requested otherwise. `Download_Options.Durability` can opt into fsync of completed files and best-effort parent-directory fsync after atomic rename.

## Response metadata convenience accessors

Added direct `Http_Client.Responses` helpers for server-declared response metadata: `Header`, `Has_Header`, `Has_Content_Type`, `Content_Type`, `Media_Type`, `Has_Charset`, and `Charset`. The helpers are side-effect-free wrappers over stored response headers; they do not sniff bodies, infer MIME types from URLs or filenames, change transport behavior, or alter buffered/download size limits.
