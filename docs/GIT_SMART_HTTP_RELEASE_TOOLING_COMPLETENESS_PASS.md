# Git smart HTTP release tooling completeness pass

This pass tightens the crate-local release guard added for the Git smart HTTP
transport surface. It does not add runtime behavior.

## Scope

The pass verifies that the offline release tool remains aligned with the current
HttpClient-only Git smart HTTP completion scope:

* required Git smart HTTP release documents must exist and be linked from
  `docs/DOCUMENTATION_INDEX.md`;
* all Git smart HTTP example programs must exist, be listed in
  `examples/examples.gpr`, and be mentioned in the README and examples guide;
* source markers must still cover HTTP/1.1 forcing, response streaming
  decompression, HTTPS-over-CONNECT, HTTPS-over-SOCKS, chunked transfer
  handling, and `Expect: 100-continue`;
* AUnit source markers must still cover Git-like chunked streaming, `Expect`,
  CONNECT, SOCKS, decompression, and forced HTTP/1.1 behavior;
* the Ada `Zlib` dependency must remain the decompression dependency;
* the old C zlib bridge, direct `-lz` linkage, and imported C zlib streaming
  symbols must not be reintroduced.

## Tool update

`tools/src/check_git_smart_http_release.adb` now treats
`GIT_SMART_HTTP_RELEASE_TOOLING_PASS.md` and this completeness document as
required Git smart HTTP release documents. The tool therefore catches stale
documentation-index updates when release verification itself changes.

## Non-goals

This tool is still not a compiler, AUnit runner, TLS fixture, proxy fixture, or
network test. The release gate must still run `alr build`, build the examples,
build `tools/tools.gpr`, run the AUnit executable, and then run
`./tools/bin/check_git_smart_http_release`.

## Status

The HttpClient crate-local scope remains separate from downstream consumers.
`Version.Transport.Http` is not a deliverable of this crate.
