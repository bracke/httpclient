# HTTP/2 guide

HTTP/2 is opt-in through configuration and ALPN policy. `HTTP2_Disabled` preserves HTTP/1.1-only behavior. `HTTP2_Allowed` advertises `h2,http/1.1` and permits HTTP/1.1 fallback before request bytes are sent. `HTTP2_Required` rejects non-h2 ALPN results.

The stable HTTP/2 surface includes settings validation, HPACK helpers for the supported subset, request/response mapping, frame and stream utilities, bounded single-stream execution, bounded multiplexing state, public streaming response support, and upload-body support. Server push, broad browser cache behavior, and unrestricted dynamic HPACK behavior are not part of the stable contract.

HPACK decoding accepts both raw and RFC 7541 static-Huffman string literals for header names and values. Malformed Huffman payloads, including EOS-as-data and invalid padding, fail deterministically with `HPACK_Huffman_Error`. The encoder uses HPACK static-table indexes for common request pseudo-header names and exact static request fields, and raw non-Huffman string literals for values that are not indexed.

Applications should normally configure HTTP/2 through the high-level client or TLS options rather than constructing frames. Frame-level packages are intended for protocol tests, diagnostics, and advanced integrations.

## Bounded multiplexing

`HTTP2_Options.Enable_Multiplexing` enables the bounded HTTP/2 connection-state model. The effective concurrent-stream limit is the minimum of `Local_Max_Concurrent_Streams` and the peer `SETTINGS_MAX_CONCURRENT_STREAMS`. Response DATA is queued per stream and exposed as entity body bytes only; frame boundaries are not visible to callers. `Max_Per_Stream_Buffered_Bytes` bounds each unread response queue, while `Max_Total_Queued_Body_Bytes` bounds aggregate queued DATA across all active streams on the connection.

The connection model tracks SETTINGS, PING, GOAWAY, WINDOW_UPDATE, HEADERS/CONTINUATION sequencing, DATA routing, RST_STREAM, stream-level and connection-level flow-control windows, including explicit response-DATA crediting for transports that serialize WINDOW_UPDATE immediately and deterministic protocol-error retirement. GOAWAY prevents new streams and classifies streams above the peer `last-stream-id`; RST_STREAM affects only the addressed stream when connection state remains valid.

HTTP/2 request uploads use DATA frames and never HTTP/1.1 chunked transfer framing. Unknown-length producer bodies require `Allow_Unknown_Length_HTTP2_Bodies`. HTTP/2 request trailers are supported as trailing HEADERS and are validated by the same conservative trailer-name policy documented below.

## Git smart HTTP buffered selection

Buffered Git smart HTTP requests may select HTTP/2 without changing request/header/body APIs:

```ada
Execution.Protocol_Policy := Http_Client.Clients.Prefer_HTTP_2;
-- or:
Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_2;
```

`Prefer_HTTP_2` enables `h2,http/1.1` ALPN and allows HTTP/1.1 fallback before request bytes are sent. `Force_HTTP_2` advertises h2 as required, rejects a TLS connection that does not negotiate HTTP/2, and rejects plain `http://` requests because h2c is not implemented. Git headers such as `Git-Protocol: version=2` map to lowercase HTTP/2 ordinary fields, and binary bodies remain byte-preserving. The public `Response_Streams` API now has explicit HTTP/2 streaming policies for callers that opt in; HTTP/1.1 remains the default large-packfile path.

### Padded and priority HEADERS metadata

For bounded multiplexing, HEADERS frame PADDED and PRIORITY fields are validated as frame metadata. Only the HPACK header-block fragment bytes count toward `Max_Header_List_Size`; continuation bytes are added to that fragment count. This prevents legal padding or priority metadata from causing false header-list overflow while still rejecting an oversized header block deterministically.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.


### HTTP/2 trailers

HTTP/2 trailers are trailing HEADERS, not HTTP/1.1 chunk trailers. Request trailers do not require an HTTP/1.1 Trailer declaration and never use Transfer-Encoding. Pseudo-headers plus framing, connection-specific, and sensitive names are rejected. Response body reads expose only DATA bytes; buffered responses expose validated trailer fields through `Http_Client.Responses.Trailers`, while the HTTP/2 connection model also records per-stream trailer receipt.

## Phase 13 HTTP/2 header/body separation

HTTP/2 DATA payloads are the only response/request body bytes. Frame headers, HPACK metadata, pseudo-headers, and trailing HEADERS are metadata and are never exposed as body bytes. HTTP/2 rejects HTTP/1.1 transfer-framing header fields such as `Transfer-Encoding`, and HTTP/2 trailers reject pseudo-headers and forbidden framing or sensitive names.


