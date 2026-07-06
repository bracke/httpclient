# Compatibility and deprecation policy

The 1.0 release API distinguishes stable, low-level stable, experimental, and implementation-detail packages. Stable packages carry the 1.0 compatibility promise. Low-level stable packages are also public, but callers should expect more protocol-specific detail and should read the package comments carefully.

## Stable packages

After 1.0, stable package names, public type names, public subprogram signatures, documented default values, and documented status-returning behavior should not be changed incompatibly without a deprecation period where practical. Additive APIs are preferred over replacements.

## Experimental packages

`Http_Client.HTTP3`, `Http_Client.HTTP3.*`, and `Http_Client.QUIC` are explicitly experimental in this release. They may change when a production QUIC backend or production HTTP/3 execution is implemented. The current execution boundary must fail before request bytes are sent when backend support is unavailable. They must not silently become browser-like networking, bypass configured proxies, bypass TLS policy, or reinterpret unsupported wire data as successful HTTP responses.

## Deprecated APIs

If an API is deprecated after 1.0, release notes should explain the replacement and the first release where removal may be considered. Deprecated compatibility shims should preserve status behavior and security defaults. Duplicate old/new APIs should not be left without guidance.

## Program control

Applications should branch on `Http_Client.Errors.Result_Status` and documented structured fields. Diagnostic messages are intended for humans and may be revised for clarity unless a package explicitly marks a message as stable.
