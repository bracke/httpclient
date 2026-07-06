# Git smart HTTP HTTPS CONNECT streaming completeness pass

This pass audits the HTTPS-over-HTTP-proxy CONNECT implementation added for the
HTTP/1.1 buffered and streaming Git smart HTTP paths.

## Confirmed behavior

* Buffered `Execute` uses `Http_Client.Transports.TLS.Open_Through_HTTP_Proxy`
  for `https://` requests when an explicit HTTP proxy is configured.
* `Response_Streams.Open` uses the same CONNECT-first TLS transport for
  streaming `https://` requests through an explicit HTTP proxy.
* The ordinary request line inside the TLS tunnel remains origin-form; absolute
  request targets and `Proxy-Authorization` are used only for cleartext HTTP
  proxy requests, not for tunneled HTTPS origins.
* Proxy credentials configured on the proxy object are serialized only on the
  CONNECT request. Origin headers, cookies, Git protocol headers, request
  bodies, and optional client certificates are withheld until CONNECT succeeds
  and the origin TLS handshake starts inside the tunnel.
* Proxy TCP failures map to `Proxy_Connection_Failed`; `407` maps to
  `Proxy_Authentication_Required`; malformed or non-2xx CONNECT responses map
  to `Proxy_Tunnel_Failed`; origin TLS failures retain the existing TLS and
  certificate status model.

## Added coverage

`Http_Client.Response_Streams.Tests` now includes
`Test_Response_Stream_HTTPS_Proxy_CONNECT_Attempts_Proxy`. The test configures a
streaming HTTPS Git-style request through an unreachable HTTP proxy and verifies
that `Response_Streams.Open` attempts the proxy path and returns
`Proxy_Connection_Failed`, rather than rejecting HTTPS proxy streaming as
unsupported or attempting a direct origin connection.

The existing buffered proxy test remains in `Http_Client.Proxies.Tests` and
checks the same unreachable-proxy status for `Clients.Execute`.

## Remaining explicit limits

This pass does not add a live TLS proxy fixture because the normal offline AUnit
suite has no local CA/proxy TLS fixture in this tree. The CONNECT success path is
therefore covered at the transport boundary by code review and compile-targeted
examples, while the deterministic failure-path routing is covered by AUnit.

SOCKS plus HTTPS streaming is covered by `GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md`. HTTP/3 through proxies
continues to be rejected by the existing HTTP/3 policy rather than bypassing the
configured proxy.


## CONNECT tunnel fixture pass

The streaming test suite now includes `Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT`.
The local fixture returns `200 Connection Established` and then closes before TLS,
so the expected client result is a TLS handshake failure rather than a proxy
failure. The test verifies CONNECT request formation, proxy-authorization
scoping, absence of origin-header leakage before TLS, and transition from the
proxy tunnel boundary into the TLS layer.
