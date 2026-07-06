# Release verification procedure

This procedure is the final manual gate before tagging a 1.0-style release.

1. Build the library with the documented switches: `alr exec -- gprbuild -P httpclient.gpr` or `alr build`.
2. Run `alr exec -- gnatprove -P httpclient.gpr --level=4` and require the documented SPARK surface to pass legality checks.
3. Build the test runner: `alr exec -- gprbuild -P tests/tests.gpr`.
4. Run `./tests/bin/tests` and require every offline AUnit test to pass.
5. Run `alr test` from the crate root.
6. Run `cd tests && alr exec -- ../tools/bin/run_aunit_coverage` and require the production Ada coverage gate to pass at 100% line and branch coverage.
7. Build examples with `alr exec -- gprbuild -P examples/examples.gpr`.
8. Build the API-stability compile check with `alr exec -- gprbuild -P tests/api_stability/api_stability.gpr`.
9. Run `alr exec -- gprbuild -P tools/tools.gpr`, then run `./tools/bin/check_all`, `./tools/bin/check_release_surface`, `./tools/bin/check_aunit_suite`, `./tools/bin/check_security_corpus`, and `./tools/bin/check_git_smart_http_release` to catch stale release-story wording, missing manifest rows, AUnit suite drift, security-corpus drift, and Git smart HTTP release-surface drift without network access or optional live services.
8. If benchmarks are part of the release archive, build them with `alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr`.
9. Review compiler warnings. New suppressions require a comment explaining the false positive or portability limitation.
10. Generate GNATdoc output for the stable application API and verify that ownership, task-safety, defaults, error behavior, and unsupported behavior appear in the generated public docs.
11. Confirm that HTTP/3/QUIC remain experimental unless a separate production QUIC release has intentionally changed the manifest, README, docs, examples, and tests.
12. Confirm that no temporary certificate, cache directory, generated object, local binary, C test fixture, pthread-based fixture support, or private credential is included in the source archive.

The release is not ready if any documented default differs from `Http_Client.Clients.Default_Client_Configuration`, `Http_Client.Transports.TLS.Default_TLS_Options`, `Http_Client.Retry.Default_Retry_Options`, `Http_Client.Cache.Default_Cache_Config`, or `Http_Client.HTTP3.Default_HTTP3_Options`.


## Git smart HTTP release checks

Before advertising the Git smart HTTP transport contract as release-ready, also
verify the following crate-local checks:

1. Build with the Ada `zlib` dependency resolved through Alire or `GPR_PROJECT_PATH`.
2. Build `examples/examples.gpr`; this covers the Git smart HTTP binary streaming,
   fixed-length upload, chunked upload, HTTPS-over-CONNECT, and HTTPS-over-SOCKS
   example sources.
3. Run the offline AUnit suite and confirm the Git smart HTTP cases in
   `http_client-http1-tests.adb` and `http_client-response_streams-tests.adb`
   pass without live network access.
4. Confirm no `src/c/http_client_zlib_bridge.c`, direct `-lz`, or imported C zlib
   symbols are present in the source archive.
5. Run `./tools/bin/check_git_smart_http_release` and require it to pass.
6. Confirm `docs/GIT_SMART_HTTP_FINAL_AUDIT_PASS.md`,
   `docs/GIT_SMART_HTTP_FINAL_COMPLETENESS_PASS.md`,
   `docs/GIT_SMART_HTTP_RELEASE_TOOLING_PASS.md`, and
   `docs/GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md` still match the
   public `.ads` declarations before publishing the archive.

## Git smart HTTP request trailer verification

Before release, confirm the request trailer tests pass with AUnit. The relevant coverage asserts that HTTP/1.1 unknown-length uploads synthesize `Trailer`, accept explicit declarations only when they cover all attached trailer field names, reject orphan `Trailer` declarations, emit trailer fields after the terminating chunk, reject trailers on fixed-length bodies, and reject forbidden trailer names such as `Content-Length`.

### Phase 1 API inventory freeze command set

The Phase 1 freeze gate uses these exact commands through Alire:

```sh
alr build
alr exec -- gnatprove -P httpclient.gpr --level=4
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr test
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_all
./tools/bin/check_git_smart_http_release
```

## Phase 2 raw-deflate streaming decompression

High-level buffered client decompression is enabled by default. The basic low-level streaming path remains raw by default and does not add `Accept-Encoding` automatically; configured high-level client streams and file downloads propagate `Client_Configuration.Enable_Decompression` to the streaming reader. When explicitly enabled, gzip, zlib-wrapped deflate, and raw deflate through `Decompression_Options.Deflate_Mode` are supported. The default HTTP `deflate` mode is `Zlib_Wrapped_Only`; `Raw_Only` and `Auto_Zlib_Then_Raw` are explicit interoperability policies. Decoded-size limits are enforced incrementally and decoded bytes remain binary-safe for Git packet-line and packfile data.


## Phase 3 HTTP/1.1 streaming correctness

HTTP/1.1 streaming reads expose entity bytes, not transfer framing. Chunked response decoding is supported, including chunk extensions, split chunk metadata, bounded response trailers, and arbitrary binary body bytes. Unknown-length request streams use chunked upload; request trailers are restricted to HTTP/1.1 chunked uploads; `Expect: 100-continue` is explicit and withholds the body until `100 Continue`. Decompression remains opt-in. Close-delimited, malformed, incomplete, failed-upload, and decompression-failed streams are closed/discarded rather than reused. See `docs/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md`.


