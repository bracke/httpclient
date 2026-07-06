# http_client

`http_client` is an Ada 2022 HTTP/HTTPS client library for explicit, correctness-oriented network applications. It provides conservative URI parsing, validated request/header models, HTTP/1.1 execution, HTTPS/TLS through OpenSSL, HTTP/2 foundations and execution support, explicit proxy/SOCKS configuration, retries, redirects, cookies, decompression, streaming, upload and multipart helpers, in-memory and persistent caches, diagnostics, client certificates, bounded async integration, and experimental HTTP/3/QUIC protocol boundaries.

This repository is currently prepared toward a **1.0.0 release**. The intended stable API surface, compatibility policy, default limits, and release checklist are documented under [`docs/`](docs/DOCUMENTATION_INDEX.md). The development manifest may use a temporary workspace pin to the sibling Ada `zlib` checkout for local validation; the publishable manifest is `httpclient.alire.release.toml`, which must remain free of local pins.

## Design goals

- **Explicit behavior:** redirects, retries, cookies, decompression, caches, proxies, SOCKS, diagnostics, async execution, protocol discovery, and HTTP/3 candidates are disabled until configured by the caller.
- **Conservative security defaults:** TLS certificate and hostname verification are enabled by default, HTTPS-to-HTTP downgrade redirects are blocked, cross-origin credentials are stripped on redirects, and diagnostics redact secrets by default.
- **Bounded resource use:** in-memory reads, headers, body sizes, caches, retry/redirect counts, diagnostics previews, async queues, and protocol-frame handling are governed by documented limits.
- **Ada-first API:** callers use typed records, explicit status values, caller-owned objects, and ordinary Ada package boundaries rather than browser-style global state.
- **Offline validation:** the default test suite is deterministic and does not require public internet access.

## Toolchain

Every active crate manifest pins GNAT 15 through Alire:

```toml
[[depends-on]]
gnat_native = "=15.2.1"
```

Do not run plain system GNAT, GPRBuild, GNATprove, GNATdoc, or related `gnat*`
tools from `PATH`. Build, prove, and inspect the compiler through Alire so the
pinned toolchain is selected:

```sh
alr exec -- gnatls --version
alr exec -- gprbuild -P httpclient.gpr
alr exec -- gnatprove -P httpclient.gpr --level=4
```

The version command must report `GNATLS 15.x`. The release tooling verifies the
compiler selection and the exact `gnat_native = "=15.2.1"` dependency in the
root, release, test, and example manifests.

## Quickstart

The shortest path is in [`docs/QUICKSTART.md`](docs/QUICKSTART.md). The basic flow is:

```sh
alr build
alr exec -- gprbuild -P httpclient.gpr

# default offline AUnit suite
cd tests
alr exec -- gprbuild -P tests.gpr
./bin/tests
cd ..

# release/static checks implemented as Ada tools
alr exec -- gnatprove -P httpclient.gpr --level=4
alr test
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_all
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
```

Compile examples with:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

## Install

With Alire, add `httpclient` as a dependency once the crate is available from your configured index:

```sh
alr with httpclient
```

For a local checkout, build the provided project file:

```sh
alr exec -- gprbuild -P httpclient.gpr
```

The crate depends on OpenSSL and an Ada `zlib` library. Http_Client imports no C zlib symbols; HTTP content-coding policy lives in HttpClient, while gzip/deflate mechanics are delegated through the internal Ada adapter `Http_Client.Zlib_Decompression`. Platform-specific TLS/crypto installation details are intentionally left to the Alire/toolchain environment and the package manager used by the target system.

## First request

A default client uses conservative settings. Optional behavior is enabled explicitly through configuration records.

```ada
with Http_Client.Clients;
with Http_Client.Errors;

procedure Simple_Get is
   Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
   Result : Http_Client.Clients.Client_Result;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Client.Get ("https://example.com/", Result);

   if Status = Http_Client.Errors.Ok then
      --  Result.Response contains the final parsed response.
      null;
   else
      --  Use Status for program control. Diagnostic text is for humans.
      null;
   end if;
end Simple_Get;
```

Manual request construction is also available when callers need lower-level control:

```ada
with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Manual_Request is
   Ref     : Http_Client.URI.URI_Reference;
   Request : Http_Client.Requests.Request;
   Status  : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.URI.Parse ("https://example.com/index.html", Ref);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Http_Client.Types.GET, Ref, Request);
   end if;
end Manual_Request;
```

