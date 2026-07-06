# 1.0 release checklist

Before tagging the 1.0.0 release:

1. `alr build` succeeds for the library.
2. `alr exec -- gnatprove -P httpclient.gpr --level=4` succeeds for the documented SPARK surface.
3. `cd tests && alr exec -- gprbuild -P tests.gpr` succeeds.
4. `cd tests && ./bin/tests` passes offline.
5. `alr test` passes from the crate root.
6. `cd tests && alr exec -- ../tools/bin/run_aunit_coverage` passes the 100% production Ada source coverage gate.
5. Optional interoperability projects, if present, build successfully; live tests are run only with an explicit opt-in and configured endpoints.
6. Tier 2 local extended and Tier 3 live interoperability results are recorded when used; missing optional endpoints skip cleanly.
7. `alr exec -- gprbuild -P examples/examples.gpr` succeeds.
8. `alr exec -- gprbuild -P tests/api_stability/api_stability.gpr` succeeds.
9. Public `.ads` comments describe ownership, task-safety, defaults, error behavior, and unsupported behavior.
10. README and `docs/` agree about stable versus experimental packages and testing tiers.
11. `DEFAULT_LIMITS.md` matches the default records and constants in the public `.ads` files.
12. HTTP/3 execution remains explicit and never bypasses proxy/SOCKS policy; fallback is policy-bound and before-send only.
13. TLS verification, hostname verification, SNI, redaction, redirect credential stripping, and HTTPS downgrade blocking remain default behavior.
14. Diagnostics and optional interop reports do not print credentials, tokens, cookies, private keys, encrypted-cache keys, or full secret-bearing bodies.
15. Persistent and encrypted cache corruption/tamper tests pass.
16. No test-only helper package is needed by ordinary application code.
17. No PAC/WPAD, browser proxy discovery, Alt-Svc/HTTPS/SVCB discovery, OAuth/OIDC/SAML, NTLM/Negotiate/Kerberos, SOCKS UDP/BIND, MASQUE/CONNECT-UDP, service-worker, or browser-like behavior is introduced.
18. New warnings are reviewed rather than ignored.
19. Run `alr exec -- gprbuild -P tools/tools.gpr && ./tools/bin/check_all` and resolve every reported release-surface drift.
20. Verify `RELEASE_SURFACE_MANIFEST.md` lists every public `.ads` package exactly once in a compatibility class.
21. Before tagging, publish from `httpclient.alire.release.toml` or an equivalent manifest without local `[[pins]]`, and verify the Ada zlib dependency resolves from a published crate that provides `zlib.gpr`.

## Resource-hardening checklist

- Confirm the AUnit suite still compiles and passes.
- Confirm resource-smoke tests pass with counters returning to zero after explicit cleanup.
- Confirm default tests remain offline and deterministic.
- Confirm optional benchmarks are not wired into the default AUnit executable as timing gates.
- Confirm no PAC/WPAD, Alt-Svc, HTTPS/SVCB, OAuth/OIDC/SAML, NTLM/Negotiate/Kerberos, OS credential store, password manager, SOCKS UDP/BIND, MASQUE, CONNECT-UDP, WebTransport, service worker, browser cache/profile, preload, or 0-RTT behavior was introduced.
