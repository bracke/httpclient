# Testing tiers and interoperability campaign

Http_Client has a deterministic offline test suite and a separate optional interoperability campaign. The default build and default AUnit executable must remain usable without DNS, public internet access, external credentials, public services, containers, or live timing assumptions.

## Tier 1: default offline suite

Tier 1 is required for ordinary development and releases.

```sh
alr build
alr exec -- gnatprove -P httpclient.gpr --level=4
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr test
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

Tier 1 includes unit tests, parser tests, loopback transport tests, TLS option tests, redirect/cookie/decompression/retry tests, proxy and SOCKS byte-sequence tests, caching and encrypted-cache tests, diagnostics tests, async tests, HTTP/2/HPACK tests, HTTP/3/QPACK/QUIC-boundary tests, API stabilization tests, small deterministic interoperability conformance vectors, and a short deterministic hostile-input corpus for security-sensitive parsers and credential paths. It does not contact public services.

## Tier 1b: optional security corpus expansion

Security seed corpus files live under `tests/fixtures/security_corpus/`. The default AUnit runner covers a small built-in smoke subset. Maintainers may build additional Ada-native or external fuzzer harnesses around these seeds, but long fuzz campaigns must remain separate from the normal library build.

Recommended maintainer rules:

```sh
# ordinary deterministic security smoke remains part of Tier 1
./tests/bin/tests

# optional corpus hygiene check; requires only the Ada tools, not live services
alr exec -- gprbuild -P tools/tools.gpr && ./tools/bin/check_security_corpus

# optional long campaigns should be explicit, bounded, and seed-controlled
# HTTP_CLIENT_FUZZ_SEED=12345 HTTP_CLIENT_FUZZ_ITERS=100000 ./tools/fuzz_uri
```

Any random fuzz harness must print its seed on failure. Any minimized crashing input should be committed as a small named file under `tests/fixtures/security_corpus/` and covered by a deterministic AUnit regression when practical.

## Tier 2: optional local extended integration

Tier 2 is for maintainers who run local services or containers such as nginx, Apache httpd, Caddy, an echo server, a local HTTP proxy, a local SOCKS proxy, and a local mutual-TLS endpoint. These services are not part of the normal library build. Tests in this tier should use configured local endpoint URLs and should be repeatable without public internet access.

## Tier 3: optional live external interoperability

Tier 3 is intentionally outside the default release build. Add or run live interoperability projects only when they are present in the tree, explicitly enabled, and configured with non-production local or test endpoints. A missing live interoperability project is not a default-suite failure.

## Tier 4: manual exploratory interoperability

Tier 4 is manual release-validation evidence against real server families and public endpoints. Record tested server family, version if known, protocol, date, configuration, result, and whether the result is automated or manual. Do not turn public sites into mandatory tests.

## Failure reporting and redaction

Optional interop output is intentionally high-level: test name, configured endpoint category, operation status, broad HTTP status code, skip/failure/unsupported classification, and redacted status names. The runner must not print raw Authorization, Proxy-Authorization, Cookie, Set-Cookie, SOCKS credentials, client-certificate private keys, encrypted-cache keys, complete request bodies, complete response bodies, or raw diagnostic payloads that may contain secrets.

## Safe local certificate handling

For local mutual-TLS experiments, use dedicated low-privilege test certificates, keep private keys outside version control, and configure them only in a private local environment. Verification-disable options are unsafe and should only be exercised against controlled endpoints to verify that they remain explicit and opt-in.


## Release coverage gate

The default test executable is backed by `All_Suites.Suite`, a real AUnit suite with each deterministic behavior registered as an individual AUnit routine. For release validation, run `cd tests && alr exec -- ../tools/bin/run_aunit_coverage` to rebuild with GNAT/gcov instrumentation and enforce 100% line and branch coverage over production Ada sources under `src/`.

SPARK legality coverage is documented in `docs/SPARK.md`; the GNATprove command above is part of the release gate.
