# Git smart HTTP Phase 4 direct TLS fixture pass

Phase 4 adds a deterministic loopback HTTPS origin fixture for the Git smart
HTTP release gate. The fixture binds to loopback, selects an ephemeral port,
performs a real OpenSSL server-side TLS handshake, serves HTTP/1.1 over TLS,
and captures request bytes for upload assertions. It is test-only
infrastructure and does not change the public production API.

The fixture certificates live in `tests/fixtures/tls/`. They are local test
materials only; the private keys are intentionally public fixture data and must
not be used in production. Positive HTTPS tests use `tests/fixtures/tls/ca.crt`
through `TLS_Options.CA_File`; they do not rely on disabling verification.

Covered behavior:

- direct HTTPS GET succeeds with a configured local CA file;
- the same private CA fails without explicit trust;
- a wrong-host certificate fails hostname/certificate verification;
- `Disable_Certificate_Verification` is explicit and remains unsafe;
- fixed-length binary HTTPS responses preserve NUL, CR, LF, high-bit bytes, and
  Git-like packfile bytes;
- chunked binary HTTPS responses are transfer-decoded without exposing trailers
  as body bytes;
- pull-based `Response_Streams.Read_Some` works over direct TLS with byte-array
  buffers;
- buffered binary POST bodies are sent over direct TLS without text conversion;
- unknown-length chunked upload, request trailers, and `Expect: 100-continue`
  are exercised over direct TLS.

SNI coverage is explicit. `Test_Direct_HTTPS_GET_Localhost_Sends_SNI`
connects to the loopback fixture through the DNS hostname `localhost`, and the
fixture observes the OpenSSL SNI callback value. The production TLS option still
defaults `Send_SNI` to True and intentionally omits SNI for IP literals.

HTTPS-over-HTTP-CONNECT and HTTPS-over-SOCKS end-to-end fixtures remain later
phases. This phase exists to prove the direct TLS origin before proxy-tunnel
coverage composes on top of it.
