# Phase 16 SOCKS5 Elaboration Runtime Path Recheck Pass

This pass fixes a regression in `tests/src/http_client-socks5_tls_tests.adb` where package-level
constants called the local `Fixture_Path` function during package elaboration. GNAT elaboration
checks can raise `PROGRAM_ERROR: access before elaboration` for that pattern.

Changes:

- Replaced elaboration-time fixture path constants with parameterless helper functions.
- Kept fixture path resolution lazy, inside test execution paths only.
- Removed default expressions from `Start_TLS_Fixture` that depended on local helper functions.
- Preserved runtime fixture path resolution for project root, `tests/`, and `tests/bin/` working directories.
- Kept pre-origin SOCKS5 negative tests using an unused origin port.
- Kept SOCKS unsupported-version test accepting the deterministic malformed-reply result.

No warning suppression was added.
