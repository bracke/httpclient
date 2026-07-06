# Git Smart HTTP Chunked Request Upload Pass

This pass implements explicit HTTP/1.1 chunked request upload for unknown-length producer bodies.

## Public API behavior

`Http_Client.Request_Bodies.From_Unknown_Length_Stream` now maps to HTTP/1.1 `Transfer-Encoding: chunked` during normal HTTP/1.1 execution and response-stream execution.

The client:

* synthesizes `Transfer-Encoding: chunked` when no `Transfer-Encoding` header is present;
* accepts an explicit `Transfer-Encoding: chunked` header for unknown-length streaming bodies;
* rejects `Content-Length` together with `Transfer-Encoding`;
* rejects unsupported request transfer codings with `Unsupported_Feature`;
* emits each successful producer read as one chunk;
* emits the final zero-size chunk when the producer returns `Ok` with `Count = 0`;
* sends explicit request trailers when the request body carries a validated trailer list;
* returns producer/write errors deterministically and does not reuse the failed connection.

Fixed-length producer bodies continue to use exact `Content-Length` synthesis/validation. Buffered bodies remain replayable and byte-preserving.

## Tests/examples added

* `Test_HTTP1_Unknown_Length_Stream_Chunked_Headers` verifies synthesized chunked headers and absence of `Content-Length`.
* `Test_High_Level_Client_Chunked_Upload_Loopback` verifies a loopback server observes exact HTTP/1.1 chunk framing for binary producer data including NUL and non-ASCII octets.
* `examples/src/git_receive_pack_chunked_upload.adb` shows an unknown-length receive-pack upload producer using `From_Unknown_Length_Stream`.

## Remaining limits

Request trailers are supported only for HTTP/1.1 chunked uploads. The Git path should still prefer fixed-length upload when it already knows the pack/request size, because fixed-length requests are easier to replay under strict redirect/retry policy.
