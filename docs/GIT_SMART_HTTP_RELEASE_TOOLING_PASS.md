# Git smart HTTP release tooling pass

This pass adds a crate-local release verification tool for the Git smart HTTP
surface. The tool is intentionally offline and does not contact public Git
servers.

## Added tool

`tools/src/check_git_smart_http_release.adb` verifies the release archive shape
that matters for the Git smart HTTP transport contract:

* required Git smart HTTP documents exist and are linked from
  `docs/DOCUMENTATION_INDEX.md`;
* all Git smart HTTP examples exist and are included in `examples/examples.gpr`;
* the README and examples documentation mention every Git smart HTTP example;
* the public source surface still exposes the HTTP/1.1 protocol policy,
  response streaming decompression option, CONNECT/SOCKS TLS tunnel entry
  points, `Transfer-Encoding` handling, and explicit `Expect: 100-continue`
  support;
* the offline AUnit sources still contain coverage markers for chunked Git-like
  pkt-line streaming, chunked transfer decoding, `Expect: 100-continue`,
  HTTPS-over-CONNECT, HTTPS-over-SOCKS, streaming decompression, and forced
  HTTP/1.1 execution;
* the crate still depends on the Ada `Zlib` project instead of a packaged C
  zlib bridge;
* production sources, tests, examples, and project files do not reintroduce
  direct `-lz` linkage or imported C zlib streaming symbols.

## Scope

This tool is not a replacement for `alr build`, example compilation, or the
AUnit executable. It is a fast release-shape guard that catches stale docs,
missing examples, accidental removal of key Git smart HTTP APIs, and accidental
reintroduction of the C zlib bridge.

## Usage

Build and run it with the existing tools project:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```

The release verification procedure now includes this tool alongside
`check_release_surface`, `check_aunit_suite`, and `check_security_corpus`.

## Completeness follow-up

`docs/GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md` records the follow-up completeness pass that made the release tooling document itself part of the required Git smart HTTP release document set.
