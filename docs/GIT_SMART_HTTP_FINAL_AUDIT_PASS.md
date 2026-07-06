# Git smart HTTP final release audit pass

This document records the Phase 15 final release audit for the Ada 2022
`HttpClient` crate after Phase 14. It is crate-local: no `Version.Transport.Http`
or downstream VCS adapter package is part of this repository.

## Audit scope

Phase 15 is a release-readiness audit, not a feature phase. The audit checks
build metadata, project files, public API/documentation consistency, release
verification instructions, examples, static source safety markers, packaging
shape, and Git smart HTTP regression coverage markers.

The crate remains a general HTTP/HTTPS client library. Git smart HTTP support is
provided through generic binary-safe request, response, streaming, TLS, proxy,
redirect, retry, timeout, cancellation, and protocol-selection APIs.

## Verification commands

The release verification command set for a maintainer checkout with Alire,
GNAT/GPRbuild, AUnit, OpenSSL, and the Ada `zlib` dependency available is:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr
```

In the sandbox used for this edit, `alr` and `gprbuild` were not installed, so
those commands were not executed here. The audit changes below are based on
source/project/documentation inspection and static checks. Do not publish a tag
until the command set above passes in a real Ada toolchain environment.

## Phase 15 fixes made by this audit

* Aligned stale project-file references with the actual root project file name:
  `httpclient.gpr`.
* Fixed `benchmarks/http_client_benchmarks.gpr`, which referenced the removed or
  nonexistent `../http_client.gpr` path.
* Updated documentation and CI references that still used `http_client.gpr`.
* Added the AUnit-suite registration guard to the CI release-tool sequence.
* Reworded the public `Retry-After` HTTP-date note as a deterministic limitation rather than stale future-work language.
* Declared `project-files = ["httpclient.gpr"]` in `alire.toml` so Alire resolves the intended root project explicitly.
* Converted checked-in Alire-style config files into stable fallback configuration files without host-specific metadata.
* Made the examples project import `../httpclient.gpr` explicitly instead of relying on config-project dependency side effects.
* Updated the Git smart HTTP release guard to inspect `httpclient.gpr` and to
  verify the Ada `zlib` dependency declaration used by the crate.
* Removed the local sibling-path `zlib` pin from `alire.toml`; the release
  manifest now declares `zlib` as an external Alire dependency instead of a
  checkout-local path.
* Replaced stale CI calls to missing Python helper scripts with the Ada release
  tools that are present in `tools/tools.gpr`.
* Refreshed this final audit document so it no longer states earlier-phase
  limitations that have since been completed.
* Performed a documentation-completeness pass: corrected stale absent-tool validation commands, fixed local documentation links, classified all compile-visible public packages, and added a complete examples manifest.
* Performed an Ada keyword identifier pass and renamed invalid test-local `Body` identifiers to non-reserved names. No public API names were changed.

## Capability matrix

| Area | Release-candidate status |
| --- | --- |
| Public API inventory | Frozen in `docs/GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md`; API stability project exists. |
| Binary request bodies | Git-safe path uses `Ada.Streams.Stream_Element_Array`; no text conversion is required. |
| Binary response bodies | Buffered byte-array APIs and streaming `Read_Some` preserve arbitrary bytes. |
| String convenience APIs | Documented as convenience paths, not the Git packet-line/packfile body path. |
| HTTP/1.1 fixed response streaming | Implemented and covered by tests. |
| HTTP/1.1 close-delimited streaming | Implemented; not reusable for pooling. |
| HTTP/1.1 chunked response streaming | Implemented, including split metadata/data and bounded trailers. |
| Fixed-length upload | Implemented for producer-backed request bodies. |
| Chunked upload | Implemented for unknown-length producers. |
| HTTP/1.1 request trailers | Implemented for chunked upload with explicit declaration and validation. |
| `Expect: 100-continue` | Implemented with early-final response preservation and upload suppression. |
| Streaming decompression | Opt-in gzip, zlib-wrapped deflate, raw-deflate, and explicit auto zlib-then-raw policy where enabled. |
| Ada `zlib` boundary | External Ada `Zlib` details remain isolated in `Http_Client.Zlib_Decompression`. |
| C zlib | No C zlib bridge and no direct `-lz` linkage in project files. |
| TLS direct HTTPS | Public TLS configuration and deterministic status behavior are retained; C loopback fixtures are not packaged in the first release. |
| HTTPS over CONNECT | CONNECT configuration, policy, and deterministic status behavior are retained; C proxy/TLS fixtures are not packaged in the first release. |
| HTTPS over SOCKS5 | SOCKS5 configuration, policy, deterministic status behavior, and Ada task-based loopback TLS fixture coverage are retained; C SOCKS5/TLS fixtures are not packaged in the first release. |
| Connection pooling | Conservative, bounded, security-keyed pooling with discard on dirty/failure/timeout/cancellation paths. |
| Timeout/cancellation | Deterministic statuses, documented checkpoints, no retry of cancellation, discard of affected connections. |
| HTTP/2 | Opt-in bounded multiplexing, DATA byte isolation, flow-control bounds, GOAWAY/RST handling, request/response trailers. |
| HTTP/3 | Experimental/backend-dependent boundary with deterministic no-backend behavior and no forced fallback. |
| Redirects | Disabled by default; HTTPS downgrade blocked by default; cross-origin credentials stripped. |
| Retries | Disabled by default; replayability and reset semantics enforced; non-replayable Git pushes protected. |
| Examples | Compile-targeted, offline-safe Git smart HTTP examples are listed in `docs/EXAMPLES.md`. |
| Release guard | `tools/src/check_git_smart_http_release.adb` checks major release-critical markers. |

## Explicit limitations

* HTTP/3 execution requires a production QUIC backend that is not provided by
  this crate release. Forced HTTP/3 must fail deterministically when no backend
  is available and must not silently fall back.
* HTTP/2 cleartext h2c is not implemented; forced HTTP/2 over plain `http://`
  is rejected deterministically.
