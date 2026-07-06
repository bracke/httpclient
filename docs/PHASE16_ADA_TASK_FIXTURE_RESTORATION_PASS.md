# Phase 16 Ada task fixture restoration pass

This pass restores the direct TLS, HTTPS-over-HTTP-CONNECT, and HTTPS-over-SOCKS5 loopback test coverage that had previously depended on project-owned C fixture files.

The restored fixture implementation is Ada-only:

- `tests/src/http_client-ada_test_fixtures.ads`
- `tests/src/http_client-ada_test_fixtures.adb`

The Ada fixture package owns local Ada server/proxy tasks for:

- a loopback TLS origin;
- a loopback HTTP CONNECT proxy;
- a loopback SOCKS5 proxy.

The package exposes ordinary Ada fixture-control subprograms used directly by the AUnit suites so the coverage is restored without C fixture source, C fixture ABI glue, or a separate fixture library project. The test project remains Ada-only apart from the already-approved production OpenSSL bridge in `src/c`.

Restored AUnit suites:

- `Http_Client.TLS.Tests`
- `Http_Client.Connect_TLS_Tests`
- `Http_Client.SOCKS5_TLS_Tests`

Packaging policy after this pass:

- keep `src/c/http_client_tls_bridge.c` and `src/c/http_client_crypto_bridge.c` as the allowed production OpenSSL bridge;
- do not package C test fixtures;
- do not add a `tests/test_fixtures.gpr` C fixture library;
- do not add POSIX-thread linker switches to the test project;
- keep test TLS certificates and keys under `tests/fixtures/tls/` because they are public test fixtures required by the Ada loopback TLS tests.

The sandbox used for this packaging pass does not provide `alr`, `gprbuild`, or GNAT. The restored fixture files therefore require maintainer verification with the normal release command set before tagging or publication.
