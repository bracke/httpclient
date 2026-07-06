# Phase 16 Stale Source Warning Recheck

This pass rechecks the packaged source after reports showing the old Ada
fixture body and stale redirect-test helper warnings.

The package contains the corrected Ada task-based fixture body:

- `tests/src/http_client-ada_test_fixtures.adb` contains explicit operator
  visibility for `CS.chars_ptr` and `Ada.Streams.Stream_Element`;
- it contains no task-body `return;` statements;
- it contains no lines over 120 columns;
- it uses Ada task-based TLS/CONNECT/SOCKS fixtures and no C test fixtures.

The pass also removes stale unused helper scaffolding from
`tests/src/http_client-redirects-tests.adb` and removes the empty local
`objcheck/` directory from the release package.
