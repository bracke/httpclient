# Phase 16 Response Streams No TLS Continuation Hang Pass

This pass keeps `Http_Client.Response_Streams.Tests` from blocking the AUnit
report by bounding live streaming transport paths and avoiding unnecessary TLS
continuation in proxy request-shape tests.

Changes:

- Added bounded streaming TCP/TLS timeout intent to live response-stream network
  tests.
- The CONNECT request-shape test now returns a deterministic non-2xx CONNECT
  response after observing the CONNECT request, so it validates proxy privacy
  without entering a long origin TLS continuation path.
- The SOCKS request-shape test now returns a deterministic SOCKS CONNECT
  failure reply after observing the SOCKS greeting/auth/connect bytes, so it
  validates proxy privacy without entering a long origin TLS continuation path.
- No warnings are suppressed.
