# Offline AUnit suite

The default release test path is a real AUnit suite, not a procedural smoke runner. It is exposed by `All_Suites.Suite` and executed by `tests/src/tests.adb` through `AUnit.Run.Test_Runner`.

The suite is deliberately split by project section. The aggregate packages `All_Suites` and `Http_Suite` only combine child suites. Section suites live under `tests/src/http_client-*-tests.adb`, for example `Http_Client.URI.Tests`, `Http_Client.Requests_Headers.Tests`, `Http_Client.HTTP1.Tests`, `Http_Client.Cache.Tests`, `Http_Client.HTTP2.Tests`, `Http_Client.HTTP3.Tests`, and `Http_Client.Protocol_Discovery.Tests`.

The test bodies live in the component-specific `Http_Client.<Component>.Tests` packages. The aggregate suite contains no direct tests, and there is no private monolithic `Offline_Test_Cases` package that all sections call through. Shared declarations may be duplicated or kept as local helpers, but ownership of each `Test_*` body stays with the section that registers it.

Build and run the default offline suite with:

```sh
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
```

The suite is intentionally deterministic and offline. It must not depend on public internet hosts, live credentials, user-specific proxy configuration, local browser profiles, OS credential stores, or downloaded conformance data. Optional live interoperability, long-running fuzzing, and benchmarks remain separate release-validation tiers.

## Section suite layout

Required section suites include:

- `Http_Client.Release_Core.Tests`
- `Http_Client.URI.Tests`
- `Http_Client.Requests_Headers.Tests`
- `Http_Client.HTTP1.Tests`
- `Http_Client.Redirects.Tests`
- `Http_Client.Retry.Tests`
- `Http_Client.Cookies.Tests`
- `Http_Client.Decompression.Tests`
- `Http_Client.Proxies.Tests`
- `Http_Client.Proxies.SOCKS.Tests`
- `Http_Client.Auth.Tests`
- `Http_Client.Response_Streams.Tests`
- `Http_Client.Request_Bodies.Tests`
- `Http_Client.Multipart.Tests`
- `Http_Client.Connection_Pools.Tests`
- `Http_Client.Cache.Tests`
- `Http_Client.Cache.Persistent.Tests`
- `Http_Client.Diagnostics.Tests`
- `Http_Client.Async.Tests`
- `Http_Client.HTTP2.Tests`
- `Http_Client.HTTP3.Tests`
- `Http_Client.Protocol_Discovery.Tests`
- `Http_Client.Security_Corpus.Tests`
- `Http_Client.Conformance.Tests`
- `Http_Client.Resources.Tests`

New tests should be added to the section suite matching the production package or behavior being tested. If a section grows too large, split it further rather than placing unrelated tests in the aggregate suite.

## Required coverage areas

The suite must keep broad behavior coverage across the release surface:

- URI parsing and hostile URI rejection.
- Header validation, header ordering, and request serialization injection protection.
- Request, response, status, and high-level client configuration behavior.
- HTTP/1.1 serialization, response parsing, bounded reading, and local loopback execution behavior.
- TLS configuration defaults and failure boundaries.
- Redirect, retry, cookie, decompression, proxy, SOCKS, authentication, streaming, upload, multipart, pooling, cache, persistent cache, encrypted cache, diagnostics, resource-limit, and async behavior.
- HTTP/2 frame/settings/HPACK/stream/multiplexing/streaming/upload behavior.
- HTTP/3, QUIC boundary, QPACK, explicit execution gating, and fallback-policy behavior.
- Alt-Svc and HTTPS/SVCB discovery parsing, selection, cache, and fallback behavior.
- Security corpus, fixture corpus, release API-stability, and status-category behavior.

`tools/src/check_aunit_suite.adb` statically audits the split suite for registration integrity and minimum coverage breadth. It verifies that each registered `Test_*` procedure is defined in the same component-specific section suite that registers it, registered routines are present, duplicate registrations are absent, required behavior areas are represented, the aggregate suite imports the section suites, the runner uses AUnit, the obsolete monolithic test-cases package is absent, and the coverage gate is still present.

Run the static suite audit with:

```sh
alr exec -- gprbuild -P tools/tools.gpr && ./tools/bin/check_aunit_suite
```

## 100% coverage gate

Complete production source coverage is enforced by the coverage tier:

```sh
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

That script rebuilds with GNAT/gcov instrumentation, runs the same AUnit suite, filters coverage to production `src/` files, and requires 100% line and 100% branch coverage. The static suite audit is not a substitute for that command; it is an offline packaging guard that catches obvious registration and breadth regressions before the Ada toolchain is available.