See [`docs/EXAMPLES.md`](docs/EXAMPLES.md) for examples covering GET, HTTPS, POST-like bodies, streaming downloads, uploads, multipart, proxies, SOCKS, authentication, cookies, caches, diagnostics, async calls, client certificates, HTTP/2, and explicit HTTP/3 configuration, including local-only `http3_force_no_backend.adb` and `http3_prefer_with_fallback.adb` boundary examples.

### Git smart HTTP compile-targeted examples

The examples project includes generic, compile-checked Git smart HTTP transport shapes for external
consumers. They use reserved `.invalid` origins and do not contact public remotes during release
verification. See [`docs/EXAMPLES.md`](docs/EXAMPLES.md) and the Phase 14 example pass. Key files are
`git_info_refs_streaming_get.adb`, `git_upload_pack_post_buffered.adb`,
`git_receive_pack_fixed_upload.adb`, `git_receive_pack_chunked_upload.adb`,
`git_chunked_upload_with_trailers.adb`, `git_receive_pack_expect_continue.adb`,
`git_https_custom_ca.adb`, `git_https_proxy_connect.adb`, `git_socks5_https.adb`,
`git_streaming_decompression.adb`, `git_http2_streaming_fetch_shape.adb`,
`http3_force_no_backend.adb`, `git_redirect_policy.adb`, `git_retry_policy.adb`,
`git_streaming_with_timeout_and_cancellation.adb`, and `git_binary_safe_transport_shape.adb`.

Build them with:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```


## Feature summary

### Stable public areas

The 1.0.0 stable surface covers ordinary user-facing APIs for:

- URI parsing and validation
- headers, requests, responses, and HTTP status handling
- HTTP/1.1 serialization, response reading, and execution
- HTTPS/TLS options and OpenSSL-backed TLS transport behavior
- high-level client configuration and execution
- redirects, retries, cookies, decompression, and resource limits
- HTTP proxy and SOCKS5 proxy configuration
- Basic, Bearer, and Digest authentication helpers
- client-certificate TLS configuration
- response streaming, fixed-length uploads, and multipart/form-data construction
- in-memory cache, persistent cache, and encrypted persistent cache configuration
- diagnostics, tracing hooks, metrics, and redaction policy
- bounded async/task integration
- documented HTTP/2 configuration, HPACK/frame/settings helpers, bounded multiplexing state, streaming, upload support, and aggregate queued-body limits
- explicit Alt-Svc and HTTPS/SVCB protocol-discovery building blocks

The stable contract is described in [`docs/STABLE_API_CONTRACT.md`](docs/STABLE_API_CONTRACT.md), [`docs/compatibility.md`](docs/compatibility.md), and [`docs/COMPATIBILITY_POLICY.md`](docs/COMPATIBILITY_POLICY.md).

### Experimental areas

`Http_Client.HTTP3`, `Http_Client.HTTP3.*`, and `Http_Client.QUIC` are experimental. This source tree exposes HTTP/3/QUIC configuration and protocol-boundary packages, but it **does not provide production HTTP/3 execution** unless a production QUIC backend is explicitly configured and supported by the build. Unsupported HTTP/3 requests fail honestly with HTTP/3/QUIC statuses before unsafe request transmission, or fall back only where the caller configured fallback-before-send policy.

## Security defaults

The default configuration is intentionally conservative:

- TLS certificate and hostname verification are enabled.
- SNI is enabled for suitable DNS names.
- Redirect following is disabled.
- Retries are disabled.
- Cookies require a caller-supplied jar.
- Decompression is disabled unless requested.
- Caches and persistent stores are disabled unless configured.
- HTTP proxy and SOCKS routing are disabled unless configured.
- Diagnostics are silent unless a diagnostics context is supplied.
- HTTP/3 and protocol discovery are disabled unless configured.
- Alt-Svc and HTTPS/SVCB discovery do not bypass configured proxies.
- HTTPS-to-HTTP downgrade redirects are blocked by default.
- Sensitive headers are stripped across cross-origin redirects by default.
- Diagnostic output redacts secrets by default.
- Sensitive authenticated responses are bypassed by cache policy unless explicitly safe to store.

Read [`docs/security.md`](docs/security.md), [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md), and [`docs/DEFAULT_LIMITS.md`](docs/DEFAULT_LIMITS.md) before enabling advanced behavior in production.

## What this library deliberately does not do

`http_client` is not a browser networking stack. It does not implement PAC/WPAD/browser proxy discovery, browser profile import, browser cache integration, service workers, browser preload behavior, server-push cache behavior, automatic form/login flows, OAuth token acquisition or refresh, OpenID Connect, SAML, NTLM, Negotiate/SPNEGO, Kerberos, OS credential stores, hardware-token integration, password-manager integration, SOCKS UDP ASSOCIATE, SOCKS BIND, MASQUE, CONNECT-UDP, WebTransport, Tor control behavior, or hidden browser-like networking policy.

## Repository layout

```text
src/                    Library source
examples/               Small compile-checked examples
tests/                  Offline AUnit tests, API-stability checks, fixtures, optional interop
benchmarks/             Optional benchmark tooling
tools/                  Ada release-check tools
docs/                   User, maintainer, API, security, and release documentation
httpclient.gpr         Main GPRbuild project
alire.toml              Alire crate metadata
```

## Testing model

The normal validation path is offline and deterministic:

```sh
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
```

Additional checks:

```sh
# API-stability compile check
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr

