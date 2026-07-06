# Configuration guide

`Http_Client.Clients.Default_Client_Configuration` is the ergonomic high-level client default. Network execution is direct, safe redirects are enabled, HTTPS-to-HTTP downgrade redirects are blocked, cross-origin credentials are stripped, bounded final-response decompression is enabled, retries are disabled, cookies are absent unless a jar is supplied, caches are disabled, persistent caches are absent unless a store is opened and supplied, proxies are disabled, SOCKS is disabled, diagnostics are silent, pooling is disabled, async execution requires explicit async objects, and HTTP/3 is disabled.

Use `Http_Client.Clients.Strict_Client_Configuration` when exact protocol behavior is required. Strict mode disables automatic redirects and disables the decoded response view while retaining the same verified TLS and explicit opt-in posture for retries, cookies, caches, proxies, diagnostics, pooling, discovery, and HTTP/3.

`Execution_Options` controls per-exchange limits, read buffers, TCP timeout intent, TLS behavior, cookie jar usage, decompression advertisement, proxy routing, and diagnostics. `Client_Configuration` composes execution options with redirects, retries, default headers, decompression, pooling, cache stores, persistent cache stores, and HTTP/3 intent.

Do not use default headers for broad credentials or framing fields. The client rejects Authorization, Proxy-Authorization, Cookie, Host, Content-Length, Transfer-Encoding, Connection, Proxy-Connection, and related hop-by-hop fields as reusable defaults. Attach origin credentials to the specific request that needs them.

Timeout fields express intent. Some socket/OpenSSL paths may be best-effort depending on platform APIs. Tests should use loopback/scripted transports rather than long wall-clock waits.

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

