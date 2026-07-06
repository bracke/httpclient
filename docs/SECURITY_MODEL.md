# Security model

TLS certificate and hostname verification are enabled by default. Disabling certificate verification is an explicitly unsafe TLS option intended only for controlled development and tests. SNI is enabled for DNS-style hosts, and ALPN policy is configured explicitly through TLS/HTTP2 options.

Credentials are explicit caller input. The library provides helpers for Basic, Bearer, Digest, proxy, SOCKS, cookie, and client-certificate use, but it does not acquire OAuth tokens, refresh tokens, use OS credential stores, talk to password managers, automate login flows, or integrate with browser profiles.

Diagnostics are opt-in. Default redaction must hide Authorization, Proxy-Authorization, Cookie, Set-Cookie, Bearer tokens, Digest material, SOCKS credentials, client-certificate/private-key metadata, encrypted cache keys, and other obvious secrets. Diagnostic message text is for humans and must not be used for program control.

The high-level default client follows bounded safe redirects. HTTPS-to-HTTP downgrades are blocked by default and sensitive headers are stripped on cross-origin redirects. Use `Strict_Client_Configuration` for no-follow behavior.

Caches are disabled by default. Conservative cache policy bypasses requests/responses with credentials or Set-Cookie unless the caller deliberately changes policy. Persistent cache directories and encrypted cache files are implementation-owned storage; callers should not store secrets in URLs or headers and should be prepared to clear cache directories across incompatible pre-release builds unless a format is documented as stable.

SOCKS routes TCP connections through an explicit proxy configuration. It is not an anonymity system, does not implement UDP ASSOCIATE or BIND, and has no Tor control integration.

HTTP/3 and QUIC APIs are experimental foundations only in this release. They must fail deterministically rather than bypassing proxy, credential, TLS, cache, or diagnostics policy.

The security/fuzzing campaign adds a focused security review and deterministic fuzzing campaign. The detailed threat model, hostile-input corpus rules, manual checklist, and reporting guidance are maintained in `security.md`. That campaign is hardening infrastructure only: it does not add PAC/WPAD discovery, Alt-Svc discovery, HTTPS/SVCB discovery, browser cache/profile behavior, service workers, OAuth/OIDC/SAML/NTLM/Negotiate/Kerberos workflows, OS credential stores, password-manager integration, SOCKS UDP/BIND, MASQUE, CONNECT-UDP, WebTransport, or browser-like networking policy.

## IPv6 literal URLs

HTTP and HTTPS URLs may use IPv6 address literals in the standard bracketed authority form:

```ada
Status := Http_Client.Clients.Get
  ("http://[::1]:8080/",
   Result);
```

Support matrix:

| Host form | Status | Notes |
| --- | --- | --- |
| DNS hostnames | Supported | Normal DNS name parsing and TLS DNS-name verification apply. |
| IPv4 literals | Supported | TLS requires a matching IPv4 IP subjectAltName for HTTPS. |
| IPv6 literals | Supported in bracketed URI form, such as `http://[::1]/`. | Socket/TLS code receives the unbracketed address internally; emitted URI authorities and Host headers remain bracketed. |
| IPv6 zone identifiers | Unsupported | Scoped forms such as `http://[fe80::1%25lo0]/` fail deterministically. |
| h2c | Unsupported | Plain HTTP/2 cleartext upgrade remains out of scope. |

HTTPS to an IPv6 literal keeps certificate verification enabled. The certificate must contain a matching IPv6 IP subjectAltName; DNS-only certificates fail hostname/IP verification.

