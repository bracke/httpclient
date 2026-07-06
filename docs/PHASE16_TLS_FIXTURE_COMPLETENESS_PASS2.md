# Phase 16 TLS Fixture Completeness Pass 2

This pass tightens the Ada TLS fixture cleanup behavior after the previous
fixture-path and proxy-status stabilization work.

## Direct TLS AUnit wrapper cleanup

`tests/src/http_client-tls-tests.adb` now calls `Fixtures.Stop_TLS` on the
successful path of each direct TLS AUnit wrapper, not only from exception
handlers.  The direct test bodies still perform their existing assertions,
including fixture result checks, and the wrapper then clears the task/socket
state before AUnit advances to the next test case.

This preserves the existing TLS verification policy:

- positive HTTPS tests keep certificate verification enabled and use the public
  test CA through runtime fixture-path resolution;
- only the explicit unsafe-verification test disables certificate verification;
- negative trust and hostname tests remain deterministic and do not accept an
  arbitrary failure class.

## Scope

No C test fixtures, pthread-based fixture support, C zlib bridge, direct `-lz`,
`Version.Transport.Http`, warning suppression, or product features were added.
