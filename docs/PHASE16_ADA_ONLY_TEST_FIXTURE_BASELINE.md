# Phase 16 Ada-only test fixture baseline

This first release package does not include project-owned C test fixtures and does not link pthread-based fixture support.

The production OpenSSL bridge remains intentionally present and allowed:

- `src/c/http_client_tls_bridge.c`
- `src/c/http_client_crypto_bridge.c`

Loopback TLS, HTTPS-over-CONNECT, and HTTPS-over-SOCKS5 release coverage is restored through Ada task-based fixtures in:

- `tests/src/http_client-ada_test_fixtures.ads`
- `tests/src/http_client-ada_test_fixtures.adb`

The Ada fixture package owns local server/proxy tasks and exposes ordinary Ada fixture-control subprograms consumed directly by the AUnit suites. This preserves the established direct TLS, CONNECT tunnel, and SOCKS5 tunnel tests without reintroducing C fixture files, C fixture ABI glue, or pthread linkage.

The release package must continue to exclude:

- `tests/src/http_client_tls_fixture.c`
- `tests/src/http_client_connect_proxy_fixture.c`
- `tests/src/http_client_socks5_proxy_fixture.c`
- `tests/test_fixtures.gpr`
- `-pthread` in test project files

The release package must continue to include the public test TLS fixture certificates and keys under `tests/fixtures/tls/`. They are test-only public fixtures and are required by the Ada loopback TLS server tests.
