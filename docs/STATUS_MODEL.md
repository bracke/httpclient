# Status and exception model

All ordinary user-input, network, TLS, proxy, SOCKS, authentication, cache, decompression, protocol, timeout, cancellation, and unsupported-feature failures are reported through `Http_Client.Errors.Result_Status`. Callers should use statuses and structured result records for program control. `Http_Client.Errors.Category` provides stable coarse grouping for diagnostics and metrics without requiring callers to parse status names.

The stable categories are:

- success: `Ok`;
- validation and configuration failures: invalid URI, header, request, credentials, proxy, SOCKS proxy, cache, diagnostics, async, TLS, HTTP/2, or HTTP/3 options;
- transport failures: DNS/connect/read/write/timeout/cancellation/not-connected conditions;
- TLS failures: handshake, verification, hostname, ALPN, SNI, and client-certificate failures;
- proxy/SOCKS failures: proxy connection, CONNECT response, SOCKS negotiation, unsupported SOCKS commands/address types;
- protocol failures: malformed HTTP/1.1, HTTP/2, HTTP/3, HPACK, QPACK, framing, body-size, file-integrity, and header-size failures;
- policy/control failures: redirect limit, redirect downgrade, credential-forwarding restriction, retry exhaustion, non-replayable body;
- cache failures: disabled cache, corrupt cache, unsupported cache format, encrypted-cache authentication failure, and storage I/O failures;
- async failures: queue full, shutdown, cancellation, invalid handle, not ready, result already taken;
- internal failures: unexpected implementation defects.

Status names should remain non-overlapping where a public distinction matters. New statuses may be added before a final 1.0 release if an existing generic status would hide a useful stable distinction.

## Exceptions

Public APIs should not raise exceptions for ordinary invalid input or expected operational failures. Exceptions are reserved for programming errors covered by preconditions/assertions, allocation failures, finalization defects, or unexpected implementation bugs. Where a convenience function has a precondition, a status-returning alternative must exist for untrusted input.

Representative tests should keep verifying that invalid URIs, invalid headers, unsupported upload modes, unavailable HTTP/3 execution, cache corruption, diagnostics callback failure policy, timeout classification, cooperative cancellation, and async cancellation are status-returning paths.
