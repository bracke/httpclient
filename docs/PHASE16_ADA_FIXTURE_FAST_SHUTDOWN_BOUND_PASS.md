# Phase 16 Ada Fixture Fast Shutdown Bound Pass

This pass fixes the test-suite apparent hang after the Ada fixture cooperative shutdown change.

The previous shutdown path introduced long bounded waits in every TLS, CONNECT, and SOCKS5 fixture stop path, and the tunnel pump could wait up to ten seconds per tunneled test before closing pump sockets. Because AUnit emits its normal text report only at the end of the run, these repeated waits made the suite appear to run without returning a report.

Changes:

- Reduced tunnel pump maximum wait from 10 seconds to 2 seconds.
- Reduced post-traffic idle-stability wait from 1 second to 0.1 seconds.
- Reduced TLS/CONNECT/SOCKS fixture stop waits from 1 second to 0.05 seconds before abort fallback.
- Kept socket-close-before-abort behavior.
- Did not add warning suppression.

The fixture remains Ada task-based and does not reintroduce C test fixtures or pthread support.
