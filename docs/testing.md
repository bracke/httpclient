# Testing

Testing is tiered so ordinary validation remains deterministic and offline.

## Tier 1: default offline build and AUnit tests

Build the library with `alr build` or `alr exec -- gprbuild -P httpclient.gpr`. Build and run the default tests with `alr exec -- gprbuild -P tests/tests.gpr` followed by `./tests/bin/tests`. For release coverage validation, run `cd tests && alr exec -- ../tools/bin/run_aunit_coverage`. These tests should not require public internet access, live DNS, live endpoints, real credentials, containers, or long-running fuzzers.

## Tier 2: local extended integration

Local integration tests may use loopback servers, local test certificates, temporary cache directories, local proxy/SOCKS fixtures, and local QUIC backend fixtures. They must use test-only credentials and must clean generated artifacts.

## Tier 3: optional live interoperability

Live interop tests are opt-in and configured through environment variables. They may use public or private endpoints selected by the maintainer, but they are not required for normal users or default CI.

## Tier 4: optional fuzz and hardening

Longer fuzz campaigns and corpus expansion are maintainer activities. Seeds should be small, deterministic, minimized, and free of production secrets.

## Tier 5: optional benchmarks

Benchmarks are advisory and must not gate ordinary correctness validation unless a release manager explicitly chooses to run them.


## Release coverage gate

The default test executable is backed by `All_Suites.Suite`, a real AUnit suite with each deterministic behavior registered as an individual AUnit routine. For release validation, run `cd tests && alr exec -- ../tools/bin/run_aunit_coverage` to rebuild with GNAT/gcov instrumentation and enforce 100% line and branch coverage over production Ada sources under `src/`.

## AUnit suite integrity

The release package includes a static suite audit implemented as an Ada tool:

```sh
alr exec -- gprbuild -P tools/tools.gpr && ./tools/bin/check_aunit_suite
```

This check is part of the release-surface static validation and ensures the default offline tests remain registered as individual AUnit routines with broad behavior coverage.
