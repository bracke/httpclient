# Git Smart HTTP Request Trailers Pass

This pass adds explicit HTTP/1.1 request trailer support for chunked uploads.

## Implemented behavior

* `Http_Client.Request_Bodies` can attach validated trailer fields to an unknown-length producer body.
* HTTP/1.1 header serialization rejects trailers on empty, buffered, and fixed-length request bodies.
* HTTP/1.1 header serialization synthesizes `Trailer: ...` when trailers are attached and no explicit declaration exists.
* An explicit `Trailer` header is accepted only when it covers all attached trailer field names.
* Forbidden trailer names are rejected, including framing, routing, connection-control, and credential-bearing fields such as `Content-Length`, `Transfer-Encoding`, `Host`, `Connection`, `Authorization`, `Proxy-Authorization`, and `Cookie`.
* Buffered execution and streaming response execution emit trailer field lines after the terminating zero-size chunk.
* Request trailers remain unavailable for fixed-length uploads and are not used for HTTP/2 or HTTP/3 in this pass.

## Git impact

Git smart HTTP does not normally require request trailers, but remotes or test harnesses that require HTTP/1.1 chunked request trailers can now be exercised deterministically without falling back to connection-close delimiting. Fixed-length uploads remain the preferred Git push path when the pack/request size is known.
