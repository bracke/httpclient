# Protocol discovery: Alt-Svc and HTTPS/SVCB

The current release adds explicit, bounded protocol-discovery facilities for callers that want to discover HTTP/3 alternatives using standards-based metadata. Discovery is disabled by default. Enabling HTTP/3 itself is still separate from enabling discovery.

Public packages:

- `Http_Client.Alt_Svc` parses conservative HTTP Alt-Svc field values, including supported `h3` alternatives, quoted authorities, `ma`, `persist`, multiple alternatives, and `clear`.
- `Http_Client.DNS_SVCB` models and parses deterministic scripted HTTPS/SVCB service records for tests and resolver backends.
- `Http_Client.HTTPS_Records` provides HTTPS-record parsing and selection helpers for deterministic scripted records.
- `Http_Client.Protocol_Discovery` owns the opt-in policy, bounded in-memory Alt-Svc cache, HTTPS/SVCB resolver hook, proxy limitation, fallback decision, and selected alternative endpoint metadata.

The implementation is intentionally not browser-like networking. It does not implement PAC/WPAD, browser proxy discovery, browser profiles, service workers, preload lists, server push caches, OAuth/OIDC/SAML token acquisition, NTLM/Negotiate/Kerberos workflows, OS credential stores, password-manager integration, SOCKS UDP ASSOCIATE/BIND, MASQUE, CONNECT-UDP, WebTransport, 0-RTT, DNSSEC validation, ECH, or privacy-preserving DNS.

## Security rules

Alt-Svc metadata is accepted only when policy enables it. The conservative acceptance path requires a successfully verified HTTPS network response. A cached HTTP response containing an Alt-Svc header must not refresh discovery state by default.

An alternative service is still a service for the original origin. TLS or QUIC verification must validate the original origin name, not merely the alternative host name. Cookies, Authorization, client-certificate selection, and HTTP cache keys remain scoped to the original origin. Proxy credentials and SOCKS credentials are never used for alternative services.

Configured HTTP or SOCKS proxies suppress discovery in the current implementation. The client must not bypass proxies to open direct QUIC to an alternative endpoint. UDP proxying, MASQUE, CONNECT-UDP, and SOCKS UDP behavior are outside this implementation scope.

Fallback from a discovered HTTP/3 alternative is governed by `Discovery_Fallback_Policy`. `Discovery_Fallback_Before_Send` permits fallback only before request headers or body bytes have been sent. After transmission, existing retry and replayability rules remain authoritative.

## Cache and async behavior

Discovery metadata is separate from HTTP response cache metadata. Persistent and encrypted response caches do not store Alt-Svc or HTTPS/SVCB state. The in-memory discovery cache is caller-owned and bounded by entry count, alternatives per origin, header length, and maximum age.

The discovery cache is not internally synchronized. Async clients that share discovery state must serialize access through their owning client or an external lock. Discovery creates no background refresh tasks; lookup and mutation occur only during explicit request execution or explicit cache-management calls.

## DNS limitations

`DNS_SVCB` and `HTTPS_Records` provide deterministic parsing and resolver abstraction. They do not make public DNS queries in default tests and do not require platform-specific DNS APIs for ordinary builds. If no resolver is configured, HTTPS/SVCB discovery returns deterministic unsupported/no-selection behavior according to the configured protocol policy.

`ipv4hint` and `ipv6hint` are modeled as hints only. ECH is recognized as unsupported metadata and is not used. HTTPS/SVCB records can influence protocol discovery, target name, and port selection, but they never replace TLS authority validation for the original origin.
