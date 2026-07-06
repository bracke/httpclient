# CI matrix

The CI matrix is split into required deterministic jobs and optional maintainer jobs. Dependency installation notes and linker troubleshooting live in `INSTALLATION.md`.

## Required jobs

| Job | Platform | Purpose |
| --- | --- | --- |
| library-build-debug | primary Linux | Build the library with assertions/runtime checks enabled. |
| library-build-release | primary Linux | Build the library with optimized release switches where the toolchain supports them. |
| default-offline-tests | primary Linux | Build and run the deterministic AUnit suite without public network access. |
| examples-compile | primary Linux | Compile all examples as API-use smoke tests. |
| api-stability-compile | primary Linux | Compile stable public API coverage. |
| docs-and-release-surface | primary Linux | Build and run the shipped Ada release-surface, AUnit-suite, security-corpus, and Git smart HTTP release guards. |
| package-downstream | primary Linux | Build a fresh downstream project that depends on the crate when Alire/package-index validation is available. |


The required shipped release tools are Ada executables built by `tools/tools.gpr`:

- `./tools/bin/check_release_surface` validates release-surface and packaging markers.
- `./tools/bin/check_aunit_suite` validates deterministic AUnit suite registration markers.
- `./tools/bin/check_security_corpus` validates security/redaction corpus markers.
- `./tools/bin/check_git_smart_http_release` validates Git smart HTTP release-critical markers, docs, examples, and prohibited-pattern checks.

Do not reference Python validation scripts in CI unless those scripts are actually present in `tools/` and are part of the release archive.

## Best-effort jobs

| Job | Platform | Purpose |
| --- | --- | --- |
| macos-build | macOS arm64 or x86_64 | Validate OpenSSL discovery and Ada `zlib` project resolution and example compilation. |
| windows-build | Windows x86_64 | Validate DLL/import-library discovery, path handling, and default tests where stable. |
| linux-aarch64-build | Linux aarch64 | Validate non-x86_64 assumptions where runner capacity exists. |

## Optional maintainer jobs

| Job | Trigger | Purpose |
| --- | --- | --- |
| optional-interop | Manual / release | Run optional live interoperability endpoints only when explicitly configured. |
| optional-http3-backend | Manual / backend branch | Build and run QUIC-backed HTTP/3 execution tests with an explicitly selected backend. |
| optional-fuzz-long | Manual / scheduled | Run longer fuzz campaigns from deterministic seeds. |
| optional-benchmark-smoke | Manual / scheduled | Run non-gating benchmark smoke checks and resource trends. |

## CI hygiene

CI logs and artifacts must not contain private credentials, live endpoint secrets, proxy credentials, client-certificate private keys beyond clearly test-only fixtures, encrypted-cache keys, raw cookies, Authorization headers, or unredacted diagnostics. Optional jobs must skip cleanly when their explicit environment variables are absent.
