# Git smart HTTP HTTP/2/HTTP/3 streaming parity completeness pass

This pass tightens the HTTP/2/HTTP/3 streaming parity work so the public API,
AUnit coverage markers, documentation, and release guard agree.

## Public API consistency

`Http_Client.Response_Streams` is documented as the protocol-independent
Git-safe pull API. HTTP/1.1 remains the default. HTTP/2 and HTTP/3 are selected
only through explicit streaming protocol policy values.

The package comments no longer describe the streaming surface as HTTP/1.1-only.
`Http_Client.HTTP2.Single_Stream` now documents its real boundary: the core is
still a conservative single-stream buffered exchange, while
`Response_Streams` can wrap the bounded h2 response into the same pull API for
explicit Git h2 calls. `Http_Client.HTTP3.Execution` now documents the same
relationship for bounded HTTP/3 execution results.

## Test completeness

The AUnit registration list now includes concrete wrappers for the markers that
were previously referenced by the release guard:

* `Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP`
* `Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend`
* `Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes`

The HTTP/2 streaming-policy test proves that `Streaming_Force_HTTP_2` rejects
plain HTTP before opening a TCP connection. The HTTP/3 streaming-policy test
proves that `Streaming_Force_HTTP_3` fails deterministically before request
bytes when no QUIC backend is configured. The HTTP/3 body-stream test proves
that the byte-array pull adapter preserves pkt-line-like bytes, NUL, high-byte
data, and LF through small caller buffers.

## Release guard

`tools/src/check_git_smart_http_release.adb` now requires this completeness
document and the additional streaming Force_HTTP2 coverage marker.

## Remaining verification boundary

Ada build and AUnit execution still need to be performed with a real GNAT/GPRbuild
toolchain and the configured Ada `Zlib` dependency.
