# Git Smart HTTP — HTTP/2 Byte-Array Streaming Pass

This pass tightens the HTTP/2 Git support boundary by adding a binary-safe
`Ada.Streams.Stream_Element_Array` read overload to the low-level HTTP/2 body
stream adapter.

## Implemented

* `Http_Client.HTTP2.Body_Streams.Read_Some` now has a byte-array overload.
* The overload preserves HTTP/2 DATA payload octets exactly, including NUL
  bytes, bytes above 127, CR, LF, pkt-line bytes, and packfile-like data.
* It does not expose HTTP/2 frame headers, padding, flow-control metadata, or
  stream-control frames.
* It reports ordinary end-of-stream and deterministic HTTP/2 stream failures
  through `Http_Client.Errors.Result_Status`.

## Test coverage

Added `Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes`.

The test queues HTTP/2 response DATA containing pkt-line-like binary bytes,
including a NUL byte and `16#FF#`, then reads through a caller-provided
`Stream_Element_Array` buffer smaller than the full body. It verifies that the
concatenated returned bytes equal the original DATA payload exactly.

## Scope boundary

This is a low-level HTTP/2 body-stream adapter enhancement. The high-level
`Http_Client.Response_Streams` now has explicit protocol policies; this pass provided the low-level HTTP/2 byte-array body stream foundation used by the later streaming parity pass.
Buffered HTTP/2 and HTTP/3 Git examples remain available through
`Http_Client.Clients.Execute` with explicit protocol policy.
