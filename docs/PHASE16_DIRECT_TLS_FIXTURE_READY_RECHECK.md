# Phase 16 Direct TLS Fixture Ready Recheck

This release-stabilization pass keeps Phase 16 product behavior unchanged and
hardens only the direct AUnit TLS fixture path.

## Scope

- No product features were added.
- No C test fixtures were added or restored.
- Existing production OpenSSL bridge files remain the only C TLS bridge code.
- TLS verification defaults remain unchanged.
- Warning suppression was not added.

## Direct TLS test changes

`tests/src/http_client-tls-tests.adb` now resolves TLS fixture certificate,
key, and CA files at runtime from subprogram bodies.  The helper covers common
runner locations:

- project root: `tests/fixtures/tls/...`
- `tests/`: `fixtures/tls/...`
- `tests/bin/`: `../fixtures/tls/...`
- nested build/run directories: `../../tests/fixtures/tls/...` and
  `../../../tests/fixtures/tls/...`

The direct TLS fixture start wrapper also stops any stale prior fixture before
starting the next one.  This avoids stale task/socket state while preserving the
rule that fixture path helpers are called only inside subprogram bodies.

Positive direct TLS assertions now include the actual `Result_Status` image in
failure messages so the next failure report identifies the common cause directly
(for example CA store loading, connection, handshake, hostname verification, or
read/write status).

Negative trust and hostname tests still require deterministic TLS-related
failures.  They additionally accept `CA_Store_Failed` for platforms where the
client cannot load the configured/default CA store before certificate-chain or
hostname validation is reached.

## Ada TLS fixture changes

`tests/src/http_client-ada_test_fixtures.adb` now publishes the ephemeral TLS
fixture port only after the server socket is listening and the OpenSSL server
context, certificate, and private key have loaded successfully.  This prevents
clients from racing a fixture that has already failed certificate/key setup.

The TLS fixture task also frees OpenSSL and socket resources on normal stop and
unexpected fixture exceptions.  `SSL_shutdown` is still intentionally not used
in the local fixture, because waiting for peer `close_notify` can deadlock tests
whose client-side parser owns connection teardown.