## Phase 4-6 TLS/proxy fixture boundary

This first release package intentionally excludes project-owned C TLS, HTTP CONNECT, and SOCKS5 test fixtures. The production OpenSSL bridge remains allowed, and the loopback TLS/proxy suites are backed by Ada task-based fixtures. Tests must not depend on `pthread` or `tests/test_fixtures.gpr`.

Release verification must confirm that no C fixture files are packaged under `tests/src`, no `-pthread` linker switch is present in `tests/tests.gpr`, and the direct TLS, HTTPS-over-CONNECT, and HTTPS-over-SOCKS5 suites are registered in `tests/src/http_suite.adb`. Full loopback end-to-end TLS/proxy fixture coverage must remain Ada task-based.

## Phase 7 connection pooling

The high-level buffered HTTP/1.1 client now has transport-attached connection reuse when `Client_Configuration.Pooling.Enabled` is true. Pooling is bounded, disabled by default, and conservative: fixed-length and fully consumed chunked responses may be reused; close-delimited, malformed, incomplete, failed-upload, timeout, proxy/TLS-failure, and explicit `Connection: close` paths discard the transport. Reuse is keyed by origin, scheme, proxy route, proxy credential identity, TLS verification/CA/SNI settings, and client-certificate identity; checked-out real handles preserve per-connection request counts. Request headers, cookies, authorization fields, SOCKS passwords, and Git headers are never sticky or logged across reused connections. See `docs/GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md`.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.

## Phase 9 HTTP/2 multiplexing verification

Before release, confirm `http_client-http2-tests.adb` covers bounded HTTP/2 multiplexing: concurrent stream limits, interleaved DATA routing, per-stream body reads, aggregate queued-body limits, RST_STREAM isolation, GOAWAY handling, flow-control accounting, upload DATA accounting, binary `Stream_Element_Array` reads, and forced HTTP/2 no-fallback policy. The release guard must include the Phase 9 document and these coverage markers.

### Phase 9 HTTP/2 multiplexing completeness pass 2

The release guard expects `Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted`, which verifies that padded/priority HEADERS metadata is excluded from HTTP/2 header-list accounting while CONTINUATION fragments remain bounded.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.


### HTTP/2 trailers

HTTP/2 trailers are trailing HEADERS, not HTTP/1.1 chunk trailers. Request trailers do not require an HTTP/1.1 Trailer declaration and never use Transfer-Encoding. Pseudo-headers plus framing, connection-specific, and sensitive names are rejected. Response body reads expose only DATA bytes; buffered responses expose validated trailer fields through `Http_Client.Responses.Trailers`, while the HTTP/2 connection model also records per-stream trailer receipt.

## Phase 11 HTTP/3 boundary verification

The release verification includes HTTP/3 boundary checks: forced HTTP/3 no-backend deterministic failure, no fallback from `Force_HTTP_3` to HTTP/2 or HTTP/1.1, proxy no-bypass behavior for HTTP and SOCKS5 proxies, preferred HTTP/3 before-send fallback policy, binary-safe HTTP/3 body-stream byte-array reads, deterministic unopened/no-backend body-stream failure, QPACK unsupported dynamic/indexed feature rejection, and local-only experimental examples. Run `./tools/bin/check_git_smart_http_release` after the AUnit suite and examples build.

## Phase 12 redirect/retry safety verification

The Git smart HTTP release gate includes the Phase 12 redirect/retry safety pass. It verifies that strict/no-transform configuration disables automatic redirects and retries, HTTPS downgrade redirects are blocked by default, cross-origin credentials and `Git-Protocol` are stripped by default when redirects are enabled, rewritten 303 POST redirects drop stale body headers such as Git `Content-Type` and `Expect: 100-continue`, non-replayable Git upload bodies are not replayed or retried, cancellation is not retried, forced protocol policies remain forced, and proxy routes remain configured across redirect/retry chains.

## Phase 13 header and binary safety verification

Phase 13 verifies that byte-array APIs are the Git-safe body APIs and that header parsing, framing metadata, and diagnostics cannot reinterpret Git pkt-line or packfile bytes as text. The AUnit suite includes `Http_Client.Binary_Safety_Tests` and `Http_Client.Binary_Test_Data` with an all-bytes corpus, NUL/high-byte preservation, CRLFCRLF body-boundary preservation, duplicate/conflicting `Content-Length` rejection, `Transfer-Encoding` plus `Content-Length` rejection, and HTTP/2 trailer/header validation coverage. Diagnostics must redact sensitive headers and must not log body bytes by default.


## Phase 14 compile-targeted Git smart HTTP examples

Before the final audit, compile the examples project and run the Git smart HTTP release guard:

```sh
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```

The examples project must include the Git discovery, upload-pack, receive-pack fixed upload,
receive-pack chunked upload, trailers, `Expect: 100-continue`, custom CA, HTTP CONNECT proxy,
SOCKS5 proxy, streaming decompression, HTTP/2 opt-in, HTTP/3 no-backend, redirect policy, retry
policy, timeout/cancellation, and binary-safe transport-shape examples documented in
`docs/EXAMPLES.md`. Automated verification must not require GitHub, GitLab, or any public remote.
