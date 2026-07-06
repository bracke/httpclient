# Phase 16 SOCKS5 handshake diagnostic fix pass

This pass tightens the Ada SOCKS5 test fixture after repeated failures across the
entire SOCKS5/TLS suite.

Changes:

- the SOCKS5 fixture now reads the greeting as a framed message using NMETHODS
  instead of assuming a fixed three-octet greeting;
- the fixture selects no-auth or username/password only if the client actually
  offered the method;
- fixture-side TLS shutdown no longer waits for peer `close_notify` after a
  complete HTTP response, avoiding tunnel fixture deadlocks;
- SOCKS5 test status assertions now include actual and expected
  `Result_Status` images so any remaining mismatch is actionable.

The test fixture remains Ada task-based. No C test fixtures or pthread fixture
support are introduced.