# Release-surface and corpus hygiene checks
alr exec -- gnatprove -P httpclient.gpr --level=4
alr test
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_all
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus

# Optional coverage gate when GNAT/gcov tooling is available
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

Optional interoperability, fuzzing, and benchmark commands are documented separately and are not required for ordinary offline validation. See [`docs/TESTING.md`](docs/TESTING.md), [`docs/AUNIT_SUITE.md`](docs/AUNIT_SUITE.md), [`docs/COVERAGE.md`](docs/COVERAGE.md), and [`docs/SPARK.md`](docs/SPARK.md).


### HTTP/2 and HTTP/3 for Git smart HTTP

Buffered Git smart HTTP calls can now select HTTP/2 or HTTP/3 explicitly through `Http_Client.Clients.Execution_Options.Protocol_Policy` or the client configuration equivalent. Use `Prefer_HTTP_2` or `Force_HTTP_2` for h2; `Force_HTTP_2` rejects plain `http://` requests because h2c is not implemented. Use `Prefer_HTTP_3` or `Force_HTTP_3` only when an HTTP/3 QUIC backend is configured and the request is HTTPS without unsupported proxy/client-certificate constraints.

The pull-based `Http_Client.Response_Streams` API now has explicit HTTP/1.1, HTTP/2, and HTTP/3 protocol policies. HTTP/1.1 remains the default and safest large-packfile path. HTTP/2 streaming requires h2 ALPN. HTTP/3 streaming is experimental and depends on a configured QUIC backend.

Compile-tested buffered examples are provided in `examples/src/git_info_refs_http2_buffered.adb` and `examples/src/git_info_refs_http3_buffered.adb`.

## AI discovery

Machine-readable project orientation is available in [`llms.txt`](llms.txt).
Coding-agent guidance is available in [`AGENTS.md`](AGENTS.md), and a longer AI
usage guide is available in [`docs/AI_USAGE_GUIDE.md`](docs/AI_USAGE_GUIDE.md).

## Documentation map

Start here:

- [`docs/QUICKSTART.md`](docs/QUICKSTART.md) — first build, test, and client usage
- [`docs/DOCUMENTATION_INDEX.md`](docs/DOCUMENTATION_INDEX.md) — complete documentation index
- [`docs/api-overview.md`](docs/api-overview.md) — API overview
- [`docs/configuration.md`](docs/configuration.md) — configuration model
- [`docs/security.md`](docs/security.md) — security model and defaults
- [`docs/DEFAULT_LIMITS.md`](docs/DEFAULT_LIMITS.md) — default limits
- [`docs/STABLE_API_CONTRACT.md`](docs/STABLE_API_CONTRACT.md) — stable API contract
- [`docs/http2.md`](docs/http2.md) and [`docs/http3.md`](docs/http3.md) — protocol-specific guidance
- [`docs/release-policy.md`](docs/release-policy.md), [`docs/RELEASE_NOTES_1_0_0.md`](docs/RELEASE_NOTES_1_0_0.md), and [`docs/POST_RELEASE_BASELINE.md`](docs/POST_RELEASE_BASELINE.md) — release policy, release notes, and post-release baseline

## Compatibility and deprecation policy

The release policy defines breaking changes conservatively: removing public packages, renaming public types, changing public record fields, changing default security behavior, changing status-return semantics, changing wire serialization, changing cache-key semantics, changing redirect/retry policy, weakening diagnostics redaction, changing exception policy, or changing ownership/lifetime semantics are treated as compatibility-sensitive changes.

