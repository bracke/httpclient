# Git smart HTTP chunked upload completeness pass

This pass tightens the explicit HTTP/1.1 chunked request upload work added for
unknown-length `Http_Client.Request_Bodies.From_Unknown_Length_Stream` bodies.

## Confirmed contract

* Fixed-length streaming bodies continue to use exact `Content-Length` framing.
* Unknown-length HTTP/1.1 streaming bodies use `Transfer-Encoding: chunked`.
* The serializer accepts an explicit single `Transfer-Encoding: chunked` header
  for unknown-length producers, but does not synthesize `Content-Length` in that
  case.
* `Content-Length` plus `Transfer-Encoding` is rejected before request body bytes
  are sent.
* Unsupported request transfer codings, such as `gzip`, are rejected before body
  bytes are sent.
* The chunked upload writer emits each successful producer read as one chunk and
  emits the final zero-size chunk and, when configured, bounded request trailers. Request trailers are supported only for HTTP/1.1 chunked uploads and
  are never emitted implicitly.
* Producer failure or write failure returns a deterministic status and prevents
  connection reuse.

## Additional test coverage added

* `Test_HTTP1_Chunked_Upload_Header_Validation` validates explicit chunked
  upload headers, conflicting `Content-Length`/`Transfer-Encoding`, and
  unsupported request transfer codings.
* The existing loopback upload test continues to validate exact binary chunk
  framing, including NUL and non-ASCII octets.

## Remaining limits

* `Expect: 100-continue` is now implemented for HTTP/1.1 buffered and streaming execution when the caller sets the exact header. It is not generated automatically.
* Request trailers are now supported by the later request-trailers pass for explicit HTTP/1.1 chunked uploads.
* HTTP/2 unknown-length upload remains governed by the existing HTTP/2 execution
  option rather than by HTTP/1.1 chunked transfer coding.
