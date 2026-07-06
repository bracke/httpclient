# Interoperability security review checklist

The interoperability campaign validates existing behavior; it must not silently expand browser-like networking or credential behavior.

Checked defaults and risks:

- Live interoperability tests are disabled unless `HTTP_CLIENT_INTEROP_ENABLE` is set.
- Missing live endpoints are skipped rather than treated as hidden dependencies.
- The default AUnit suite remains offline and deterministic.
- TLS certificate and hostname verification remain enabled by default.
- TLS verification-disable behavior remains opt-in and test-only.
- HTTP/3 remains explicit and does not bypass configured HTTP or SOCKS proxies.
- HTTP/3 fallback is allowed only according to explicit fallback policy before request bytes are sent.
- No PAC/WPAD, Alt-Svc, HTTPS/SVCB, preload, service-worker, browser profile, browser cache, or credential-store behavior is introduced.
- No OAuth/OIDC/SAML, NTLM, Negotiate/SPNEGO, Kerberos, OS credential-store, password-manager, hardware-token, or automatic login flow is introduced.
- No SOCKS UDP ASSOCIATE/BIND, MASQUE, CONNECT-UDP, WebTransport, or browser-like proxy discovery is introduced.
- Optional interop output avoids raw credentials, private keys, sensitive cookies, full bodies, and raw secret-bearing diagnostics.
- Basic, Bearer, and mutual-TLS runner checks use only explicitly configured local test credentials and never require production secrets.
- Proxy credentials are proxy-facing only; SOCKS credentials are not serialized as HTTP headers.
- Cross-origin redirect stripping and HTTPS-to-HTTP downgrade blocking remain covered by offline tests.
- Persistent and encrypted cache corruption/tamper tests remain part of Tier 1.
- HPACK/QPACK and diagnostics behavior remains bounded and redacted.
- Async live testing, when configured, should remain low-load and respect endpoint rate limits.

Release-candidate confirmation:

1. `alr build` or equivalent GPR build succeeds.
2. `alr exec -- gprbuild -P tests/tests.gpr` succeeds.
3. `./tests/bin/tests` passes offline.
4. optional interoperability projects, if present, build successfully.
5. Optional Tier 2 local services pass where configured.
6. Optional Tier 3 live endpoints pass or skip cleanly where not configured.
7. Examples still compile.
8. Documentation and compatibility matrix are current.
9. Diagnostics redaction is confirmed for configured live tests.
10. No new public API surface was added solely for test convenience.

Additional completeness-pass checks validate that HTTP/3 required mode still rejects configured HTTP and SOCKS proxies instead of bypassing them or silently falling back through unsupported proxy paths.
