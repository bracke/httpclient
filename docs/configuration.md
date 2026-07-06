# Configuration

Configuration is caller-owned and explicit. The default high-level client configuration is ergonomic but still bounded: TLS certificate and hostname verification are enabled; safe redirects are followed; HTTPS-to-HTTP downgrade redirects remain blocked; cross-origin credentials are stripped; bounded final-response decompression is enabled; retries, cookies, proxies, SOCKS, caching, persistent caching, encrypted caching, diagnostics, pooling, async execution, HTTP/3, Alt-Svc, and HTTPS/SVCB discovery are disabled until the caller configures them.

Use `Http_Client.Clients.Strict_Client_Configuration` for exact no-redirect/no-transform behavior, including Git smart HTTP packet/packfile paths and byte-exact fixtures.

## Main configuration areas

Use `Http_Client.Clients.Client_Configuration` for high-level client behavior. Related stable packages own specialized records: `Http_Client.Transports.TLS` for TLS verification and connection options, `Http_Client.TLS.Client_Certificates` for mTLS credentials, `Http_Client.Retry` for retry policy, `Http_Client.Proxies` and `Http_Client.Proxies.SOCKS` for explicit proxy routing, `Http_Client.Cookies` for caller-owned cookie jars, `Http_Client.Decompression` for decoded bodies, `Http_Client.Cache` and `Http_Client.Cache.Persistent` for cache stores, `Http_Client.Diagnostics` for observers, `Http_Client.Response_Streams` for streaming limits, `Http_Client.Request_Bodies` and `Http_Client.Multipart` for uploads, `Http_Client.HTTP2` for HTTP/2 policy, `Http_Client.HTTP3` for experimental HTTP/3 policy, and `Http_Client.Protocol_Discovery` for explicit Alt-Svc/HTTPS/SVCB selection.

## Conflicts

Conflicting options must be rejected deterministically with a documented status. Examples include insecure TLS combinations not deliberately requested, invalid redirect limits, unsupported proxy/protocol combinations, HTTP/3 through configured proxies, non-replayable request bodies with retry or redirect replay, cache stores without enabled cache policy, and invalid resource-limit relationships.

## No global policy

The 1.0.0 configuration model does not introduce a global default client, global cookie jar, global cache, global proxy discovery policy, global diagnostics observer, global async worker pool, global Alt-Svc cache, or global HTTP/3 discovery state. Prefer explicit caller-owned objects.
