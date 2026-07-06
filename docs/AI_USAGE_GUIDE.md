# AI usage guide and repository map

This document exists so an AI coding assistant, documentation agent, package reviewer, or downstream integrator can locate, understand, and use the `http_client` library without relying on prior conversation context.

## What this repository is

`http_client` is an Ada 2022 Alire library crate. It exposes an explicit HTTP/HTTPS client API with stable HTTP/1.1, TLS, proxy, retry, cache, diagnostics, streaming, upload, authentication-helper, HTTP/2, async, PAC/WPAD helper, and protocol-discovery surfaces. HTTP/3 and QUIC packages are experimental and are present as optional boundaries.

This repository is not a browser, proxy auto-configuration daemon, credential manager, OAuth client, operating-system proxy importer, service-worker runtime, MASQUE implementation, CONNECT-UDP implementation, WebTransport implementation, or SOCKS UDP/BIND implementation.

## Files that identify the library

| Purpose | File |
| --- | --- |
| Alire crate manifest | `alire.toml` |
| Library project exported to downstream users | `httpclient.gpr` |
| Root Ada namespace | `src/http_client.ads` |
| Public package classification | `docs/PUBLIC_PACKAGES.md` |
| Stable API contract | `docs/STABLE_API_CONTRACT.md` |
| API stability and release surface | `docs/API_STABILITY.md` |
| Examples project | `examples/examples.gpr` |
| Offline AUnit test project | `tests/tests.gpr` |
| Platform and packaging support | `docs/PLATFORM_SUPPORT.md`, `docs/PACKAGING_VALIDATION.md`, `docs/INSTALLATION.md` |
| CI validation plan | `docs/CI_MATRIX.md` |
| Agent orientation | `../AGENTS.md` |

## Recommended first imports for generated Ada code

Use these stable packages first unless a task explicitly requires a lower-level protocol package:

```ada
with Http_Client.Clients;
with Http_Client.Errors;
```

For manual request construction:

```ada
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;
```

For explicit configuration areas:

```ada
with Http_Client.Retry;
with Http_Client.Proxies;
with Http_Client.Proxies.SOCKS;
with Http_Client.Proxy_Discovery;
with Http_Client.Protocol_Discovery;
with Http_Client.Diagnostics;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Decompression;
```

For HTTP/2-specific advanced code, consult `docs/HTTP2_GUIDE.md` before using `Http_Client.HTTP2.*`. For HTTP/3/QUIC code, consult `docs/HTTP3_EXPERIMENTAL.md`; those packages are experimental and backend availability is not guaranteed.

## Minimal downstream shape

A downstream Alire project should depend on the crate, with `httpclient.gpr` exported by the package manifest. Application code should import stable packages such as `Http_Client.Clients`, not test packages or implementation fixtures. AUnit is test-only and must not be required by runtime users.

A clean-room downstream smoke project should be created manually or by future maintainer tooling when `gprbuild` is available; no downstream Python checker is shipped in this release archive.

## How to choose the right document

- Need to know whether a package is stable or experimental: `docs/PUBLIC_PACKAGES.md`.
- Need to use the high-level API: `../README.md`, `docs/EXAMPLES.md`, and `examples/src/simple_get.adb`.
- Need to understand configuration defaults: `docs/CONFIGURATION.md` and `docs/DEFAULT_LIMITS.md`.
- Need to understand status values and error handling: `docs/STATUS_MODEL.md`.
- Need to understand ownership and task behavior: `docs/THREADING_AND_OWNERSHIP.md`.
- Need to understand security boundaries: `docs/SECURITY_MODEL.md`.
- Need to build or install: `docs/INSTALLATION.md`.
- Need to validate package contents: `docs/PACKAGING_VALIDATION.md`.
- Need to understand platform claims: `docs/PLATFORM_SUPPORT.md`.
- Need examples for a feature family: `docs/EXAMPLES.md`.

## Safe defaults to preserve in generated code

Generated examples or downstream code should assume these defaults:

- TLS certificate and hostname verification are enabled.
- Redirects, retries, cookies, decompression, caches, proxies, SOCKS, PAC/WPAD helpers, diagnostics observers, async execution, protocol discovery, and HTTP/3 are disabled until explicitly configured.
- No environment proxy variable should be used implicitly by this library.
- No browser profiles, OS credential store, password manager, or system proxy setting should be read implicitly.
- Diagnostics text is for humans; program control should use `Http_Client.Errors.Result_Status` and structured metadata.

## Validation commands for AI-authored changes

Run the shipped offline validators after documentation, packaging, examples, or public-spec changes:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
./tools/bin/check_git_smart_http_release
```

When GNAT/GPRbuild/AUnit are installed, also run:

```sh
alr exec -- gprbuild -P httpclient.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
```

## Search terms that should find the library

The repository intentionally contains the following discoverability terms: Ada HTTP client, Ada HTTPS client, Alire HTTP client, GNAT HTTP client, OpenSSL TLS client, HTTP/2 Ada client, explicit proxy configuration, SOCKS5 proxy, PAC/WPAD helper, Alt-Svc, HTTPS/SVCB, deterministic offline tests, platform packaging validation.
