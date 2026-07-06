# Git smart HTTP HTTPS-over-SOCKS streaming completeness pass

This pass audits the HTTPS-over-SOCKS5 implementation added for the Git smart HTTP HTTP/1.1 path and removes stale documentation that still described HTTPS-over-SOCKS as unsupported.

## Confirmed behavior

* Buffered `Http_Client.Clients.Execute` routes `https://` requests through `Http_Client.Transports.TLS.Open_Through_SOCKS_Proxy` when `Execution_Options.Proxy` is an explicit SOCKS5 proxy.
* Streaming `Http_Client.Response_Streams.Open` routes `https://` requests through the same SOCKS-then-TLS transport path.
* The SOCKS connection is established before the origin TLS handshake.
* SOCKS username/password credentials are scoped to SOCKS negotiation only.
* Origin `Authorization`, `Cookie`, Git protocol headers, request bodies, and mutual-TLS client certificates are sent only after SOCKS negotiation and origin TLS handshake have succeeded.
* Plain HTTP through SOCKS continues to serialize origin-form HTTP requests through the SOCKS tunnel.
* HTTP proxy CONNECT and SOCKS proxy routing remain separate paths; proxy credentials are not cross-applied.
* SOCKS TCP connection failure is normalized to `Proxy_Connection_Failed`; SOCKS negotiation failures use deterministic `SOCKS_*` statuses.

## Documentation cleanup

The `Execution_Options.Proxy` public comment in `src/http_client-clients.ads` now states that HTTPS-over-SOCKS5 is supported for the HTTP/1.1 buffered and streaming paths instead of describing it as a future transport bridge.

## Coverage status

The offline AUnit suite contains buffered and streaming routing tests that configure an unreachable SOCKS5 proxy and assert that the SOCKS proxy path is attempted. A SOCKS5 tunnel-shape fixture now validates successful SOCKS negotiation through the CONNECT reply and transition to TLS. Full SOCKS5 plus completed local TLS remains recommended for an environment with GNAT/GPRbuild and local certificate fixtures; the OpenSSL C bridge compiles cleanly with `gcc -fsyntax-only -Wall -Wextra` in this sandbox.

## Remaining limitations

SOCKS UDP ASSOCIATE, SOCKS BIND, SOCKS4, SOCKS4a, Tor control behavior, MASQUE, CONNECT-UDP, and HTTP/3-through-proxy execution remain unsupported. These are outside the Git smart HTTP HTTP/1.1 transport contract.