Minor releases may add APIs, add optional features disabled by default, improve documentation, fix bugs, reject unsafe malformed input more strictly, and optimize internals while preserving documented behavior. Deprecated APIs must be documented with replacements and preserved for a compatibility window before removal in a major version. See [`docs/compatibility.md`](docs/compatibility.md) and [`docs/release-policy.md`](docs/release-policy.md).

## License

`http_client` is distributed under the MIT license. See [`LICENSE`](LICENSE).

## Using `http_client` for Git smart HTTP

`http_client` provides a narrow binary streaming surface suitable for Git smart HTTP clients. Use `Http_Client.Response_Streams.Open` or `Http_Client.Clients.Execute_Stream` to obtain response metadata after headers are parsed, then repeatedly call `Http_Client.Response_Streams.Read_Some` with an `Ada.Streams.Stream_Element_Array` buffer until `End_Of_Stream` or `End_Of_Body`.

The Git path should set `Accept-Encoding: identity`, keep `Cookie_Jar => null`, and avoid decoded execution unless streaming decompression is explicitly needed. Automatic cookie storage is not used unless an explicit jar is supplied. Decompression is explicit; buffered decoded execution and opt-in streaming decompression support `gzip` via `Zlib.GZip` and HTTP `deflate` via zlib-wrapped Deflate (`Zlib.Zlib_Header`), enforce decoded-size limits, reject raw Deflate for HTTP `deflate`, and map malformed compressed streams to deterministic statuses. The Git examples request identity encoding so pkt-line parsers see the expected byte stream.

HTTP/1.1 response streaming supports fixed `Content-Length`, connection-close-delimited bodies for one-shot connections, bodyless status/method cases, and `Transfer-Encoding: chunked`. Chunked response bodies are decoded before bytes are returned. Chunk-size lines, chunk CRLF bytes, extensions, and trailers are never exposed through the normal response-body API; valid extensions are ignored and bounded trailers are parsed and discarded.

AUnit coverage includes a Git-shape loopback fixture for `/repo.git/git-upload-pack` that streams a chunked pkt-line-like binary response through a caller-provided `Ada.Streams.Stream_Element_Array` buffer smaller than the chunks and verifies exact decoded byte reconstruction, including NUL and non-ASCII octets.

For upload-pack requests with small or prebuilt bodies, use `Http_Client.Request_Bodies.From_Bytes`. For receive-pack push bodies, use `From_Fixed_Length_Stream` with a caller-owned producer and an exact known length. Unknown-length request streaming uses HTTP/1.1 `Transfer-Encoding: chunked` via `From_Unknown_Length_Stream`; fixed-length push uploads should still use `From_Fixed_Length_Stream` when the pack size is already known. HTTP/1.1 request trailers are supported for chunked uploads by attaching a validated trailer list to the request body; they are declared with `Trailer` and emitted after the terminating chunk. HTTP/2 request trailers are supported separately as trailing HEADERS, without HTTP/1.1 chunk framing or a `Trailer` declaration. Explicit HTTP/1.1 `Trailer` headers must cover every attached trailer field. Trailer fields remain metadata rather than body bytes, and unsupported or forbidden trailer positions/names fail deterministically.

HTTPS is selected automatically for `https://` URIs. TLS certificate validation, hostname verification, and SNI remain enabled by default through `Http_Client.Transports.TLS.Default_TLS_Options`. Configure custom CA paths through TLS options when the user explicitly asks for a private CA. Disabling verification requires the unsafe TLS option and should not be used for normal Git remotes.

HTTPS through an explicit HTTP proxy uses HTTP/1.1 CONNECT before the origin TLS handshake in both buffered and streaming HTTP/1.1 paths. HTTPS through an explicit SOCKS5 proxy performs SOCKS CONNECT first and starts origin TLS inside that tunnel in both buffered and streaming HTTP/1.1 paths. HTTP proxy credentials are sent only on CONNECT; SOCKS credentials are used only in SOCKS negotiation; origin headers, cookies, request bodies, and client certificates are sent only after the tunnel is established and TLS verification succeeds.

Redirects and retries are explicit and bounded. For Git-style callers, keep them disabled initially, or enable only policies that strip credentials on cross-origin redirects, block HTTPS-to-HTTP downgrades, and replay only replayable request bodies. Mid-stream failures after a response stream is returned are reported to the caller and are not retried automatically.

