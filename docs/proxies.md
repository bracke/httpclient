# Proxies

Proxy routing is explicit. `Http_Client.Proxies` configures direct connections, HTTP proxies, and SOCKS5 proxies. SOCKS username/password credentials are scoped to SOCKS negotiation and are not serialized as HTTP proxy credentials.

There is no automatic environment proxy import, PAC, WPAD, browser proxy discovery, browser-profile import, Tor control behavior, SOCKS UDP ASSOCIATE, SOCKS BIND, MASQUE, or CONNECT-UDP support in this release. HTTP/3 and protocol discovery do not bypass configured proxies; unsupported proxy/protocol combinations fail before request bytes are sent.


## HTTPS over HTTP proxy CONNECT

Buffered and streaming HTTP/1.1 HTTPS requests support explicit HTTP proxy CONNECT. The client opens the proxy connection, sends a bounded CONNECT request for the origin authority, maps proxy connection failures to `Proxy_Connection_Failed`, maps `407` to `Proxy_Authentication_Required`, maps other non-2xx or malformed CONNECT responses to `Proxy_Tunnel_Failed`, and only then starts origin TLS verification inside the tunnel. Proxy credentials are never serialized inside the origin TLS stream.


## HTTPS over SOCKS5 proxy

Buffered and streaming HTTP/1.1 HTTPS requests support explicit SOCKS5 proxy tunneling. The client opens the SOCKS proxy connection, performs SOCKS5 CONNECT to the origin authority according to the configured DNS policy, maps proxy TCP failures to `Proxy_Connection_Failed`, returns deterministic `SOCKS_*` statuses for negotiation failures, and only then starts origin TLS verification inside the SOCKS tunnel. SOCKS username/password credentials are used only in the SOCKS negotiation and are never serialized as HTTP headers. Origin Authorization, Cookie, Git headers, request bodies, and client certificates are sent only after the tunnel and TLS handshake are established.


## Direct TLS baseline before proxy tunnels

The direct loopback HTTPS fixture is the baseline for later HTTPS-over-CONNECT and HTTPS-over-SOCKS end-to-end fixtures. Proxy tests should reuse the same origin behavior so that certificate verification, hostname verification, SNI policy where observable, binary response streaming, chunked upload, trailers, and `Expect: 100-continue` are validated inside the tunnel rather than by disabling TLS verification.

## HTTPS over HTTP CONNECT end-to-end fixture

HTTPS requests through an explicit HTTP proxy use `CONNECT` before any origin request headers or bodies are serialized. TLS starts only after a successful `HTTP/1.1 200 Connection Established` response from the proxy. Certificate validation remains enabled by default; positive CONNECT/TLS tests use the configured local test CA and do not use unsafe verification disable. Hostname verification and SNI use the origin hostname, not the proxy hostname.

Proxy credentials are serialized only as `Proxy-Authorization` on the CONNECT request. Origin `Authorization`, `Cookie`, `Git-Protocol`, Git `Content-Type`, request bodies, request trailers, and client-certificate material are sent only inside the established TLS tunnel. The origin request must not receive `Proxy-Authorization` or proxy-only headers.

The Phase 5 fixture coverage exercises buffered responses, byte-array streaming responses, chunked response decoding, buffered binary POST, proxy credential isolation, origin credential/header/body isolation, and deterministic failures for 407, 403, 502, malformed CONNECT responses, tunnel close during TLS, and origin hostname verification failure. SOCKS5 end-to-end coverage remains the next proxy fixture phase.

## HTTPS over SOCKS5 end-to-end fixture

HTTPS requests through an explicit SOCKS5 proxy use SOCKS5 greeting/authentication and SOCKS CONNECT before any origin HTTP request headers or bodies are serialized. TLS starts only after a successful SOCKS CONNECT reply. Certificate validation remains enabled by default; positive SOCKS5/TLS tests use the configured local test CA and do not use unsafe verification disable. Hostname verification and SNI use the origin hostname, not the SOCKS proxy hostname.

SOCKS credentials are serialized only as RFC 1929 username/password authentication bytes. Origin `Authorization`, `Cookie`, `Git-Protocol`, Git `Content-Type`, request bodies, request trailers, request path/query, and client-certificate material are sent only inside the established TLS tunnel. The origin request must not receive SOCKS username/password credentials.

The Phase 6 fixture coverage exercises no-auth and username/password SOCKS5 success, configured-CA TLS success through SOCKS5, byte-array streaming responses, chunked response decoding, buffered binary POST, SOCKS credential isolation, origin credential/header/body isolation, origin-host SNI, certificate and hostname failures after SOCKS CONNECT, and deterministic SOCKS authentication/CONNECT/malformed-reply failures.


### HTTPS-over-SOCKS5 Phase 6 completeness pass coverage

Phase 6 includes deterministic local SOCKS5-over-TLS tests for no-auth and username/password negotiation, configured-CA validation, origin-host SNI/hostname verification, credential/header/body isolation before tunnel establishment, byte-array streaming, chunked response decoding, buffered POST, fixed-length streaming upload, unknown-length chunked upload, request trailers, `Expect: 100-continue`, and negative SOCKS/TLS failures. The SOCKS proxy fixture records only SOCKS greeting/auth/CONNECT bytes before tunnel success; origin `Authorization`, cookies, Git headers, request bodies, paths, trailers, and Expect headers are asserted to remain inside the TLS tunnel.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.

## HTTP/3 boundary

HTTP/3 does not bypass explicit proxy configuration. With an HTTP proxy or SOCKS5 proxy configured, forced HTTP/3 fails deterministically with `HTTP3_Proxy_Unsupported` unless a future proxy-compatible HTTP/3 route is explicitly implemented and documented. Preferred HTTP/3 may fall back only before request bytes are sent, and the fallback HTTP/1.1 or HTTP/2 request continues to use the configured proxy route.
