# Git smart HTTP Phase 5 — HTTPS over HTTP CONNECT TLS fixture completeness pass

This pass tightens the Phase 5 HTTP proxy `CONNECT` end-to-end fixture and tests.

## Corrections and additions

- Fixed the CONNECT TLS hostname-failure assertion to use the real public status name: `Hostname_Verification_Failed`.
- Corrected the chunked-response test to assert the Phase 4 TLS fixture's binary body bytes instead of a text fixture value.
- Added reusable binary-body assertion coverage for fixed-length and chunked tunneled responses.
- Added `Test_CONNECT_TLS_Localhost_SNI_Uses_Origin_Host` to prove the CONNECT authority and TLS SNI use the origin URI host, not the proxy host.
- Added `Test_CONNECT_TLS_Certificate_Failure_After_Tunnel` to prove certificate validation failure occurs after the proxy tunnel is established and without unsafe verification disable.
- Added `Test_CONNECT_Close_Before_Response_Returns_Deterministic_Status` to cover a proxy closing before a CONNECT response.
- Strengthened the proxy fixture so a test can require a specific `Proxy-Authorization` value and return `407 Proxy Authentication Required` when it is absent.
- Updated the release guard to require the added Phase 5 SNI, certificate-failure, and close-before-response coverage markers.
- Recompiled the C proxy fixture with `gcc -O2 -Wall` successfully.

## Remaining scope boundary

This remains Phase 5 coverage only: HTTPS over an HTTP proxy using `CONNECT`. SOCKS5 end-to-end fixture coverage remains Phase 6, and real pooling/reuse hardening was outside that historical phase unless implemented elsewhere.