* HTTP/2 server push, priority-tree behavior, and extended CONNECT are not part
  of the Git smart HTTP release scope.
* Browser-like behavior is intentionally absent. Cookies are explicit and
  non-browser-like; redirects and retries are explicit policy decisions.
* Timeout precision can depend on the target GNAT/runtime/socket platform, but
  timeout intent, deterministic statuses, and connection-discard behavior are
  documented and tested at the library boundary.
* The crate does not parse Git pkt-line, Git packfiles, Git refs, or repository
  state. That remains downstream consumer work.

## Static audit results performed in this pass

The following source-tree checks were performed by inspection and shell grep in
this sandbox:

* no packaged `src/c/http_client_zlib_bridge.c` source exists;
* no C zlib `inflateInit`, `deflateInit`, or `z_stream` symbols were found in
  `src`, `tests`, `examples`, or `tools`;
* no `Response_Body` use was found in `examples/src`;
* no `Version.Transport.Http` package exists under `src`;
* no attempted Ada discriminant assignments were found; the only discriminated task/protected types are initialized at creation;
* generated object files, `.ali` files, executables, temporary zips, local
  `alire/` state directories, and obvious scratch artifacts are absent from the
  source tree;
* every example listed in `examples/examples.gpr` exists under `examples/src`;
* every example listed in `examples/examples.gpr` is documented in the complete manifest in `docs/EXAMPLES.md`;
* every `src/*.ads` package is mentioned in the public package/stability/release-surface documentation set;
* no remaining live validation-command references to absent Python checker scripts were found in `docs/`, `README.md`, or `.github/`;
* the API stability project, tests project, examples project, tools project,
  and benchmark project now reference the actual `httpclient.gpr` root project
  where applicable.

Documentation may mention the removed C
zlib bridge and direct `-lz` only as audit statements confirming their absence.

## Supported Git smart HTTP example set

The release guard and examples project cover these compile-targeted Git smart
HTTP examples:

