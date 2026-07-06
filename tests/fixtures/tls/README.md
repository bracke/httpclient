# Local TLS test certificates

These PEM files are deterministic local test fixtures for the HttpClient AUnit
suite. The private keys are intentionally committed test data and are not
secret. They must never be used for production systems.

The default server certificate is signed by `ca.crt` and contains SAN entries
for `localhost` and `127.0.0.1`. The wrong-host certificate is signed by the
same test CA but intentionally lacks a SAN for the test origin host.
