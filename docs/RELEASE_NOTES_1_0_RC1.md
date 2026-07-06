# Release notes: 1.0.0-rc1

This pre-release stabilizes the accumulated `http_client` API into a coherent 1.0-style surface. It is a release-hardening pass, not a protocol-expansion release.

## Stable feature surface

The stable public surface covers URI parsing, validated headers, request/response models, HTTP/1.1 serialization and execution, HTTPS/TLS through OpenSSL, redirects, cookies, decompression, HTTP and SOCKS proxy configuration, retries, Basic/Bearer/Digest helpers, high-level client configuration, streaming response bodies, fixed-length uploads, multipart/form-data, in-memory cache, persistent cache, encrypted persistent cache, diagnostics/metrics, HTTP/2 support, client-certificate TLS authentication, and explicit bounded async/task integration.

## Experimental surface

`Http_Client.HTTP3`, `Http_Client.HTTP3.*`, and `Http_Client.QUIC` remain experimental protocol foundations. They expose configuration, fallback, frame, stream, settings, mapping, and QPACK boundaries, and now include an explicit buffered execution insertion point, but they do not provide production HTTP/3 execution or an available QUIC backend.

## Stabilization changes

- The README now presents the crate as a cohesive Ada HTTP client rather than a development log.
- Public package comments describe stable entry points, conservative defaults, ownership expectations, task-safety limitations, unsupported browser behavior, and experimental HTTP/3 boundaries.
- `Http_Client.Errors` exposes `Result_Category` and `Category` for stable coarse grouping while preserving precise `Result_Status` program control.
- Documentation now includes API stability, public-package classification, release-surface manifest, configuration, security model, status model, ownership/task-safety, header/protocol semantics, timeout/resource-limit, HTTP/2, HTTP/3 experimental, example, compatibility, audit, verification, and release-checklist notes.
- Examples cover the main stable API areas and the explicit unsupported HTTP/3 execution boundary.
- Regression tests cover conservative defaults, security-sensitive redaction, forbidden default headers, explicit unsafe TLS naming, HTTP/3 fallback constraints, QUIC 0-RTT rejection, HTTP/3 server-push rejection, cache-store composition, redirect/decompression limit validation, and total result-status category coverage.
- `tools/src/check_release_surface.adb` provides source-tree checks for metadata drift, manifest coverage, stale phase-oriented documentation wording, and required HTTP/3/PAC/WPAD disclaimers without requiring network access or optional live services.

## Compatibility notes

This is a pre-1.0 stabilization boundary. Stable packages are intended to carry the post-1.0 compatibility promise once the final release is cut. Experimental HTTP/3 and QUIC packages may change when production HTTP/3 execution is deliberately implemented.

## Unsupported behavior

This release does not add production HTTP/3 execution, QUIC backend integration, PAC/WPAD discovery, browser profile integration, service workers, browser preload behavior, OAuth/OIDC/SAML token acquisition, NTLM, Negotiate/SPNEGO, Kerberos, OS credential stores, password managers, hardware-token integration, automatic login flows, SOCKS UDP ASSOCIATE/BIND, Tor control behavior, or browser-like networking policy.

## Security/fuzzing hardening

The security/fuzzing coverage adds a focused threat-model update, deterministic security corpus smoke tests, minimization-friendly seed files under `tests/fixtures/security_corpus/`, and `docs/security.md`. This is hardening infrastructure only: it preserves the established public semantics and does not introduce browser-like discovery, credential-store integration, token acquisition workflows, SOCKS UDP/BIND behavior, MASQUE, CONNECT-UDP, WebTransport, service-worker behavior, browser cache/profile integration, or automatic protocol/proxy discovery.
