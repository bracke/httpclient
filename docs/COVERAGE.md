# AUnit coverage gate

The default offline tests are a real AUnit suite, exposed by `All_Suites.Suite` and executed by `tests/src/tests.adb`. The aggregate suite is split into section packages under `Http_Client.<Section>.Tests`, and each deterministic unit/conformance/security/resource/API-stability test is registered as a separate AUnit routine so failures are reported per behavior area.

Release-candidate validation requires the complete offline AUnit suite and a coverage pass over production Ada sources:

```sh
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

`tools/bin/run_aunit_coverage` rebuilds the test executable with GNAT/gcov instrumentation, runs the AUnit suite, and uses `gcovr` to enforce 100% line and branch coverage for production sources under `src/`, including Ada units and C bridge files compiled into the library.

The coverage gate intentionally excludes optional live interoperability, long-running fuzz campaigns, benchmarks, downloaded third-party conformance data, generated local cache directories, and private local certificates. Those remain separate release-evidence tiers.

When adding or changing production code, maintainers should add deterministic AUnit coverage first. New uncovered code should not be accepted into the release branch unless it is explicitly unreachable defensive code and the release notes document the reason.

## Suite integrity audit

Before running instrumented coverage, maintainers can run the static AUnit suite audit:

```sh
alr exec -- gprbuild -P tools/tools.gpr && ./tools/bin/check_aunit_suite
```

This audit verifies that the offline suite remains a real split AUnit suite, that section packages remain present, that registered test routines are defined in their component section, that registration names are unique, and that required release behavior areas are still represented. It complements, but does not replace, the 100% coverage gate.
