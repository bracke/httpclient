# Documentation index

This directory is part of the 1.0 release stabilization surface. Documents here describe current behavior and limits; they are not speculative roadmaps.

## Start here

- `QUICKSTART.md` — shortest build/test path, first GET, manual request construction, and first optional configuration steps.
- `API_STABILITY.md` — stable, low-level, experimental, and implementation-detail package boundaries.
- `PUBLIC_PACKAGES.md` — concise package classification table for application authors.
- `CONFIGURATION.md` — default behavior and how options compose.
- `SECURITY_MODEL.md` — security posture, redaction rules, and explicit non-goals.
- `security.md` — threat model, deterministic fuzzing strategy, and manual security checklist.
- `AI_USAGE_GUIDE.md` and `../llms.txt` — AI-facing repository map, recommended imports, validation commands, and non-goals.

## Feature guidance

- `STATUS_MODEL.md` — result-status categories, exception policy, and program-control guidance.
- `THREADING_AND_OWNERSHIP.md` — ownership, close/finalization, and task-safety rules.
- `HEADERS_AND_PROTOCOL_SEMANTICS.md` — header validation, duplicate policy, and protocol-specific restrictions.
- `TIMEOUTS_AND_LIMITS.md` — bounded resource and timeout expectations.
- `DOWNLOAD_TO_FILE.md` — download-to-file convenience API, response metadata, file safety, and Max_Download_Size semantics.
- `DEFAULT_LIMITS.md` — concrete release default values and limits.
- `HTTP2_GUIDE.md` — HTTP/2 configuration and limitations.
- `HTTP3_EXPERIMENTAL.md` — HTTP/3 and QUIC foundation boundary.
- `PROTOCOL_DISCOVERY.md` — explicit Alt-Svc and HTTPS/SVCB discovery policy, security boundaries, resolver limits, and cache ownership.
- `EXAMPLES.md` — examples project and compile-oriented API coverage.
- `TESTING.md` — offline, local extended, live external, and manual interoperability tiers.
- `INTEROPERABILITY_MATRIX.md` — feature coverage matrix across deterministic and optional tiers.
- `SECURITY_REVIEW.md` — security-focused release checklist.
- `INTEROPERABILITY_SECURITY_REVIEW.md` — security checklist for the optional live interoperability runner.
- `STABLE_API_CONTRACT.md` — compact list of stable public package, type, status, option, and representative subprogram commitments.
- `GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md` — exact public API surface and ownership rules for Ada Git smart HTTP consumers.
- `GIT_SMART_HTTP_INTEGRATION_CONTRACT.md` — tested Git-style transport behavior and recommended caller configuration.
- [Git smart HTTP Phase 1 completeness pass](GIT_SMART_HTTP_PHASE1_COMPLETENESS_PASS.md)
- `GIT_SMART_HTTP_CHUNKED_REQUEST_UPLOAD_PASS.md` — implementation note for explicit unknown-length HTTP/1.1 chunked request upload.
- `GIT_SMART_HTTP_CHUNKED_UPLOAD_COMPLETENESS_PASS.md` — completeness pass for chunked upload validation and remaining limits.

## Release control

- `RELEASE_CHECKLIST.md` — final checks before a 1.0-style tag.
- `RELEASE_SURFACE_MANIFEST.md` — package-by-package compatibility classification.
- `RELEASE_VERIFICATION.md` — final build, test, documentation, and archive verification procedure.
- `API_AUDIT_REPORT.md` — audit summary of public namespace, internal boundaries, result model, and remaining checks.
- `RELEASE_NOTES_1_0_0.md` — factual notes for the 1.0.0 release.
- `POST_RELEASE_BASELINE.md` — post-release compatibility and next-base marker.
- `PHASE16_RELEASE_PACKAGING_PASS.md` — release packaging and sandbox verification note.
- `PHASE16_COMPLETENESS_PASS.md` — follow-up release-packaging completeness audit.
- `PHASE16_TEST_FIXTURE_LINKAGE_PASS.md` — test fixture static-library linkage fix for the packaged AUnit project.
- `NEXT_DEVELOPMENT_PLAN.md` — short pointer for work after the release branch is frozen.
- `PACKAGING_VALIDATION.md` — source-package content and dependency validation.
- `PHASE15_STATIC_AUDIT_SUMMARY.md` — static audit summary for the Phase 15 release.
- `DOCUMENTATION_COMPLETENESS_PASS.md` — documentation-only completeness pass for the Phase 15 candidate.
- `ADA_KEYWORD_IDENTIFIER_AUDIT.md` — Phase 15 audit for Ada reserved words accidentally used as identifiers.
- `MAIN_CODE_DELEGATION_AUDIT.md` — Phase 15 audit for production-code delegation/accessor patterns after AUnit wrapper cleanup.

- `RESOURCE_USAGE.md` — resource ownership, bounds, cleanup, counters, and performance-hardening expectations.
- `BENCHMARKS.md` — Optional non-gating benchmark smoke executable usage.
- `security.md` — security review and fuzzing campaign details.

