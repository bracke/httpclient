# Git smart HTTP Phase 7 — connection pooling pass

Phase 7 wires the previously policy-only connection-pooling surface into the high-level buffered HTTP/1.1 client.

This pass documents real transport-attached connection reuse for the buffered HTTP/1.1 client: when pooling is enabled and a response is fully consumed, the client may retain the actual TCP/TLS transport handle behind the pool key rather than only recording policy-level reuse eligibility.

## Implemented behavior

- Pooling remains disabled by default.
- When `Client_Configuration.Pooling.Enabled` is true, the high-level buffered client suppresses the synthetic `Connection: close` header.
- Clean direct HTTP/1.1 TCP connections may be retained behind the `Client` object and reused for a later request with the same pool key.
- Clean HTTPS/TLS HTTP/1.1 connections may be retained behind the `Client` object and reused for a later request with the same pool key.
- HTTPS-over-CONNECT and HTTPS-over-SOCKS5 use the same TLS handle retention path and retain the origin-specific tunnel only under the strict proxy/TLS/origin pool key.
- Fixed-length responses are reusable only after the complete response body has been read.
- Chunked responses are reusable only after the final chunk and trailers have been consumed by the HTTP/1 reader.
- Close-delimited responses are not reusable.
- Explicit `Connection: close`, `Connection: upgrade`, `Upgrade`, malformed responses, incomplete responses, upload failures, TLS/proxy failures, and read errors retire the connection.
- Pool bounds are enforced by closing evicted idle handles.
- Request headers, cookies, Authorization, Proxy-Authorization, Git headers, request bodies, and response objects are rebuilt per exchange; only the transport handle is retained.

## Streaming status

`Response_Streams.Streaming_Response` still owns and closes its transport handle. Streaming pool check-in remains conservative and policy-mode only in this pass, because safe early-close draining requires additional stream-owned transport handoff work.

## Security boundaries

The pool key separates scheme, origin host and port, proxy mode, proxy endpoint, proxy credential identity, TLS verification mode, CA locations, SNI setting, and client-certificate material identity. Diagnostics and key images must not expose proxy passwords, Authorization values, cookies, bearer tokens, or client private-key contents.

## Completeness pass

The completeness pass tightens the real-pool integration in three places:

- checked-out pooled TCP/TLS handles now preserve and re-check their per-connection request count, so `Max_Requests_Per_Connection` is enforced by the real handle pool rather than only by policy tokens;
- SOCKS5 password values are not retained verbatim in pool keys; the key stores password presence plus an internal, non-logged fingerprint for credential separation;
- pooled check-out/check-in diagnostics are emitted on the buffered real-pool path when a handle is reused or returned;
- the release guard now checks for the Phase 7 documentation, the client-side real release path, request-count preservation, and the credential-fingerprint marker.

Streaming responses remain intentionally outside the real handle pool in this phase. They suppress synthetic `Connection: close` through the client configuration when pooling is enabled, but the stream object still owns and closes its transport handle. Safe streaming drain/check-in remains a later implementation step.
