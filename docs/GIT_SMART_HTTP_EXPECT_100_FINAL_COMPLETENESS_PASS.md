# Git smart HTTP Expect: 100-continue final completeness pass

This pass verifies the `Expect: 100-continue` behavior after the early-final
chunked-response limitation was removed.

## Confirmed behavior

* Buffered HTTP/1.1 execution sends headers first when the request explicitly
  contains `Expect: 100-continue` and the request has a body.
* The body is sent only after a `100 Continue` interim response.
* If the server sends a final response instead of `100 Continue`, the request
  body is not uploaded.
* Early final responses with `Content-Length` are read and exposed by buffered
  execution.
* Early final responses with `Transfer-Encoding: chunked` are decoded and
  exposed by buffered execution. Chunk extensions are accepted and bounded
  trailers are parsed and discarded.
* Streaming response execution also handles early final responses: `Open`
  returns successfully with the final response metadata, and callers read the
  final response body through `Read_Some` without uploading the request body.
* `Expect` is never generated automatically. Callers must set
  `Expect: 100-continue` explicitly when they want this handshake.
* Unsupported `Expect` values and duplicate `Expect` headers fail
  deterministically during request/header validation.

## Test coverage added in this pass

`Test_Response_Stream_Expect_Chunked_Final_Response_Does_Not_Upload` covers the
streaming path where a loopback server returns `417 Expectation Failed` with a
chunked response body, chunk extension, trailer, and an embedded NUL byte. The
test verifies that:

* `Response_Streams.Open` returns a valid stream with status code `417`;
* `Read_Some` exposes only decoded entity bytes;
* the decoded body exactly matches `no\0-upload`;
* the original request body `abc` was not sent to the server.

## Remaining scope boundaries

Request trailers are supported only for HTTP/1.1 chunked uploads. The implementation does not perform an
automatic delayed-upload heuristic; `Expect: 100-continue` is honored only when
the caller explicitly sets the header. These are deliberate scope boundaries,
not Git smart HTTP blockers.
