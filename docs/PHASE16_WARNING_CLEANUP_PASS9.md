# Phase 16 Warning Cleanup Pass 9

This pass responds to the warning-only build log after pass 8.

Scope:

- Restored suite registration for Requests_Headers, Response_Streams, Security_Corpus, TLS, CONNECT/TLS, and SOCKS5/TLS test suites in `tests/src/http_suite.adb`.
- Removed unused suite-driver imports for `Http_Client.Ada_Test_Fixtures` and `Ada.Text_IO`.
- Removed directly reported unused, redundant, and unnecessary `with` clauses from newly surfaced warning files.
- Removed directly reported no-effect `use` / `use type` clauses from newly surfaced warning files.

Conservative choices:

- Did not remove broad shared helper scaffolding even where GNAT reports helper declarations as unused.
- Did not suppress warnings.
- Did not alter TLS defaults.
- Did not add C test fixtures, pthread-based C support, direct `-lz`, or a C zlib bridge.
