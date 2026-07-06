# Git smart HTTP HTTPS-over-SOCKS streaming pass

This pass adds HTTPS-over-SOCKS5 support to the Git smart HTTP HTTP/1.1 execution path.

## Implemented behavior

* `Http_Client.Transports.TLS.Open_Through_SOCKS_Proxy` connects to the configured SOCKS5 proxy, performs SOCKS CONNECT to the origin host and port, then starts the normal OpenSSL TLS handshake inside the tunnel.
* Buffered `Http_Client.Clients.Execute` chooses SOCKS tunneling for HTTPS requests when `Execution_Options.Proxy` is a SOCKS5 proxy.
* Streaming `Http_Client.Response_Streams.Open` chooses the same SOCKS/TLS path for HTTPS streaming responses, so Git upload-pack and receive-pack responses can be read incrementally through SOCKS.
* SOCKS username/password credentials are used only in the SOCKS negotiation and are not serialized as HTTP headers.
* Origin `Authorization`, `Cookie`, Git protocol headers, request bodies, and mutual-TLS client certificates are sent only after the SOCKS tunnel exists and TLS has started to the origin.
* SOCKS negotiation failures return deterministic `SOCKS_*` statuses. Failure to connect to the SOCKS proxy is normalized to `Proxy_Connection_Failed`.

## Still outside scope

SOCKS UDP ASSOCIATE, SOCKS BIND, SOCKS4, SOCKS4a, Tor control behavior, MASQUE, CONNECT-UDP, and HTTP/3-through-proxy execution remain unsupported.

## Coverage

The AUnit suite now includes buffered and streaming routing tests that configure an HTTPS request with an unreachable SOCKS5 proxy and assert that the SOCKS proxy is attempted instead of a direct origin connection. A deterministic SOCKS tunnel-shape fixture now validates successful SOCKS negotiation through the CONNECT reply and transition to the TLS layer; full local TLS completion remains a later build-environment fixture.
