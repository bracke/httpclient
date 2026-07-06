# Phase 16 TLS Fixture Completeness Recheck

This pass tightens the Ada-only TLS fixture stabilization package after the
direct TLS readiness recheck.

## Scope

No product HTTP behavior was added.  The pass is limited to release-candidate
fixture, test, and source-package hygiene:

- keep direct TLS, CONNECT-over-TLS, and SOCKS5-over-TLS fixture control in Ada;
- keep runtime TLS fixture path resolution inside subprogram bodies;
- avoid package-body elaboration-time helper calls for fixture paths;
- avoid starting unused TLS origin fixtures for CONNECT proxy failures that
  terminate before the tunnel can reach origin TLS;
- make CONNECT/SOCKS close-during-TLS fixtures send a successful proxy reply and
  close the client side without connecting to an origin server;
- remove the obsolete C zlib bridge source from the package;
- remove generated Alire/build state from the source artifact.

## CONNECT/TLS fixture path cleanup

`Http_Client.Connect_TLS_Tests` now mirrors the runtime path discipline already
used by the direct TLS and SOCKS5 TLS suites.  Certificate and key package-level
constants are leaf names only.  Runtime path resolution happens inside helper
subprogram bodies immediately before the Ada TLS fixture is started or client
TLS options are constructed.

The CONNECT proxy-status tests for close-before-response, 407, 403, 502,
malformed response, and close-during-TLS now use an unused loopback origin port
instead of starting a TLS origin fixture that the proxy mode should never reach.

## Ada proxy close-during-TLS behavior

The Ada CONNECT fixture now handles `CONNECT_Close_During_TLS` by sending a
successful `200 Connection Established` response and closing the tunnel without
connecting to origin.  The Ada SOCKS5 fixture now handles
`SOCKS_Close_During_TLS` by sending a successful SOCKS5 connect reply and closing
without connecting to origin.

This keeps the failure point deterministic at the client TLS continuation rather
than depending on an unnecessary origin server.

## Package hygiene

The package no longer includes `src/c/http_client_zlib_bridge.c`.  Compression
remains routed through the Ada `Zlib` dependency and the isolated
`Http_Client.Zlib_Decompression` adapter.  The only project-owned C sources left
under `src/c` are the allowed production OpenSSL bridge files.

Generated Alire state directories were removed from the source package.  The
package remains a source artifact rather than a build workspace snapshot.
