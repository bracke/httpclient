# Phase 16 Ada Task Fixture Completeness Pass

This pass tightens the first-release test fixture policy after restoring loopback TLS, HTTPS-over-CONNECT, and HTTPS-over-SOCKS5 coverage.

## Result

The package keeps the approved production OpenSSL bridge under `src/c`, but test fixture control is now Ada-to-Ada:

- `tests/src/http_client-ada_test_fixtures.ads` exposes ordinary Ada fixture-control subprograms.
- `tests/src/http_client-ada_test_fixtures.adb` implements local TLS, CONNECT proxy, and SOCKS5 proxy fixtures using Ada tasks and `GNAT.Sockets`.
- `Http_Client.TLS.Tests`, `Http_Client.Connect_TLS_Tests`, and `Http_Client.SOCKS5_TLS_Tests` call those Ada fixture APIs directly.

## Removed hazards

The release package does not include:

- C TLS/CONNECT/SOCKS test fixture source files;
- a `tests/test_fixtures.gpr` C fixture project;
- pthread-based test support;
- C fixture symbol imports such as `hctls_*`, `hcp_*`, or `hcs5_*` in the AUnit suites;
- Ada fixture exports that recreate the old C fixture ABI.

## Release guard

The release guard now checks that:

- C fixture files are absent;
- `tests/tests.gpr` does not use `-pthread`;
- the Ada fixture package exposes direct Ada fixture-control APIs;
- the direct TLS, CONNECT TLS, and SOCKS5 TLS suites remain registered;
- the restored fixture implementation uses Ada task types for the local origin/proxy servers.

## Verification status

Static package checks passed in the packaging environment. Full `alr`, `gprbuild`, and AUnit execution still require a local Ada toolchain.