Compile-tested examples are in `examples/src/git_info_refs_stream.adb`, `examples/src/git_upload_pack_stream.adb`, `examples/src/git_receive_pack_fixed_upload.adb`, `examples/src/git_receive_pack_chunked_upload.adb`, `examples/src/git_receive_pack_chunked_upload_trailers.adb`, `examples/src/git_info_refs_https_proxy_stream.adb`, `examples/src/git_info_refs_https_socks_stream.adb`, `examples/src/git_info_refs_http2_buffered.adb`, `examples/src/git_info_refs_http3_buffered.adb`, `examples/src/git_upload_pack_http2_stream.adb`, and `examples/src/git_info_refs_http3_stream.adb`. The exact public API and ownership contract are documented in `docs/GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md`; the Git smart HTTP integration contract is documented in `docs/GIT_SMART_HTTP_INTEGRATION_CONTRACT.md`.


### Expect: 100-continue for uploads


Git integrations that require stable HTTP/1.1 transfer semantics should set `Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1` for buffered execution or `Streaming_HTTP_1_1_Only` for pull streaming. Callers may explicitly opt into `Streaming_Prefer_HTTP_2`, `Streaming_Force_HTTP_2`, `Streaming_Prefer_HTTP_3`, or `Streaming_Force_HTTP_3`.

For large HTTP/1.1 uploads, callers may set `Expect: 100-continue`. The client sends headers first and sends the body only after the server returns `100 Continue`. The header is not generated automatically.


Expect: 100-continue completeness note: buffered and streaming request bodies are withheld when the explicit `Expect: 100-continue` header is present. The client writes headers first, waits for `100 Continue`, and only then sends the body. If the server returns a final response such as `417 Expectation Failed`, the body is not sent. The client never adds `Expect` automatically.


#### Expect: 100-continue early final bodies

If a server rejects `Expect: 100-continue` with a final response before upload, buffered execution returns that response body and does not send the request body. Fixed-length and HTTP/1.1 chunked early final response bodies are decoded through the same entity-body semantics as ordinary responses; chunk trailers are parsed and discarded. Streaming execution exposes the early final response metadata from `Open` and lets callers read the decoded final response body through `Read_Some` without uploading the request body.


The streaming test suite includes a local HTTP proxy CONNECT fixture that returns
`200 Connection Established` and then closes before TLS. That test verifies that
HTTPS streaming routes through the proxy, sends only CONNECT metadata and proxy
authorization before TLS, does not leak origin Git headers/cookies/credentials to
the proxy, and proceeds to the TLS layer after a successful CONNECT response.

The streaming test suite also includes a local SOCKS5 tunnel fixture. It verifies
SOCKS username/password negotiation, a SOCKS CONNECT request to `example.com:443`,
absence of origin Git headers/cookies/credentials during SOCKS negotiation, and
transition to the TLS layer after a successful SOCKS CONNECT reply.


## HTTP/1.1 protocol-policy completeness note

Force_HTTP_1_1 is an execution-level override: it disables HTTP/3 candidate selection, Alt-Svc/HTTPS-SVCB upgrade selection, and HTTP3-required early failure for that execution path without mutating the reusable client configuration. Cache dispatch treats forced HTTP/1.1 executions as HTTP/1.1 cache-wrapper executions rather than HTTP/3 fresh-cache lookups.

The final HttpClient-side Git smart HTTP audit is tracked in `docs/GIT_SMART_HTTP_FINAL_AUDIT_PASS.md`. That document is scoped only to this crate; downstream adapters remain out of scope for HttpClient. The release tooling guard for this surface is `./tools/bin/check_git_smart_http_release`, documented in `docs/GIT_SMART_HTTP_RELEASE_TOOLING_PASS.md` and checked by the follow-up `docs/GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md`.


### HTTP/2 Git byte streams

The low-level `Http_Client.HTTP2.Body_Streams` and `Http_Client.HTTP3.Body_Streams` adapters include `Read_Some` overloads for `Ada.Streams.Stream_Element_Array`. They are binary-safe for Git pkt-line and packfile bytes. The high-level `Http_Client.Response_Streams` API now exposes explicit HTTP/2 and HTTP/3 streaming policies while keeping HTTP/1.1 as the default.


### HTTP/2 and HTTP/3 Git streaming examples

