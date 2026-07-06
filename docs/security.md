# Security

The security model is conservative and explicit. TLS certificate-chain verification and hostname verification are enabled by default for HTTPS. SNI is enabled for suitable DNS names. Unsafe TLS modes require explicit configuration and are not shown as normal examples.

## Sensitive data

Diagnostics redact secrets by default. Authorization headers, Proxy-Authorization headers, cookies, client-certificate material, TLS secrets, QUIC secrets, encryption keys, passwords, and request/response bodies must not be emitted by default diagnostic events. Program control should use `Http_Client.Errors.Result_Status` and structured fields, not diagnostic message strings.

## Redirects, retries, and credentials

The high-level default client follows bounded safe redirects; retries remain disabled by default. HTTPS-to-HTTP downgrade redirects are blocked by default. Sensitive headers are stripped across cross-origin redirects. Use `Strict_Client_Configuration` for no-follow behavior. Retries are bounded and apply only to safe or explicitly replayable requests according to retry policy.

## Caches

Caches are disabled by default and caller-owned. Authenticated or client-certificate-sensitive responses are bypassed unless the documented cache policy allows safe storage. Persistent and encrypted cache directories are application-managed. If a cache file format is not marked stable, applications should be prepared to clear the directory across incompatible releases.

## Proxies and discovery

Only explicit direct, HTTP proxy, and SOCKS5 routing are supported. PAC, WPAD, browser proxy discovery, browser profiles, browser cache integration, service workers, browser preload behavior, MASQUE, CONNECT-UDP, SOCKS UDP ASSOCIATE/BIND, and Tor control behavior are not implemented. Alt-Svc and HTTPS/SVCB discovery are disabled by default, bounded, caller-controlled, and do not bypass configured proxies.

## Authentication scope

Authentication helpers attach caller-supplied Basic, Bearer, Digest, proxy, or client-certificate credentials. They do not acquire or refresh OAuth/OIDC/SAML tokens, perform NTLM/Negotiate/SPNEGO/Kerberos, query OS credential stores, integrate password managers, prompt users, or automate browser login flows.

## HTTP/3 and QUIC

HTTP/3 is experimental and backend-dependent. Unsupported HTTP/3 fails before request bytes are sent or falls back only under an explicit before-send fallback policy. The 1.0.0 API does not implement 0-RTT, server push cache, WebTransport, MASQUE, CONNECT-UDP, or proxy-bypassing QUIC.

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

