# AI agent orientation for `http_client`

This repository is an Ada 2022 Alire crate named `http_client`. It provides an explicit HTTP client library, not an application, command-line tool, browser integration layer, or credential manager.

## Fast identification

- Crate name: `http_client`
- Main library project: `httpclient.gpr`
- Alire manifest: `alire.toml`
- Root Ada package: `Http_Client` in `src/http_client.ads`
- High-level client package: `Http_Client.Clients`
- Public package map: `docs/PUBLIC_PACKAGES.md`
- API stability policy: `docs/API_STABILITY.md` and `docs/STABLE_API_CONTRACT.md`
- Examples project: `examples/examples.gpr`
- Main offline test project: `tests/tests.gpr`

## Default orientation for code changes

Preserve the public semantics documented for phases 0 through 41. Phase 41 is platform packaging validation only; do not add protocol features or browser-like behavior while working in this area.

Prefer small, deterministic changes with tests or offline validators. The default test suite must remain offline and must not require public internet, public DNS, live proxies, live HTTP/3 endpoints, private credentials, browser profiles, OS credential stores, or host proxy settings.

## Public entry points to use first

For application code, start with these stable packages:

- `Http_Client.Clients` for high-level buffered and streaming client usage.
- `Http_Client.URI` for absolute HTTP/HTTPS URI parsing.
- `Http_Client.Headers`, `Http_Client.Requests`, and `Http_Client.Responses` for low-level request/response modeling.
- `Http_Client.Errors` for program-control status values.
- `Http_Client.Proxies` and `Http_Client.Proxies.SOCKS` for explicit proxy configuration.
- `Http_Client.Proxy_Discovery` only for explicit bounded PAC/WPAD helpers.
- `Http_Client.Protocol_Discovery`, `Http_Client.Alt_Svc`, `Http_Client.DNS_SVCB`, and `Http_Client.HTTPS_Records` only for explicit protocol discovery.

HTTP/3 and QUIC packages are experimental and optional. Missing QUIC support must produce deterministic unsupported statuses rather than implicit fallback after unsafe transmission.

## Build and validation commands

The repository enforces GNAT 15 through Alire with `gnat_native = "=15.2.1"` in
each active crate manifest. Do not run plain system GNAT, GPRBuild, GNATprove,
GNATdoc, or related `gnat*` tools from `PATH`; run compiler, builder, prover,
and documentation tools through `alr exec --`.

Before building or testing, verify:

```sh
alr exec -- gnatls --version
```

The command must report `GNATLS 15.x`.

Typical local checks:

```sh
alr exec -- gprbuild -P httpclient.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
```

Offline release-surface, suite, and security-corpus checks:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
./tools/bin/check_git_smart_http_release
```

The coverage gate is an Ada tool that drives GNAT/gcov tooling:

```sh
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

## Non-goals to preserve

Do not introduce hidden environment proxy use, browser/profile integration, service workers, server push cache behavior, browser preload behavior, OAuth/OIDC/SAML token workflows, NTLM/Negotiate/Kerberos workflows, OS credential stores, password manager integration, SOCKS UDP ASSOCIATE/BIND, MASQUE, CONNECT-UDP, WebTransport, or Tor control behavior unless a later explicitly scoped phase adds them.

## Documentation map for assistants

Use `llms.txt` for the shortest AI-facing project map. Use `docs/AI_USAGE_GUIDE.md` when trying to understand how to consume the library from a fresh checkout. Use `docs/DOCUMENTATION_INDEX.md` for the full documentation map and `docs/EXAMPLES.md` for compile-oriented examples.