## Lowercase topic entry points

- `api-overview.md` — stable, experimental, internal API, and response metadata summary.
- `configuration.md` — caller-owned configuration model and conflicts.
- `security.md` — primary security model and fuzzing guidance.
- `testing.md` — Tier 1 through Tier 5 testing model.
- `proxies.md` — explicit HTTP/SOCKS proxy behavior and non-goals.
- `caching.md` — cache ownership, sensitivity, and file-format support.
- `streaming-and-uploads.md` — response stream and request-body ownership.
- `decompression.md` — gzip/zlib content-encoding adapter contract.
- `http2.md` — HTTP/2 release behavior.
- `http3.md` — experimental HTTP/3 and QUIC behavior.
- `diagnostics.md` — structured diagnostics and redaction.
- `async.md` — explicit bounded async/task integration.
- `release-policy.md` — versioning and release policy.
- `compatibility.md` — breaking-change and deprecation rules.

- `docs/COVERAGE.md` — AUnit suite structure and 100% release coverage gate.
- [AUnit suite](AUNIT_SUITE.md): default offline AUnit suite structure, required behavior areas, and suite integrity checks.

* `GIT_SMART_HTTP_EXPECT_100_CONTINUE_PASS.md` — explicit HTTP/1.1 Expect: 100-continue upload behavior.

- [Git smart HTTP Expect: 100-continue completeness pass](GIT_SMART_HTTP_EXPECT_100_COMPLETENESS_PASS.md)

- `GIT_SMART_HTTP_EXPECT_100_SECOND_COMPLETENESS_PASS.md` — second completeness pass for `Expect: 100-continue`; its fixed-length-only limitation is superseded by `GIT_SMART_HTTP_EXPECT_100_LIMITATION_FIX_PASS.md`.
- `GIT_SMART_HTTP_EXPECT_100_LIMITATION_FIX_PASS.md` — removes the buffered early-final chunked-response limitation for `Expect: 100-continue`.
- `GIT_SMART_HTTP_EXPECT_100_FINAL_COMPLETENESS_PASS.md` — final completeness pass covering streaming early-final chunked `Expect: 100-continue` responses.

- `GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_PASS.md` — documents the HTTPS-over-HTTP-proxy CONNECT streaming implementation pass.
- `GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_COMPLETENESS_PASS.md` — completeness pass for HTTPS-over-HTTP-proxy CONNECT streaming routing and coverage.

* [`GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md`](GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md) — HTTPS-over-SOCKS5 support for Git smart HTTP streaming and buffered HTTP/1.1 paths.
* [`GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_COMPLETENESS_PASS.md`](GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_COMPLETENESS_PASS.md) — completeness pass for HTTPS-over-SOCKS5 documentation, routing, and remaining limitations.

* [Git smart HTTP streaming decompression pass](GIT_SMART_HTTP_STREAMING_DECOMPRESSION_PASS.md)
- [Git smart HTTP streaming raw-deflate pass](GIT_SMART_HTTP_STREAMING_RAW_DEFLATE_PASS.md)

- [GIT_SMART_HTTP_ADA_ZLIB_DECOMPRESSION_PASS.md](GIT_SMART_HTTP_ADA_ZLIB_DECOMPRESSION_PASS.md) - removal of C zlib bridge and migration to the Ada Zlib dependency.
- [GIT_SMART_HTTP_ADA_ZLIB_DECOMPRESSION_COMPLETENESS_PASS.md](GIT_SMART_HTTP_ADA_ZLIB_DECOMPRESSION_COMPLETENESS_PASS.md) - completeness pass for Ada Zlib-backed streaming gzip/deflate coverage and no-C-zlib validation.

- [Git smart HTTP CONNECT tunnel fixture pass](GIT_SMART_HTTP_CONNECT_TUNNEL_FIXTURE_PASS.md)
- [Git smart HTTP SOCKS tunnel fixture completeness pass](GIT_SMART_HTTP_SOCKS_TUNNEL_FIXTURE_COMPLETENESS_PASS.md)

- `GIT_SMART_HTTP_HTTP1_PROTOCOL_POLICY_PASS.md` — explicit HTTP/1.1 protocol guard for Git smart HTTP.

- [Git Smart HTTP HTTP/1.1 Protocol Policy Completeness Pass](GIT_SMART_HTTP_HTTP1_PROTOCOL_POLICY_COMPLETENESS_PASS.md)

- [Git smart HTTP final HttpClient audit pass](GIT_SMART_HTTP_FINAL_AUDIT_PASS.md)
- [Git smart HTTP final completeness pass](GIT_SMART_HTTP_FINAL_COMPLETENESS_PASS.md)
- [Git smart HTTP release tooling pass](GIT_SMART_HTTP_RELEASE_TOOLING_PASS.md)
- [Git smart HTTP release tooling completeness pass](GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md)

* [Git smart HTTP HTTP/2 and HTTP/3 pass](GIT_SMART_HTTP_HTTP2_HTTP3_PASS.md)

