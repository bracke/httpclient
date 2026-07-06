# Packaging validation checklist

Packaging validation proves that the release source tree can be consumed as an ordinary Ada/Alire dependency. It is not a feature-development phase.

## Required release checks

1. Start from a clean checkout or release archive.
2. Confirm `alire.toml` resolves without local absolute paths or private pins.
3. Build the library with `alr build` or, when dependency project paths are already configured, `alr exec -- gprbuild -P httpclient.gpr`.
4. Build the default test executable with `cd tests && alr exec -- gprbuild -P tests.gpr`.
5. Run `cd tests && ./bin/tests`; it must remain deterministic and offline.
6. Build examples with `alr exec -- gprbuild -P examples/examples.gpr`.
7. Build API-stability compile tests with `alr exec -- gprbuild -P tests/api_stability/api_stability.gpr`.
8. Build maintainer tools with `alr exec -- gprbuild -P tools/tools.gpr`.
9. Run `./tools/bin/check_release_surface`.
10. Run `./tools/bin/check_aunit_suite`.
11. Run `./tools/bin/check_security_corpus`.
12. Run `./tools/bin/check_git_smart_http_release`.
13. Build the optional benchmark smoke project with `alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr` when benchmarks are shipped in the release archive.
14. Build both debug/development and release/optimized profiles when supported by the local toolchain.
15. Verify optional interop tests skip cleanly unless explicitly enabled.
16. Verify optional HTTP/3/QUIC backend tests skip or report deterministic backend-unavailable statuses when no backend is configured.
17. Inspect generated CI artifacts and logs for no secrets, no private keys beyond test fixtures, and no unredacted diagnostics.

## Package contents that should be included

- Source files under `src/`.
- C bridge source files required by the project.
- `httpclient.gpr`.
- `alire.toml`.
- `LICENSE`.
- `README.md`.
- Public documentation under `docs/`.
- Examples under `examples/`.
- Deterministic tests, fixtures, and API-stability compile tests when the package intentionally ships tests.
- Maintainer tools that do not require network access for ordinary validation.

## Package contents that should be excluded

- Object files, library outputs, executables, coverage files, build caches, temporary directories, benchmark output, fuzz crash artifacts, downloaded dependencies, editor metadata not deliberately tracked, private keys, live-test credentials, local interop configuration files, host CA stores, user-specific paths, and generated archives.

Test private keys and certificates are permitted only when clearly marked as fixtures and unsuitable for production. Live endpoint credentials must never be packaged.

## Dependency behavior

OpenSSL is a runtime/link dependency. Compression/decompression uses the Ada `zlib` project dependency; HttpClient does not link directly against `-lz`. The development checkout currently uses a workspace pin to the sibling Ada zlib project. A release manifest must remove that pin and resolve to a published crate that provides `zlib.gpr`; resolving to the system C `zlib` package is not sufficient. If a platform cannot discover these libraries through Alire or system package configuration, the failure should be clear and documented. Optional QUIC backend dependencies must be explicit and must not break HTTP/1.1 or HTTP/2 users when HTTP/3 execution is not enabled.

AUnit is a test-only dependency for `tests/tests.gpr`. Runtime library users should not be forced to depend on AUnit merely by depending on `httpclient.gpr`. CI or maintainer environments that run the default AUnit executable must install or resolve AUnit explicitly.

## Downstream consumption check

A downstream check should create a separate project, depend on `httpclient` as a normal crate, import stable public packages, build a small executable, and avoid test-only package imports. This catches missing project exports, incorrect library names, hidden local paths, and dependency leakage.

## Example constraints

Examples must compile on supported platforms where practical. No example should require real credentials, live proxies, live SOCKS endpoints, live HTTP/3 endpoints, private CA material, or user-specific filesystem paths. Manual examples that need local fixtures must say so explicitly.

## Clean-room constraints

Validation must not require public internet, live DNS WPAD, public HTTPS/SVCB records, live proxies, live SOCKS servers, live HTTP/3 endpoints, private credentials, browser profiles, OS credential stores, password managers, or local absolute paths.


## Maintainer validation tools

The release archive currently ships Ada maintainer tools under `tools/src/` and builds them with `tools/tools.gpr`. The shipped executables are:

- `check_release_surface` — validates release-surface, project-file, documentation-marker, and no-C-zlib invariants.
- `check_aunit_suite` — validates that the deterministic AUnit suite keeps the expected registration and coverage markers.
- `check_security_corpus` — validates security corpus and redaction-marker expectations.
- `check_git_smart_http_release` — validates Git smart HTTP release-critical documentation, examples, source markers, and no prohibited zlib/version-adapter markers.

Earlier planning notes referred to Python packaging validators. Those tools are not part of this release archive. Do not list them as required release commands unless they are actually restored to `tools/` and wired into CI.

## Installation documentation

`docs/INSTALLATION.md` is the user-facing dependency and troubleshooting note for platform/package validation. It must stay aligned with `PLATFORM_SUPPORT.md`, `CI_MATRIX.md`, `alire.toml`, and `httpclient.gpr`. In particular, it must identify OpenSSL as a runtime/link dependency and Ada `zlib` as a project dependency, AUnit as test-only, OpenSSL 3.x as the primary validation target, and QUIC/HTTP/3 execution as optional unless a production backend is explicitly configured.


## AI-consumption validation

`../llms.txt`, `docs/AI_USAGE_GUIDE.md`, `../AGENTS.md`, this checklist, the README, documentation index, public package map, examples documentation, Alire manifest, GPR project, and validation command references form the AI-consumption surface. In this release archive that surface is reviewed manually and by the shipped Ada release guards; no separate Python AI-consumption validator is shipped.