RST_STREAM handling preserves retry-safe REFUSED_STREAM semantics: peer RST_STREAM frames with error code 7 are reported as HTTP2_Stream_Refused so the retry layer can replay eligible idempotent requests, while other reset codes remain HTTP2_Stream_Reset.

The single-stream HTTP/2 execution path only treats `RST_STREAM` as fatal when it targets the active request stream; resets for unrelated peer streams are ignored rather than collapsed into `HTTP2_Stream_Reset`.




HTTP/2 request mapping strips HTTP/1.1-only compatibility fields such as synthesized `Connection: close`, preserves legal `TE: trailers`, and synthesizes `content-length` for known non-empty request bodies before HPACK encoding so strict h2 peers receive a protocol-native request block.

HTTP/2 stream resets are not masked by HTTP/1.1 fallback. `Prefer_HTTP_2` may fall back only before HTTP/2 request bytes are sent; once a peer resets the active HTTP/2 stream, the reset remains visible as `HTTP2_Stream_Refused` for REFUSED_STREAM or `HTTP2_Stream_Reset` for other reset codes.


HTTP/2 request mapping note: `Expect: 100-continue` is not forwarded on HTTP/2 requests.

HTTP/2 request mapping note: Expect: 100-continue is not forwarded on HTTP/2 requests. It is an HTTP/1.1 upload handshake, while HTTP/2 uses stream framing and flow control for request bodies. Dropping this compatibility header avoids strict peer `RST_STREAM` resets caused by HTTP/1.1-only expectation semantics on h2 streams.


## Single-stream request bodies

The single-stream HTTP/2 execution path serializes fixed-length producer request bodies as DATA before END_STREAM. This prevents producer-backed POST requests from being half-closed as empty streams, which strict peers can reject with RST_STREAM.

Release guard token: single-stream HTTP/2 serializes fixed-length producer request bodies as DATA before END_STREAM.

HTTP/2 peer RST_STREAM frames are mapped to the most specific existing result status when the reset code is known. RST_STREAM frames are mapped to the most specific existing result status, so PROTOCOL_ERROR, FLOW_CONTROL_ERROR, FRAME_SIZE_ERROR, COMPRESSION_ERROR, REFUSED_STREAM, and HTTP_1_1_REQUIRED no longer collapse into only HTTP2_STREAM_RESET.

HTTP/2 TLS reads and writes now honor configured TLS/TCP read and write timeout intent through the OpenSSL transport bridge where the platform exposes socket-level timeouts. In high-level one-shot execution, `Execution_Options.Timeouts` are also used as the HTTPS/TLS timeout default when `Execution_Options.TLS.Timeouts` is left at its all-zero default; explicit TLS timeouts still take precedence. A stalled h2 peer should therefore return `Timeout` instead of leaving the single-stream frame loop blocked indefinitely when callers configure nonzero request timeouts.

## HTTP/2 wire probe diagnostic tool

`tools/bin/h2_wire_probe` is a diagnostic helper for failing HTTP/2
interoperability cases. It opens a direct TLS connection with ALPN `h2`
required, emits the exact client connection preface, SETTINGS ACK, and stream 1
HEADERS bytes, and prints the raw bytes and parsed frame summaries received from
the server. When response DATA is received, the probe now sends connection- and
stream-level `WINDOW_UPDATE` frames for the consumed DATA bytes so large
responses do not stall after the initial HTTP/2 receive window. This is intended
for diagnosing stalls, peer resets, bad SETTINGS handling, malformed HPACK
request blocks, flow-control behavior, and incorrect END_STREAM sequencing
without hiding the problem behind HTTP/1.1 fallback.

Example:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/h2_wire_probe https://example.com/
```

Use `--insecure` only against local test fixtures when certificate verification
is intentionally disabled.


HTTP/2 buffered execution advertises a larger default receive window and sends an initial connection-level WINDOW_UPDATE before request HEADERS, then continues to replenish receive windows while DATA is consumed. This prevents large responses from stalling at the HTTP/2 initial 65,535-byte connection window.

- Retired TLS connections are closed without a blocking TLS close-notify round trip after HTTP/2 END_STREAM has been processed, avoiding slow completion on peers that do not answer close_notify promptly.


Buffered HTTP/2 responses are still bounded. The default high-level buffered body limit is 16 MiB after the HPACK/flow-control interoperability work; callers that need stricter or larger bounds should set `Execution.Max_Body_Size` and `Execution.Max_Response_Size` explicitly.