* `git_info_refs_stream.adb`
* `git_upload_pack_stream.adb`
* `git_receive_pack_fixed_upload.adb`
* `git_receive_pack_chunked_upload.adb`
* `git_receive_pack_chunked_upload_trailers.adb`
* `git_info_refs_https_proxy_stream.adb`
* `git_info_refs_https_socks_stream.adb`
* `git_info_refs_http2_buffered.adb`
* `git_info_refs_http3_buffered.adb`
* `git_upload_pack_http2_stream.adb`
* `git_info_refs_http3_stream.adb`
* `http3_force_no_backend.adb`
* `http3_prefer_with_fallback.adb`
* `git_info_refs_streaming_get.adb`
* `git_upload_pack_post_buffered.adb`
* `git_chunked_upload_with_trailers.adb`
* `git_receive_pack_expect_continue.adb`
* `git_https_custom_ca.adb`
* `git_https_proxy_connect.adb`
* `git_socks5_https.adb`
* `git_streaming_decompression.adb`
* `git_http2_streaming_fetch_shape.adb`
* `git_redirect_policy.adb`
* `git_retry_policy.adb`
* `git_streaming_with_timeout_and_cancellation.adb`
* `git_binary_safe_transport_shape.adb`

All Git body examples are required to use byte-array/body-producer APIs rather
than the string `Response_Body` path.

## Release decision

This tree is a Phase 15 release source package after the static audit
fixes above. Final publication still requires a real-toolchain verification run
of the commands listed at the top of this document. If those commands pass, the
crate is suitable to tag as a release and to consume as a stable
`HttpClient` dependency from an external Git smart HTTP implementation.

## AUnit wrapper cleanup follow-up

A follow-up test-suite readability pass removed trivial delegate-only AUnit wrappers.
Registered tests now point directly at the real `Test_*` routine where no wrapper behavior is required.
The only remaining `AUnit_Test_*` wrappers are fixture-boundary wrappers that provide cleanup behavior before re-raising failures.
See `docs/AUNIT_TEST_WRAPPER_AUDIT.md`.


## Main-code delegation follow-up

A follow-up production-source audit looked for pointless delegation patterns analogous to the removed AUnit wrappers. No actionable production-code wrappers were removed. The small forwarding/accessor subprograms in `src/` are retained because they preserve public API convenience, private representation boundaries, semantic origin/proxy naming, protected-state encapsulation, or cleanup intent. See `docs/MAIN_CODE_DELEGATION_AUDIT.md`.

## GNATdoc `@param` / `@return` follow-up

A follow-up documentation pass audited every `.ads` file in the release tree for GNATdoc-style subprogram comments. All 634 parsed subprogram specifications now have adjacent `@param` entries for all formal parameters and `@return` entries for functions. The pass was documentation-only and did not change public signatures or runtime behavior. See `docs/GNATDOC_PARAM_RETURN_AUDIT.md`.

## Examples release-audit follow-up

A follow-up examples audit checked all 56 `examples/examples.gpr` executable mains against `examples/src` and `docs/EXAMPLES.md`. The release guard now verifies the complete compile-checked example manifest, not only the Git smart HTTP subset. Static checks found no missing example mains, no undocumented compile-checked example, removed an obsolete unlisted `examples.adb` file that was not part of the examples project, no `Response_Body` use in examples, no positive HTTPS example disabling certificate verification, no downstream `Version.Transport.Http` adapter code, and no C zlib bridge or direct `-lz` marker in examples. See `docs/EXAMPLES_RELEASE_AUDIT.md`.
## Incomplete-content audit follow-up

A follow-up release-source pass searched for unfinished-scaffolding markers across source, tests, examples, tools, fixtures, project files, and docs. It reworded QUIC/HTTP3 boundary text, replaced security-corpus category marker files with deterministic non-secret sample entries, renamed marker-shaped local production naming, and corrected the HTTP/2 guide's stale trailer statement. The final marker scan reported zero hits for the configured release-blocker marker family and zero empty files. See `docs/INCOMPLETE_CONTENT_AUDIT.md`.

