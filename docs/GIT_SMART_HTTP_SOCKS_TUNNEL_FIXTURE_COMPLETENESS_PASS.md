# Git smart HTTP SOCKS tunnel fixture completeness pass

This pass adds a deterministic offline streaming fixture for HTTPS over SOCKS5.

## Test added

`Test_Response_Stream_HTTPS_SOCKS_Tunnel_Handshake_Shape`

The fixture starts a local SOCKS5 server, configures a streaming HTTPS Git-style
request through that proxy, and verifies the following protocol boundary before
origin TLS begins:

* the client connects to the configured SOCKS5 proxy;
* the client offers only the configured username/password SOCKS5 method;
* the username/password credentials are serialized only in the SOCKS
  authentication exchange;
* the SOCKS CONNECT request targets `example.com:443` using remote-DNS domain
  encoding;
* origin HTTP request material is not sent during SOCKS negotiation:
  `Git-Protocol`, origin `Authorization`, `Cookie`, `GET`, and `POST` are not
  present in the observed SOCKS handshake bytes;
* after a successful SOCKS CONNECT reply, the client transitions to the origin
  TLS layer and returns a TLS failure when the fixture closes before completing
  TLS.

This complements the existing unreachable-proxy routing test. Together they
prove that the streaming HTTPS-over-SOCKS path uses the configured SOCKS proxy,
performs SOCKS negotiation before TLS, scopes SOCKS credentials to SOCKS only,
and does not leak origin headers or Git metadata before TLS.

## Remaining verification boundary

The fixture intentionally closes before completing TLS because the sandbox does
not provide the Ada build/test environment or local certificate harness needed
for a full successful TLS exchange. A later environment with GNAT/GPRbuild and
local test certificates should add a full SOCKS5 + TLS + Git-like streamed body
fixture if release policy requires end-to-end proxy TLS success coverage.
