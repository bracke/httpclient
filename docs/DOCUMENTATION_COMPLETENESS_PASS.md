# Documentation completeness pass

This document records a documentation-only completeness pass over the Phase 15 1.0.0 release tree.

## Scope

The pass checked the documentation surface for:

- broken local Markdown links;
- stale validation commands that referenced tools not present in the release archive;
- public `.ads` packages that were compile-visible but not classified in the public-package, stability, or release-surface documents;
- examples listed in `examples/examples.gpr` but not enumerated in `docs/EXAMPLES.md`;
- documentation index omissions for Phase 15 audit documents;
- stale wording that could imply missing features, hidden Python validators, browser-like behavior, C zlib linkage, or production HTTP/3 support.

## Fixes made

- Corrected local links in packaging/AI guidance so root-level `README.md` and `AGENTS.md` are linked as `../README.md` and `../AGENTS.md` from documents under `docs/`.
- Replaced stale Python validator commands with the Ada release tools actually shipped in `tools/tools.gpr`:
  - `check_release_surface`;
  - `check_aunit_suite`;
  - `check_security_corpus`;
  - `check_git_smart_http_release`.
- Updated installation and CI documentation so Python is not described as a required release-validation dependency for absent tooling.
- Added complete compile-visible package coverage to:
  - `PUBLIC_PACKAGES.md`;
  - `STABLE_API_CONTRACT.md`;
  - `API_STABILITY.md`;
  - `RELEASE_SURFACE_MANIFEST.md`;
  - `GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md`.
- Documented `Http_Client.Proxy_Discovery`, `Http_Client.HTTP3.Body_Streams`, and `Http_Client.Zlib_Decompression` in the appropriate stability classes.
- Added a complete example manifest to `EXAMPLES.md` that mirrors the `Main` list in `examples/examples.gpr`.
- Added this document and the Phase 15 static audit summary to `DOCUMENTATION_INDEX.md`.

## Explicit remaining limitations

This pass did not claim to run `alr`, `gprbuild`, AUnit, or the Ada release tools because the audit environment did not provide the Ada toolchain. The authoritative verification remains the command set in `RELEASE_VERIFICATION.md` and `GIT_SMART_HTTP_FINAL_AUDIT_PASS.md`.

HTTP/3 documentation remains intentionally conservative: HTTP/3 execution is experimental/backend-dependent, forced HTTP/3 must not silently fall back, and no production QUIC backend is implied by the release archive.

The crate still deliberately avoids browser behavior: no implicit browser profile import, environment proxy use, PAC/WPAD auto-discovery, OS credential-store integration, OAuth/OIDC/SAML/NTLM/Negotiate/Kerberos workflows, service workers, MASQUE, CONNECT-UDP, WebTransport, or hidden policy changes.

## Documentation checks performed in this pass

Static checks in this environment confirmed:

- no remaining live validation-command references to absent Python checker scripts in `docs/`, `README.md`, or `.github/`;
- all local Markdown links from `README.md` and all Markdown files under `docs/` resolve to existing files after path normalization;
- every `src/*.ads` package declaration is mentioned in the release-surface/stability documentation set;
- every `examples/examples.gpr` main is listed in the complete example manifest;
- the documentation index references the Phase 15 documentation-completeness and static-audit summaries.
