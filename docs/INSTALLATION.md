# Installation and dependency notes

This document records the ordinary build prerequisites for `http_client` and the troubleshooting notes that are intentionally separate from protocol behavior. It does not add feature semantics and it does not broaden the supported-platform claim in `PLATFORM_SUPPORT.md`.

## Required tools

For a source checkout or release archive, the expected maintainer toolchain is:

- an Ada 2022-capable GNAT compiler;
- `gprbuild` for direct project-file builds;
- Alire for manifest resolution and downstream package validation where available.

The runtime library project is `httpclient.gpr`. The default test project is `tests/tests.gpr`. The example project is `examples/examples.gpr`. The API-stability compile project is `tests/api_stability/api_stability.gpr`.

## Required link dependencies

The library build requires OpenSSL headers/libraries plus the Ada `zlib` project dependency declared by `alire.toml` and `httpclient.gpr`:

- OpenSSL provides TLS, ALPN, client-certificate handling, random generation, and cryptographic helpers used by the current implementation.
- the Ada `Zlib` library provides gzip/deflate mechanics through `Http_Client.Zlib_Decompression`; HttpClient imports no C zlib symbols and does not use the system C `zlib` package as its Ada project dependency.

OpenSSL 3.x is the primary validation target for the current platform-packaging validation. OpenSSL 1.1.1 may work on systems that still ship it, but it is not part of the primary support claim unless that exact platform/dependency combination is tested by a maintainer.

AUnit is a test-only dependency. It is needed to build `tests/tests.gpr`, but ordinary downstream users of `httpclient.gpr` should not need AUnit.

## Linux baseline

On the primary Linux validation target, install GNAT, GPRbuild, OpenSSL development files, the Ada `zlib` crate, and AUnit when running tests. Package names vary by distribution. For Debian/Ubuntu-like environments, the CI workflow currently uses packages equivalent to:

```sh
sudo apt-get install gnat gprbuild libssl-dev
sudo apt-get install libaunit-dev || sudo apt-get install libaunit22-dev || sudo apt-get install libaunit24-dev
```

Then build and validate:

```sh
alr build
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
./tools/bin/check_git_smart_http_release
```

## macOS best-effort notes

macOS does not normally use OpenSSL as the system TLS library. Use an Ada toolchain, GPRbuild, and package-manager OpenSSL development files and the Ada `zlib` dependency. The best-effort CI slot documents this platform but is not a full release-blocking support claim until the complete matrix is green.

Common macOS issues are linker search paths and runtime library paths for package-manager OpenSSL. Prefer Alire-managed dependencies where available. When using a package manager, document any required `LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, `GPR_PROJECT_PATH`, or equivalent local setup in release notes before claiming that exact environment as fully supported.

## Windows best-effort notes

Windows support is best-effort until the full build/test/package matrix is validated. Expected areas requiring explicit validation are OpenSSL DLL/import-library discovery, Ada zlib project resolution, socket initialization, path separators, temporary directories, file deletion semantics, and tasking behavior.

Do not claim a Windows environment as fully supported until a clean checkout builds the library, builds and runs the default offline tests, compiles examples, compiles API-stability tests, and passes the package/downstream validators with the documented dependency layout.

## Alire consumption

The manifest exports `httpclient.gpr` for downstream users. A downstream smoke check should create a separate project, depend on the crate as an ordinary dependency, import stable public packages, and link a minimal executable without importing test-only packages.

Run this check by creating a fresh external Alire/GPRbuild project, depending on this crate, importing `Http_Client.Clients` and `Http_Client.Errors`, and building a minimal executable. This release archive does not ship an automated downstream Python checker.

## Optional QUIC / HTTP/3 backend

HTTP/3 protocol packages and the QUIC boundary are experimental. A production QUIC backend is not implicitly selected by platform detection. If no backend is explicitly configured and available, HTTP/3 execution must return deterministic unsupported statuses before request bytes are sent, or fall back only when existing fallback-before-send policy permits it.

Missing QUIC support must not break ordinary HTTP/1.1 or HTTP/2 builds. If a release branch pins or requires a QUIC backend, that dependency must be documented separately and validated in a dedicated optional CI job.

## Common build and link failures

| Symptom | Likely cause | Expected action |
| --- | --- | --- |
| `cannot find -lssl` or `cannot find -lcrypto` | OpenSSL development library not installed or not on the linker path. | Install OpenSSL development package or configure the documented linker path. |
| missing `zlib.gpr` or `Zlib` unit | Ada `zlib` dependency not resolved by Alire/GPRbuild, or Alire resolved the system C `zlib` package instead of the Ada project dependency. | Use the sibling Ada zlib checkout during development, or depend on a published Ada zlib crate that provides `zlib.gpr` before release. |
| AUnit project not found while building tests | Test-only AUnit dependency unavailable. | Install/resolve AUnit for test builds; ordinary library consumers do not need it. |
| OpenSSL DLL/shared library not found at runtime | Runtime library search path does not include the OpenSSL binaries. | Install runtime package or configure the platform-specific runtime search path. |
| HTTP/3 returns unsupported status | No production QUIC backend is configured or available. | Configure a supported backend only if HTTP/3 execution is intentionally being validated. |

## What installation does not configure

Installing or building the crate does not enable browser-like behavior. The library does not automatically read browser profiles, OS credential stores, password managers, system proxy settings, environment proxy variables, DHCP WPAD, DNS search domains, public DNS HTTPS/SVCB records, live PAC URLs, or OAuth/OIDC/SAML/NTLM/Negotiate/Kerberos workflows. Those remain outside the platform-packaging validation scope.
