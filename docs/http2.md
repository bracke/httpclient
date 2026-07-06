# HTTP/2

HTTP/2 support is part of the stable release surface. The API includes HTTP/2 configuration, ALPN selection policy, settings, frames, streams, HPACK support for the implemented scope, bounded single-stream execution, bounded multiplexing state, response streaming, and upload support.

HTTP/2 server push cache behavior is not implemented. Applications should not depend on internal frame dispatch details or diagnostic message text for protocol control.

## HPACK Huffman decoding

HTTP/2 HPACK decoding supports both raw and Huffman-encoded string literals. Malformed HPACK Huffman payloads fail deterministically with `HPACK_Huffman_Error`; legal Huffman-encoded response header names and values are decoded before header validation and dynamic-table insertion.

The single-stream HTTP/2 execution path only treats `RST_STREAM` as fatal when it targets the active request stream; resets for unrelated peer streams are ignored rather than collapsed into `HTTP2_Stream_Reset`.




HTTP/2 request mapping strips HTTP/1.1-only compatibility fields such as synthesized `Connection: close`, preserves legal `TE: trailers`, and synthesizes `content-length` for known non-empty request bodies before HPACK encoding so strict h2 peers receive a protocol-native request block.

HTTP/2 stream resets are not masked by HTTP/1.1 fallback. `Prefer_HTTP_2` may fall back only before HTTP/2 request bytes are sent; once a peer resets the active HTTP/2 stream, the reset remains visible as `HTTP2_Stream_Refused` for REFUSED_STREAM or `HTTP2_Stream_Reset` for other reset codes.


`Expect: 100-continue` is normalized away for HTTP/2 request headers because the h2 body path uses DATA frames and flow control rather than the HTTP/1.1 continue handshake.


## Single-stream request bodies

The single-stream HTTP/2 execution path serializes fixed-length producer request bodies as DATA before END_STREAM. This prevents producer-backed POST requests from being half-closed as empty streams, which strict peers can reject with RST_STREAM.

Release guard token: single-stream HTTP/2 serializes fixed-length producer request bodies as DATA before END_STREAM.


HTTP/2 response DATA handling replenishes both connection-level and stream-level receive windows with WINDOW_UPDATE frames. Buffered single-stream execution sends those updates immediately after accepted DATA, and the multiplexed connection model exposes explicit response-DATA crediting so transports can do the same without double-crediting later body-stream reads. Large responses are therefore not left stalled at the initial flow-control window.

HTTP/2 peer RST_STREAM frames are mapped to the most specific existing result status when the reset code is known. RST_STREAM frames are mapped to the most specific existing result status, so PROTOCOL_ERROR, FLOW_CONTROL_ERROR, FRAME_SIZE_ERROR, COMPRESSION_ERROR, REFUSED_STREAM, and HTTP_1_1_REQUIRED no longer collapse into only HTTP2_STREAM_RESET.

HTTP/2 TLS reads and writes honor configured read and write timeout intent through the OpenSSL transport bridge where the platform exposes socket-level timeouts. In high-level one-shot execution, `Execution_Options.Timeouts` are also used as the HTTPS/TLS timeout default when `Execution_Options.TLS.Timeouts` is left at its all-zero default; explicit TLS timeouts still take precedence. A stalled h2 peer should therefore return `Timeout` instead of leaving the single-stream frame loop blocked indefinitely when callers configure nonzero request timeouts.


HTTP/2 buffered execution advertises a larger default receive window and sends an initial connection-level WINDOW_UPDATE before request HEADERS, then continues to replenish receive windows while DATA is consumed. This prevents large responses from stalling at the HTTP/2 initial 65,535-byte connection window.

- HTTP/2 retired TLS connections use deterministic non-blocking client-side close after protocol completion.


Buffered HTTP/2 responses are still bounded. The default high-level buffered body limit is 16 MiB after the HPACK/flow-control interoperability work; callers that need stricter or larger bounds should set `Execution.Max_Body_Size` and `Execution.Max_Response_Size` explicitly.
