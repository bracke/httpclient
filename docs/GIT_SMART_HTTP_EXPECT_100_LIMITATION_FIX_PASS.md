# Git smart HTTP Expect: 100-continue limitation fix pass

This pass removes the remaining buffered `Expect: 100-continue` limitation for early final responses using HTTP/1.1 transfer coding.

## Implemented behavior

When a request explicitly contains `Expect: 100-continue`, HTTP/1.1 buffered and streaming execution still send only the request headers first. If the server returns `100 Continue`, the request body is uploaded normally. If the server returns a final response before `100 Continue`, the request body is not sent.

Buffered `Execute` now reads early final response bodies in both supported HTTP/1.1 body forms:

* fixed `Content-Length`; and
* `Transfer-Encoding: chunked`.

Chunked early final responses are decoded before the response body is exposed. Chunk extensions are ignored, bounded trailers are parsed and discarded, malformed chunk framing returns deterministic protocol/header/status failures, and decoded body size limits are enforced. The public response body never contains chunk-size lines, chunk CRLF bytes, or trailers.

## Tests added

`Test_High_Level_Client_Expect_Chunked_Final_Response_Does_Not_Upload` covers a loopback server that:

* receives only the request headers;
* returns `417 Expectation Failed` with `Transfer-Encoding: chunked`;
* includes a chunk extension and a trailer;
* includes a NUL byte in the decoded response body; and
* proves the buffered request body was not sent.

The existing fixed-length early final response test remains in place.

## Remaining non-goals

The client still does not generate `Expect: 100-continue` automatically. Request trailers are supported only for HTTP/1.1 chunked uploads after `100 Continue` permits the body. Unsupported response transfer codings other than final `chunked` still fail deterministically.