The Git smart HTTP examples now include `git_upload_pack_http2_stream.adb` and `git_info_refs_http3_stream.adb`. HTTP/2 streaming is selected explicitly with `Streaming_Prefer_HTTP_2` or `Streaming_Force_HTTP_2`. HTTP/3 streaming is selected explicitly with `Streaming_Prefer_HTTP_3` or `Streaming_Force_HTTP_3` and remains dependent on the configured QUIC backend.

Git smart HTTP HTTP/2/HTTP/3 streaming parity completeness notes are in `docs/GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_COMPLETENESS_PASS.md`.


## Phase 3 HTTP/1.1 streaming correctness

HTTP/1.1 streaming reads expose entity bytes, not transfer framing. Chunked response decoding is supported, including chunk extensions, split chunk metadata, bounded response trailers, and arbitrary binary body bytes. Unknown-length request streams use chunked upload; request trailers are restricted to HTTP/1.1 chunked uploads; `Expect: 100-continue` is explicit and withholds the body until `100 Continue`. Decompression remains opt-in. Close-delimited, malformed, incomplete, failed-upload, and decompression-failed streams are closed/discarded rather than reused. See `docs/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md`.


### TLS and proxy fixture policy

The first release package does not include project-owned C TLS, HTTP CONNECT, or SOCKS5 test fixtures and does not link pthread-based fixture support. The production OpenSSL bridge remains the only allowed project-owned C source. Loopback end-to-end TLS/proxy fixture coverage is implemented in Ada task-based test packages.

### HTTPS-over-HTTP-CONNECT

HTTPS-over-CONNECT remains part of the public client capability surface. The compile-checked examples demonstrate the configuration shape, and deterministic proxy policy/status behavior remains covered by Ada tests that do not rely on custom C fixture code.

### HTTPS-over-SOCKS5

HTTPS-over-SOCKS5 remains part of the public client capability surface. The compile-checked examples demonstrate SOCKS5 proxy configuration, and deterministic SOCKS policy/status behavior remains covered by Ada tests that do not rely on custom C fixture code.


## Phase 7 connection pooling

The high-level buffered HTTP/1.1 client now has transport-attached connection reuse when `Client_Configuration.Pooling.Enabled` is true. Pooling is bounded, disabled by default, and conservative: fixed-length and fully consumed chunked responses may be reused; close-delimited, malformed, incomplete, failed-upload, timeout, proxy/TLS-failure, and explicit `Connection: close` paths discard the transport. Reuse is keyed by origin, scheme, proxy route, proxy credential identity, TLS verification/CA/SNI settings, and client-certificate identity; checked-out real handles preserve per-connection request counts. Request headers, cookies, authorization fields, SOCKS passwords, and Git headers are never sticky or logged across reused connections. See `docs/GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md`.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.


- `streaming_get_with_cancellation.adb` demonstrates byte-array streaming with explicit connect/read/write timeout values and an optional cooperative cancellation token.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.


### Experimental HTTP/3 boundary

HTTP/3 is experimental and backend-dependent in this tree. The compile-visible helpers and examples do not imply production QUIC support. `Force_HTTP_3` and `Streaming_Force_HTTP_3` never silently fall back to HTTP/2 or HTTP/1.1; without a production QUIC backend they return deterministic unsupported/no-backend status. `Prefer_HTTP_3` may fall back only before request bytes are sent and must preserve configured TLS/proxy/security options. See `docs/HTTP3_EXPERIMENTAL.md`, `docs/GIT_SMART_HTTP_PHASE11_HTTP3_BOUNDARY_PASS.md`, `examples/src/http3_force_no_backend.adb`, and `examples/src/http3_prefer_with_fallback.adb`.

### Phase 12 redirect/retry safety for Git smart HTTP

Redirects and retries are explicit opt-ins. HTTPS downgrade redirects are blocked by default; cross-origin redirects strip credentials, cookies, and `Git-Protocol`; 301/302/303 rewrites that drop the body also drop stale Git body headers and `Expect: 100-continue`; non-replayable Git upload bodies are not retried or replayed; forced protocol policies and configured proxy routes remain preserved across redirect/retry chains. See `docs/GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md`.

### Phase 13 Git header/binary safety

The Git smart HTTP surface treats `Ada.Streams.Stream_Element_Array` as the authoritative body representation. Header validation rejects CR/LF injection, duplicate or conflicting framing headers fail deterministically, HTTP/2 DATA bytes stay separate from metadata and trailers, and diagnostics redact sensitive headers without logging body bytes by default. See `docs/GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md`.