- [Git Smart HTTP HTTP/2 / HTTP/3 Completeness Pass](GIT_SMART_HTTP_HTTP2_HTTP3_COMPLETENESS_PASS.md)
- [Git Smart HTTP HTTP/2 Byte-Array Streaming Pass](GIT_SMART_HTTP_HTTP2_STREAM_BYTE_ARRAY_PASS.md)

- [Git smart HTTP request trailers pass](GIT_SMART_HTTP_REQUEST_TRAILERS_PASS.md)
- [Git smart HTTP request trailers completeness pass](GIT_SMART_HTTP_REQUEST_TRAILERS_COMPLETENESS_PASS.md)

- [Git smart HTTP HTTP/2/HTTP/3 streaming parity pass](GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_PASS.md)
- [Git smart HTTP HTTP/2/HTTP/3 streaming parity completeness pass](GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_COMPLETENESS_PASS.md)



- [Git smart HTTP Phase 3 streaming correctness pass](GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md)
- [Git smart HTTP Phase 4 direct TLS fixture pass](GIT_SMART_HTTP_PHASE4_DIRECT_TLS_FIXTURE_PASS.md)
- [Git smart HTTP Phase 5 HTTP CONNECT TLS fixture pass](GIT_SMART_HTTP_PHASE5_HTTP_CONNECT_TLS_FIXTURE_PASS.md)
- [Git smart HTTP Phase 5 HTTP CONNECT TLS fixture completeness pass](GIT_SMART_HTTP_PHASE5_HTTP_CONNECT_TLS_FIXTURE_COMPLETENESS_PASS.md)
- [Git smart HTTP Phase 6 HTTPS SOCKS5 TLS fixture pass](GIT_SMART_HTTP_PHASE6_HTTPS_SOCKS5_TLS_FIXTURE_PASS.md)
- [Git smart HTTP Phase 9 HTTP/2 multiplexing pass](GIT_SMART_HTTP_PHASE9_HTTP2_MULTIPLEXING_PASS.md)
- [Git smart HTTP Phase 10 HTTP/2 trailers pass](GIT_SMART_HTTP_PHASE10_HTTP2_TRAILERS_PASS.md)
- [Git Smart HTTP Phase 11 HTTP/3 Boundary Hardening Pass](GIT_SMART_HTTP_PHASE11_HTTP3_BOUNDARY_PASS.md)

- [GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md](GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md)


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.

- [Git smart HTTP Phase 12 redirect/retry safety pass](GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md)

- [Git smart HTTP Phase 13 header and binary safety pass](GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md)
- [Git smart HTTP Phase 14 compile-targeted examples pass](GIT_SMART_HTTP_PHASE14_COMPILE_TARGETED_EXAMPLES_PASS.md)

- [Git smart HTTP early completeness pass](GIT_SMART_HTTP_COMPLETENESS_PASS.md)
- [Ada discriminant mutation audit](ADA_DISCRIMINANT_MUTATION_AUDIT.md)
- [AUnit test wrapper audit](AUNIT_TEST_WRAPPER_AUDIT.md)
- [GNATdoc `@param` / `@return` audit](GNATDOC_PARAM_RETURN_AUDIT.md)
- [Examples release audit](EXAMPLES_RELEASE_AUDIT.md)
- [Incomplete-content audit](INCOMPLETE_CONTENT_AUDIT.md)


- [Phase 16 Ada-only test fixture baseline](PHASE16_ADA_ONLY_TEST_FIXTURE_BASELINE.md)

* [`PHASE16_ADA_TASK_FIXTURE_RESTORATION_PASS.md`](PHASE16_ADA_TASK_FIXTURE_RESTORATION_PASS.md) — restoration of TLS/CONNECT/SOCKS loopback coverage through Ada task-based fixtures.

- `PHASE16_ADA_TASK_FIXTURE_COMPLETENESS_PASS.md` — final Ada task fixture completeness pass for restored loopback TLS/proxy coverage.

- [Phase 16 SOCKS5 exact handshake fixture fix](PHASE16_SOCKS5_EXACT_HANDSHAKE_FIX_PASS.md)

- [Phase 16 SOCKS5 CA Path and Negative Failure Pass](PHASE16_SOCKS5_CA_PATH_AND_NEGATIVE_FAILURE_PASS.md)

- `PHASE16_CLIENT_ERGONOMIC_DEFAULTS_DOCS_PASS.md` — documentation and example updates for safe redirect/decompression defaults, strict configuration, `Response_Text`, `Final_URL`, and one-shot `Get`.

- IPv6 literal URLs — supported in bracketed authority form; zone identifiers unsupported; h2c unsupported. See README, QUICKSTART, CONFIGURATION, security model, API overview, examples, release notes, and stable API contract.

- [Phase 17 IPv6 Literal Completeness Pass](PHASE17_IPV6_LITERAL_COMPLETENESS_PASS.md)

- `SPARK.md` — SPARK-enabled units and the GNATprove release command.
