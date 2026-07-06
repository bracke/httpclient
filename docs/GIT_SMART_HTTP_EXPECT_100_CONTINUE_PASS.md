# Git smart HTTP Expect: 100-continue pass

This pass implements explicit HTTP/1.1 `Expect: 100-continue` handling for upload requests.

## Behavior

* The client does not generate `Expect: 100-continue` automatically.
* If the caller sets exactly `Expect: 100-continue`, HTTP/1.1 buffered and streaming execution send request headers first.
* The client then waits for an interim response using bounded header reads.
* If the server sends `100 Continue`, the request body is sent normally.
* If the server sends a final response instead of `100 Continue`, the request body is not sent.
* Unsupported `Expect` values are rejected during HTTP/1.1 request serialization with `Unsupported_Feature`.
* Duplicate `Expect` headers are rejected as `Invalid_Header`.
* Request trailers are supported only for HTTP/1.1 chunked uploads and are sent after `100 Continue` permits the body.

## Git use

`version` may set `Expect: 100-continue` for large `git-receive-pack` pushes to avoid sending a pack when the server rejects the request based on headers, authentication, authorization, repository state, or size policy.

The initial Git recommendation remains conservative: use this header only when the caller wants the extra round trip for large uploads. Smaller upload-pack/receive-pack requests can omit it.
