# Platform support and dependency matrix

This document defines validated platform support and packaging behavior. It does not add protocol features and it does not change public API semantics.

## Support levels

| Level | Meaning |
| --- | --- |
| Fully supported | The crate is expected to build from a clean checkout, link, run the default offline AUnit suite, compile examples, compile the API-stability program, and pass package-content checks in CI or an equivalent maintainer environment. |
| Best effort | The source is intended to be portable and issues are accepted, but every release may not run the full default matrix on this platform. Optional dependency layout may require local setup. |
| Experimental | The API or backend boundary exists, but production execution or platform packaging is not guaranteed. Failures must be deterministic and documented. |
| Unsupported | The environment is outside the current support claim. The crate should fail clearly rather than pretending support. |

## Current support matrix

| Platform | CPU | GNAT | Alire | OpenSSL | zlib | QUIC / HTTP/3 execution | Support level | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux, glibc baseline distribution | x86_64 | GNAT FSF/GNAT Community compatible with Ada 2022, validated in CI with GNAT/GPRbuild; Alire manifest resolution is part of package validation | Current stable Alire for downstream package validation; CI also supports direct GPRbuild validation | OpenSSL 3.x preferred and documented as the validation target; OpenSSL 1.1.1 is not part of the primary support claim | Ada `zlib` project resolved by Alire/GPRbuild | Optional backend boundary only unless a production backend is pinned by the maintainer | Fully supported primary platform | Default offline tests must pass without internet access. |
| Linux, alternate distributions | x86_64, aarch64 | Ada 2022-capable GNAT | Current stable Alire | Distribution OpenSSL layout may vary | Ada `zlib` project resolution may vary | Optional | Best effort | CA store paths, IPv6 availability, resolver behavior, and library names vary by distribution. |
| macOS | arm64, x86_64 | Ada 2022-capable GNAT from Alire/toolchain package | Current stable Alire | Usually package-manager OpenSSL rather than system TLS | Ada `zlib` project dependency | Optional | Best effort | Linker paths, rpaths, and CA-store behavior must be documented by the local package manager. |
| Windows | x86_64 | Ada 2022-capable GNAT from Alire/toolchain package | Current stable Alire | OpenSSL DLL/import library layout must be explicitly installed or supplied by Alire | Ada zlib project layout must be explicitly installed or supplied by Alire | Optional | Best effort until full CI is green | Requires review of socket initialization, path handling, file deletion semantics, temporary directories, and DLL discovery. |
| Cross-compilation targets | Any | Any | Any | Any | Any | Any | Unsupported unless separately tested | Cross-compilation is not part of the current support claim. |
| Embedded or bare-metal targets | Any | Any | Any | Any | Any | None | Unsupported | The crate requires sockets, tasking where async is used, filesystem support for persistent caches/tests, and TLS libraries. |

## Dependency requirements

The ordinary library build depends on OpenSSL through the platform/toolchain and Ada `zlib` through `alire.toml` and the project file. Required dependencies should fail clearly at build or link time when absent. Optional QUIC backend behavior is not silently inferred from the host platform.

Minimum dependency expectations:

- OpenSSL: 3.x is the preferred and documented validation target. OpenSSL 1.1.1 may work where still shipped, but it is not part of the primary support claim unless a maintainer validates that exact platform/dependency combination. TLS, ALPN, client certificates, random generation, Digest hashing when OpenSSL-backed, encrypted-cache cryptography, and QUIC integration can depend on OpenSSL version and link layout.
- Ada `zlib`: required for compression/decompression through `Http_Client.Zlib_Decompression`; HttpClient imports no C zlib symbols and does not add `-lz` itself.
- QUIC backend: optional. Builds without a production QUIC backend must still succeed when the package claims optional HTTP/3. HTTP/3 execution must return deterministic unsupported statuses before request bytes are sent unless a backend is explicitly configured and available.
- AUnit: required only for the test project. Runtime library users should not need AUnit unless they build the shipped AUnit test executable.

If a platform needs environment variables, library paths, linker flags, Alire pins, or package-manager commands, record them in release notes or CI setup and keep the current notes in `INSTALLATION.md` accurate. The library must not require private absolute paths.

## Filesystem assumptions

The implementation and tests should tolerate platform path separators, temporary directory differences, case sensitivity differences, permission failures, file locking behavior, atomic rename limitations, and cleanup failures. Persistent and encrypted caches must not write outside configured directories. Test fixtures and protocol samples must be opened as byte data where exact wire content matters.

Current Unicode path support is not claimed beyond Ada `String` path handling and platform API behavior tested in the matrix. Unsupported path inputs should fail deterministically or be documented as platform-limited.

## Socket, resolver, and IPv6 assumptions

Default tests must remain deterministic and offline. Loopback tests should allocate ephemeral ports and clean up listeners. IPv4 loopback is expected on fully supported platforms. IPv6 is validated only where enabled by the host and should be skipped explicitly when unavailable; URI parsing support for IPv6 literals is not by itself a claim that every transport/proxy path has validated IPv6 execution.

PAC/WPAD, Alt-Svc, HTTPS/SVCB, proxy, SOCKS, and HTTP/3 discovery behavior remains explicit. The library does not read browser profiles, OS proxy settings, environment proxy variables, DHCP WPAD, public DNS, or live endpoints by default.

## TLS trust stores

HTTPS uses OpenSSL. If OpenSSL defaults are used to locate CA stores, that is OpenSSL/platform behavior and must be documented for the platform. Tests that require certificate validation should use local test CA fixtures and explicit CA configuration. Default offline tests must not depend on the host trust store or public internet endpoints.

Environment variables such as `SSL_CERT_FILE` and `SSL_CERT_DIR` may influence OpenSSL itself. The library should not add hidden behavior around them unless explicitly documented.

## Tasking expectations

Synchronous APIs are the default. Async/task integration is explicit and bounded. Supported platforms must provide an Ada tasking runtime capable of worker creation, cancellation, shutdown, protected shared state, and deterministic finalization in the default tests. Platform runtime limitations should be documented instead of hidden behind broad portability claims.

## CI environments

Required CI jobs should cover the fully supported primary Linux platform. Best-effort macOS and Windows jobs may compile without being release-blocking until they are stable. Optional jobs may validate HTTP/3 backends, live interoperability, benchmark smoke tests, and platform-specific dependency layouts.
