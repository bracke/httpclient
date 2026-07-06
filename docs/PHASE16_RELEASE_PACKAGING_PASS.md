# Phase 16 release packaging pass

Date: 2026-05-17

This pass packages the Phase 15 audited tree as the `httpclient` 1.0.0 release baseline. It is a release-engineering pass only; no protocol feature or public execution behavior is added.

## Metadata updates

- `alire.toml` now declares version `1.0.0`.
- `Http_Client.Version` now returns `1.0.0`.
- The release-surface checker and release-core test expectation were updated to the same version.
- Current-facing README and release control documentation now describe the final 1.0.0 release instead of the 1.0.0 release state.
- `docs/RELEASE_NOTES_1_0_0.md`, `docs/POST_RELEASE_BASELINE.md`, and `docs/NEXT_DEVELOPMENT_PLAN.md` were added.

## Package cleanliness checks

The source package was checked for generated object/build artifacts and stale release-blocking markers. The package contains no `.o`, `.ali`, `obj`, `bin`, temporary archive, coverage, local Alire cache, or editor scratch artifacts.

Static package checks also found no actual `src/c/http_client_zlib_bridge.c`, no direct `-lz` in project/code files, and no `Version.Transport.Http` source package or example. References to those names in audit documents and release-guard scanners are intentionally retained as absence checks.


## Artifact verification performed in this sandbox

The sandbox did not provide `alr` or `gprbuild`, so the Ada build, AUnit, API-stability, examples, tools, benchmark, and release-guard commands still need to be run by the maintainer on a configured Ada toolchain before publishing.

The following checks were performed from the clean unpacked source archive:

- required source, docs, tests, examples, tools, benchmark, manifest, project, and license files are present;
- generated build artifacts and local archives are absent;
- code/project files do not contain direct `-lz` linkage or the removed C zlib bridge;
- code/project/example/test files do not contain a downstream `Version.Transport.Http` adapter;
- `alire.toml`, `Http_Client.Version`, release-surface tooling, and release-core tests agree on `1.0.0`;
- Production C bridge files are limited to the approved OpenSSL bridge; no C test fixtures are packaged.

## Maintainer commands still required before publication

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

## Tag readiness

Suggested tag: `v1.0.0`

Do not claim that the tag was pushed unless the maintainer actually creates and pushes it. After any release-blocking fix, rebuild the source package and rerun the full verification command set.
