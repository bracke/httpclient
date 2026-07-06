# Phase 16 SOCKS5 CA Path and Negative Failure Pass

This pass fixes the SOCKS5/TLS tests after the diagnostic assertion showed that
all SOCKS5 cases were failing before SOCKS negotiation with `CA_STORE_FAILED`.

Changes:

- `tests/src/http_client-socks5_tls_tests.adb` now resolves TLS fixture files
  through a small path helper that supports running the AUnit binary from the
  project root, `tests/`, or `tests/bin/`.
- SOCKS5 protocol-negative tests no longer configure the TLS fixture CA file.
  These tests are intended to validate SOCKS5 handshake/reply failures before
  TLS can be reached, so CA loading must not mask the SOCKS result.
- Positive HTTPS-over-SOCKS5 tests still use the configured public test CA and
  continue to exercise TLS certificate verification through the SOCKS5 tunnel.

No production behavior changed.
