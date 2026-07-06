# Git smart HTTP HTTPS CONNECT streaming pass

This pass implements HTTPS over an explicit HTTP proxy for the HTTP/1.1 buffered and streaming execution paths.

## Transport behavior

`Http_Client.Transports.TLS.Open_Through_HTTP_Proxy` opens a TCP connection to the configured HTTP proxy, sends an HTTP/1.1 `CONNECT host:port` request, optionally includes the proxy configuration's `Proxy-Authorization` value, accepts only a 2xx CONNECT response, and then performs the normal origin TLS handshake inside the tunnel.

The function returns deterministic statuses: proxy TCP open failures are reported as `Proxy_Connection_Failed`, a `407` CONNECT response as `Proxy_Authentication_Required`, malformed or non-2xx CONNECT responses as `Proxy_Tunnel_Failed`, and origin TLS failures through the existing TLS status model.

## Git relevance

`Response_Streams.Open` no longer rejects HTTPS requests with an HTTP proxy. It uses CONNECT first, then sends Git request headers and binary bodies only inside the TLS stream. Buffered `Execute` uses the same transport boundary.

## Credential boundary

Proxy credentials are sent only to the proxy during CONNECT. Origin credentials, cookies, Git protocol headers, request bodies, and optional mTLS client certificates are not sent until after CONNECT succeeds and the TLS handshake is running against the origin authority.

## Remaining limitation

SOCKS plus HTTPS streaming is covered by `GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md`. HTTP/3 through proxies remains explicitly unsupported by the existing HTTP/3 policy.

## Follow-up completeness coverage

See `GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_COMPLETENESS_PASS.md` for the follow-up routing audit and streaming unreachable-proxy AUnit coverage.


## CONNECT tunnel fixture pass

The streaming test suite now includes `Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT`.
The local fixture returns `200 Connection Established` and then closes before TLS,
so the expected client result is a TLS handshake failure rather than a proxy
failure. The test verifies CONNECT request formation, proxy-authorization
scoping, absence of origin-header leakage before TLS, and transition from the
proxy tunnel boundary into the TLS layer.
